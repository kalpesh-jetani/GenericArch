---
name: release-bump
description: Release a change to an extracted repo — GenericArch-NetworkKit or GenericArch-ImageCache — and bump the app to consume it. Use when asked to release, tag, bump, publish or "ship" one of them, or "what breaks if I change this package". Produces the two-step plan, classifies the semver level, and flags when the change should not have been in an extracted repo. Do NOT use for local packages under Packages/, or for App Store releases — that is DELIVERY.
---

# Release bump

Only **two** packages are versioned independently (CLAUDE.md §4.2):

- `GenericArch-NetworkKit`
- `GenericArch-ImageCache`

Everything under `Packages/` is local, unversioned, and ships in the same commit as its consumers.
**If the change is local, there is nothing to bump — say so and stop.** The commit is the user's
(CLAUDE.md §2.11).

## 1. Classify the change

| Change | Bump |
|---|---|
| Removed or renamed public API; changed a signature; added a protocol requirement without a default | **major** |
| Added public API; added a protocol requirement **with** a default in an extension | minor |
| Internal fix, no public surface change | patch |

Two that get misjudged:

- **Adding an error case** is a minor bump here, *because* these packages use untyped `throws` at
  their public boundary (CLAUDE.md §6). If someone has introduced a typed throw, adding a case
  becomes major — flag that as a design regression, not just a version number.
- **Changing a default parameter value** is a source-compatible but behavior-breaking change.
  Treat it as major; consumers won't recompile their way to noticing.

## 2. The plan — two steps, always

```
1. GenericArch-NetworkKit   2.3.1 → 2.4.0   (minor: added ETag middleware)
2. GenericArch (app repo)   update dependency range, commit Package.resolved
```

Per step: `swift build && swift test` standalone → update the module `.md` if behavior changed
(STRUCTURE) → commit → tag → push tag. Then in the app repo: drop any `swift package edit`
override, resolve, build both platforms, commit `Package.resolved`.

**Produce that plan and the exact commands — do not run the git steps.** Invoking this skill asks
for the release plan; it is not permission to commit, tag or push (CLAUDE.md §2.11).

**Never bump the app before the tag exists** — the range won't resolve.

## 3. Stop if the plan is longer than two steps

There is no valid third step. If one appears, something is wrong:

| Symptom | What it means |
|---|---|
| The change needs `Core` to change too | The package is reaching for something it shouldn't. It has **zero dependencies** by design (§4.2) — bridge at the app boundary instead |
| Both extracted repos must change together | They share a concept that belongs in neither. Put it in the app repo |
| A feature must change in lockstep | The public API is leaking product-specific shape — it isn't product-independent (§4.2) |

In all three cases, say so before editing. The likely correct fix is **moving the code back into
`Packages/`**, not coordinating a bigger release.

## 4. Rules that don't bend

- `.upToNextMajor(from:)` only. **Never** `branch:` or `revision:`.
- **Never commit a `.package(path:)` for these two** — it's a local override only. For packages
  under `Packages/`, a path dependency is the normal mechanism.
- `Package.resolved` is committed in the app repo, and is the record of what ships.
- Each extracted repo's CI must be green standalone — build **and** test, iOS and macOS — before
  its tag. If its CI needs a host app, it isn't standalone and §9 is being violated.

## 5. Verify

```bash
swift package unedit --force NetworkKit    # drop any local override first
swift package resolve
```

Then build both schemes and confirm `Package.resolved` names the tag you just pushed — not a
cached older one.
