// ImapSpike.swift — entry point for the Milestone 0 spike.
//
// For one account: connect over TLS, log in with the app password from the Keychain, list every
// folder, open one folder read-only (EXAMINE, so no flags change), find the newest N messages and
// download each with BODY.PEEK[] to spike-output/<email>/<folder>/<uid>.eml. Everything learned
// along the way (capabilities, folders, UIDVALIDITY, sizes, timing) goes into report.txt.

import Foundation
import NIOCore
import NIOIMAP

@main
struct ImapSpike {
    /// UIDs fetched per UID FETCH command.
    static let batchSize = 25

    static func main() async {
        do {
            let options = try SpikeOptions(arguments: Array(CommandLine.arguments.dropFirst()))
            try await run(options)
        } catch {
            FileHandle.standardError.write(Data("\n\(error)\n".utf8))
            exit(1)
        }
    }

    static func run(_ options: SpikeOptions) async throws {
        let password = try options.testPassword ?? KeychainPassword.read(account: options.email)
        if options.isProviderPreset, let warning = KeychainPassword.appPasswordWarning(password, account: options.email) {
            FileHandle.standardError.write(Data("\(warning)\n\n".utf8))
        }
        var report = SpikeReport(options: options)
        let clock = ContinuousClock()
        let started = clock.now

        print("Connecting to \(options.host):\(options.port) (\(options.useTLS ? "TLS" : "plaintext"))...")
        let channel = try await IMAPConnector.connect(host: options.host, port: options.port, useTLS: options.useTLS)

        try await channel.executeThenClose { inbound, outbound in
            let session = IMAPSession(inbound: inbound, outbound: outbound)
            report.greeting = try await session.readGreeting()

            try await session.run("LOGIN", .login(username: options.email, password: password))
            print("Logged in as \(options.email)")

            // Capabilities after login; Gmail and Yahoo both advertise more once authenticated.
            try await session.run("CAPABILITY", .capability) { response in
                if case .untagged(.capabilityData(let capabilities)) = response {
                    report.capabilities = capabilities.map { String($0) }
                }
            }

            // Identify the client. Harmless everywhere; some providers expect it.
            if report.capabilities.contains("ID") {
                try await session.run("ID", .id(["name": "MailReserve-spike", "version": "0.0.1"])) { response in
                    if case .untagged(.id(let fields)) = response {
                        report.serverID = fields.map { "\($0.key)=\($0.value ?? "NIL")" }.joined(separator: ", ")
                    }
                }
            }

            // Every folder ("*" matches all levels).
            var folders: [MailboxInfo] = []
            try await session.run("LIST", .list(nil, reference: MailboxName(ByteBuffer(string: "")), .mailbox(ByteBuffer(string: "*")))) { response in
                if case .untagged(.mailboxData(.list(let info))) = response { folders.append(info) }
            }
            report.folders = folders.map { FolderLine(info: $0) }
            print("Found \(folders.count) folders")

            if !options.listOnly {
                try await backUp(options: options, folders: folders, session: session, report: &report)
            }

            try await session.run("LOGOUT", .logout)
        }

        report.seconds = (clock.now - started) / .seconds(1)
        let reportURL = try report.write()
        print(report.summary)
        print("Report: \(reportURL.path)")
    }

    static func backUp(options: SpikeOptions, folders: [MailboxInfo], session: IMAPSession, report: inout SpikeReport) async throws {
        // Use the server's own encoded name when the folder is in the list (handles non-ASCII names).
        guard let folder = folders.first(where: { FolderLine(info: $0).name == options.folder }) else {
            throw SpikeError.folderNotFound(options.folder)
        }

        try await session.run("EXAMINE", .examine(folder.path.name)) { response in
            switch response {
            case .untagged(.conditionalState(.ok(let text))):
                switch text.code {
                case .uidValidity(let value): report.uidValidity = UInt32(value)
                case .uidNext(let uid): report.uidNext = uid.rawValue
                default: break
                }
            case .untagged(.mailboxData(.exists(let count))):
                report.exists = count
            default:
                break
            }
        }
        print("\(options.folder): \(report.exists ?? 0) messages, UIDVALIDITY \(report.uidValidity.map(String.init) ?? "?")")

        // The newest N messages are the last N sequence numbers (EXISTS-N+1 ... EXISTS), so no SEARCH
        // is needed. `UID SEARCH ALL` returns every UID on one line, which breaks swift-nio-imap's
        // fixed 8 KB line limit once a folder holds a few thousand messages (Yahoo, 10,000: 2026-10-23).
        let exists = report.exists ?? 0
        let first = max(1, exists - options.count + 1)
        let total = exists >= first ? exists - first + 1 : 0
        if options.isYahoo && exists == 10_000 {
            report.notes.append("EXISTS is exactly 10,000: Yahoo's IMAP server shows only the newest 10,000 messages per folder; older mail is not reachable here.")
        }
        print("Downloading the newest \(total) of \(exists) messages...")

        let isGmail = report.capabilities.contains("X-GM-EXT-1")
        var attributes: [FetchAttribute] = [.uid, .rfc822Size, .bodySection(peek: true, .complete, nil)]
        if isGmail { attributes += [.gmailMessageID, .gmailLabels] }

        let directory = URL(fileURLWithPath: options.output)
            .appendingPathComponent(options.email)
            .appendingPathComponent(FolderLine.safeDirectoryName(options.folder))
        let sink = try MessageSink(directory: directory)

        // Sequence numbers are stable for this session: EXAMINE is read-only, so nothing is expunged.
        for low in stride(from: first, through: exists, by: batchSize) {
            let high = min(low + batchSize - 1, exists)
            let range = MessageIdentifierRange(SequenceNumber(rawValue: UInt32(low))...SequenceNumber(rawValue: UInt32(high)))
            try await session.run("FETCH", .fetch(.range(range), attributes, [])) { response in
                if case .fetch(let event) = response { try sink.handle(event) }
            }
            print("  \(sink.saved.count)/\(total)")
        }

        report.directory = directory
        report.messages = sink.saved
    }
}
