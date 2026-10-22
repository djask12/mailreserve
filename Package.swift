// swift-tools-version: 6.0
// Package.swift — builds the MailReserve backup engine (MailReserveKit) and its tests.
// The macOS app in App/ depends on this package; the CLI target arrives in Milestone 1.

import PackageDescription

let package = Package(
    name: "MailReserve",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MailReserveKit", targets: ["MailReserveKit"]),
    ],
    targets: [
        // The engine: no UI code, and it must also build on Linux (CI runs it there).
        .target(name: "MailReserveKit"),

        // Fast tests with no network access.
        .testTarget(
            name: "MailReserveKitTests",
            dependencies: ["MailReserveKit"]
        ),

        // Tests against a real IMAP server (GreenMail). Skipped unless
        // MAILRESERVE_IMAP_TEST_HOST is set; see scripts/test-integration.sh.
        .testTarget(
            name: "MailReserveIntegrationTests",
            dependencies: ["MailReserveKit"]
        ),
    ]
)
