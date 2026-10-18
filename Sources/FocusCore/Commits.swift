import Foundation

public struct LocalCommit: Sendable, Equatable {
    public var sha: String
    public var email: String
    public var timestamp: Double
}

public enum CommitRules {
    /// Normalize user-entered author identities as a single atomic settings update.
    /// nil means an incomplete/invalid address; an empty array explicitly clears extras.
    public static func authorEmails(_ input: String) -> [String]? {
        var emails: [String] = []
        for value in input.split(whereSeparator: { $0 == "," || $0 == "\n" }) {
            let email = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if email.isEmpty { continue }
            let parts = email.split(separator: "@", omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty,
                  !email.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }) else { return nil }
            if !emails.contains(email) { emails.append(email) }
        }
        return emails
    }

    public static func parse(_ output: String) -> [LocalCommit] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 3, fields[0].count >= 40,
                  fields[0].allSatisfy({ $0.isHexDigit }), let stamp = Double(fields[2]) else { return nil }
            return LocalCommit(sha: String(fields[0]), email: String(fields[1]).lowercased(), timestamp: stamp)
        }
    }
    public static func matching(_ commits: [LocalCommit], emails: Set<String>, from: Date, to: Date) -> Set<String> {
        let identities = Set(emails.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        return Set(commits.filter { identities.contains($0.email) && $0.timestamp >= from.timeIntervalSince1970 && $0.timestamp < to.timeIntervalSince1970 }.map(\.sha))
    }
    public static func sshUsername(_ output: String) -> String? {
        // GitHub deliberately exits with status 1 after successful authentication.
        guard output.contains("You've successfully authenticated"),
              let expression = try? NSRegularExpression(pattern: "Hi ([A-Za-z0-9-]+)!"),
              let match = expression.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output) else { return nil }
        return String(output[range])
    }
}
