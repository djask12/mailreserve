// MailReserveKit.swift — package-wide constants for the backup engine.
// Real engine code (accounts, IMAP sync, archive, index) is added from Milestone 1.

/// Namespace for engine-wide values.
public enum MailReserveKit {
    /// Engine version. Bumped with each tagged release.
    public static let version = "0.0.1"

    /// Identifies MailReserve to IMAP servers (sent with the IMAP `ID` command from Milestone 1).
    public static var clientName: String {
        "MailReserve/\(version)"
    }
}
