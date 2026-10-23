// KeychainPassword.swift — reads an account's app password from the macOS Keychain.
//
// Store it once in Terminal (the -w with no value makes `security` prompt without echoing,
// so the password never lands in shell history):
//   security add-generic-password -s mailreserve-spike -a you@gmail.com -w
// The first read shows a macOS prompt asking to let imap-spike use the item; choose Allow.

import Foundation
import Security

enum KeychainPassword {
    static let service = "mailreserve-spike"

    static func read(account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let password = String(data: data, encoding: .utf8) else {
            throw SpikeError.missingPassword(account: account, status: status)
        }
        // Google shows app passwords in groups of four ("abcd efgh ..."); the spaces are not part of it.
        return password.filter { !$0.isWhitespace }
    }

    /// Gmail and Yahoo app passwords are exactly 16 lowercase letters. Returns a warning when the
    /// stored password doesn't look like one: the usual cause of "Invalid credentials" is pasting the
    /// normal account password, or invisible characters copied along with the app password.
    /// Describes only the length and character types, never the password itself.
    static func appPasswordWarning(_ password: String, account: String) -> String? {
        let isAppPassword = password.count == 16 && password.allSatisfy { ("a"..."z").contains($0) }
        guard !isAppPassword else { return nil }
        let kinds = password.allSatisfy(\.isASCII) ? "" : ", including non-text characters (often copied invisibly)"
        return """
            warning: the Keychain password for \(account) is \(password.count) characters\(kinds), but Gmail and \
            Yahoo app passwords are 16 lowercase letters. The server will probably reject it. Re-store it by \
            typing the 16 letters:
              security add-generic-password -U -s \(service) -a \(account) -w
            """
    }
}
