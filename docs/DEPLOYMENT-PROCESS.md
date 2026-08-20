# Deployment process

- **When to read this:** shipping — a merge that will reach testers or users, a release tag, an
  extracted-package release, or a rollback. **Not** session reading.
- **Owns:** the ordered path from a merged change to a released build, and who owns each gate.
- **Does not own:** what CI runs, the three version numbers, signing setup, the release checklist,
  rollback mechanics — all of that is [DELIVERY.md](DELIVERY.md), which this file walks you through
  rather than repeating.

---

## The path, and who owns each step

| # | Step | Owned by | Gate before moving on |
|---|---|---|---|
| 1 | Change merged to `main` | the author | PR pipeline green — packages tested, both apps built |
| 2 | TEST build to TestFlight internal | CI, on merge | QA has the latest `main` and it launches |
| 3 | Version bumped | a person, deliberately | Marketing version decided; build number is CI's |
| 4 | Release tag `vX.Y.Z` | a person | The release checklist in [DELIVERY.md](DELIVERY.md) *Release checklist* |
| 5 | BETA archived, notarized, external TestFlight | CI, on tag | Soak period observed, crash-free rate acceptable |
| 6 | PROD archived and submitted | CI | **From the same commit as the soaked BETA** |
| 7 | Rollback if needed | a person | See below — a rollback is a decision, not a reflex |

Claude does not perform any of these (§2.12). It prepares them: the version bump, the changelog, the
checklist walked against the diff, and it says what to run.

## The one rule people get wrong

**PROD is built from the same commit as the BETA that soaked** — never rebuilt from a moved branch.
A rebuild is a different binary with the same version number, and every soak hour you spent was
spent on something else.

## Before tagging

Walk the checklist in [DELIVERY.md](DELIVERY.md) *Release checklist* rather than from memory. The
two
items most often missed:

- `Package.resolved` pinned to **released tags** of the extracted packages, with no `swift package
  edit` override active.
- Screenshots regenerated **per language and per device class**.

For an extracted package, releasing it is its own two-step process — tag the package, then bump the
app that consumes it: [release-bump](patterns/release-bump.md).

## dSYMs

Uploaded to the crash reporter on every archive, automatically. They cannot be regenerated after the
fact, so an archive whose dSYMs were not uploaded is an archive whose crashes you cannot act on.

## Rollback

A rollback is a decision with a trigger recorded **before** the release, not improvised during one.
Triggers, the App Store's constraints on what can actually be rolled back, and the phased-release
lever: [DELIVERY.md](DELIVERY.md) *Rollback*.

## Building any of these locally

That is a separate process, with a separate rule about who runs it:
[BUILD-PROCESS.md](BUILD-PROCESS.md).
