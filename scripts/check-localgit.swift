import Foundation
import FocusCore

struct Failure: Error, CustomStringConvertible { var description: String }
func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw Failure(description: message) }
}

@main
struct LocalGitChecks {
    @MainActor
    static func main() async throws {
        if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--inspect" {
            let selection = try await LocalGit.inspect(CommandLine.arguments[2])
            let snapshot = try await LocalGit.snapshot([selection], extraEmails: CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "", date: Date())
            print("Repository:", selection.name)
            print("Resolved author:", selection.email)
            print("Today’s matching commits:", snapshot.commits)
            return
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("focus-island-checks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appendingPathComponent("original").path
        let clone = root.appendingPathComponent("clone").path
        let empty = root.appendingPathComponent("empty").path
        let worktree = root.appendingPathComponent("worktree").path
        func run(_ args: [String]) async throws {
            let result = try await LocalGit.command("/usr/bin/git", args)
            guard result.status == 0 else { throw Failure(description: "Fixture command failed: \(result.text)") }
        }
        func configure(_ path: String) async throws {
            try await run(["-C", path, "config", "user.email", "me@example.test"])
            try await run(["-C", path, "config", "user.name", "Focus Island Test"])
        }
        try await run(["init", repo])
        try await configure(repo)
        try await run(["-C", repo, "-c", "commit.gpgsign=false", "commit", "--allow-empty", "-m", "My first commit"])
        try await run(["-C", repo, "-c", "commit.gpgsign=false", "commit", "--allow-empty", "--author=Other Author <other@example.test>", "-m", "Other author"])
        let original = try await LocalGit.inspect(repo)
        let first = try await LocalGit.snapshot([original], extraEmails: "", date: Date())
        try check(first.commits == 1, "The scanner must count my commit and exclude another author")
        print("PASS real Git author attribution")
        try await run(["clone", "--no-hardlinks", repo, clone])
        try await configure(clone)
        try await run(["-C", clone, "-c", "commit.gpgsign=false", "commit", "--allow-empty", "-m", "My second commit"])
        let duplicate = try await LocalGit.inspect(clone)
        let combined = try await LocalGit.snapshot([original, duplicate], extraEmails: "", date: Date())
        try check(combined.commits == 2 && combined.repositories.reduce(0) { $0 + $1.count } == 3, "Hashes shared across clones must count once in the total")
        let extras = try await LocalGit.snapshot([original], extraEmails: "other@example.test", date: Date())
        try check(extras.commits == 2, "Additional email identities must be applied")
        print("PASS cross-repository deduplication and additional identities")
        try await run(["init", empty])
        try await configure(empty)
        let emptySelection = try await LocalGit.inspect(empty)
        let zero = try await LocalGit.snapshot([emptySelection], extraEmails: "", date: Date())
        try check(zero.commits == 0, "Empty repositories must return a confirmed zero")
        print("PASS empty repository")
        try await run(["-C", repo, "worktree", "add", "-b", "linked", worktree])
        let linked = try await LocalGit.inspect(worktree)
        try check(linked.gitDirectory != original.gitDirectory && linked.commonDirectory == original.commonDirectory, "Worktree paths must resolve correctly")
        let shared = try await LocalGit.snapshot([original, linked], extraEmails: "", date: Date())
        try check(shared.commits == 1, "Shared worktree histories must not double count")
        print("PASS Git worktrees")
        let watcher = RepositoryWatcher()
        var notified = false
        watcher.watch([emptySelection]) { notified = true }
        try await run(["-C", empty, "-c", "commit.gpgsign=false", "commit", "--allow-empty", "-m", "First watched commit"])
        for _ in 0..<20 {
            if notified { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        watcher.stop()
        try check(notified, "Git metadata changes must trigger the live watcher")
        let after = try await LocalGit.snapshot([emptySelection], extraEmails: "", date: Date())
        try check(after.commits == 1, "A new commit must be visible in the next scan")
        print("PASS live metadata watcher and first-commit refresh")
        try await run(["-C", empty, "config", "--unset", "user.email"])
        let automatic = try await LocalGit.authorEmail(empty)
        try check(automatic != nil, "Resolve the identity Git uses when repository user.email is unset")
        try await run(["-C", empty, "-c", "commit.gpgsign=false", "commit", "--allow-empty", "-m", "Commit using resolved local identity"])
        let autoSnapshot = try await LocalGit.snapshot([emptySelection], extraEmails: "unrelated@example.test", date: Date())
        try check(autoSnapshot.commits >= 1 && autoSnapshot.detectedEmails[emptySelection.path] == automatic, "Count the actual local Git author identity even when the saved GitHub email differs")
        print("PASS generated local Git author identity with a different saved email")
        // A repository can enable signature display and choose an executable verifier.
        // Reproduce the old command's side effect, then prove the scanner suppresses it.
        let hostile = root.appendingPathComponent("signature-fixture").path
        try await run(["init", hostile])
        try await configure(hostile)
        let marker = root.appendingPathComponent("verifier-ran")
        let verifier = root.appendingPathComponent("verifier")
        try Data("#!/bin/sh\n/usr/bin/touch '\(marker.path)'\nexit 1\n".utf8).write(to: verifier)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: verifier.path)
        try await run(["-C", hostile, "config", "log.showSignature", "true"])
        try await run(["-C", hostile, "config", "gpg.program", verifier.path])
        let tree = try await LocalGit.command("/usr/bin/git", ["-C", hostile, "write-tree"])
        let stamp = Int(Date().timeIntervalSince1970)
        let commit = "tree \(tree.text.trimmingCharacters(in: .whitespacesAndNewlines))\nauthor Test <me@example.test> \(stamp) +0000\ncommitter Test <me@example.test> \(stamp) +0000\ngpgsig -----BEGIN PGP SIGNATURE-----\n ZmFrZQ==\n -----END PGP SIGNATURE-----\n\nSignature fixture\n"
        let object = root.appendingPathComponent("commit-object")
        try Data(commit.utf8).write(to: object)
        let hash = try await LocalGit.command("/usr/bin/git", ["-C", hostile, "hash-object", "-t", "commit", "-w", object.path])
        try check(hash.status == 0, "Signed fixture must be stored")
        try await run(["-C", hostile, "update-ref", "HEAD", hash.text.trimmingCharacters(in: .whitespacesAndNewlines)])
        _ = try await LocalGit.command("/usr/bin/git", ["-C", hostile, "log", "--all", "--format=%H"])
        try check(FileManager.default.fileExists(atPath: marker.path), "Unsafe baseline must reproduce verifier execution")
        try FileManager.default.removeItem(at: marker)
        let hostileSelection = try await LocalGit.inspect(hostile)
        let safe = try await LocalGit.snapshot([hostileSelection], extraEmails: "", date: Date())
        try check(safe.commits == 1 && !FileManager.default.fileExists(atPath: marker.path), "Scanner must count without executing the repository verifier")
        print("PASS repository-controlled verifier execution blocked (baseline reproduced)")
        do {
            _ = try await LocalGit.command("/usr/bin/yes", [], timeout: 5)
            throw Failure(description: "Unlimited output must be rejected")
        } catch let error as ServiceError {
            try check(error.message.contains("size limit"), "Output limit must fail explicitly")
        }
        let stubborn = try await LocalGit.command("/bin/sh", ["-c", "trap '' TERM; exec /bin/sleep 10"], timeout: 0.1)
        try check(stubborn.status == 124, "Timeout must stop a process that ignores SIGTERM")
        print("PASS bounded output and enforced timeout")
        let timed = try await LocalGit.command("/bin/sleep", ["10"], timeout: 0.1)
        try check(timed.status != 0, "Long-running processes must time out")
        print("PASS process timeout")
        let hostFolder = root.appendingPathComponent("host keys with spaces")
        try FileManager.default.createDirectory(at: hostFolder, withIntermediateDirectories: true)
        let knownHosts = hostFolder.appendingPathComponent("known_hosts")
        try Data(LocalGit.githubHostKey.utf8).write(to: knownHosts)
        let fingerprint = try await LocalGit.command("/usr/bin/ssh-keygen", ["-lf", knownHosts.path, "-E", "sha256"])
        try check(fingerprint.status == 0 && fingerprint.text.contains(LocalGit.githubHostFingerprint), "Bundled GitHub host key must match the reviewed official fingerprint")
        let sshConfig = root.appendingPathComponent("ssh-config")
        try Data("Host *\n ForwardAgent yes\n ForwardX11 yes\n LocalForward 12345 localhost:80\n PermitLocalCommand yes\n LocalCommand touch should-not-run\n ControlMaster auto\n ControlPath /tmp/should-not-reuse\n VerifyHostKeyDNS yes\n KnownHostsCommand echo alternate-key\n".utf8).write(to: sshConfig)
        let config = try await LocalGit.command("/usr/bin/ssh", ["-G", "-F", sshConfig.path] + LocalGit.sshArguments(knownHosts: knownHosts))
        try check(config.status == 0 && config.text.contains("stricthostkeychecking true") && config.text.contains("hostkeyalgorithms ssh-ed25519"), "SSH must enforce strict host checking and the pinned key algorithm")
        for setting in ["forwardagent no", "forwardx11 no", "clearallforwardings yes", "permitlocalcommand no", "controlmaster false", "verifyhostkeydns false", "preferredauthentications publickey"] {
            try check(config.text.contains(setting), "SSH must enforce \(setting)")
        }
        try check(!config.text.contains("should-not-reuse") && !config.text.contains("knownhostscommand ") && !config.text.contains("localforward "), "SSH must not reuse multiplexed sessions or configured tunnels")
        try check(config.text.contains(knownHosts.path) && config.text.contains("hostkeyalias github.com"), "Known-host paths with spaces and canonical host aliases must survive option parsing")
        try check(LocalGit.sshFailure("Permission denied (publickey).", status: 255, agentStatus: 1).contains("no unlocked keys"), "An empty agent needs a specific error")
        try check(LocalGit.sshFailure("Permission denied (publickey).", status: 255, agentStatus: 0).contains("GitHub rejected"), "A rejected loaded key needs a specific error")
        try check(LocalGit.sshFailure("Host key verification failed", status: 255, agentStatus: 0).contains("does not match"), "Host-key mismatches must be rejected")
        let environment = try await LocalGit.command("/usr/bin/printenv", ["FOCUS_ISLAND_CHECK"], environment: ["FOCUS_ISLAND_CHECK": "agent-fallback-check"])
        try check(environment.text.trimmingCharacters(in: .whitespacesAndNewlines) == "agent-fallback-check", "Agent environment overrides must reach child processes")
        print("PASS pinned host key, SSH option parsing, failure diagnostics, and agent environment")
        print("All local Git integration checks passed. No SSH connection was made.")
    }
}
