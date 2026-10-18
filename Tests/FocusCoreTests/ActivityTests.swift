import Foundation
import FocusCore

struct CheckFailure: Error, CustomStringConvertible { var description: String }
func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw CheckFailure(description: message) }
}

@main
struct CoreChecks {
    static func main() throws {
        try expect(Activity.isActive(bundleID: "com.microsoft.VSCode", idle: 59, suspended: false, paused: false, consented: true), "Recent foreground VS Code must count")
        try expect(Activity.isActive(bundleID: "com.microsoft.VSCodeInsiders", idle: 0, suspended: false, paused: false, consented: true), "Insiders must count")
        try expect(!Activity.isActive(bundleID: "com.apple.Safari", idle: 0, suspended: false, paused: false, consented: true), "Other applications must not count")
        try expect(!Activity.isActive(bundleID: "com.microsoft.VSCode", idle: 60, suspended: false, paused: false, consented: true), "Idle threshold must pause tracking")
        try expect(!Activity.isActive(bundleID: "com.microsoft.VSCode", idle: 0, suspended: true, paused: false, consented: true), "Sleep/lock must pause tracking")
        try expect(!Activity.isActive(bundleID: "com.microsoft.VSCode", idle: 0, suspended: false, paused: true, consented: true), "Manual pause must stop tracking")
        try expect(!Activity.isActive(bundleID: nil, idle: 0, suspended: false, paused: false, consented: true), "Missing foreground app must not count")
        print("PASS activity eligibility")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        let start = ISO8601DateFormatter().date(from: "2026-10-19T02:59:59Z")!
        var days: [String: DayRecord] = [:]
        Activity.record(from: start, to: start.addingTimeInterval(2), into: &days, calendar: calendar)
        try expect(days["2026-10-18"]?.seconds == 1 && days["2026-10-19"]?.seconds == 1, "Midnight must split time into local days")
        try expect(days["2026-10-18"]?.hours[23] == 1 && days["2026-10-19"]?.hours[0] == 1, "Hourly buckets must match the split")
        print("PASS local midnight and hourly attribution")

        var skipped: [String: DayRecord] = [:]
        Activity.record(from: start, to: start.addingTimeInterval(3600), into: &skipped)
        Activity.record(from: start, to: start.addingTimeInterval(-1), into: &skipped)
        try expect(skipped.isEmpty, "Sleep gaps and clock reversals must be discarded")
        print("PASS sleep gaps and clock reversal")

        let decoded = try JSONDecoder().decode([String: DayRecord].self, from: JSONEncoder().encode(days))
        try expect(decoded == days, "History must survive persistence")
        try expect(decoded["2026-10-18"]?.commits == nil, "Unknown commits must remain unknown")
        print("PASS history persistence and unknown metrics")

        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let dst = ISO8601DateFormatter().date(from: "2026-11-01T05:59:59Z")!
        var autumn: [String: DayRecord] = [:]
        Activity.record(from: dst, to: dst.addingTimeInterval(2), into: &autumn, calendar: calendar)
        try expect(autumn["2026-11-01"]?.seconds == 2 && autumn["2026-11-01"]?.hours.reduce(0, +) == 2, "Fall DST must preserve total elapsed time")
        print("PASS daylight saving boundary")
        let a = String(repeating: "a", count: 40)
        let b = String(repeating: "b", count: 40)
        let parsed = CommitRules.parse("\(a)\tME@example.test\t100\n\(a)\tme@example.test\t100\n\(b)\tother@example.test\t100\ninvalid")
        let matching = CommitRules.matching(parsed, emails: [" me@example.test "], from: Date(timeIntervalSince1970: 90), to: Date(timeIntervalSince1970: 110))
        try expect(matching == [a], "Only my email counts; duplicate hashes and malformed records must be excluded")
        try expect(CommitRules.matching(parsed, emails: ["me@example.test"], from: Date(timeIntervalSince1970: 100), to: Date(timeIntervalSince1970: 100)).isEmpty, "Commit windows are half-open")
        try expect(CommitRules.sshUsername("Hi coder-name! You've successfully authenticated, but GitHub does not provide shell access.") == "coder-name", "Parse successful SSH identity")
        try expect(CommitRules.sshUsername("Permission denied (publickey).") == nil, "Failed SSH auth must never yield an identity")
        try expect(Activity.liveDuration(61) == "01:01" && Activity.liveDuration(3661) == "1:01:01", "Live timer must show seconds")
        print("PASS commit attribution, deduplication, SSH identity, and live clock")
        try expect(CommitRules.authorEmails(" Me@Example.com, me@example.com, 123+coder@users.noreply.github.com ") == ["me@example.com", "123+coder@users.noreply.github.com"], "Saved email identities must normalize and deduplicate without losing noreply addresses")
        try expect(CommitRules.authorEmails("not-an-email") == nil && CommitRules.authorEmails("user@") == nil && CommitRules.authorEmails("a b@example.com") == nil, "Incomplete drafts must not become saved author identities")
        try expect(CommitRules.authorEmails("me@example.com, invalid") == nil, "An invalid address must reject the whole draft instead of saving part of it")
        try expect(CommitRules.authorEmails("  ") == [], "An empty draft must support clearing additional identities")
        print("PASS email draft validation and normalization")
        try expect(!Activity.isActive(bundleID: "com.microsoft.VSCode", idle: 0, suspended: false, paused: false, consented: false), "Foreground activity must never count before consent")
        var consent = SessionConsent()
        consent.reconcile([101])
        try expect(!consent.hasPermission && consent.decision(for: 101) == nil, "New sessions must wait for a choice")
        consent.respond(to: 101, allow: false)
        try expect(!consent.allows(101) && consent.decision(for: 101) == false, "Not now must prevent tracking for the session")
        consent.reconcile([101])
        try expect(consent.decision(for: 101) == false, "App switching must not reset a declined session")
        consent.reconcile([])
        consent.reconcile([102])
        try expect(consent.decision(for: 102) == nil && !consent.hasPermission, "Reopening the editor must require a fresh choice")
        consent.respond(to: 102, allow: true)
        try expect(consent.allows(102) && consent.hasPermission && !consent.allows(103), "Consent must authorize only its own live editor process")
        consent.reconcile([])
        try expect(!consent.hasPermission, "Closing the editor must end consent")
        print("PASS session consent, decline, app switching, relaunch, and termination")
        print("All core checks passed.")
    }
}
