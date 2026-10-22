// MailReserveKitTests.swift — unit tests for package-wide constants.

import Testing
@testable import MailReserveKit

@Suite("MailReserveKit")
struct MailReserveKitTests {
    @Test("version is a dotted semantic version")
    func versionIsSemantic() {
        let parts = MailReserveKit.version.split(separator: ".")
        #expect(parts.count == 3)
        #expect(parts.allSatisfy { Int($0) != nil })
    }

    @Test("client name includes the version")
    func clientNameIncludesVersion() {
        #expect(MailReserveKit.clientName == "MailReserve/\(MailReserveKit.version)")
    }
}
