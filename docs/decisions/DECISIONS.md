# Decisions

Settled choices. **Read this before asking a CLAUDE.md §0 question** — it may already be answered.
Add a row when a §0 decision is made; never remove one. Stack- and pattern-specific decisions belong
to the active **stack profile**, not here — this file records the **layer's** own decisions.

---

## Settled — follow these, don't re-derive

| Scope | Decision | Why | Detail |
|---|---|---|---|
| Layer identity | **Tech-stack-agnostic.** The repo is a layer for managing any development environment — shared memory with Claude. It ships **no stack content**: language, build system, architecture pattern and their rules come from a declared **stack profile** (`profiles/`), and **none ships by default** | An architecture baked into the layer is one every consumer inherits whether it fits or not. Making the stack a declared profile lets one layer serve any project | §1, [profiles/CLAUDE.md](../profiles/CLAUDE.md) |
| Stack | **Declared, not assumed.** The active profile declares language, build system, UI/runtime, concurrency and test framework; detection only assists. Versions are acquired — project wins, machine fills gaps, the remainder asked by `/declare-profile` | A layer that hardcodes a stack is not generic, and a machine upgrade must not silently change what a project targets | §1 |
| Reference profile | **None ships — not even an example.** Any default profile that existed was removed outright, and so was the worked example, which shipped to every consumer and contradicted this row | A shipped default is the thing consumers cargo-cult; the layer is the machinery, a profile is authored per project | §1 |
| Install shapes | **One.** `install.sh` refuses a target it cannot recognise, and `--mode` is gone | Two modes meant every gate, ledger row and doc had to say which one it meant | [SEQUENCE.md](/docs/operations/SEQUENCE.md)(/docs/operations/SEQUENCE.md) |
| Lifecycle steps | **No `scaffold` step** — install → declare-profile → project-init → sync-app-notes → ready | Nothing in the layer creates a project layout, so a step that could never run was a gate everything waited behind. `declare-profile` is the opposite case — it always runs, and every step after it reads what it records | §3 |
| Offering a gated command | **A command never offers one whose `require` line would fail at that moment** — it describes the order and runs nothing | A step records itself at its end, so anything gated on it is refused for its whole run | [SEQUENCE.md](/docs/operations/SEQUENCE.md)(/docs/operations/SEQUENCE.md) |
| Recording a resolution | **Every resolved conflict is *Settled* or *Do not re-propose* before the step is recorded** — only a genuine deferral is *Open* | §0 reads an *Open* row as unanswered and asks again; a resolution that exists only in a transcript is gone next session | [adoption/ADOPTION.md](/docs/adoption/ADOPTION.md)(/docs/adoption/ADOPTION.md) |
| Component rules | **Every component carries its own `CLAUDE.md`** — boundary first, then rules true only inside it. No list of components is ever written; the rule follows the directory that exists | A rule reaches the session about to break it, at the moment it would, and costs nothing until then | §2.6, [STRUCTURE.md](/docs/reference/STRUCTURE.md)(/docs/reference/STRUCTURE.md) |
| Component reference doc | **Optional** — `<component>/<Name>.md`, only when a caller needs it | Rules must be pushed; reference is pulled. Making it mandatory buys a file nobody opens | [STRUCTURE.md](/docs/reference/STRUCTURE.md)(/docs/reference/STRUCTURE.md) |
| OpenSpec | **Adopted** as an optional external CLI, wired by `/openspec-install` — the layer's one external dependency, so a supply-chain policy is due | Spec-driven planning the agent follows step by step. Optional because a project that does not want it carries nothing but one doc row | [OPENSPEC.md](/docs/reference/OPENSPEC.md)(/docs/reference/OPENSPEC.md), §0 |
| OpenSpec install | **Unpinned, resolved live** from `https://github.com/Fission-AI/openspec` each run — no version, package name or install command is recorded here | Their repo is revised by other people; a copy is stale the moment they change it. The resolved version goes in the run's report, not a file | [OPENSPEC.md](/docs/reference/OPENSPEC.md)(/docs/reference/OPENSPEC.md) |
| OpenSpec projection | **Reads the repo it runs in**, never a GenericArch checkout, and `openspec-sync.sh` **writes no YAML** — it computes, the command applies | `CLAUDE.md` does not travel and `DECISIONS.md` arrives empty, so a projector reading the base would arrive with its inputs missing. sed/awk surgery on a semantically-indented block scalar is the least safe part of the bridge | [OPENSPEC.md](/docs/reference/OPENSPEC.md)(/docs/reference/OPENSPEC.md), [adoption/ADOPTION.md](/docs/adoption/ADOPTION.md)(/docs/adoption/ADOPTION.md) |
| OpenSpec parser defects | **Revise the script, and file an issue** — `github.com/kalpesh-jetani/GenericArch/issues`. An issue only: no branch, no commit, no PR, so §2.2 needs no exception. Limited to `SHAPE-UNRECOGNISED` and an installed CLI returning nothing | Their interface moving makes this repo wrong, and a warning nobody tracks is how a bridge rots | [OPENSPEC.md](/docs/reference/OPENSPEC.md)(/docs/reference/OPENSPEC.md) |
| OpenSpec staleness | **`./Scripts/check.sh`**, as a warning that skips when there is no OpenSpec config | The projection is built from the repo's rules, so editing one stales it silently. Hanging it off the gate that already runs before a PR removes a habit nobody would keep | [OPENSPEC.md](/docs/reference/OPENSPEC.md)(/docs/reference/OPENSPEC.md) |
| Version support | **v0.6 is the LTS line** (`GA_LTS_LINE`), current patch `GA_LATEST_VERSION`. Below `GA_INSTALL_FLOOR` = v0.6.0 is deprecated: **removable, never installable** | Deprecating a release must mean "do not put this on anything new", never "you can no longer get it off". Stripping old versions would strand every install that has one | [SHARING.md](/docs/adoption/SHARING.md)(/docs/adoption/SHARING.md), `Scripts/ga-lifecycle.sh` |
| Tool profiles | **`.claude/tools/<tool>.md`** holds what one external platform exposes — attributes, units, reachability, extraction method, scope. One profile per platform; a new input or output **extends** it | The next session otherwise re-reaches the platform to rediscover what it exposes, or infers it | [TOOL-PROFILES.md](/docs/reference/TOOL-PROFILES.md)(/docs/reference/TOOL-PROFILES.md) |
| Tool-profile provenance | **Observation only.** Every cell comes from a real response; anything unseen is written `not observed` and left there. `--apply` refuses a profile with no observed row | A wrong unit is worse than a missing one because it is trusted; `not observed` is a required entry, not a gap to fill in | §2.4, [TOOL-PROFILES.md](/docs/reference/TOOL-PROFILES.md)(/docs/reference/TOOL-PROFILES.md) |
| Tool-profile failures | **1 → `suspect`, 2 → `stale` (back to generate, on fresh observation), 3 → retire** via `ga-remove.sh`. A failure is the recorded recipe not working; an authorization prompt is not one | Without a fixed threshold the question is argued every time one fails | [TOOL-PROFILES.md](/docs/reference/TOOL-PROFILES.md)(/docs/reference/TOOL-PROFILES.md) |
| Meta-commentary | **`.claude/log.md`**, appended by `Scripts/ga-log.sh` — never a skill, command, script, doc or `#` comment. It is **never read to decide anything**; this file is | The reasoning had no legal home and landed in reusable files, where it rots. Two normative sources would leave one stale, hence the read-nothing rule | [STRUCTURE.md](/docs/reference/STRUCTURE.md)(/docs/reference/STRUCTURE.md), §2.7 |
| OpenSpec precedence | **Installed, OpenSpec is the priority executor for spec-workflow work** — proposing, planning, specs, tasks, archiving. No house skill may claim that vocabulary, whether or not OpenSpec is present | A house skill firing on "propose a change" produces a package nobody asked for and skips the spec that was the point. `Scripts/check-skill-triggers.py` enforces it either way | [OPENSPEC.md](/docs/reference/OPENSPEC.md)(/docs/reference/OPENSPEC.md) |
| Ecosystem detection | **None ships.** The layer carries no table of build markers and recognises no language, build system or dependency manager. `ga_check_compatible` answers only *is this tree empty*. `--extract` matches nothing but a profile the project itself authored, via its `detect_marker_*` rows | A built-in marker table is stack content: permanently incomplete, and a standing statement about which ecosystems are first-class. Detecting 12 and missing the 13th is bias, not neutrality — so the layer detects none and asks instead | §1, `Scripts/ga-profile.sh` |
| Stack declaration | **Its own gated step** — `declare-profile`, between install and project-init. Satisfied by an active profile **or** by consciously declaring none. `declared` is a separate key from `active`, which stays empty either way | `ready` used to certify a repo nobody had asked, leaving the whole stack half dormant with nothing saying so. And `active=none` would send every `[ -z "$PROFILE" ]` reader hunting for `profiles/none/` | [SEQUENCE.md](/docs/operations/SEQUENCE.md)(/docs/operations/SEQUENCE.md), `Scripts/ga-profile.sh` |
| Tool profiles at adopt time | **Scaffolded, never copied.** A target gets `.claude/tools/CLAUDE.md` verbatim and a header-only `LEDGER.tsv`; no `<tool>.md`, no `Scripts/Generated/`, and the generated spans in `MAP.tsv` and the registry note are blanked between their markers | A consumer must not inherit a verified profile no session of theirs observed — prose and rules travel, observations do not | [TOOL-PROFILES.md](/docs/reference/TOOL-PROFILES.md)(/docs/reference/TOOL-PROFILES.md), [`Scripts/adopt.sh`](../Scripts/adopt.sh) |

## Ask every time — never assume

**Any new external dependency**, always, before adding it. Everything else that once lived here —
presentation pattern, persistence, caching, package extraction, deployment floors — is the **active
profile's** to state; the neutral layer asks nothing stack-specific of its own. Record the answer
below with `/decide`.

## Do not re-propose

Rejected with reasons already recorded — reopen only with new information, not a fresh preference.

| Rejected | Where the reasoning lives |
|---|---|
| Baking a stack into the layer, or shipping a built-in "default" profile | The *Reference profile* row above — the layer is machinery; a stack is a profile a project authors |
| Forking OpenSpec's schema or copying its templates into this repo | [OPENSPEC.md](/docs/reference/OPENSPEC.md)(/docs/reference/OPENSPEC.md) — a copy of a file other people revise is what rots. Extra guidance goes in their `rules:` keys, which are config we own |
| A GenericArch OpenSpec *store* exposing rules as generated specs | [OPENSPEC.md](/docs/reference/OPENSPEC.md)(/docs/reference/OPENSPEC.md) — the spec format wants `SHALL` plus examples, so every generated spec would invent untested normative prose. Stores are also beta with no auto-sync |

## Open

| Question | Blocks | Note |
|---|---|---|
| A `profile.tsv` schema and a lint for an authored `profiles/<name>/` directory | The first non-trivial profile | Narrowed: `ga-profile.sh --check` now validates the **projection** — row shape, `active` resolving to a real profile, `declared` present, tracked in git. The static definition's own contract is still unwritten |
