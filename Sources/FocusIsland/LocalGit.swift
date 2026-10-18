import Foundation
import FocusCore
import Darwin

struct ServiceError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}
struct RepositoryCount: Identifiable, Sendable {
    var id: String
    var count: Int
}
struct RepositorySelection: Codable, Identifiable, Equatable, Sendable {
    var path: String
    var gitDirectory: String
    var commonDirectory: String
    var email: String
    var id: String { path }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
}
struct LocalSnapshot: Sendable {
    var commits: Int
    var repositories: [RepositoryCount]
    var detectedEmails: [String: String]
}
struct CommandOutput: Sendable { var status: Int32; var text: String }

enum LocalGit {
    /// Arguments go directly to Process: no shell, no credentials interpolated into commands.
    static func command(_ executable: String, _ arguments: [String], timeout: Double = 20, environment overrides: [String: String] = [:]) async throws -> CommandOutput {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            var environment = ProcessInfo.processInfo.environment
            environment["GIT_TERMINAL_PROMPT"] = "0"
            environment["GIT_OPTIONAL_LOCKS"] = "0"
            environment["LC_ALL"] = "C"
            environment.merge(overrides) { _, replacement in replacement }
            process.environment = environment
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice
            try process.run()
            // Nonblocking, bounded reads prevent hostile repository output or a
            // descendant holding the pipe open from exhausting memory or hanging scans.
            let fd = pipe.fileHandleForReading.fileDescriptor
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
            let deadline = ProcessInfo.processInfo.systemUptime + timeout
            let limit = 8 * 1024 * 1024
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 16 * 1024)
            while true {
                if ProcessInfo.processInfo.systemUptime >= deadline {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                    process.waitUntilExit()
                    return CommandOutput(status: 124, text: "Command exceeded its time limit.")
                }
                let count = read(fd, &buffer, buffer.count)
                if count > 0 {
                    guard data.count + count <= limit else {
                        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                        process.waitUntilExit()
                        throw ServiceError(message: "Command output exceeded the safe size limit.")
                    }
                    data.append(contentsOf: buffer.prefix(count))
                    continue
                }
                if count == 0 || !process.isRunning { break }
                if errno != EAGAIN && errno != EINTR {
                    kill(process.processIdentifier, SIGKILL)
                    process.waitUntilExit()
                    throw ServiceError(message: "Could not read command output.")
                }
                usleep(10_000)
            }
            // EOF can arrive before process exit, so keep enforcing the deadline.
            while process.isRunning {
                if ProcessInfo.processInfo.systemUptime >= deadline {
                    kill(process.processIdentifier, SIGKILL)
                    process.waitUntilExit()
                    return CommandOutput(status: 124, text: "Command exceeded its time limit.")
                }
                usleep(10_000)
            }
            process.waitUntilExit()
            return CommandOutput(status: process.terminationStatus, text: String(decoding: data, as: UTF8.self))
        }.value
    }
    static func git(_ path: String, _ arguments: [String]) async throws -> CommandOutput {
        try await command("/usr/bin/git", ["--no-pager", "--no-replace-objects", "-c", "core.fsmonitor=false", "-c", "log.showSignature=false", "-c", "core.hooksPath=/dev/null", "-c", "protocol.allow=never", "-C", path] + arguments, environment: ["GIT_NO_LAZY_FETCH": "1"])
    }
    // GitHub's published Ed25519 host key. Never accept a key obtained from an
    // unverified scan. A rotation requires reviewing the official source and updating this pin.
    // https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints
    static let githubHostKey = "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl\n"
    static let githubHostFingerprint = "SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU"

    static func sshArguments(knownHosts: URL) -> [String] {
        let escaped = knownHosts.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return ["-T", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
                "-o", "UserKnownHostsFile=\"\(escaped)\"", "-o", "GlobalKnownHostsFile=/dev/null",
                "-o", "HostKeyAlgorithms=ssh-ed25519", "-o", "HostKeyAlias=github.com",
                "-o", "UpdateHostKeys=no", "-o", "KnownHostsCommand=none",
                "-o", "VerifyHostKeyDNS=no", "-o", "PreferredAuthentications=publickey",
                "-o", "ForwardAgent=no",
                "-o", "ForwardX11=no", "-o", "ClearAllForwardings=yes",
                "-o", "PermitLocalCommand=no", "-o", "RemoteCommand=none",
                "-o", "ControlMaster=no", "-o", "ControlPath=none",
                "-o", "ConnectTimeout=10",
                "-o", "ConnectionAttempts=1", "git@github.com"]
    }
    static func sshFailure(_ output: String, status: Int32, agentStatus: Int32?) -> String {
        if output.contains("Host key verification failed") || output.contains("REMOTE HOST IDENTIFICATION HAS CHANGED") || output.contains("no matching host key") {
            return "GitHub’s server key does not match the published Ed25519 key bundled with Focus Island. Connection stopped. Check your network and GitHub’s official SSH fingerprint documentation; a legitimate key rotation requires an app update."
        }
        if output.contains("Permission denied") || output.contains("sign_and_send_pubkey") {
            if agentStatus == 1 {
                return "Your SSH agent has no unlocked keys. Load your GitHub key in Terminal using ssh-add --apple-use-keychain /path/to/your/key, then connect again. The app never asks for your private key or passphrase."
            }
            if agentStatus == 0 {
                return "GitHub rejected the SSH keys available to the app. Check that your public authentication key is added to the correct GitHub account. If you use several accounts, configure IdentityFile and IdentitiesOnly for Host github.com in ~/.ssh/config."
            }
            return "GitHub could not authenticate your key. Check that ssh-agent is running, unlock your key there, and add its public key to your GitHub account."
        }
        if output.contains("Could not resolve hostname") { return "Could not resolve GitHub’s address. Check your internet connection or VPN and try again." }
        if output.contains("Connection timed out") || output.contains("Connection refused") || output.contains("Network is unreachable") || status == 15 {
            return "The SSH connection to GitHub could not finish. Check your network and firewall. If port 22 is blocked, configure Host github.com to use HostName ssh.github.com and Port 443 in ~/.ssh/config."
        }
        return "SSH verification failed (exit \(status)). Check your SSH configuration and agent, then try again. Local commit monitoring is still available."
    }
    static func verifySSH() async throws -> String {
        // GUI apps do not always inherit a Terminal's SSH_AUTH_SOCK. Prefer the
        // inherited agent, and fall back to launchd's agent only when it is absent/stale.
        var environment: [String: String] = [:]
        let inherited = ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"] ?? ""
        if inherited.isEmpty || !FileManager.default.fileExists(atPath: inherited) {
            let agent = try? await command("/bin/launchctl", ["getenv", "SSH_AUTH_SOCK"], timeout: 3)
            let socket = agent?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if agent?.status == 0, !socket.isEmpty { environment["SSH_AUTH_SOCK"] = socket }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("focus-island-ssh-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let knownHosts = directory.appendingPathComponent("known_hosts")
        try Data(githubHostKey.utf8).write(to: knownHosts, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: knownHosts.path)
        let result = try await command("/usr/bin/ssh", sshArguments(knownHosts: knownHosts), timeout: 15, environment: environment)
        guard result.status == 1, let name = CommitRules.sshUsername(result.text) else {
            let agent = try? await command("/usr/bin/ssh-add", ["-l"], timeout: 3, environment: environment)
            throw ServiceError(message: sshFailure(result.text, status: result.status, agentStatus: agent?.status))
        }
        return name
    }
    static func authorEmail(_ path: String) async throws -> String? {
        // Git may synthesize an author address from the local username/hostname even
        // when user.email is unset. Resolve the identity Git actually uses for commits.
        let identity = try await git(path, ["var", "GIT_AUTHOR_IDENT"])
        guard identity.status == 0, let left = identity.text.lastIndex(of: "<"),
              let right = identity.text[left...].firstIndex(of: ">"), left < right else { return nil }
        let email = String(identity.text[identity.text.index(after: left)..<right]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return email.isEmpty ? nil : email
    }
    static func inspect(_ path: String) async throws -> RepositorySelection {
        let root = try await git(path, ["rev-parse", "--show-toplevel"])
        guard root.status == 0 else { throw ServiceError(message: "Choose a working Git repository folder.") }
        let canonical = root.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let directory = try await git(canonical, ["rev-parse", "--absolute-git-dir"])
        let common = try await git(canonical, ["rev-parse", "--path-format=absolute", "--git-common-dir"])
        let email = try await authorEmail(canonical)
        guard directory.status == 0, common.status == 0 else { throw ServiceError(message: "Could not read the repository metadata.") }
        return RepositorySelection(path: canonical, gitDirectory: directory.text.trimmingCharacters(in: .whitespacesAndNewlines), commonDirectory: common.text.trimmingCharacters(in: .whitespacesAndNewlines), email: email ?? "")
    }
    static func snapshot(_ selections: [RepositorySelection], extraEmails: String, date: Date) async throws -> LocalSnapshot {
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let extras = extraEmails.split(whereSeparator: { $0 == "," || $0 == "\n" }).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
        var all: Set<String> = []
        var counts: [RepositoryCount] = []
        var detectedEmails: [String: String] = [:]
        for selection in selections {
            let configured = try await authorEmail(selection.path)
            var emails = Set(extras)
            if let configured { emails.insert(configured); detectedEmails[selection.path] = configured }
            guard !emails.isEmpty else { throw ServiceError(message: "Set git config user.email in \(selection.name), or add your author email in Settings, so other people’s commits aren’t counted.") }
            let result = try await git(selection.path, ["log", "--no-show-signature", "--no-ext-diff", "--no-textconv", "--all", "--since-as-filter=@\(Int(start.timeIntervalSince1970))", "--until=@\(Int(end.timeIntervalSince1970))", "--format=%H%x09%ae%x09%ct"])
            if result.status != 0 {
                // An initialized repository with no commits is a valid zero.
                let head = try await git(selection.path, ["rev-parse", "--verify", "HEAD"])
                let refs = try await git(selection.path, ["show-ref"])
                guard head.status != 0 && refs.status == 1 else { throw ServiceError(message: "Could not read commits in \(selection.name). Check that the folder is still accessible.") }
                counts.append(RepositoryCount(id: selection.path, count: 0))
                continue
            }
            let hashes = CommitRules.matching(CommitRules.parse(result.text), emails: emails, from: start, to: min(end, date.addingTimeInterval(1)))
            all.formUnion(hashes)
            counts.append(RepositoryCount(id: selection.path, count: hashes.count))
        }
        return LocalSnapshot(commits: all.count, repositories: counts.sorted { $0.count > $1.count }, detectedEmails: detectedEmails)
    }
}

/// Git writes logs/HEAD and replaces refs atomically. Watch both the metadata folders and
/// their live files, then re-arm after each change. A two-second scan also covers new refs.
@MainActor
final class RepositoryWatcher {
    private var sources: [DispatchSourceFileSystemObject] = []
    func watch(_ repositories: [RepositorySelection], changed: @escaping @MainActor @Sendable () -> Void) {
        stop()
        var paths: Set<String> = []
        for repo in repositories {
            for base in Set([repo.gitDirectory, repo.commonDirectory]) {
                paths.formUnion([base, base + "/HEAD", base + "/logs", base + "/logs/HEAD", base + "/refs", base + "/refs/heads", base + "/packed-refs"])
            }
        }
        for path in paths {
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend], queue: .main)
            source.setEventHandler { Task { @MainActor in changed() } }
            source.setCancelHandler { close(fd) }
            source.resume()
            sources.append(source)
        }
    }
    func stop() { sources.forEach { $0.cancel() }; sources.removeAll() }
}
