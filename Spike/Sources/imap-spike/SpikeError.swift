// SpikeError.swift — every way the spike can fail, with messages meant for a person.

import Foundation

enum SpikeError: Error, CustomStringConvertible {
    case usage(String?)
    case missingPassword(account: String, status: OSStatus)
    case connectionClosed
    case unexpectedGreeting(String)
    case commandFailed(command: String, response: String)
    case folderNotFound(String)

    var description: String {
        switch self {
        case .usage(let message):
            return (message.map { "error: \($0)\n\n" } ?? "") + SpikeOptions.usage
        case .missingPassword(let account, let status):
            return """
                No app password in the Keychain for \(account) (OSStatus \(status)).
                Store it with:  security add-generic-password -s \(KeychainPassword.service) -a \(account) -w
                """
        case .connectionClosed:
            return "The server closed the connection unexpectedly."
        case .unexpectedGreeting(let text):
            return "The server did not greet with OK: \(text)"
        case .commandFailed(let command, let response):
            return "\(command) failed: \(response)"
        case .folderNotFound(let name):
            return "Folder \"\(name)\" was not in the server's folder list (see the list above)."
        }
    }
}
