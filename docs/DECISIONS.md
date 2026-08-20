# Decisions

Settled choices. **Read this before asking a CLAUDE.md §0 question** — it may already be answered.
Add a row when a §0 decision is made; never remove one.

---

## Settled — follow these, don't re-derive

| Scope | Decision | Why | Detail |
|---|---|---|---|
| Stack | **Acquired, not assumed** — `Scripts/detect-toolchain.sh`. Project wins; machine fills gaps; the remainder is asked at init with machine-derived options, latest recommended | A baseline nobody can build with is worse than none, and a machine upgrade must not silently change what the app supports or what it is written in. §1's values are this repo's answers, not the tool's defaults | §1 |
| Deployment targets | iOS/iPadOS **17.0**, macOS **26.6** | Asymmetric by intent; shared code compiles to the iOS 17 floor | §1.1 |
| macOS strategy | Native SwiftUI target, **no Mac Catalyst** | Catalyst compromises menu bar, windowing, toolbars | §1 |
| Project files | **SPM only** | No second build-system-of-record | [REPO.md](REPO.md) |
| Repository | **Single repo**; only `GenericArch-NetworkKit` + `GenericArch-ImageCache` extracted | Feature packages change most, have one consumer, and would cost a tag + app bump each | §4.1–4.2 |
| Extracted packages | **Standalone, zero-dependency** — no `Core` import | SPM resolves a git dep from its own root manifest; map at our boundary like a vendor | §4.2, §7 |
| Extraction test | All three must hold: product-independent · actually reused · stable | Otherwise keep it local — local costs nothing | §4.2 |
| Seed packages — **closed list** | `NetworkKit` + `ImageCache` were designated extracted at inception, before any second product could satisfy test 2. The designation does not grow by precedent | They had to exist before a consumer could reuse them. Any further extraction must pass all three tests on evidence — "we did it for NetworkKit" is not evidence. Feature packages fail all three by definition | §4.2 |
| Naming | `GenericArch-<Name>` for extracted repos; bare name under `Packages/` for local | Dependency URLs embed it | [REPO.md](REPO.md) |
| Dependency injection | **Own typed registry in `DIKit`** | Least root boilerplate, no vendor to wrap. Its two failure modes are designed out, not tolerated | [DIKit.md](modules/DIKit.md) |
| `DependencyKey` | Two values — `liveValue`, `testValue` | A third `previewValue` defaulted to `testValue` and earned nothing | [DIKit.md](modules/DIKit.md) |
| Presentation options | MVVM + `@Observable` (default) **or** view-owned for trivial screens | §3's shared-behavior promise only holds if screens share a shape | §0 |
| Inheritance | Protocol + extension. **No generic base classes** | Sits badly beside "prefer composition"; the extension path already delivers it | §3 |
| Paged content | `Paged<Item>` + `PageState` in `Core`, as `ContentState<Paged<Item>>` | Prevents per-feature `isLoadingMore`; stops a failed page discarding loaded rows | [Core.md](modules/Core.md) |
| Typed throws | Inside a package only; **untyped** at an extracted package's public boundary | Widening a typed throw is a major bump for a routine new error case | §6 |
| Certificate pinning | **Off by default**; opt-in per product | A rotated cert bricks every installed copy with no remote fix | §8 |
| Snapshot scope | Full matrix for DesignSystem components; screens get `loaded` + one failure | The full matrix per screen is 40+ each and becomes the flakiest suite | §9 |
| Contrast | Asserted by token test, **not** tabulated in a note | A hand-maintained duplicate of a test result drifts, then gets believed | [ASSETS-COLORS.md](../.claude/notes/ASSETS-COLORS.md) |
| Dependency graph | **No `DEPENDENCY-GRAPH.md`** | Would drift; the DEBUG container dump + per-package key tests are automatic | [DIKit.md](modules/DIKit.md) |

## Ask every time — never assume

Presentation pattern (per feature/screen) · persistence engine (only if data is stored) · caching
and offline policy (any remote fetch) · any new external dependency · extracting a package ·
**deployment floors** (before any `platforms:` line — never defaulted) · **which layers exist on day
one** (scaffolding a new repo only).
Options and phrasing: the `new-feature` skill carries the first five;
[Scaffold/ARCHITECTURE-OPTIONS.md](../Scaffold/ARCHITECTURE-OPTIONS.md) carries the last two.
Record the answer below.

## Do not re-propose

Rejected with reasons already recorded — reopen only with new information, not a fresh preference.

| Rejected | Where the reasoning lives |
|---|---|
| Multi-repo per package *(tried, reversed 2026-08-12)* | §4.2 |
| Tuist · XcodeGen | [REPO.md](REPO.md) |
| Manual composition root · `@Environment`-only DI · third-party container | [DIKit.md](modules/DIKit.md) |
| Reducer/TCA presentation | §0 |
| `SmartSense-` · `SSS-` name prefixes | — |
| `AsyncImage` for lists | [ImageCache.md](modules/ImageCache.md) |

## Open

| Question | Blocks | Note |
|---|---|---|
| Visual language across iOS 17 / macOS 26 — native-per-platform vs. one owned look | Nothing yet | Only blocks once DesignSystem tokens go beyond platform-neutral (§1.1) |
| macOS 26.6 minimum — verify against real user data | First release | Excludes every Mac that can't run macOS 26 ([GAPS.md](GAPS.md) E1) |

---

## Per feature

| Date | Feature | Presentation | Persistence | Caching / offline |
|---|---|---|---|---|
| — | — | — | — | — |
