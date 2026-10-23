// SpikeOptions.swift — parses the spike's command line and resolves provider presets.
//
//   imap-spike <gmail|yahoo|host[:port]> <email> [--folder INBOX] [--count 100]
//              [--output spike-output] [--list-only]
//   Local GreenMail testing only (refused for any other host):
//              [--plaintext] [--test-password <password>]

import Foundation

struct SpikeOptions {
    var host: String
    var port: Int
    var email: String
    var folder = "INBOX"
    var count = 100
    var output = "spike-output"
    var listOnly = false
    var useTLS = true
    /// Only for localhost GreenMail runs; real accounts always read the Keychain.
    var testPassword: String?

    static let usage = """
        usage: imap-spike <gmail|yahoo|host[:port]> <email> [--folder INBOX] [--count 100]
                          [--output spike-output] [--list-only]
               localhost only: [--plaintext] [--test-password <password>]
        """

    /// Known providers. Both use implicit TLS on port 993.
    static let presets: [String: (host: String, port: Int)] = [
        "gmail": ("imap.gmail.com", 993),
        "yahoo": ("imap.mail.yahoo.com", 993),
    ]

    var isLocalhost: Bool { ["localhost", "127.0.0.1", "::1"].contains(host) }

    /// True for Gmail and Yahoo, whose app passwords have a known shape.
    var isProviderPreset: Bool { Self.presets.values.contains { $0.host == host } }

    init(arguments: [String]) throws {
        var positional: [String] = []
        var folder: String?, count: Int?, output: String?, testPassword: String?
        var listOnly = false, plaintext = false

        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            func value() throws -> String {
                guard let next = iterator.next() else { throw SpikeError.usage("\(argument) needs a value") }
                return next
            }
            switch argument {
            case "--folder": folder = try value()
            case "--count":
                guard let parsed = Int(try value()), parsed > 0 else { throw SpikeError.usage("--count must be a positive number") }
                count = parsed
            case "--output": output = try value()
            case "--list-only": listOnly = true
            case "--plaintext": plaintext = true
            case "--test-password": testPassword = try value()
            case "-h", "--help": throw SpikeError.usage(nil)
            default:
                if argument.hasPrefix("--") { throw SpikeError.usage("unknown option \(argument)") }
                positional.append(argument)
            }
        }
        guard positional.count == 2 else { throw SpikeError.usage("expected a server and an email address") }

        let server = positional[0]
        if let preset = Self.presets[server.lowercased()] {
            (host, port) = preset
        } else {
            let parts = server.split(separator: ":", maxSplits: 1)
            host = String(parts[0])
            port = parts.count == 2 ? Int(parts[1]) ?? 993 : 993
        }
        email = positional[1]
        if let folder { self.folder = folder }
        if let count { self.count = count }
        if let output { self.output = output }
        self.listOnly = listOnly
        self.useTLS = !plaintext
        self.testPassword = testPassword

        // Plaintext and command-line passwords exist only to test against local GreenMail.
        if (plaintext || testPassword != nil) && !isLocalhost {
            throw SpikeError.usage("--plaintext and --test-password are only allowed for localhost")
        }
    }
}
