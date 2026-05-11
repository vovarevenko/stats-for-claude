# Stats for Claude

> Single-repo macOS app. Living document — when an invariant in this file
> goes out of date, fix the file in the same commit that broke it.

---

## What This Is

A native macOS menu-bar app that surfaces Claude Code usage:

- 5-hour session and weekly utilisation percentages.
- Per-project breakdown of monthly cost (subscription price amortised by
  output-token share).
- Updates silently every minute (API) and every five minutes (JSONL parse).

Strictly local: reads `~/.claude/projects/*.jsonl` via a security-scoped
bookmark and calls `https://api.anthropic.com/api/oauth/usage` with the
OAuth token from Claude Code CLI's Keychain. Nothing is ever uploaded.

The widget target was excised before this iteration shipped; it returns in
v2 and the model layer (`WidgetSnapshot`, `AppGroupStore.save`) is already
in place for that.

---

## Architecture

### Modules — direction of dependency is one-way

```
StatsForClaude          (app target — SwiftUI views, @main, scenes)
        │
        ▼
StatsForClaudeAppKit    (view-models, app-level stores)
        │
        ▼
StatsForClaudeKit       (models, parsers, IO clients, formatters, logging)
```

`StatsForClaudeAppKit` is a separate library target inside the same SPM
package so `swift test` can exercise `MenuBarViewModel` and `SettingsStore`
with `@testable import`. The app target is intentionally thin — adding
business logic to it is a smell; lift it down a layer.

### IO surface — protocol-fronted

| Protocol | Production impl | Used by |
| --- | --- | --- |
| `UsageFetching` | `UsageAPIClient` | `UsageStore.refreshAPI` |
| `KeychainCredentialsReading` | `KeychainStore` (`Claude Code-credentials`) | `UsageStore.resolveAccessToken` (fallback only) |
| `BookmarkResolving` | `BookmarkStore` | `UsageStore.refreshJSONL`, `MenuBarViewModel.needsOnboarding` |
| `CredentialsCacheStoring` | `KeychainCredentialsCache` (own service) | `UsageStore.resolveAccessToken` |
| `TokenRefreshing` | `ClaudeOAuthClient` | `UsageStore.resolveAccessToken`, `.refreshAndRetry` |
| `SettingsPersisting` | `SettingsStore` | `MenuBarViewModel.updateSettings` |

Everything that reaches the network, Keychain, file system, or
`UserDefaults` goes through one of these protocols. **New IO must do the
same** — never instantiate concrete IO types inside business logic.

### Refresh cadences

- API: 180 s. Anthropic rate-limits `/api/oauth/usage` to ~1 request per
  2 min per OAuth session (shared with the Claude Code CLI's own usage).
  60 s caused every other tick to 429 and feed the cooldown loop; 120 s
  sat right at the limit; 180 s leaves 60 s of headroom for concurrent
  CLI activity.
- JSONL: 300 s (heavy, file enumeration).

Two independent timers in `MenuBarViewModel.start()`. Don't merge them —
running the JSONL parser every minute is what the previous version did and
that was wrong.

### State model

`UsageStore` is `@Observable @MainActor`. `apiInFlight` and `jsonlInFlight`
are private flags; `isLoading` is a computed OR projection for UI binding.

`OverviewTabView` derives a four-case `State` enum
(`needsOnboarding` / `loading` / `unavailable` / `ready`) from the VM
instead of letting individual subviews render zero values when there's no
data. Reuse this pattern for new screens.

---

## Tech Stack

| Component | Decision |
| --- | --- |
| UI | SwiftUI; AppKit only for `NSOpenPanel`, `NSApp`, `NSViewRepresentable` |
| State | `@Observable` (Observation framework), not `@ObservableObject` |
| Concurrency | Strict (`SWIFT_STRICT_CONCURRENCY: complete`); structured `Task`, `MainActor.run` for re-entry |
| Logging | `os.Logger` under subsystem `org.revenko.stats-for-claude` |
| Persistence | Keychain (token cache + Claude Code creds), App Group `UserDefaults` (cached API response, snapshot, settings mirror), security-scoped bookmark |
| Localization | `Localizable.xcstrings` (en + ru); referenced from `project.yml` and `SWIFT_EMIT_LOC_STRINGS=YES` extracts new keys at build time |
| Parsing | `JSONDecoder.iso8601WithOptionalMillis()` — handles both API (millis) and JSONL (no millis) date strings |
| Tests | Swift Testing (`@Test`, `#expect`, `#require`) — not XCTest |

**Why protocol-fronted IO instead of actors:** the IO layer is thin and the
view-models are already `@MainActor`. Promoting stores to actors buys
nothing and complicates SwiftUI binding.

**Why `@unchecked Sendable` on stores:** `UserDefaults` and the Security
framework are documented thread-safe but not annotated `Sendable`. Every
such conformance carries a comment justifying it; new ones must too.

---

## Repository Structure

```
stats-for-claude/
  project.yml                    ← xcodegen source of truth
  Makefile                       ← gen / test / lint / format / clean
  .swiftlint.yml                 ← root config; nested override in Tests/
  .swiftformat
  .github/workflows/ci.yml
  PROMPT.md                      ← historical refactor brief (May 2026)
  CLAUDE.md                      ← this file

  StatsForClaude/                ← app target
    StatsForClaudeApp.swift      ← @main, scenes, MenuBarLabelView
    Dashboard/                   ← TabView, Overview, History, Settings tabs
    MenuBar/                     ← popover and HIToolbox window glue
    Onboarding/                  ← welcome → success/failed phases
    Settings/                    ← form, Claude directory picker
    Resources/
      Info.plist
      Localizable.xcstrings
      PrivacyInfo.xcprivacy
      StatsForClaude.entitlements
      Assets.xcassets/           ← AccentColor + AppIcon

  StatsForClaudeKit/
    Package.swift                ← two products: StatsForClaudeKit, StatsForClaudeAppKit
    Sources/
      StatsForClaudeKit/
        API/                     ← UsageAPIClient, UsageAPIResponse, CachedAPIResponse
        Formatters/              ← TokenFormatter, CountdownFormatter
        Limits/                  ← LimitCalculator, PlanLimits
        Logging/                 ← Log.make(_:)
        Models/                  ← AppSettings, SessionRecord, WidgetSnapshot, etc.
        Parser/                  ← JSONLParser, ProjectPathDecoder, JSONDecoder+ISO8601
        Pricing/                 ← Pricing, CostCalculator
        Store/                   ← AppGroupStore, BookmarkStore, KeychainStore, TokenCache, UsageStore
      StatsForClaudeAppKit/
        MenuBarViewModel.swift   ← public; DashboardTab here
        SettingsStore.swift      ← SettingsPersisting
    Tests/
      .swiftlint.yml             ← test-folder rule overrides
      StatsForClaudeKitTests/    ← kit unit tests + golden Codable fixtures
      StatsForClaudeAppKitTests/ ← VM/store fakes + state transitions
```

---

## Identifiers

| Slot | Value | Where it must match |
| --- | --- | --- |
| Bundle ID (app) | `org.revenko.stats-for-claude` | `project.yml`, App Store Connect |
| Apple Team ID | `4DDDLR4X3X` | `project.yml`, both entitlements files |
| App Group ID | `4DDDLR4X3X.group.org.revenko.stats-for-claude` | `AppGroupStore.appGroupID`, app entitlements (and future widget entitlements) |
| Token-cache Keychain service | `org.revenko.stats-for-claude.token-cache` | `KeychainTokenCache.defaultService` only |
| Logger subsystem | `org.revenko.stats-for-claude` | `Log.subsystem` |

When Bundle ID changes, **all five rows above** have to move together. This
is one reason tests use ephemeral `UserDefaults(suiteName:)` and not the
real App Group container.

---

## Entitlements

App target needs all of:

- `com.apple.security.app-sandbox`
- `com.apple.security.files.user-selected.read-only` — for `~/.claude` bookmark.
- `com.apple.security.files.bookmarks.app-scope` — for storing the bookmark.
- `com.apple.security.network.client` — for Anthropic API.
- `com.apple.security.application-groups` — single entry, see table above.

**Don't** add `files.all`, `apple-events`, or audio/camera entitlements.
The app doesn't need them and any extra entitlement raises the App Review
bar.

---

## Conventions

### Logging

- Production code: `os.Logger`, never `print`.
- One logger per file/category: `private let log = Log.make("Component")`.
- Levels: `.error` for handled failures, `.info` for lifecycle, `.debug` for
  trace.
- **Never** log tokens, bookmark URLs, raw API bodies, or parsed message
  contents. Use `privacy: .public` only for error descriptions.

To inspect logs:

```bash
log stream --predicate 'subsystem == "org.revenko.stats-for-claude"' --level debug
```

### Localization

Every user-facing string lives in `Localizable.xcstrings` with an `en`
value (and ideally `ru`). Use `String(localized: "key")` for free-form text
and `Text(LocalizedStringKey)` inside SwiftUI when a single literal works.

`Text("…")` with a String **variable** is *not* localized — wrap the source
string with `String(localized:)` first or pass `LocalizedStringKey`.

VoiceOver labels use the `a11y_*` key prefix and a `.combine`d
`.accessibilityElement` modifier. Decorative SF Symbols are
`.accessibilityHidden(true)`.

### Error handling

- `try?` is reserved for cases where we *genuinely* don't care
  (e.g. invalidating a stale bookmark, encoding for non-critical caches).
- Anywhere a failure should reach the user, use `do/catch` and log via the
  module's `Logger`.
- `APIError` is `LocalizedError`; add cases instead of stringly-typed
  errors.

### Magic numbers

Named constants on the type that owns them. Live examples to mirror:

- `MenuBarViewModel.apiRefreshInterval`, `.jsonlRefreshInterval`
- `CachedAPIResponse.staleAfter`
- `MenuBarPopoverView.stalenessHintThreshold`
- `LimitCalculator.weekDuration`

### Wire format

Codable models in `Tests/StatsForClaudeKitTests/ModelsCodableTests.swift`
are golden fixtures. Editing them = changing on-disk format for users.
**Don't update fixtures casually**; if a wire change is intentional, ship
it as its own commit with a migration path and a `BREAKING CHANGE` footer.

---

## Testing

- Run with `make test` (= `cd StatsForClaudeKit && swift test`).
- Two test bundles: `StatsForClaudeKitTests` (pure logic + Codable goldens)
  and `StatsForClaudeAppKitTests` (VM/store transitions through fakes in
  `Fakes.swift`).
- Each App Group test creates a unique `UserDefaults(suiteName:)` and tears
  it down via `removePersistentDomain` in `defer`.
- Two test seams (`UsageStore.refreshAPIInternal`, `.refreshJSONLInternal`)
  are `internal` on purpose — drive them directly from tests instead of
  polling the spawned `Task`.
- Performance budgets live in `PerformanceTests.swift` with
  `.timeLimit(.minutes(1))` — meant to catch O(n²) regressions, not
  microsecond drift.
- **Adding a new IO dependency** to `UsageStore` or a view-model: protocol
  it, default-init it to the production impl, fake it in `Fakes.swift`,
  cover the state transition.
- **If a refactor makes a tested member `private` and `@testable import`
  breaks**, raise the visibility to `internal` (or `package`) — don't
  delete the test. Two such seams already exist
  (`UsageStore.refreshAPIInternal`, `.refreshJSONLInternal`).
- **Don't "fix" a red test by editing it.** A failing test is either a
  real regression or a test that captured the wrong contract; both
  outcomes need the human, not a quick rewrite.
- **Swift Testing parameterized arguments — hoist to typed constants.**
  When `@Test(arguments: [...])` contains tuples whose elements are
  non-literal expressions (initializer calls like `TimeInterval(...)`,
  integer arithmetic, etc.), the macro expansion blows the type-check
  budget ("the compiler is unable to type-check this expression in
  reasonable time"). Lift the array out to a `static let cases:
  [(T, U)] = [...]` and pass it by name. `CountdownFormatterTests`
  has the canonical pattern.

---

## Build & Dev Workflow

| Want to | Run |
| --- | --- |
| Generate `.xcodeproj` after adding/removing files | `make gen` |
| Run all unit tests | `make test` |
| Lint | `make lint` (needs `brew install swiftlint`) |
| Auto-format | `make format` (needs `brew install swiftformat`) |
| CI-style check (no writes) | `make format-check && make lint` |
| Clean build artefacts | `make clean` |
| Open the app | `open StatsForClaude.xcodeproj` → Cmd+R |

`make gen` is **only** needed when the file list changes. Day-to-day
edits: run from Xcode with Cmd+R.

The Xcode project file is generated and committed (xcodegen). The
localization catalog is referenced via an explicit
`StatsForClaude/Resources/Localizable.xcstrings` entry under `sources:` in
`project.yml` with `buildPhase: resources`. If the project file looks
wrong, regenerate before debugging.

### After Making Changes — What to Rebuild

| Changed | What gets rebuilt |
| --- | --- |
| `StatsForClaudeKit/Sources/StatsForClaudeKit/**` | Both kit modules + app, via SPM |
| `StatsForClaudeKit/Sources/StatsForClaudeAppKit/**` | AppKit module + app |
| `StatsForClaude/**` | App target only |
| `project.yml` / new `.swift` files | `make gen` first, then build |
| `Localizable.xcstrings` | Picked up automatically; no `make gen` |
| `Resources/*.entitlements`, `Info.plist`, `PrivacyInfo.xcprivacy` | App rebuild + re-sign |

---

## Conventional Commits

Format: `<type>(<scope>): <imperative subject ≤72 chars>`.

`type` ∈ {`feat`, `fix`, `refactor`, `chore`, `test`, `docs`, `style`,
`perf`, `build`, `ci`, `i18n`, `a11y`}.

`scope` ∈ {`kit`, `app`, `parser`, `api`, `store`, `ui`, `settings`,
`onboarding`, `build`, `ci`, `deps`, `security`}.

Body explains **why**, not what — the diff already shows what. Use HEREDOC
for multi-line messages so newlines survive:

```bash
git commit -m "$(cat <<'EOF'
refactor(kit): one-line summary

Body with paragraphs, ~72 chars wrap.
EOF
)"
```

Hard rules:

- **No `Co-Authored-By: Claude` trailer.**
- No `--no-verify`, no `--amend` for pushed commits, no `push --force` to
  the default branch (`dev` in this repo).
- Stage by name (`git add path/to/file`), never `-A` or `.` — keeps
  `.env`, build artefacts, screenshots out of commits.
- Wire-format breaking change → add `BREAKING CHANGE:` footer and ship a
  migration in the same commit.
- One atomic change per commit. `swift test` must stay green at every
  commit on the branch.

If a pre-commit hook fails, fix the cause and create a **new** commit; do
not amend. Amend on a hook-failed commit modifies the previous one and can
delete in-flight work.

### When to stop and ask the human

- Any change to a Codable wire format (the models in `ModelsCodableTests`
  golden fixtures).
- Removing a `public` API, even if it has no in-tree callers.
- Picking a license, choosing telemetry SDKs, changing distribution
  channels (App Store vs notarised `.dmg`).
- Anything that materially deviates from the plan agreed for the current
  session.

### When to just do it

- Renaming internal identifiers, extracting constants, replacing `print`
  with `Logger`, fixing lint warnings.
- Adding tests against an already-protocol-fronted IO seam.
- Tightening `try?` to `do/catch` + log when the failure is user-visible.

---

## CI

`.github/workflows/ci.yml` runs two jobs on `macos-15`:

1. `swift test --parallel` (with SPM build cache).
2. `swiftlint --strict` + `swiftformat --lint .`.

`xcodebuild` of the app target is **not** in CI yet — the app deploys to
macOS 26 and the runner image is on Xcode 16. When the GitHub `macos-26`
runner ships, add a third job calling `xcodebuild -scheme StatsForClaude
-destination 'platform=macOS' build`.

---

## Pre-Commit Mental Checklist

Before every commit:

- [ ] `swift test` green.
- [ ] `xcodebuild build` of the app target succeeds (only if Swift sources
      changed).
- [ ] `make format-check && make lint` pass.
- [ ] Commit message follows the format above; body explains *why*.
- [ ] No new `print()`, no new `try?` swallowing user-visible failures, no
      new `@unchecked Sendable` without a comment.
- [ ] If you added a new user-facing string: it's in
      `Localizable.xcstrings` with `en` and ideally `ru`.
- [ ] If you added a new IO dependency to a store/VM: it's protocol-fronted
      and faked in tests.

If any of these doesn't hold, fix it in the same commit. Don't open a PR
saying "lint will be fixed in a follow-up" — there are no follow-ups.

---

## Architectural Pitfalls

- **`@unchecked Sendable` without a comment is a smell.** Three stores
  carry it (`AppGroupStore`, `BookmarkStore`, `KeychainStore`,
  `SettingsStore`) and each comment cites the docs that justify it. New
  ones must do the same.
- **Don't read `Claude Code-credentials` from a hot path.** macOS shows an
  ACL prompt the first time, and the CLI rotates its Keychain item on every
  token refresh — rotation resets the ACL, so even "Always Allow" stops
  helping after one OAuth cycle. The resolve chain is: in-memory creds → our
  `KeychainCredentialsCache` (with `ClaudeOAuthClient` refresh when the
  access token is expiring) → `Claude Code-credentials` as last resort. Keep
  step 3 to a one-time event; never add a code path that reaches the CLI
  Keychain on a steady-state refresh.
- **OAuth refresh against `console.anthropic.com/v1/oauth/token`.** Client
  ID `9d1c250a-e61b-44d9-88ed-5944d1962f5e` matches the Claude Code CLI.
  When `UsageAPIClient` returns 401, `UsageStore.refreshAndRetry` does one
  refresh-and-retry before invalidating the cache; don't short-circuit that
  retry, otherwise a transient 401 evicts good credentials and forces a CLI
  Keychain read on the next tick.
- **429 has a shared cooldown across both Anthropic endpoints.** Anthropic
  rate-limits `/api/oauth/usage` and `/v1/oauth/token` from the same bucket.
  `UsageStore.cooldownUntil` suppresses **both** for the duration of one
  back-off window. `Retry-After ≤ 0` is treated as "no useful guidance" and
  the schedule `[60, 120, 240, 480, 960, 1800]` is used instead (indexed by
  `consecutive429Count`). A 429 from OAuth refresh **never invalidates the
  credentials cache** — it just enters cooldown, so the slightly-expired
  token survives until the limit lifts and we never fall through to the CLI
  Keychain (which would re-prompt).
- **App Sandbox + bookmark lifecycle.** A URL resolved from a security
  bookmark is only readable inside
  `startAccessingSecurityScopedResource() … stopAccessingSecurityScopedResource()`.
  `UsageStore.loadJSONL` sets `securityScoped: false` for the onboarding
  path (URL is fresh from `NSOpenPanel`) and `true` for the steady-state
  path; new code that touches `~/.claude/` must follow that pattern.
- **`ISO8601DateFormatter` is non-Sendable.** Use the shared decoder
  factory `JSONDecoder.iso8601WithOptionalMillis()` — don't roll your own
  inline; the `nonisolated(unsafe)` formatters live in
  `JSONDecoder+ISO8601.swift`.
- **App Group container is shared with future widget v2.** Don't write
  anything into it that the widget shouldn't see, even if no consumer
  exists yet.
- **macOS 26: `Text + Text` is deprecated.** Use
  `Text("\(Text(part).foregroundStyle(...))rest")` interpolation.

---

## Testing the App End-to-End

When something looks wrong on screen, run through this in order:

1. `log stream --predicate 'subsystem == "org.revenko.stats-for-claude"' --level debug`
2. Confirm the right binary is running:
   `ps aux | grep StatsForClaude | grep -v grep` — pid + executable path
   should be in `~/Library/Developer/Xcode/DerivedData/StatsForClaude-*/`,
   not `/Applications/` (the latter is a stale prebuilt copy).
3. Reset state for clean-launch testing:
   ```bash
   security delete-generic-password -s "org.revenko.stats-for-claude.token-cache" -a "claude-oauth-v2"
   security delete-generic-password -s "org.revenko.stats-for-claude.token-cache" -a "claude-oauth" 2>/dev/null
   defaults delete org.revenko.stats-for-claude 2>/dev/null
   defaults delete 4DDDLR4X3X.group.org.revenko.stats-for-claude 2>/dev/null
   ```
4. Quit (`⌘Q` from menu — closing the dashboard window doesn't quit a
   `LSUIElement` app) and relaunch from Xcode.

---

## Pre-Release Checklist

Path to v1.0.0 on the App Store. Items are listed in roughly the order
they unblock each other; finish a row, delete it from this list in the
same commit (don't mark `[x]`).

- [ ] Apple Developer Program enrollment ($99/year).
- [ ] App Store Connect: Paid Applications Agreement, tax (W-8BEN as
      non-US individual), banking.
- [ ] App ID registered in Developer Portal with required capabilities.
- [ ] Mac App Distribution certificate issued.
- [ ] App Store Connect app record created (name, bundle ID, SKU,
      primary language).
- [ ] Privacy Policy URL set in App Store Connect: `https://vovarevenko.github.io/stats-for-claude/privacy.html`.
- [ ] First archive uploaded; Export Compliance answered.
- [ ] TestFlight build distributed to internal testers (and external if
      needed, after Beta App Review).
- [ ] Pricing configured in App Store Connect: $5.00 / €6.00.
- [ ] App Privacy questionnaire filled (no data collection).
- [ ] Screenshots 2880×1800 in `docs/screenshots/`, uploaded.
- [ ] Hero screenshot `docs/screenshots/hero.png` referenced from README.
- [ ] Architecture diagram (SVG, replaces ASCII fallback in README).
- [ ] App Store metadata (description, keywords, support URL, category
      Developer Tools, age 4+).
- [ ] App Review notes — explain `~/.claude/` access, Keychain
      credentials read, Anthropic API usage, demo token if reviewer needs
      one.
- [ ] `CHANGELOG.md` — Keep-a-Changelog format; first entry `1.0.0` with
      key features. Written just before Submit.
- [ ] Submit for App Review; respond to reviewer questions.
- [ ] Generate promo codes for colleagues after approval.

---

## Backlog

Items previously evaluated and intentionally deferred:

- **Widget v2** — small + medium families reading `WidgetSnapshot` from
  the App Group, plus snapshot tests via `pointfreeco/swift-snapshot-testing`.
  Model layer is already in place; just needs view + entitlements +
  target.
- **Real-data fixtures** — obfuscated samples from `~/.claude/projects/`
  in `Tests/StatsForClaudeKitTests/Fixtures/real_*/` for edge cases the
  synthetic JSONL doesn't cover.
- **Backward-compat fixtures** — the moment any wire format
  (`AppSettings`, `WidgetSnapshot`, `SessionRecord`) is changed, add a
  golden fixture of the *old* version to `ModelsCodableTests` plus a
  decode-via-migration test.
- **macOS 26 CI runner** — add `xcodebuild` of the app target as a third
  job once GitHub ships `macos-26`.
- **Distinguish "no active 5-hour session" from "0%."** Anthropic's
  `/api/oauth/usage` returns `five_hour: null` when the user hasn't made a
  request in the last 5 hours. Right now `sessionPercent` becomes `0` and
  the menu bar reads `0% · X%` — indistinguishable from a session that is
  open and idle. Render `—` (em-dash) in both the menu bar label and the
  Overview header when `apiResponse?.fiveHour == nil`. Mirror the same
  rule for the 7-day window even though `sevenDay: null` is unlikely in
  practice.
