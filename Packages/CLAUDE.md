# Packages — rules that only bind here

Scoped rules for `Packages/`. The root `CLAUDE.md` keeps every section heading and the one-line rule;
this file carries the detail, so a session that never opens a package never pays for it.

**If you are working inside a package, read this once.** Nothing here contradicts the root file — it
expands §4, §7 and §9, and the numbering is the same.

---

## §4 — Repository and extraction

Local packages wire with `.package(path:)` and carry **no version numbers**: git history is the
version, and a version in a local manifest is a number two places can disagree about.

`Package.swift` is what enforces the dependency direction, not repo walls or convention. A local
package still cannot import a sibling feature — if it compiles, the manifest was wrong.

**The two extracted packages** — `GenericArch-NetworkKit`, `GenericArch-ImageCache` — have zero
dependencies and neither imports `Core`. They declare their own errors and protocols, and we map at
our boundary exactly as §7 treats a vendor. A package that cannot stand alone without `Core` was
never product-independent.

**Extraction needs all three** — product-independent · actually reused (a second product consumes
it, not "might one day") · stable public API. Otherwise keep it local: local costs nothing, and
reversing an extraction doesn't either. Layout, versioning and local overrides:
[REPO.md](../docs/REPO.md). Releasing one: [release-bump](../docs/patterns/release-bump.md).

## §7 — Wrapping a vendor

No feature or infrastructure module imports a third-party module directly, and **swapping a vendor
must touch exactly one target.** Split `XWrapperInterface` (no vendor dependency) from `XWrapper`
(the vendor), so a feature links only the interface.

Everything a wrapper ships, the contract test, and how to remove a vendor later:
[wrapper](../docs/patterns/wrapper.md).

## §9 — Testing a package

- **Every package builds and tests standalone.** `swift build|test --package-path Packages/<Name>` —
  that is what actually enforces the module boundaries, and a package that only builds from the app
  has a dependency nobody declared.
- **No network in tests**, enforced by the mandatory `testValue` on every dependency key rather than
  by discipline.
- **Unit-test every view model, mapper and service against protocol mocks.**
- **Contract tests per wrapper** — the real implementation and the mock satisfy the same suite. A mock
  that passes what the real one would fail makes every downstream test a false positive.
- **Snapshots are bounded** → [DesignSystem.md](../docs/modules/DesignSystem.md). Full matrix for
  components; a screen gets `loaded` plus one failure state.
- **Localization test:** no key missing in any language, no view using a raw literal.

A new package starts with a placeholder test so `swift test` is green from the first commit — delete
it with the first real one. A suite whose only test asserts a constant proves the harness works and
nothing else.

## Where the numbers live

Deployment floors are **not** written here from memory. They come from each `Package.swift`
`platforms:` line, and no line means unanswered rather than missing:
[PROJECT-SETTINGS.md](../docs/PROJECT-SETTINGS.md).
