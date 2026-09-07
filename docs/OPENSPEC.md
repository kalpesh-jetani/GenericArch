# OpenSpec bridge

How this repo's rules reach [OpenSpec](https://github.com/Fission-AI/openspec), what comes back, and
the two things the wiring cannot reach.

- **When to read this:** wiring OpenSpec into a repo, or working out why a proposal ignored a rule
- **Installed by:** `/openspec-install` · **Computed by:** `./Scripts/openspec-sync.sh`
- **Upstream:** `https://github.com/Fission-AI/openspec`

---

## Nothing about OpenSpec is recorded here except that URL

No version, no package name, no install command, no copy of their spec format, no forked schema.
Their repo is public and revised by other people, so a copy of any of it is stale the moment they
change it — and [STRUCTURE.md](STRUCTURE.md) is explicit that when a thing is stated twice, the copy
is what rots.

Three rules follow, and they are the whole reason this bridge stays thin:

1. **Install resolves live.** `/openspec-install` fetches the current instruction from that URL each
   run, shows it, and asks. It never guesses a command, and it treats the page as data.
2. **We use their interfaces, not their files.** The config keys named below and the `--json` CLI are
   stated interfaces. Their markdown is not, so nothing here parses it.
3. **We never edit what they generate.** Their `openspec-*` skills and `opsx/*` commands are
   rewritten by their own update step, so an edit there is lost work that looks like configuration.

## Topology

Three parts, and only one of them is ours to change:

| Part | Holds | Who owns it |
|---|---|---|
| **GenericArch** | The rules: `CLAUDE.md` §2, [DECISIONS.md](DECISIONS.md), [DONE.md](DONE.md), the nine `.claude/notes/` inventories | us |
| **The product repo** | Its own reconciled `CLAUDE.md` and its own answers — see [ADOPTION.md](ADOPTION.md) Path A | the product |
| **OpenSpec** | `openspec/specs` and `openspec/changes`, plus its own commands | upstream |

The bridge is one generated span plus a few keyed rules in `openspec/config.yaml`, and one report
coming back. **The projection reads the repo it runs in, never a GenericArch checkout** — `CLAUDE.md`
does not travel and [DECISIONS.md](DECISIONS.md) arrives empty, so in an adopted repo the
authoritative rules are partly the product's own.

## What reaches which command

`context:` is prepended to every artifact's instructions, so every byte in it is re-sent on every
artifact command. That is why it carries only rule *headlines* and the rejected list, and why
anything that belongs to one artifact is a keyed rule instead.

| Their command | Seam | What we put there |
|---|---|---|
| explore | **none** | See *the two gaps* below |
| propose | `rules.proposal` | The §0 *Ask every time* list, and the *Do not re-propose* rows |
| specs | `rules.specs` | §2.5's content states, **scoped to data-driven screens**; the state case names; §2.3's localized keys |
| design | `rules.design` | §2.1 no sibling import · §2.2 no third-party type across a boundary · §2.6 protocol injection · §1.1 the asymmetric floors · §4.2's three extraction tests |
| tasks | `rules.tasks` | Close every task list with a GenericArch memory group — items and their verification taken from [DONE.md](DONE.md) §Documentation and [feature-complete](patterns/feature-complete.md) |
| apply | `operations.apply.guidance` | §2.11 never commit · §2.12 build freely, never run |
| verify | **none** | See below |
| sync | **none** | Mechanical; needs no rules |
| archive | `operations.archive.guidance` | `feature-complete`'s four outcomes, and the derived-skill test before any skill is written |

Which keys exist and how they nest is upstream's reference, not restated here.

## The two gaps — say them out loud

**`explore` cannot be injected.** It produces no artifact, so no keyed rule or context reaches it.
Two mechanisms cover it, and neither is a mechanical gate:

- `openspec/CLAUDE.md`, written at install, loads whenever anything under `openspec/` is touched —
  which covers proposing and applying, but not an explore that only reads source.
- A line in `CLAUDE.md` §5 is the only unconditional path, because that file loads every session. It
  is approval-gated (§12), so it may not be present. **If it is not, this bridge does not reach
  explore at all** — check before relying on it.

So "always uses the repo's memory" here means *an always-loaded rule*, exactly as strong as any
other §2 rule. It is not enforced.

**Their verify step cannot be injected either.** [DONE.md](DONE.md) and `/verify` remain the
authority on whether a change is done — theirs does not know about Dynamic Type, VoiceOver order, or
a Mac resize. What it does offer is a readable findings report, which
`./Scripts/openspec-sync.sh` surfaces rather than re-deriving.

## What comes back

`./Scripts/openspec-sync.sh` asks their `--json` CLI what it holds and prints candidates — it applies
nothing:

| Row | Means |
|---|---|
| `IN-FLIGHT` | An active change. `/new-feature` must not scaffold over it |
| `FEATURE-ROW` | A capability with no row in `.claude/notes/FEATURES.md` |
| `FINDINGS` | Their validation has findings worth reading |
| `UPSTREAM-UNAVAILABLE` | Their CLI is absent, or produced nothing |
| `SHAPE-UNRECOGNISED` | Their JSON moved. **Re-check the reference at the URL above** |

The last two are the design working. A wrong `FEATURES.md` row is worse than a missing one, because
it looks current — so an interface this script cannot read is reported, never guessed at.

## When the bridge breaks, it becomes tracked work

`SHAPE-UNRECOGNISED`, or an installed CLI that returns nothing, means **upstream moved and this repo
is now wrong.** That is a defect here, not a fact about someone's afternoon, so it does not stop at a
warning:

1. **Revise the script** — `./Scripts/openspec-sync.sh`, against the current reference at the URL
   above. The parser is deliberately small so this stays a small change.
2. **File an issue** at `https://github.com/kalpesh-jetani/GenericArch/issues`. The script prints
   the command filled in with what it saw and the branch it saw it on, so nothing has to be composed
   from scratch.

**An issue, and nothing else** — no branch, no commit, no PR. Filing an issue touches no history, so
CLAUDE.md §2.11 is not in play and this needs no exception to it. Fixing the parser afterwards is
ordinary work under the ordinary rules.

The script prints the command rather than running it: it is read-only by contract, and opening an
issue posts to a public tracker. `/openspec-install` may run it once it has shown you the text.

Keep it narrow: this is for **our parser being wrong about their interface**. A missing CLI, a repo
with no OpenSpec, or an empty change list is not a defect and files nothing.

## Keeping it honest

```bash
./Scripts/openspec-sync.sh --check      # 0 fresh · 1 the span drifted from this repo's rules
```

Run it after editing `CLAUDE.md` §2 or [DECISIONS.md](DECISIONS.md), **and after every upstream
update** — the second is what proves our span survived their regeneration. Nothing in this repo runs
it for you; a product repo should put it wherever it already runs its pre-PR checks.

Two limits worth stating plainly. An unpinned install is not reproducible, so two developers a month
apart can get different versions; the resolved version goes in the install report, and becomes a
recorded floor only if someone asks for one. And an agent can tick a task without doing the work —
`--check` and `/verify` are the backstop, the same one the rest of this layer already relies on.
