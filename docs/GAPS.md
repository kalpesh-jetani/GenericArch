# Gaps

What this architecture does not cover yet, as **decisions to make** rather than a backlog to burn
down. Run `/gaps` to triage the open items.

- **When to read this:** before adding a capability, before a release, or when wondering whether
  something was overlooked or deliberately excluded.
- **Last reviewed:** 2026-08-12.

## How `/gaps` triages — it depends on the repo

| Repo state | Behaviour |
|---|---|
| **Existing repo** | Statuses are **derived from the code, not asked.** Evidence of a capability sets ✅ or flags it present-but-undocumented; no evidence sets ⛔ *with the evidence noted* |
| **Fresh repo** | The user chooses per item: Adopt · Defer · **Skip** · Other |

One asymmetry the derive path must respect: **absence of evidence is not always a decision.** No
StoreKit means the product doesn't monetise, so ⛔ is safe. No crash reporting, no dSYM upload, no
kill switch, no lint config is a **missing safeguard** — reported as a risk, never auto-skipped.

## Status legend

| Status | Meaning | Gets re-raised? |
|---|---|---|
| ✅ **Applied** | Landed. The row records where | No |
| ▶ **Open** | Needs a decision — no one has chosen yet | Yes, by `/gaps` |
| ⏸ **Deferred** | Tracked, with a named revisit trigger | Only when the trigger fires |
| ⛔ **Skipped** | Decided against, or no evidence of it in an existing repo. Recorded in [DECISIONS.md](DECISIONS.md) *Do not re-propose* | **No** |

**Skip is a real answer.** An item marked Skipped stops being suggested — that is the point. Most of
section B *should* end up Skipped for any given product; a mobile app that will never have a widget
gains nothing from carrying "widgets" as an open question forever.

---

## ✅ Applied — 2026-08-12

| Was missing | Landed in |
|---|---|
| CI/CD, signing automation, app versioning | [DELIVERY.md](DELIVERY.md) |
| Launch budget, SwiftUI rendering performance | [PERFORMANCE.md](PERFORMANCE.md) |
| App lifecycle, state restoration, force-update gate | [AppShell.md](modules/AppShell.md) |
| Push notifications | [NotificationKit.md](modules/NotificationKit.md) |
| Remote images and caching | [ImageCache.md](modules/ImageCache.md) *(extracted repo)* |
| Pagination / partial content | `Paged<Item>` in [Core.md](modules/Core.md) |

| Was over-specified | Trimmed to |
|---|---|
| `DEPENDENCY-GRAPH.md` requirement | removed — automated checks cover it |
| `previewValue` on `DependencyKey` | two values, not three |
| Three presentation patterns | reducer/TCA dropped |
| Generic base view models | protocol + extension only |
| Certificate pinning as default | off by default, opt-in per product |
| Typed throws at package boundaries | inside a package only |
| Snapshot matrix on every screen | components only; screens get `loaded` + one failure |
| Contrast column in a note | token test asserts it |
| Multi-repo per package | single repo + two extracted |

The launch-budget-vs-eager-DI conflict is resolved by the facade rule in
[PERFORMANCE.md](PERFORMANCE.md).

---

## ▶ B. Product capabilities — expect most of these to be Skipped

Each is absent by choice, not oversight. **Adopt only when the product needs it**; Skip the rest so
they stop surfacing.

| Capability | Lands in | Cost of skipping | Recommend |
|---|---|---|---|
| Feature flags / remote config | new module + wrapper | **No kill switch.** A bad release can only be fixed by a new release — see [DELIVERY.md](DELIVERY.md) rollback | **Adopt** — it's the only rollback that reaches installed copies |
| Analytics event taxonomy | wrapper + naming convention | Events accrete ad-hoc and become unqueryable | Adopt if anyone will read the data; else Skip |
| Crash reporting operations | LoggingKit + CI | dSYMs unuploaded → unreadable crash reports, unrecoverable after the fact | **Adopt** before first external build |
| StoreKit 2 / IAP | new module | — | Skip unless monetised |
| Auth flows (OAuth, Sign in with Apple) | FeatureAuth | Token *storage* is covered; the flows are not | Adopt when there's a login |
| CloudKit / sync | StorageKit | §0's "offline-first with sync" option has no design behind it | Skip until a product picks that option |
| Widgets, App Intents, Live Activities | new targets | [PROJECT.md](../.claude/notes/PROJECT.md) has the target slot, no guidance | Skip until scoped |
| Universal links — AASA hosting | Navigation | Parsing is covered; server-side setup isn't | Adopt with the first deep link |
| Handoff / Continuity | app shell | Unusually relevant given iOS + Mac from one codebase | Defer to post-v1 |
| Keyboard & focus management | DesignSystem | Forms are awkward and inaccessible without it | **Adopt** if there is any multi-field form |
| Haptics | wrapper | Must respect Reduce Motion | Skip — add with the first use |
| Biometrics | StorageKit | `BiometricAuthenticating` is named but undocumented | Adopt when something needs gating |
| Onboarding / first-run | feature | Interacts with permission pre-prompts | Adopt with the first permission ask |
| Search | DesignSystem + feature | Cross-cutting UI pattern with its own states | Skip until a screen needs it |
| Watch / tvOS / visionOS | — | Not a gap — a **scope question** | **Skip explicitly**, so it's settled |

## ▶ C. Tooling & process

| Item | Missing | Cost of skipping | Recommend |
|---|---|---|---|
| **SwiftLint / SwiftFormat** | No config; no statement of which violations are errors | Rules already written in §2 and [DONE.md](DONE.md) — no force-unwrap, no `try?`-swallow, no raw literal in UI — stay review-only and decay | **Adopt first.** It mechanizes rules that already exist; highest value per hour in this list |
| **PR / review checklist** | [DONE.md](DONE.md) is a definition of done, not a review process | Reviewers apply different bars | Adopt — thin, derive from DONE.md |
| **UI test strategy** | XCTest is named; no robot/page-object pattern, no flakiness policy | UI tests get written, go flaky, get disabled, stay disabled | Defer until there are screens to test |
| **Dependency supply-chain policy** | §0 gates *adding* a dependency; nothing covers auditing or an abandoned vendor | Low while the dependency count is near zero | Defer — revisit at the third external dependency |
| **Package deprecation / archival** | [REPO.md](REPO.md) covers adding, not retiring | Dead packages linger and get linked | Skip — trivial to decide when it first happens |
| **Release publishes the tag** | Nothing asserts the version tag reached the remote before that tag is used as a fetch base | An installed `MAP.tsv` writes `FETCH-BASE: …/<tag>`. With the tag unpushed, every `:remote` row 404s and `bootstrap.sh` resolves the *previous* release instead — silently. Measured on v0.3.0: 52 dead rows, and the same paths return 200 at v0.2.0 | **Adopt** — assert `git ls-remote --tags origin` carries the tag, in `ga-roundtrip.sh` or the release pattern. It is the one failure a local round trip cannot see |
| **Where a failure report is written** | `ga-handoff.sh` resolves `.genericarch/failures/` from the working directory, not from the target repo | Running a target's script from anywhere else writes the diagnosis into an unrelated repo — measured: into this checkout, and into an empty scratch directory. CLAUDE.md then sends Claude to a path that may belong to a different repo. Reports also accumulate one file per run, undeduplicated | **Adopt** — resolve the state dir from the target root, and overwrite the report for a repeated script+cause |
| **Who owes the reseal** | [INSTALL-MANIFEST.md](INSTALL-MANIFEST.md) puts the obligation on three slash commands. `sync-notes.sh --apply` and `notes-staleness.sh --stamp` also rewrite installed notes and reseal nothing; `/gaps` edits `docs/GAPS.md` with no reseal step either | Every direct run of those scripts leaves a permanent orphan. Measured: after `--stamp`, uninstall preserved `.claude/notes/FEATURES.md` and told the operator *"you edited it"* — for a write GenericArch itself made | **Adopt** — move the obligation into whatever writes the file, rather than onto each caller that has to remember |
| **What counts as "source"** | `sync-notes.sh` scans the filesystem; `notes-staleness.sh` enumerates tracked files. Nothing says which is authoritative | The two disagree about an uncommitted asset: indexed by one, `no baseline — full scan` in the other. Neither is wrong, and the divergence reads as a broken script until you commit | Defer — document the split and move on. **Trigger:** the first time a note is generated in CI, before the commit that adds its source |

## ▶ E. Decided, but worth re-verifying

| Item | Question | Cost of skipping | Recommend |
|---|---|---|---|
| **E1. macOS 26.6 minimum** | Verify against real user data | Excludes every Mac that can't run macOS 26. Cheap to change now, expensive after release | **Adopt the check** before first release |
| **E3. Launch budget** | The facade rule exists; the budget is unmeasured | A slow launch is found by users, not by CI | Defer — verify once there's an app to measure |
| **E4. Two doc roots** | `docs/` vs `.claude/notes/` | Resolved — the rule is in [STRUCTURE.md](STRUCTURE.md) | ✅ Close it |

---

## Recording an answer

`/gaps` does this, but by hand:

- **Adopt** → do the work, then move the row to *Applied* with where it landed.
- **Defer** → set Status ⏸ and **name the trigger** ("at the third dependency", "once an app exists").
  A deferral with no trigger is an Open item pretending to be decided.
- **Skip** → set Status ⛔ **and** add a row to [DECISIONS.md](DECISIONS.md) *Do not re-propose*. Both,
  or it comes back. On an existing repo, note the evidence: `⛔ no StoreKit usage found`.

Never delete a row. The value of this file is knowing what was considered and declined, not just
what was built.
