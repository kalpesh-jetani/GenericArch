# Sharing GenericArch

Three ways to hand this to someone else. They are not alternatives to pick once — most teams end up
using two of them, for different layers.

- **When to read this:** giving this base to a teammate, starting a new product, or adding it to an
  existing codebase.

---

## First: this repo holds two different things

The base is reusable. The rest is **this product's state**, and carrying it into another repo makes
the target's own docs lie.

| Travels | Stays here |
|---|---|
| `docs/modules/*.md` — design per package | `CLAUDE.md` — the target's rules are its own |
| `docs/{STRUCTURE,CONVENTIONS,DONE,REPO,DELIVERY,PERFORMANCE}.md` | `.claude/notes/*` — **this app's** screens, routes, assets, fonts |
| `.claude/skills/*`, `.claude/commands/*` | `docs/DECISIONS.md` — **this product's** answers |
| `.swiftlint.yml`, `.swiftformat`, `Scripts/*` | `docs/GAPS.md` — statuses are per-product |
| `Packages/{Core,DIKit}` as starting code | `Packages/Features/*`, `App/*` |

`Scripts/adopt.sh` enforces this split so nobody has to remember it. Empty note *scaffolds* are
useful and do travel; populated inventories never do.

**`CLAUDE.md` is on the "stays" side deliberately.** A target repo's rules were set with context you
don't have, and `/project-init` reconciles rather than overwrites.

---

## Option 1 — Template repository · for a **new** product

Best when the product starts from nothing. One command, everything present, no history.

```bash
# once, on the base repo
gh repo create <org>/GenericArch --private --source=. --push
gh repo edit <org>/GenericArch --template

# per new product
gh repo create <org>/MyApp --template <org>/GenericArch --private --clone
cd MyApp
```

Then in Claude Code: **`/project-init MyApp`** — detects a fresh repo, shows the available skills and
commands, and asks for bundle ID, Team ID, v1 languages, the open §1.1 visual-language decision, and
permissions per group.

**Then reset the inherited state**, which a template copies wholesale:

```bash
# keep the toolchain rows in DECISIONS.md; drop this product's answers
# reset GAPS.md statuses to ▶ Open
# leave .claude/notes/ as empty scaffolds
```

| Good | Bad |
|---|---|
| Everything in one step; code and docs included | Inherits state that must be reset by hand |
| No sync obligation — the fork is yours | Divergence is permanent; later base fixes don't reach it |

## Option 2 — Plugin · for the **tooling layer**, across many repos

Ships only skills and commands, installable anywhere, updated centrally. This is the right answer
when several products should share the *tooling* while keeping their own rules.

```bash
./Scripts/build-plugin.sh 0.1.0        # generates dist/genericarch/
cd dist/genericarch
git init && git add -A && git commit -m "genericarch plugin 0.1.0"
gh repo create <org>/genericarch-plugin --public --source=. --push
```

In any repo:

```
/plugin marketplace add <org>/genericarch-plugin
/plugin install genericarch
```

The plugin is **generated, never hand-edited** — `.claude/skills` and `.claude/commands` stay the
single source of truth, because a hand-copied plugin drifts and this repo's own rule is that a doc
which drifts from its source is worse than none.

| Good | Bad |
|---|---|
| One install; central updates reach every repo | Tooling only — no rules, docs, or code |
| Each product keeps its own CLAUDE.md | `/verify`, `/decide`, `/gaps` need the docs adopted too |

## Option 3 — Adopt script · for an **existing** codebase

```bash
cd /path/to/GenericArch
./Scripts/adopt.sh /path/to/ExistingApp             # dry run — shows the plan
./Scripts/adopt.sh /path/to/ExistingApp --apply
```

Copies the base, refuses to copy the state, and **never overwrites** — an existing file is reported
as a collision and kept. Then:

1. **`/project-init`** — reads their CLAUDE.md in full, builds the rule-conflict table (CocoaPods vs
   SPM, UIKit vs SwiftUI, Combine, existing DI, min OS), classifies each honestly, and asks per
   conflict with **keep-theirs as the default**. *Adopt for new code only* is usually the right
   answer for a hard conflict — it's the only option honest about code that already exists.
2. **`/gaps`** — derives status from their code instead of asking; reports missing safeguards as
   risks rather than silently skipping them.
3. **`./Scripts/check.sh`** — expect failures. That is the point; triage them above.

| Good | Bad |
|---|---|
| Non-destructive; their rules survive | Rule adoption is a negotiation, not a copy |
| Works on a codebase that violates half the rules | Base updates need re-running the script |

---

## Which layer to keep in sync — and which not to

Don't try to sync all of it. Three layers, three honest answers:

| Layer | Strategy |
|---|---|
| `Packages/{NetworkKit,ImageCache}` | **Already solved** — semver over SPM, `/release-bump` |
| Skills, commands, lint config | **Genuinely shared** → Option 2, the plugin |
| `CLAUDE.md`, `docs/` | **Let them diverge** |

That last row is a recommendation, not a shrug. These are a product's rules. The moment two products
need different persistence engines or a different minimum OS, a shared rules file becomes a blocker
and someone edits it for everyone. Divergence here is correct behaviour, not debt.

## Before you share

- [ ] `git init` and a first commit exist, with `.build/` excluded — it is ~49 MB of artifacts
- [ ] The two seed repos exist: `GenericArch-NetworkKit`, `GenericArch-ImageCache` (consumed by URL)
- [ ] `./Scripts/check.sh` and `Scripts/check-skill-triggers.py` pass
- [ ] **The toolchain baseline matches reality** — §1 declares Swift 6.4 / Xcode 27; verify against
      what your team actually has, because every consumer hits the same mismatch
- [ ] Decide on the name. Keeping `GenericArch` means it appears in every consumer's dependency list
      and scheme names — fine if each product forks the blueprint, odd if several share these repos
