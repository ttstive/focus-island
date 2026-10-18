# Contributing

Thanks for helping make Focus Island useful and calm.

## Local setup

Use macOS 14+ and Swift 6+. Open `Package.swift` in Xcode or work from Terminal:

```sh
swift run FocusIsland
swift run FocusCoreChecks
./scripts/check-localgit.sh
./scripts/build-app.sh
```

The integration checks use disposable local repositories and make no SSH connections. Never run destructive test commands against a real project.

## Pull requests

Describe the user-visible problem, the resulting behavior, and how you checked it. Keep changes focused. Include interface screenshots for visual changes, using demo data.

Preserve these principles:

- Session consent is explicit, temporary, and off by default.
- Activity stays local; GitHub identity verification remains optional.
- Never record keystroke content, source code, or private keys.
- Keep unknown metrics distinct from a confirmed zero.
- Treat commit volume as context, not a score of a person’s productivity.

## Documentation and screenshots

Onboarding lives in `docs/GETTING-STARTED.md`; counting semantics and storage details live in `docs/TECHNICAL-NOTES.md`.

To regenerate native interface screenshots with illustrative data:

```sh
swift build --product FocusIsland
"$(swift build --show-bin-path)/FocusIsland" --export-screenshots "$PWD/docs/images"
```

Inspect every image before committing. Do not include account emails, repository paths, real activity exports, credentials, `.build`, or `dist` artifacts in the source tree.

## Reporting issues

Provide your macOS and Swift versions, reproduction steps, expected behavior, and the app’s current status/error. Redact personal information from logs and screenshots. Avoid posting security-sensitive details in a public issue.
