// IMAPSession.swift — connects to an IMAP server with swift-nio-imap and runs one command at a time.
//
// Pipeline: [TLS (NIOSSL)] -> IMAPClientHandler (bytes <-> typed commands/responses) -> async channel.
// `run` sends a tagged command and hands every untagged response to a callback until the matching
// tagged OK/NO/BAD arrives. One command in flight at a time keeps the spike easy to follow; M1 can
// pipeline later.

import NIOCore
import NIOIMAP
import NIOPosix
import NIOSSL

typealias IMAPChannel = NIOAsyncChannel<Response, IMAPClientHandler.Message>

enum IMAPConnector {
    static func connect(host: String, port: Int, useTLS: Bool) async throws -> IMAPChannel {
        // Default client configuration verifies the server certificate against the system trust store.
        let sslContext = useTLS ? try NIOSSLContext(configuration: .makeClientConfiguration()) : nil
        return try await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .connectTimeout(.seconds(30))
            .connect(host: host, port: port) { channel in
                channel.eventLoop.makeCompletedFuture {
                    if let sslContext {
                        try channel.pipeline.syncOperations.addHandler(
                            NIOSSLClientHandler(context: sslContext, serverHostname: host)
                        )
                    }
                    try channel.pipeline.syncOperations.addHandler(IMAPClientHandler())
                    return try IMAPChannel(wrappingChannelSynchronously: channel)
                }
            }
    }
}

final class IMAPSession {
    private var responses: NIOAsyncChannelInboundStream<Response>.AsyncIterator
    private let outbound: NIOAsyncChannelOutboundWriter<IMAPClientHandler.Message>
    private var nextTag = 1

    init(inbound: NIOAsyncChannelInboundStream<Response>, outbound: NIOAsyncChannelOutboundWriter<IMAPClientHandler.Message>) {
        self.responses = inbound.makeAsyncIterator()
        self.outbound = outbound
    }

    /// Reads the server greeting, which must be an untagged OK (or PREAUTH).
    func readGreeting() async throws -> String {
        let response = try await nextResponse()
        switch response {
        case .untagged(.conditionalState(.ok(let text))), .untagged(.conditionalState(.preauth(let text))):
            return text.text
        default:
            throw SpikeError.unexpectedGreeting(String(describing: response))
        }
    }

    /// Sends `command` and passes each untagged response to `handle` until the tagged result arrives.
    /// `label` names the command in errors; never put the LOGIN password in it.
    @discardableResult
    func run(_ label: String, _ command: Command, handle: (Response) throws -> Void = { _ in }) async throws -> String {
        let tag = "A\(nextTag)"
        nextTag += 1
        try await outbound.write(.part(.tagged(TaggedCommand(tag: tag, command: command))))

        while true {
            let response = try await nextResponse()
            switch response {
            case .tagged(let tagged) where tagged.tag == tag:
                switch tagged.state {
                case .ok(let text): return text.text
                case .no(let text): throw SpikeError.commandFailed(command: label, response: "NO \(text.text)")
                case .bad(let text): throw SpikeError.commandFailed(command: label, response: "BAD \(text.text)")
                }
            case .fatal(let text):
                throw SpikeError.commandFailed(command: label, response: "server ended the session: \(text.text)")
            default:
                try handle(response)
            }
        }
    }

    private func nextResponse() async throws -> Response {
        guard let response = try await responses.next() else { throw SpikeError.connectionClosed }
        return response
    }
}
