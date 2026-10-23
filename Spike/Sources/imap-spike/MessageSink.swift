// MessageSink.swift — writes streamed FETCH bodies to disk as .eml files without holding them in memory.
//
// A FETCH response arrives as events: start, simple attributes (UID, size, Gmail IDs) and the body
// stream (begin, bytes..., end), then finish. The UID can arrive before or after the body, so the
// body goes to "<sequence>.eml.partial" first and is renamed to "<uid>.eml" on finish. That is the
// same crash-safe write-then-rename pattern M1 will use.

import Foundation
import NIOCore
import NIOIMAP

struct SavedMessage {
    var uid: UInt32?
    var bytesWritten: Int
    var bytesExpected: Int
    var gmailMessageID: UInt64?
    var gmailLabels: [String]
    var file: URL?
}

final class MessageSink {
    private let directory: URL
    private(set) var saved: [SavedMessage] = []

    // State for the message currently being received.
    private var sequence = 0
    private var current = SavedMessage(uid: nil, bytesWritten: 0, bytesExpected: 0, gmailMessageID: nil, gmailLabels: [])
    private var partialURL: URL?
    private var handle: FileHandle?

    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func handle(_ event: FetchResponse) throws {
        switch event {
        case .start(let sequenceNumber):
            begin(sequence: Int(sequenceNumber.rawValue))
        case .startUID(let uid):
            begin(sequence: Int(uid.rawValue))
            current.uid = uid.rawValue
        case .simpleAttribute(.uid(let uid)):
            current.uid = uid.rawValue
        case .simpleAttribute(.gmailMessageID(let id)):
            current.gmailMessageID = id
        case .simpleAttribute(.gmailLabels(let labels)):
            current.gmailLabels = labels.map { String(describing: $0) }
        case .simpleAttribute:
            break
        case .streamingBegin(_, let byteCount):
            // We only request BODY.PEEK[] (the whole raw message), so this is always the message.
            current.bytesExpected = byteCount
            let url = directory.appendingPathComponent("\(sequence).eml.partial")
            FileManager.default.createFile(atPath: url.path, contents: nil)
            handle = try FileHandle(forWritingTo: url)
            partialURL = url
        case .streamingBytes(let bytes):
            try handle?.write(contentsOf: Data(bytes.readableBytesView))
            current.bytesWritten += bytes.readableBytes
        case .streamingEnd:
            try handle?.synchronize()
            try handle?.close()
            handle = nil
        case .finish:
            try finishMessage()
        }
    }

    private func begin(sequence: Int) {
        self.sequence = sequence
        current = SavedMessage(uid: nil, bytesWritten: 0, bytesExpected: 0, gmailMessageID: nil, gmailLabels: [])
        partialURL = nil
    }

    private func finishMessage() throws {
        if let partialURL {
            let name = current.uid.map { "\($0).eml" } ?? "seq-\(sequence).eml"
            let finalURL = directory.appendingPathComponent(name)
            // Re-running the spike overwrites earlier copies.
            try? FileManager.default.removeItem(at: finalURL)
            try FileManager.default.moveItem(at: partialURL, to: finalURL)
            current.file = finalURL
        }
        saved.append(current)
    }
}
