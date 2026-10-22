// IntegrationEnvironment.swift — reads the test IMAP server settings from environment variables.
//
// Integration tests run only when MAILRESERVE_IMAP_TEST_HOST is set (scripts/test-integration.sh
// and CI set it). CI also sets MAILRESERVE_REQUIRE_INTEGRATION=1: the tests then stay enabled even
// without a host, so a missing server fails loudly instead of skipping silently.

import Foundation

enum IntegrationEnvironment {
    private static let env = ProcessInfo.processInfo.environment

    /// True when integration tests should run (server configured, or CI demands them).
    static var isEnabled: Bool {
        host != nil || env["MAILRESERVE_REQUIRE_INTEGRATION"] == "1"
    }

    static var host: String? { env["MAILRESERVE_IMAP_TEST_HOST"] }

    /// GreenMail's plain-text IMAP port in its "test" setup.
    static var plainPort: UInt16 { UInt16(env["MAILRESERVE_IMAP_TEST_PORT"] ?? "") ?? 3143 }

    /// Fake GreenMail user (set up by the CI service container and scripts/test-integration.sh).
    /// Never a real account.
    static var user: String { env["MAILRESERVE_IMAP_TEST_USER"] ?? "test@localhost" }
    static var password: String { env["MAILRESERVE_IMAP_TEST_PASSWORD"] ?? "test-password" }
}
