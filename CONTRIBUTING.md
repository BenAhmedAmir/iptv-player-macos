# Contributing

Thanks for your interest in the project. Issues and pull requests are both
welcome.

## Getting set up

```bash
scripts/fetch_vlckit.sh      # one-time: downloads VLCKit into vendor/
scripts/build_app.sh debug
scripts/run_tests.sh
```

You need macOS 13+, Apple Silicon and the Swift 5.9 toolchain. `vendor/` and
`.build/` are deliberately untracked; never commit either.

## Before opening a pull request

- `scripts/run_tests.sh` passes.
- The app builds and launches: `scripts/build_app.sh debug`.
- New model or service behaviour comes with tests in `Tests/TestRunner.swift`.
  The suite compiles the model and service layers standalone, so anything
  reachable without SwiftUI is testable.
- No credentials, portal URLs, playlists or personal stream data in the diff,
  including in test fixtures. Use `example.com` hosts and dummy values.

## Code style

Match the surrounding code. A few conventions the codebase already follows:

- MVVM: views stay declarative, logic lives in the view model, I/O lives in a
  service.
- `// MARK:` sections to divide types into public API / internals.
- Comments explain *why*, not *what* — particularly where the reason is a
  platform quirk. The Keychain memoization and the in-place bundle update in
  `build_app.sh` are both load-bearing workarounds, and both say so in a
  comment. Keep that habit.

## Reporting bugs

Please include:

- macOS version and hardware (e.g. macOS 15.1, M2 Pro)
- Source type: Xtream Codes, M3U file or M3U URL
- What you expected and what happened
- For playback issues: the container and codec if you know them, and whether
  the stream is live or VOD — the two paths use different engines (AVPlayer vs
  VLCKit), so this narrows it down immediately

Do **not** paste your portal URL, username or password into an issue. Redact
them.

## Scope

The project is a player. Features that make it a better player are in scope.
Anything that bundles, aggregates, scrapes or distributes channel lists or
stream sources is not, and will be declined.
