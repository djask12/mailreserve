// GreenMailSmokeTests.swift — proves the integration-test server is reachable and accepts the
// fake test user. Every later integration test relies on this setup working.

import Testing

@Suite("GreenMail smoke", .enabled(if: IntegrationEnvironment.isEnabled))
struct GreenMailSmokeTests {
    @Test("server greets, accepts LOGIN and LOGOUT")
    func loginRoundTrip() throws {
        let host = try #require(
            IntegrationEnvironment.host,
            "MAILRESERVE_IMAP_TEST_HOST is not set, but integration tests are required"
        )
        let socket = try LineSocket(host: host, port: IntegrationEnvironment.plainPort)

        let greeting = try socket.readLine()
        #expect(greeting.hasPrefix("* OK"))

        try socket.send("a1 LOGIN \"\(IntegrationEnvironment.user)\" \"\(IntegrationEnvironment.password)\"")
        let login = try socket.readTagged("a1")
        #expect(login.hasPrefix("a1 OK"), "LOGIN failed: \(login)")

        try socket.send("a2 LOGOUT")
        let logout = try socket.readTagged("a2")
        #expect(logout.hasPrefix("a2 OK"))
    }
}
