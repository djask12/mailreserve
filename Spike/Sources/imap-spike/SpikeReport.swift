// SpikeReport.swift — collects what the spike learned about a server and writes report.txt.
// These answers feed the Milestone 1 engine design (Gmail IDs, folder names, sizes, speed).

import Foundation
import NIOIMAP

/// One folder from LIST, with a readable name and its attributes (\Noselect, \All, \Sent, ...).
struct FolderLine {
    var name: String
    var attributes: [String]

    init(info: MailboxInfo) {
        let separator = info.path.pathSeparator.map(String.init) ?? "/"
        name = info.path.displayStringComponents().joined(separator: separator)
        attributes = info.attributes.map { String($0) }
    }

    /// A folder name made safe as a single directory name ("[Gmail]/Sent Mail" -> "[Gmail]_Sent Mail").
    static func safeDirectoryName(_ name: String) -> String {
        name.map { "/:\\".contains($0) ? "_" : $0 }.reduce(into: "") { $0.append($1) }
    }
}

/// One folder's result in --survey mode.
struct SurveyLine {
    var folder: String
    var exists: Int?
    var error: String?

    /// Flags what matters for a complete backup.
    var flag: String {
        guard let exists else { return "FAILED: \(error ?? "unknown")" }
        if exists == 10_000 { return "exactly 10,000: likely capped (regular Yahoo server hides older mail)" }
        if exists >= 100_000 { return "100,000+: Yahoo says folders this big may not download fully; split it" }
        return "ok"
    }
}

struct SpikeReport {
    let options: SpikeOptions
    var greeting = ""
    var capabilities: [String] = []
    var serverID: String?
    var folders: [FolderLine] = []
    var uidValidity: UInt32?
    var uidNext: UInt32?
    var exists: Int?
    var messages: [SavedMessage] = []
    var directory: URL?
    var seconds: Double = 0
    /// Observations worth flagging for M1 (provider limits and the like).
    var notes: [String] = []
    var survey: [SurveyLine] = []

    var totalBytes: Int { messages.reduce(0) { $0 + $1.bytesWritten } }
    var sizeMismatches: [SavedMessage] { messages.filter { $0.bytesWritten != $0.bytesExpected } }
    var missingUID: [SavedMessage] { messages.filter { $0.uid == nil } }

    var summary: String {
        var lines = ["", "== \(options.email) (\(options.host)) =="]
        lines.append("Folders: \(folders.count)")
        if !options.listOnly && !options.survey {
            lines.append("Downloaded: \(messages.count) messages, \(totalBytes / 1024) KB in \(String(format: "%.1f", seconds))s")
            lines.append("Size mismatches: \(sizeMismatches.count); messages without UID: \(missingUID.count)")
            if let directory { lines.append("Files: \(directory.path)") }
        }
        lines += notes.map { "NOTE: \($0)" }
        if options.survey {
            let total = survey.compactMap(\.exists).reduce(0, +)
            lines.append("Survey: \(survey.count) folders, \(total) messages visible in total")
            lines += survey.filter { $0.flag != "ok" }.map { "  CHECK \($0.folder): \($0.flag)" }
        }
        return lines.joined(separator: "\n")
    }

    /// Writes spike-output/<email>/report.txt and returns its URL.
    func write() throws -> URL {
        var text = ["MailReserve M0 IMAP spike report", "Generated: \(Date())", ""]
        text.append("Server: \(options.host):\(options.port) TLS=\(options.useTLS)")
        text.append("Account: \(options.email)")
        text.append("Greeting: \(greeting)")
        text.append("Server ID: \(serverID ?? "(not sent or not supported)")")
        text.append("Capabilities (\(capabilities.count)): \(capabilities.joined(separator: " "))")
        text.append("Gmail extensions (X-GM-EXT-1): \(capabilities.contains("X-GM-EXT-1"))")
        text += notes.map { "NOTE: \($0)" }
        text.append("")
        text.append("Folders (\(folders.count)):")
        text += folders.map { "  \($0.name)  \($0.attributes.joined(separator: " "))" }
        if options.survey {
            text.append("")
            text.append("Survey (messages visible per folder):")
            text += survey.map { "  \($0.folder)  \($0.exists.map(String.init) ?? "-")  \($0.flag)" }
            text.append("  TOTAL  \(survey.compactMap(\.exists).reduce(0, +))")
        }
        if !options.listOnly && !options.survey {
            text.append("")
            text.append("Folder examined: \(options.folder)")
            text.append("EXISTS: \(exists.map(String.init) ?? "?")  UIDVALIDITY: \(uidValidity.map(String.init) ?? "?")  UIDNEXT: \(uidNext.map(String.init) ?? "?")")
            text.append("Downloaded: \(messages.count)  Bytes: \(totalBytes)  Seconds: \(String(format: "%.2f", seconds))")
            text.append("Size mismatches: \(sizeMismatches.count)  Without UID: \(missingUID.count)")
            text.append("")
            text.append("Messages (uid  bytes  gmail-msgid  labels):")
            text += messages.map { message in
                let uid = message.uid.map(String.init) ?? "?"
                let gmail = message.gmailMessageID.map(String.init) ?? "-"
                return "  \(uid)  \(message.bytesWritten)/\(message.bytesExpected)  \(gmail)  \(message.gmailLabels.joined(separator: ","))"
            }
        }

        let accountDirectory = URL(fileURLWithPath: options.output).appendingPathComponent(options.email)
        try FileManager.default.createDirectory(at: accountDirectory, withIntermediateDirectories: true)
        let url = accountDirectory.appendingPathComponent("report.txt")
        try (text.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
