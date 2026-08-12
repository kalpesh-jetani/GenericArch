# Sharing GenericArch

Three ways to hand this to someone else. They are not alternatives to pick once — most teams end up
using two of them, for different layers.

- **When to read this:** you are the one **publishing** this base.
- **Consumers read [../README.md](../README.md)** instead — it has the copy-paste install for each
  case. Keep the two in step: the version pinned in README's `curl` URL must be a tag that exists.

---

## First: three categories, not two

Copying is only one of the three ways something reaches a consumer.

### 1. Copied — the reusable base

| What | Why it travels |
|---|---|
| `docs/modules/*.md` | Design per package, product-independent |
| `docs/{STRUCTURE,CONVENTIONS,DONE,REPO,DELIVERY,PERFORMANCE}.md` | Cross-cutting reference |
| `.claude/skills/*`, `.claude/commands/*` | Agent tooling |
| `.swiftlint.yml`, `.swiftformat`, `Scripts/*` (incl. `detect-toolchain.sh`) | Enforcement |
| `Packages/{Core,DIKit}` | Starting code — a consumer edits its own copy |

### 2. Resolved — the extracted packages, **never copied**

| Package | Reaches a consumer as |
|---|---|
| `GenericArch-NetworkKit` | an SPM dependency by URL, pinned with `.upToNextMajor(from:)` |
| `GenericArch-ImageCache` | the same |

**These are standalone modular packages in their own repositories. A consuming project does not
include their source, and `adopt.sh` never copies them.** A consumer adds one line to
`Package.swift` and gets a versioned binary-compatible dependency:

```swift
.package(url: "https://github.com/<org>/GenericArch-NetworkKit.git", from: "1.0.0")
```

That is the whole point of extracting them (CLAUDE.md §4.2): they carry **zero dependencies** — not
even `Core` — so any product can resolve them without inheriting this architecture. A consumer that
vendors the source has undone the extraction and now owns a fork.

Consequences worth stating:

- They need to **exist and be reachable** only for a consumer that actually uses them. A project with
  no networking never resolves NetworkKit, and nothing breaks.
- They version **independently of the app and of each other** — `/release-bump`, [REPO.md](REPO.md).
- They are the one layer where central updates reach every consumer for free, by bumping a version.

### 3. Neither — this product's state

| What | Why it must not travel |
|---|---|
| `CLAUDE.md` | The target's rules are its own; `/project-init` reconciles rather than overwrites |
| `.claude/notes/*` | Inventories of **this app's** screens, routes, assets, fonts |
| `docs/DECISIONS.md` | **This product's** answers |
| `docs/GAPS.md` | Gap statuses are per-product |
| `Packages/Features/*`, `App/*` | This product's code |

`Scripts/adopt.sh` enforces all three categories so nobody has to remember them: it copies group 1,
skips group 3 with the reason printed, and never touches group 2 — those arrive by dependency
resolution, not by file copy.

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
./Scripts/detect-toolchain.sh     # §1 must describe THIS machine, not GenericArch's
# drop this product's answers from DECISIONS.md
# reset GAPS.md statuses to ▶ Open
# clear .claude/notes/ table bodies
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

## Option 3 — Installer · for an **existing** codebase

Consumers run `install.sh` from inside their own repo — it fetches a pinned tag and delegates to
`adopt.sh`, so the "what travels" list lives in exactly one place:

```bash
# what a consumer runs, from their repo
curl -fsSLO https://raw.githubusercontent.com/<org>/GenericArch/v0.1.0/install.sh
bash install.sh --apply
```

`adopt.sh` is still the direct path when you already have a checkout:

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
| `GenericArch-{NetworkKit,ImageCache}` | **Already solved** — separate repos, semver over SPM. A consumer bumps a version; no files move. Category 2 above |
| Skills, commands, lint config | **Genuinely shared** → Option 2, the plugin |
| `CLAUDE.md`, `docs/` | **Let them diverge** |

That last row is a recommendation, not a shrug. These are a product's rules. The moment two products
need different persistence engines or a different minimum OS, a shared rules file becomes a blocker
and someone edits it for everyone. Divergence here is correct behaviour, not debt.

## Before you share

- [ ] `git init` and a first commit exist, with `.build/` excluded — it is ~49 MB of artifacts
- [ ] **A tag exists and README's install URL points at it.** `install.sh` defaults to a pinned ref;
      if that tag isn't pushed, every consumer silently falls back to the default branch
- [ ] `install.sh` tested against both a fresh and an existing repo — the existing case is the one
      that can damage someone's work
- [ ] The two extracted packages are **published as their own repositories and tagged** —
      `GenericArch-NetworkKit`, `GenericArch-ImageCache`. Consumers resolve them by URL; their source
      is never copied into a consuming repo, so an untagged or unreachable repo is what breaks, not a
      missing file. Each must build and test standalone with **zero dependencies** (CLAUDE.md §4.2)
- [ ] `./Scripts/check.sh` and `Scripts/check-skill-triggers.py` pass
- [ ] **`./Scripts/detect-toolchain.sh` is clean** — §1 is detected from the machine and the project
      file, not hand-written, and `check.sh` fails when it drifts. Each consumer detects its own;
      never inherit GenericArch's numbers
- [ ] Decide on the name. Keeping `GenericArch` means it appears in every consumer's dependency list
      and scheme names — fine if each product forks the blueprint, odd if several share these repos
