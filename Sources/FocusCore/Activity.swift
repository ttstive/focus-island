import Foundation

public struct DayRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var seconds: Double = 0
    public var commits: Int? = nil
    public var hours: [Double] = Array(repeating: 0, count: 24)
    public init(id: String) { self.id = id }
}

public enum Activity {
    public static let editors = EditorCatalog.defaultIDs
    public static func isActive(bundleID: String?, idle: Double, suspended: Bool, paused: Bool, consented: Bool, editorBundleIDs: Set<String> = EditorCatalog.defaultIDs) -> Bool {
        consented && !suspended && !paused && idle < 60 && idle >= 0 && EditorCatalog.contains(bundleID, in: editorBundleIDs)
    }
    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    /// Attribute only short, continuously observed intervals; split at local hour/day boundaries.
    public static func record(from start: Date, to end: Date, into days: inout [String: DayRecord], calendar: Calendar = .current) {
        guard end > start, end.timeIntervalSince(start) <= 5 else { return }
        var cursor = start
        while cursor < end {
            let boundary = calendar.dateInterval(of: .hour, for: cursor)!.end
            let stop = min(boundary, end)
            let key = dayKey(cursor, calendar: calendar)
            var day = days[key] ?? DayRecord(id: key)
            let seconds = stop.timeIntervalSince(cursor)
            day.seconds += seconds
            day.hours[calendar.component(.hour, from: cursor)] += seconds
            days[key] = day
            cursor = stop
        }
    }
    public static func liveDuration(_ seconds: Double) -> String {
        let value = max(0, Int(seconds))
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) : String(format: "%02d:%02d", value / 60, value % 60)
    }
    public static func duration(_ seconds: Double) -> String {
        let minutes = max(0, Int(seconds) / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}
