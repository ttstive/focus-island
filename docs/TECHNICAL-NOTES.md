# Technical notes

A native macOS companion for intentional work. Live IDE tracking, daily local commit goals, SSH account verification, a SwiftUI dashboard, and a floating island below the menu bar. MIT licensed. No Electron, analytics, API tokens, backend, or third-party dependencies.

## Run

Requires macOS 14+ and Swift 6 (Xcode 16+ or compatible Command Line Tools).

```sh
./scripts/build-app.sh
open "dist/Focus Island.app"
```

For development: `swift run FocusIsland`. Open `Package.swift` in Xcode if preferred. Closing the dashboard keeps monitoring running. Use the waveform menu to reopen it, hide the island, pause, or quit. Launch at login is not configured automatically.

## Island placement and size

Drag the dotted grip at the left of the island to move it smoothly across monitors. Drag its lower-right resize grip (or native window edges) to adjust width; expand it first to adjust height too. Expanded and compact sizes are remembered separately, along with placement. Reconnecting displays keeps it within a visible screen. The menu bar’s **Reset island position and size** restores the default placement.

## Live IDE monitoring

Every enabled IDE launch presents a floating consent prompt: **Track this session** or **Not now**. Until explicitly accepted, neither focus time nor repository commit scans run. Declining skips that editor process without prompting again on app switches. Quitting and reopening the editor process requires a fresh choice; permissions are kept only in memory. Starting Focus Island while an enabled IDE is already running also asks. **Start session** in the dashboard lets you reconsider a declined session.

After consent, workspace activation/deactivation notifications update tracking immediately when you switch apps. A live clock samples every 250 ms in common run-loop modes, including while interacting with controls. The island and dashboard show hours/minutes/seconds. This is interactive monitoring, not hard real-time scheduling; macOS can delay callbacks under load.

Time counts only while an enabled IDE with its own accepted session is the frontmost app, the Mac is awake with an unlocked active session, and input idle time is less than 60 seconds. The idle cutoff truncates the final interval at the threshold. App switches close the prior active interval at notification delivery. No keystroke content, file names, source code, or window titles are collected. No Accessibility or Screen Recording permission is requested.

Intervals longer than five seconds are discarded to avoid counting sleep or process suspension. Reading without input for more than a minute pauses the timer. Daily/hourly buckets use the current local calendar and split at midnight; changing time zones can mix zones in history. State saves atomically every 15 seconds, on sleep, and on normal exit. A crash can lose up to 15 seconds. Damaged history is preserved and further writes stop for that launch.

IDE recognition uses an explicit catalogue of bundle identifiers and optional user-selected `.app` bundles. Matching normalizes case and uses exact identifiers, so helpers and vendor launchers do not match by prefix. Settings persist disabled identifiers and custom application names/identifiers, not application paths. Consent stays separate per process and is discarded when an IDE is disabled or quits. Totals are combined across IDEs; only one foreground application contributes at a time.

## GitHub identity via SSH

In Settings, choose **Connect with SSH key**. Focus Island invokes macOS OpenSSH with `BatchMode=yes`, `StrictHostKeyChecking=yes`, and a connection timeout. Your existing SSH configuration and agent handle the key. The app does not read, upload, copy, generate, or store private keys or passphrases. It recognizes GitHub’s successful authentication greeting (which intentionally exits with status 1) and remembers the verified username.

Add your public authentication key to GitHub and unlock its private key in your existing SSH agent. Focus Island pins GitHub’s [official Ed25519 host key](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints), fingerprint `SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU` (reviewed October 18, 2026). It writes that public key into a private temporary known-hosts file, enforces Ed25519 and strict checking, then removes the temporary file. Your `~/.ssh/known_hosts` and SSH configuration are not modified, and no first-use host-trust prompt is needed. A mismatched server key is rejected. A legitimate GitHub host-key rotation requires reviewing the official key and updating the app; do not disable verification.

GUI launches can inherit a different environment from Terminal. When `SSH_AUTH_SOCK` is missing or stale, Focus Island falls back to launchd’s SSH agent socket, while preserving a valid inherited custom agent. Keys requiring interactive unlock/touch may need preparation in Terminal. Authentication errors distinguish an empty agent, a rejected key, host-key mismatch, and network failures. If port 22 is blocked, configure `Host github.com` with `HostName ssh.github.com` and `Port 443` in your own SSH configuration; the same pinned GitHub key is enforced through the canonical host alias.

SSH runs only when you click Connect or Verify again. The remembered verification is not a persistent remote login session. Disconnect forgets it without modifying your keys or agent.

**SSH authenticates Git operations; it is not an authentication method for GitHub’s HTTP metrics API.** This version measures commits locally instead of claiming SSH access to that API. It uses no OAuth client ID, personal access token, or API request. Upgrading from the earlier prototype removes its own obsolete Keychain token and clears old API-derived commit snapshots so the two counting methods are not mixed. Other Keychain items and all SSH keys remain untouched.

## Live commit tracking

1. Open Settings and click **Add folders…**.
2. Select the local Git repositories you want to monitor. Multiple folders and Git worktrees are supported.
3. Git’s resolved author identity is detected automatically, including its generated local username/hostname address when `user.email` is unset. Enter your author emails (including GitHub noreply addresses) in Settings and click **Save emails** or press Return. **Done** also saves a valid draft before closing. Addresses are validated and stored locally; the saved list is displayed below the field.

Git metadata watchers trigger a refresh after a 150 ms debounce. A two-second fallback scan covers new refs or missed filesystem notifications. Scans run only during an accepted editor session and stop while paused or suspended. The daily scan can include commits made earlier that day; consent controls when monitoring runs, rather than limiting the daily metric to session-only commits. Git commands run off the main thread, with timeouts. No clone, fetch, push, or repository modification is performed. Local commit tracking works offline and independently of optional SSH verification.

Counts include unique commit hashes reachable through the selected repositories’ refs, authored with Git’s resolved author identity or the additional saved email identities, and with a **committer timestamp within the current local day**. Unpushed commits count. The same hash in multiple repositories counts once in the total; per-repository rows can therefore add up to more than the total. Removing refs, rebasing, or amending may change the count. These are currently reachable commits, not a permanent audit of every commit ever created. A shallow clone only includes its available history. Selected repositories can be hosted anywhere; the count is explicitly local rather than a GitHub contribution-calendar total.

SSH verifies the account identity; it does not establish that a Git author email belongs to that account. Explicit email filtering avoids counting all collaborators’ work. If a selected repository is inaccessible or Git cannot resolve an author email, a visible error keeps the previous snapshot rather than silently reporting an incomplete zero. A dash means no configured data; zero means a successful scan found none.

Only today is refreshed; past commit counts are the last observed snapshots from those days. Changing repositories or email filters updates today, not old snapshots. The History tab shows a week and exports all recorded history as JSON. After 8 pm, the island expands once on a day with tracked focus to show the daily recap while the app is running.

Commit volume is a personal signal, not a measure of code quality or productivity.

## Privacy and storage

- Activity: `~/Library/Application Support/FocusIsland/days.json` (daily/hourly totals and commit counts).
- Preferences: goals, verified SSH username, enabled editor identifiers, custom application names/identifiers, selected local repository paths, and author emails in macOS user defaults.
- SSH: handled by system OpenSSH and your existing agent; the app stores no credentials.
- Network: an SSH verification connection to GitHub, only on explicit user action. Local tracking sends no repository data.
- Exports include daily/hourly totals and commit counts, never repository paths, emails, keys, or credentials.

## Development

```sh
swift run FocusCoreChecks
./scripts/check-localgit.sh
./scripts/build-app.sh
```

The dependency-free checks run with Command Line Tools and Xcode. They cover eligibility, midnight and daylight-saving boundaries, sleep gaps, persistence, email filtering, deduplication, SSH greeting parsing, and the live timer. Integration checks create disposable Git repositories to verify the actual local scanner.

`FocusCore` contains activity, per-process session consent, and commit rules. `FocusIsland` contains AppKit lifecycle/panels, SwiftUI/Charts views, workspace observation, JSON persistence, system SSH verification, and Git metadata watchers. No third-party packages are needed.

The build script creates an ad hoc signed app in `dist/`. Public distribution still requires Developer ID signing and notarization. No public repository or release is created by the local build.

Manual checks: foreground/background IDE transitions and switches between two consented IDEs, idle cutoff, lock/unlock, sleep/wake, overnight tracking, first commit in an empty repository, worktrees, commit/amend/rebase, multiple cloned repositories, invalid/missing author emails, trusted/untrusted SSH hosts, and display changes. Live SSH verification requires your configured key and explicit user action.

## Contributing

Keep tracking local, account verification optional, and metrics supportive. Include reproduction and validation notes in pull requests. Never commit credentials, personal paths, or activity exports. See [LICENSE](../LICENSE).
