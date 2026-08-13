# Delivery — CI, signing, versioning, release

How a commit becomes a build, and a build becomes a release.

- **When to read this:** setting up CI, changing signing, cutting a release, or answering "what
  build is that?"
- **Companions:** [SCHEMES.md](../.claude/notes/SCHEMES.md) (what each configuration *is*),
  [PROJECT.md](../.claude/notes/PROJECT.md) (targets and entitlements).

---

## What CI runs

| Repo | Pipeline |
|---|---|
| The app repo | lint → build every package → test every package → build iOS + macOS → (on tag) archive + upload |
| Any package in its own repo | lint → `swift build` → `swift test`, on iOS **and** macOS |

A package in its own repo never builds an app. If its CI needs a host app to pass, it is not
standalone and CLAUDE.md §9 is being violated.

---

## Versioning — three different numbers, don't conflate them

| Number | Example | Owned by | Changes when |
|---|---|---|---|
| **Marketing version** (`CFBundleShortVersionString`) | `2.4.0` | Product | A release ships to users |
| **Build number** (`CFBundleVersion`) | `1043` | CI | Every single build |
| **Package semver** | `1.2.0` | The two extracted repos | Their public API changes |

Rules:

- **Build number comes from CI, never from a committed file.** A committed counter guarantees merge
  conflicts and duplicate numbers. Use a monotonic CI run number, or the App Store Connect
  "latest build + 1".
- Build numbers are **monotonic across all four schemes**, never reset per configuration. TestFlight
  rejects a duplicate, and a reset makes "which build is newer" unanswerable.
- Marketing version is set in `Base.xcconfig` and reviewed like any other change.
- **Package semver is unrelated to app version.** NetworkKit `3.0.0` inside app `1.1.0` is normal.

### Hotfix

Branch from the release tag, not from `main`. Bump patch (`2.4.0` → `2.4.1`), cherry-pick forward
to `main` in the same PR that fixes it — never leave the fix only on the release branch.

---

## Code signing

**Use App Store Connect API keys, not personal Apple IDs.** A pipeline tied to one engineer's
account breaks the day they change their password, and two-factor prompts cannot be automated.

| Item | Where it lives |
|---|---|
| App Store Connect API key (`.p8`) | CI secret store — **never** in the repo |
| Signing certificates | CI keychain, provisioned at job start, discarded at job end |
| Provisioning profiles | Fetched per build, not committed |
| Team ID, bundle IDs | `.xcconfig`, committed ([SCHEMES.md](../.claude/notes/SCHEMES.md)) |

- DEV uses automatic signing locally. **TEST, BETA, and PROD use manual signing in CI** so the
  profile is explicit and diffable.
- macOS additionally needs **Developer ID + notarization** for direct distribution, and that path
  must be exercised from BETA onward — first attempting notarization at PROD is how releases slip.
- Rotate the API key on a schedule and when anyone with access leaves.

---

## Pipeline

### On every PR
```
lint (SwiftLint, SwiftFormat --lint)
  → swift build + swift test for every package
  → build iOS app (DEV)
  → build macOS app (DEV)
  → UI tests (TEST) on one simulator
```
Fast, no signing, no upload. If this is slow, split it — but never skip the package tests, they're
the cheapest signal in the repo.

### On merge to main
Adds: build TEST configuration, sign, upload to TestFlight internal. QA always has the latest main.

### On a release tag (`v2.4.0`)
```
archive BETA → notarize (macOS) → upload → TestFlight external
```
Then, after soak: `archive PROD → upload → submit`. **PROD is built from the same commit as the
BETA that soaked**, not rebuilt from a moved branch.

### dSYMs
Upload to the crash reporter on every archive, automatically. A crash report without symbols is a
crash report you can't act on, and dSYMs cannot be regenerated after the fact for a bitcode-less
archive.

---

## What CI must enforce, not just report

These are CLAUDE.md rules that are mechanically checkable. A rule only reviewed by humans decays:

| Rule | Check |
|---|---|
| §2.3 no raw user-facing string | grep for string literals in `Views/`; localization key parity |
| §2.7 no force-unwrap / `try?`-swallow / `fatalError` | SwiftLint rules, set to **error** |
| §2.8 no unjustified `@unchecked Sendable` | grep + require an adjacent comment |
| §2.10 no `#if DEBUG` in a feature package | grep `Packages/Features/` |
| §9 no network in unit tests | `testValue` presence test per key |
| [DONE.md](DONE.md) zero warnings | `-warnings-as-errors` on TEST/BETA/PROD |
| §1.1 iOS 17 floor | **`swift build` does NOT check this** — on a Mac it compiles only the macOS slice. `./Scripts/check.sh` typechecks each package against the iOS 17 SDK; the complete check is the app's iOS build |

Warnings-as-errors is **off for DEV** deliberately; a warning mid-edit shouldn't block a local run.

---

## Release checklist

- [ ] Version bumped in `Base.xcconfig`; build number from CI
- [ ] `Package.resolved` pinned to released tags of NetworkKit + ImageCache — no `edit` overrides
- [ ] All packages green standalone
- [ ] Zero warnings under strict concurrency
- [ ] `./Scripts/detect-toolchain.sh` clean — deployment targets at or below the installed SDK
- [ ] Localization complete for every shipping language ([LocalizationKit.md](modules/LocalizationKit.md))
- [ ] Screenshots regenerated **per language and per device class** — the most-missed release task
- [ ] What's New text localized
- [ ] Privacy manifests current, including required-reason APIs ([PROJECT.md](../.claude/notes/PROJECT.md))
- [ ] Force-update threshold set for the new version ([AppShell.md](modules/AppShell.md))
- [ ] dSYMs uploaded
- [ ] Phased release enabled, with the rollback plan written down before submitting

---

## Rollback

An App Store release cannot be un-shipped — that is the point of phased release and a remote kill
switch. Before submitting, know which it is:

1. **Phased release paused** — stops the bleed for new installs; does nothing for those who have it.
2. **Remote flag off** — the only fix that reaches installed copies. Requires the flag to exist
   *before* the release, which is why it belongs in the pre-submit checklist rather than the
   incident.
3. **Expedited review of a hotfix** — hours to days. Assume it, don't rely on it.
