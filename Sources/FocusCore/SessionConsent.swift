import Foundation

/// Consent belongs to a running editor process and is never persisted across launches.
public struct SessionConsent: Sendable {
    private var running: Set<Int32> = []
    private var decisions: [Int32: Bool] = [:]
    public init() {}
    public mutating func reconcile(_ processIDs: Set<Int32>) {
        running = processIDs
        decisions = decisions.filter { processIDs.contains($0.key) }
    }
    public func decision(for processID: Int32) -> Bool? { decisions[processID] }
    public func allows(_ processID: Int32) -> Bool { running.contains(processID) && decisions[processID] == true }
    public var hasPermission: Bool { decisions.contains { running.contains($0.key) && $0.value } }
    public mutating func respond(to processID: Int32, allow: Bool) {
        guard running.contains(processID) else { return }
        decisions[processID] = allow
    }
    public mutating func requestAgain(_ processID: Int32) { decisions.removeValue(forKey: processID) }
}
