// LineSocket.swift — a minimal blocking TCP client that reads and writes CRLF-terminated lines.
//
// Test-only helper for talking raw IMAP to GreenMail before the real IMAP client exists
// (Milestone 1 replaces most uses with swift-nio-imap). Uses POSIX sockets so it works on
// both macOS and Linux.

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

struct LineSocketError: Error, CustomStringConvertible {
    let description: String
}

final class LineSocket {
    private let fd: Int32
    private var buffer: [UInt8] = []

    /// Connects to `host:port`, trying each resolved address in turn.
    init(host: String, port: UInt16) throws {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        #if canImport(Glibc)
        hints.ai_socktype = Int32(SOCK_STREAM.rawValue)
        #else
        hints.ai_socktype = SOCK_STREAM
        #endif

        var results: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, String(port), &hints, &results)
        guard status == 0, let first = results else {
            throw LineSocketError(description: "cannot resolve \(host): \(String(cString: gai_strerror(status)))")
        }
        defer { freeaddrinfo(results) }

        var candidate: UnsafeMutablePointer<addrinfo>? = first
        while let info = candidate {
            let sock = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
            if sock >= 0 {
                if connect(sock, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0 {
                    fd = sock
                    return
                }
                close(sock)
            }
            candidate = info.pointee.ai_next
        }
        throw LineSocketError(description: "cannot connect to \(host):\(port)")
    }

    deinit { close(fd) }

    /// Sends one line, appending CRLF.
    func send(_ line: String) throws {
        let bytes = Array((line + "\r\n").utf8)
        var offset = 0
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            guard written > 0 else { throw LineSocketError(description: "write failed") }
            offset += written
        }
    }

    /// Reads one line, without its CRLF.
    func readLine() throws -> String {
        while true {
            if let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                var line = Array(buffer[..<newline])
                buffer.removeSubrange(...newline)
                if line.last == UInt8(ascii: "\r") { line.removeLast() }
                return String(decoding: line, as: UTF8.self)
            }
            var chunk = [UInt8](repeating: 0, count: 4096)
            let count = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            guard count > 0 else { throw LineSocketError(description: "connection closed") }
            buffer.append(contentsOf: chunk[..<count])
        }
    }

    /// Reads lines until the tagged response for `tag` arrives, and returns that final line.
    func readTagged(_ tag: String) throws -> String {
        while true {
            let line = try readLine()
            if line.hasPrefix(tag + " ") { return line }
        }
    }
}
