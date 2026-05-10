# Stats for Claude

A native macOS menu-bar app that surfaces your Claude Code usage.

<!-- TODO: hero screenshot in docs/screenshots/hero.png -->

## What it does

- **5-hour session and weekly utilisation** — see how much of your plan you've burned through, at a glance from the menu bar.
- **Per-project cost breakdown** — your monthly subscription price amortised across projects by output-token share.
- **Silent background refresh** — every minute for the API, every five minutes for `~/.claude/projects/*.jsonl`. No manual reloads.

## Requirements

- macOS 26 (Tahoe) or later
- Apple Silicon or Intel
- Claude Code CLI installed and signed in (Stats for Claude reads the OAuth token from the system Keychain)

## Install

- App Store: _coming soon_ — sign up for TestFlight via the link on the project page when available.
- From source: see [Build from source](#build-from-source) below.

## Privacy

Stats for Claude is **strictly local**:

- Reads `~/.claude/projects/*.jsonl` via a security-scoped bookmark you grant in onboarding.
- Calls `https://api.anthropic.com/api/oauth/usage` with the OAuth token from Claude Code CLI's Keychain entry.
- **Nothing else leaves your machine.** No analytics, no crash reporting, no telemetry.

The source is open so you can verify this yourself — this is the main reason the repository is public. See the [Architecture](#architecture) section for where to start reading.

## Build from source

```sh
brew install xcodegen swiftlint swiftformat
make gen     # generate StatsForClaude.xcodeproj from project.yml
make test    # run unit tests
open StatsForClaude.xcodeproj
```

In Xcode: select the `StatsForClaude` scheme → Cmd+R.

Code-signing for personal builds works with your own Apple ID (free provisioning); a paid Apple Developer Program account is only needed to ship via the App Store or TestFlight.

## Architecture

Three modules, one-way dependency:

```text
StatsForClaude          (SwiftUI app target)
        │
        ▼
StatsForClaudeAppKit    (view-models, app-level stores)
        │
        ▼
StatsForClaudeKit       (models, parsers, IO clients, formatters)
```

Full conventions, IO boundaries, and architectural pitfalls live in [`CLAUDE.md`](CLAUDE.md).

<!-- TODO: architecture diagram in docs/screenshots/architecture.svg -->

## License

[PolyForm Noncommercial 1.0.0](LICENSE) — **source-available, not open source**. You may read, audit, build for personal/non-commercial use, and contribute. Commercial use and redistribution of a competing build are not permitted.

If you want to use Stats for Claude commercially, contact the author.

## Author

Vova Revenko · [@vovarevenko](https://github.com/vovarevenko)
