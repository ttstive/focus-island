# Changelog

## 0.2.1

- Prevent repository-configured signature-verification programs from executing during commit scans.
- Disable Git transport protocols and lazy object fetching during monitoring.
- Bound subprocess output to 8 MiB and enforce deadlines even when a process ignores graceful termination.
- Enforce SSH public-key authentication, disable forwarding and local commands, and prevent multiplexed sessions, DNS trust, or alternate known-host helpers from bypassing the pinned host-key check.
- Save activity history with owner-only directory/file permissions.
- Add regression fixtures reproducing verifier execution and testing the mitigations.

## 0.2.0

- Support Xcode, DataGrip, and other popular IDEs alongside VS Code.
- Choose individual editors in **Settings & connections → Editors & IDEs**.
- Add another IDE or beta edition by selecting its `.app` with **Add app…**.
- Request independent consent for each running IDE session. Enabling an editor does not grant tracking permission.
- Show the active IDE in the dashboard and floating island. Count only the foreground, accepted session toward one daily focus total.
- Include native screenshots of editor settings, Xcode and DataGrip session prompts, and their active islands in the README.

Existing features include active-time monitoring that excludes idle, sleep, and lock; local daily commit counts; optional GitHub SSH identity verification; saved author emails; a movable, resizable island; and a native app icon for Spotlight.

Focus history remains a combined daily total, without a per-IDE breakdown. The screenshots use illustrative data; they are not records of live Xcode or DataGrip sessions.
