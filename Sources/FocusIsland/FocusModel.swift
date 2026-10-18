import AppKit
import Combine
import CoreGraphics
import FocusCore
import Security

struct EditorSession: Identifiable, Equatable, Sendable {
    var id: Int32
    var name: String
}

@MainActor
final class FocusModel: ObservableObject {
    @Published var days: [String: DayRecord] = [:]
    @Published var requestedEditor: EditorSession?
    @Published var active = false
    @Published var paused = false
    @Published var status = "Waiting for VS Code"
    @Published var login = UserDefaults.standard.string(forKey: "sshLogin") ?? ""
    @Published var repositories: [RepositoryCount] = []
    @Published var selections: [RepositorySelection] = []
    @Published var syncDate: Date?
    @Published var error: String?
    @Published var connectionError: String?
    @Published var syncing = false
    @Published var authorizing = false
    @Published var connected = false
    @Published var focusGoal = UserDefaults.standard.object(forKey: "focusGoal") as? Double ?? 120 {
        didSet { if !previewMode { UserDefaults.standard.set(focusGoal, forKey: "focusGoal") } }
    }
    @Published var commitGoal = UserDefaults.standard.object(forKey: "commitGoal") as? Int ?? 5 {
        didSet { if !previewMode { UserDefaults.standard.set(commitGoal, forKey: "commitGoal") } }
    }
    @Published private(set) var extraEmails = UserDefaults.standard.string(forKey: "authorEmails") ?? ""
    var showSummary: (() -> Void)?
    private var previewMode = false
    private var consent = SessionConsent()
    private var pendingEditors: [EditorSession] = []
    var hasSessionConsent: Bool { consent.hasPermission }
    private var lastSample = Date()
    private var previousActive = false
    private var suspended = false
    private var timer: Timer?
    private var lastSaved = Date()
    private var lastScanned = Date.distantPast
    private var loadFailed = false
    private var repositoryGeneration = 0
    private var changeTask: Task<Void, Never>?
    private let watcher = RepositoryWatcher()
    private let storeURL: URL
    var today: DayRecord { days[Activity.dayKey(Date())] ?? DayRecord(id: Activity.dayKey(Date())) }
    var week: [DayRecord] {
        (0..<7).reversed().map { offset in
            let key = Activity.dayKey(Calendar.current.date(byAdding: .day, value: -offset, to: Date())!)
            return days[key] ?? DayRecord(id: key)
        }
    }
    var focusProgress: Double { min(1, today.seconds / max(1, focusGoal * 60)) }
    var commitProgress: Double { min(1, Double(today.commits ?? 0) / Double(max(1, commitGoal))) }

    init(preview: Bool = false) {
        storeURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FocusIsland/days.json")
        if preview {
            previewMode = true
            focusGoal = 180
            commitGoal = 10
            login = "developer"
            connected = true
            extraEmails = "you@example.com"
            selections = [RepositorySelection(path: "/Example/nebula", gitDirectory: "/Example/nebula/.git", commonDirectory: "/Example/nebula/.git", email: "you@example.com")]
            repositories = [RepositoryCount(id: "/Example/nebula", count: 5), RepositoryCount(id: "/Example/orbit", count: 2)]
            syncDate = Date()
            consent.reconcile([1])
            consent.respond(to: 1, allow: true)
            for offset in 0..<7 {
                let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date())!
                let key = Activity.dayKey(date)
                var record = DayRecord(id: key)
                record.seconds = offset == 0 ? 9258 : Double([0, 8100, 11700, 6300, 10800, 0, 4200][offset])
                record.commits = offset == 0 ? 7 : [0, 4, 9, 3, 6, 0, 2][offset]
                if offset == 0 { for (hour, minutes) in [(8, 12), (9, 43), (10, 54), (11, 31), (14, 14)] { record.hours[hour] = Double(minutes * 60) } }
                days[key] = record
            }
            active = true
            status = "In the flow · VS Code"
            return
        }
        if FileManager.default.fileExists(atPath: storeURL.path) {
            do { days = try JSONDecoder().decode([String: DayRecord].self, from: Data(contentsOf: storeURL)) }
            catch { loadFailed = true; self.error = "Could not load saved activity. The original file is preserved; restart after checking it. \(error.localizedDescription)" }
        }
        if let data = UserDefaults.standard.data(forKey: "repositories") {
            selections = (try? JSONDecoder().decode([RepositorySelection].self, from: data)) ?? []
        }
        // SSH replaces the former API integration. Delete only our own obsolete credential.
        if !UserDefaults.standard.bool(forKey: "localGitMigration") {
            let removed = SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "org.focusisland.github", kSecAttrAccount as String: "token"] as CFDictionary)
            if removed == errSecSuccess || removed == errSecItemNotFound {
                UserDefaults.standard.set(true, forKey: "localGitMigration")
            } else { error = "Could not remove the previous GitHub API token from Keychain. Remove the org.focusisland.github credential in Keychain Access; this version never reads or uses it." }
            for key in Array(days.keys) { days[key]?.commits = nil }
            UserDefaults.standard.removeObject(forKey: "clientID")
            UserDefaults.standard.removeObject(forKey: "githubLogin")
        }
        connected = UserDefaults.standard.bool(forKey: "sshVerified") && !login.isEmpty
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.suspend() } }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.resume() } }
        }
        // App switches update eligibility immediately; the live clock is not tied to a slow poll.
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didDeactivateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.tick() } }
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.editorSessionsChanged() }
            }
        }
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
            DistributedNotificationCenter.default().addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] notification in
                let locked = notification.name.rawValue == "com.apple.screenIsLocked"
                Task { @MainActor in if locked { self?.suspend() } else { self?.resume() } }
            }
        }
        timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        RunLoop.main.add(timer!, forMode: .common)
        editorSessionsChanged()
        tick()
    }
    func editorSessionsChanged() {
        let editors = NSWorkspace.shared.runningApplications.filter { Activity.editors.contains($0.bundleIdentifier ?? "") }
        let running = Set(editors.map(\.processIdentifier))
        let hadPermission = consent.hasPermission
        consent.reconcile(running)
        if hadPermission && !consent.hasPermission {
            repositoryGeneration += 1
            watcher.stop()
            changeTask?.cancel()
        }
        pendingEditors.removeAll { !running.contains($0.id) }
        if let requested = requestedEditor, !running.contains(requested.id) { requestedEditor = nil }
        for editor in editors where consent.decision(for: editor.processIdentifier) == nil && requestedEditor?.id != editor.processIdentifier && !pendingEditors.contains(where: { $0.id == editor.processIdentifier }) {
            pendingEditors.append(EditorSession(id: editor.processIdentifier, name: editor.localizedName ?? "VS Code"))
        }
        presentNextConsent()
        tick()
    }
    private func presentNextConsent() {
        if requestedEditor == nil && !pendingEditors.isEmpty { requestedEditor = pendingEditors.removeFirst() }
    }
    func respondToConsent(_ editor: EditorSession, allow: Bool) {
        guard requestedEditor?.id == editor.id else { return }
        // Settle only previously authorized time before changing the session gate.
        tick()
        consent.respond(to: editor.id, allow: allow)
        requestedEditor = nil
        previousActive = false
        lastSample = Date()
        if allow {
            paused = false
            armWatchers()
            Task { await refresh() }
        }
        presentNextConsent()
        tick()
    }
    private func requestSessionConsent() {
        let editors = NSWorkspace.shared.runningApplications.filter { Activity.editors.contains($0.bundleIdentifier ?? "") }
        guard let editor = editors.first(where: { $0.isActive }) ?? editors.first else {
            status = "Open VS Code to start a session"
            return
        }
        consent.requestAgain(editor.processIdentifier)
        editorSessionsChanged()
    }
    func suspend() {
        tick()
        suspended = true
        previousActive = false
        active = false
        status = "Mac is resting"
        save()
    }
    func resume() {
        suspended = false
        lastSample = Date()
        previousActive = false
        tick()
        Task { await refresh() }
    }
    func tick() {
        let now = Date()
        // Quartz uses UINT32_MAX for any input; .null measures null events and never resets on typing.
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let locked = session?["CGSSessionScreenIsLocked"] as? Bool ?? false
        let onConsole = session?["kCGSSessionOnConsoleKey"] as? Bool ?? true
        let foreground = NSWorkspace.shared.frontmostApplication
        let permitted = foreground.map { consent.allows($0.processIdentifier) } ?? false
        let current = Activity.isActive(bundleID: foreground?.bundleIdentifier, idle: idle, suspended: suspended || locked || !onConsole, paused: paused, consented: permitted)
        if previousActive {
            // Stop exactly at the idle cutoff even if the next observation arrives later.
            let end = idle >= 60 ? min(now, now.addingTimeInterval(60 - idle)) : now
            Activity.record(from: lastSample, to: end, into: &days)
        }
        lastSample = now
        previousActive = current
        active = current
        if requestedEditor != nil && !hasSessionConsent { status = "Waiting for your tracking choice" }
        else if !hasSessionConsent { status = "Session tracking is off" }
        else if paused { status = "Tracking paused" }
        else if suspended || locked || !onConsole { status = "Mac is resting" }
        else if idle >= 60 { status = "Idle · timer resting" }
        else if current { status = "In the flow · VS Code" }
        else { status = "Waiting for VS Code" }
        if now.timeIntervalSince(lastSaved) >= 15 { save(); lastSaved = now }
        if now.timeIntervalSince(lastScanned) >= 2 { lastScanned = now; Task { await refresh() } }
        let key = Activity.dayKey(now)
        if Calendar.current.component(.hour, from: now) >= 20 && today.seconds > 0 && UserDefaults.standard.string(forKey: "lastSummary") != key {
            UserDefaults.standard.set(key, forKey: "lastSummary")
            showSummary?()
        }
    }
    func togglePause() {
        guard hasSessionConsent else { requestSessionConsent(); return }
        tick(); paused.toggle(); tick(); save()
        if !paused { Task { await refresh() } }
    }
    func save() {
        guard !loadFailed else { return }
        do {
            try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(days).write(to: storeURL, options: .atomic)
        } catch { self.error = "Could not save activity: \(error.localizedDescription)" }
    }
    private func armWatchers() {
        guard hasSessionConsent else { watcher.stop(); return }
        watcher.watch(selections) { [weak self] in
            guard let self else { return }
            self.changeTask?.cancel()
            self.changeTask = Task {
                do { try await Task.sleep(for: .milliseconds(150)); try Task.checkCancellation() }
                catch { return }
                await self.refresh()
                self.armWatchers()
            }
        }
    }
    func refresh() async {
        guard hasSessionConsent, !paused, !suspended, !syncing, !selections.isEmpty else { return }
        syncing = true
        let generation = repositoryGeneration
        let date = Date()
        defer { syncing = false }
        do {
            let result = try await LocalGit.snapshot(selections, extraEmails: extraEmails, date: date)
            guard generation == repositoryGeneration, hasSessionConsent, !paused, !suspended else { return }
            let key = Activity.dayKey(date)
            var record = days[key] ?? DayRecord(id: key)
            let changed = record.commits != result.commits
            record.commits = result.commits
            days[key] = record
            repositories = result.repositories
            for index in selections.indices {
                if let email = result.detectedEmails[selections[index].path], selections[index].email != email { selections[index].email = email }
            }
            syncDate = Date()
            error = nil
            if changed { save() }
        } catch {
            guard generation == repositoryGeneration, hasSessionConsent, !paused, !suspended else { return }
            self.error = error.localizedDescription
        }
    }
    func saveAuthorEmails(_ draft: String) throws {
        guard let emails = CommitRules.authorEmails(draft) else {
            throw ServiceError(message: "Enter a complete email such as you@example.com. Separate multiple addresses with commas.")
        }
        let saved = emails.joined(separator: ", ")
        guard saved != extraEmails else { return }
        extraEmails = saved
        UserDefaults.standard.set(saved, forKey: "authorEmails")
        repositoryGeneration += 1
        error = nil
        Task { await refresh() }
    }
    func connectSSH() {
        guard !authorizing else { return }
        authorizing = true
        connectionError = nil
        Task {
            defer { authorizing = false }
            do {
                login = try await LocalGit.verifySSH()
                connected = true
                UserDefaults.standard.set(login, forKey: "sshLogin")
                UserDefaults.standard.set(true, forKey: "sshVerified")
                connectionError = nil
            } catch {
                connectionError = error.localizedDescription
                connected = false
                UserDefaults.standard.set(false, forKey: "sshVerified")
            }
        }
    }
    func addRepository() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.message = "Select the local repositories you want to monitor."
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task {
            do {
                for url in urls {
                    let selection = try await LocalGit.inspect(url.path)
                    if !selections.contains(where: { $0.path == selection.path }) { selections.append(selection) }
                }
                persistSelections()
                await refresh()
            } catch { self.error = error.localizedDescription; persistSelections() }
        }
    }
    func removeRepository(_ selection: RepositorySelection) {
        selections.removeAll { $0.path == selection.path }
        persistSelections()
        if selections.isEmpty { days[Activity.dayKey(Date())]?.commits = nil; repositories = []; syncDate = nil; save() }
        else { Task { await refresh() } }
    }
    private func persistSelections() {
        repositoryGeneration += 1
        UserDefaults.standard.set(try? JSONEncoder().encode(selections), forKey: "repositories")
        armWatchers()
    }
    func disconnect() {
        connectionError = nil
        connected = false
        login = ""
        UserDefaults.standard.removeObject(forKey: "sshLogin")
        UserDefaults.standard.removeObject(forKey: "sshVerified")
    }
    func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "focus-island-history.json"
        if panel.runModal() == .OK, let url = panel.url {
            do { try JSONEncoder().encode(days).write(to: url, options: .atomic) }
            catch { self.error = "Export failed: \(error.localizedDescription)" }
        }
    }
}
