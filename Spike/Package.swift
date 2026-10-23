// swift-tools-version: 6.0
// Package.swift — Milestone 0 IMAP spike. A throwaway command-line tool that proves swift-nio-imap
// against real Gmail and Yahoo accounts. Kept separate from the main package and deleted once the
// M0 gate passes (see Spike/README.md).

import PackageDescription

let package = Package(
    name: "MailReserveSpike",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio-imap.git", exact: "0.4.0"),
        .package(url: "https://github.com/apple/swift-nio.git", exact: "2.104.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", exact: "2.37.5"),
    ],
    targets: [
        .executableTarget(
            name: "imap-spike",
            dependencies: [
                .product(name: "NIOIMAP", package: "swift-nio-imap"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
            ]
        ),
    ]
)
