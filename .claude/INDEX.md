# Index

Everything this repo knows, in one table each. **A thing not indexed here is a thing nobody finds** —
add the row in the same change that adds the thing.

- **Maintained by:** targeted edit. `/learn` adds rows for resources and promoted skills;
  `/sync-app-notes` refreshes the generated inventories.
- **Read this when:** starting anything — before grepping, before adding, before assuming something
  does not exist.

Every row points at the detail: **a code path where the thing exists**, or a doc where it does not.
Never a bare path — say what is there.

---

## Features

Each feature links to the skill that governs it, so the pattern travels with the code.

| Feature | Package — *what's there* | Screens | Governed by | Derived skill |
|---|---|---|---|---|
| — | — | — | — | — |

<!-- Example, delete when the first feature lands:
| Auth | `Packages/Features/FeatureAuth` — sign-in, OTP, reset | 3 | `new-feature` | `auth-screen-flow` (from FeatureAuth) |
-->

**Governed by** is the skill that built it. **Derived skill** is the one it *produced*, if closing it
out found a reusable sequence — most features leave none, and that is the normal outcome.

Screens, routes and states: [notes/FEATURES.md](notes/FEATURES.md) ·
[notes/NAVIGATION.md](notes/NAVIGATION.md).

## Tooling — skills, patterns, commands, docs

**Not listed here — grep [`MAP.tsv`](MAP.tsv).** It carries every skill, unpromoted pattern, command,
module doc and note with its topics and when to read it. This file indexes what the *product* has;
MAP.tsv indexes what the *repo* provides.

```bash
awk -F'\t' '$2=="skill" || $2=="pattern"' .claude/MAP.tsv
```

A pattern in `docs/patterns/` is documented but cannot fire — it needs the code it describes to
exist. `/learn <name>` promotes one when it has earned it.

## Frameworks and tools

Anything brought in from outside, with the note that says how we use it. A vendor with no wrapper is
a §7 violation.

| Name | Wrapper | Usage note |
|---|---|---|
| — | — | — |

<!--
| Firebase Crashlytics | `Packages/Wrappers/CrashReportingWrapper` — the only import site | `docs/resources/crashlytics.md` |
-->

## Resources learned from

Design files, sample repos, vendor docs — each with what we took and what we deliberately did not.

| Resource | Goal it served | Note |
|---|---|---|
| — | — | — |

<!--
| Figma — Checkout v3 | The payment sheet layout | `docs/resources/figma-checkout-v3.md` |
-->

## Style

Tokens and components: [notes/STYLE-GUIDE.md](notes/STYLE-GUIDE.md) — itself an index over code
paths and `notes/styles/` specs. Colours: [notes/ASSETS-COLORS.md](notes/ASSETS-COLORS.md). Fonts:
[notes/FONTS.md](notes/FONTS.md).
