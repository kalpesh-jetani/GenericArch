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
| Dependency injection | **Own typed registry**, no third party | Least root boilerplate, no vendor to wrap. Its two failure modes are designed out, not tolerated | §2.6 |
| `DependencyKey` | Two values — `liveValue`, `testValue` | A third `previewValue` defaulted to `testValue` and earned nothing | §2.6 |
| Presentation options | MVVM + `@Observable` (default) **or** view-owned for trivial screens | §3's shared-behavior promise only holds if screens share a shape | §0 |
| Inheritance | Protocol + extension. **No generic base classes** | Sits badly beside "prefer composition"; the extension path already delivers it | §3 |
| Paged content | Page state nested **inside** the screen's state value | Prevents per-feature `isLoadingMore`; stops a failed page discarding loaded rows | §2.5 |
| Typed throws | Inside a package only; **untyped** at an extracted package's public boundary | Widening a typed throw is a major bump for a routine new error case | §6 |
| Certificate pinning | **Off by default**; opt-in per product | A rotated cert bricks every installed copy with no remote fix | §8 |
| Snapshot scope | Full matrix for DesignSystem components; screens get `loaded` + one failure | The full matrix per screen is 40+ each and becomes the flakiest suite | §9 |
| Contrast | Asserted by token test, **not** tabulated in a note | A hand-maintained duplicate of a test result drifts, then gets believed | [ASSETS-COLORS.md](../.claude/notes/ASSETS-COLORS.md) |
| Dependency graph | **No `DEPENDENCY-GRAPH.md`** | Would drift; the DEBUG container dump + per-package key tests are automatic | §2.6 |
| Repo boundary | **Two repos.** This one installs into a repo that already has its Xcode project; the project checklist and the package layout live in [GenericXCodeSetup](https://github.com/kalpesh-jetani/GenericXCodeSetup) | They answer different questions. Every guarantee here comes from the installer — a manifest, hashes, a reversible uninstall — and none of it means anything in an empty directory. Keeping the layout here meant carrying a code path for a repo that does not exist yet | [SHARING.md](SHARING.md) |
| Install shapes | **One.** `install.sh` refuses a target with no project and no structure, and `--mode` is gone | Two modes meant every gate, every ledger row and every doc had to say which one it meant. The second one was for a repo this base has nothing to reconcile against | [SEQUENCE.md](SEQUENCE.md) |
| Lifecycle steps | **No `scaffold` step** — install → project-init → gaps → sync-app-notes → ready | Nothing here creates a package layout any more, so a step that could never run was a gate everything else waited behind | §5 |
| Module docs | **None.** The base ships no per-package doc; a package's doc lives beside its code as `Packages/<Name>/<Name>.md` | A root-level doc outlives the package it names: it reads as current, describes code that is not there, and the index routes to it forever. Every session concluded `DIKit` existed, failed to find it, and demanded it again | [STRUCTURE.md](STRUCTURE.md), [REPO.md](REPO.md) |
| Offering a gated command | **A command never offers one whose `require` line would fail at that moment** — it describes the order and runs nothing | A step records itself at its end, so anything gated on it is refused for its whole run. `/project-init` S3 offered `/sync-app-notes`; the gate exited 5, its header said stop, and the next run offered it again | [SEQUENCE.md](SEQUENCE.md) |
| Recording a resolution | **Every resolved conflict is *Settled* or *Do not re-propose* before the step is recorded** — S5 lists any that are not and refuses to continue. Only a genuine deferral is *Open* | §0 reads an *Open* row as unanswered and asks again. A resolution that exists only in a transcript is gone next session, so the question returns forever | [ADOPTION.md](ADOPTION.md) §A6 |
| Layer selection | **Derived from requirements, never defaulted.** `/project-init` proposes only what the requirements reach; its table is an illustration of what each layer is *for* | "Default to Core + Navigation" was a default in a base that ships no architecture, and the answer landed under *Open*, so it was re-asked every run | [REPO.md](REPO.md) |
| Component rules | **Every component carries its own `CLAUDE.md`** — boundary first, then rules true only inside it. No list of components is ever written; the rule follows the directory that exists | A rule reaches the session about to break it, at the moment it would, and costs nothing until then. A catalogue of components that *should* exist is what the retired per-module docs were | §2.16, [STRUCTURE.md](STRUCTURE.md) |
| Component reference doc | **Optional** — `<component>/<Name>.md`, only when a caller needs it | Rules must be pushed; reference is pulled. Making it mandatory buys a file nobody opens | [STRUCTURE.md](STRUCTURE.md) |
| Layer shape | **Described, never asserted.** [REPO.md](REPO.md) §Layout gives the shape a product *may* take and what each layer owns; a product has whatever subset it needs | A §2 rule must stay binding without naming a package that owns it. Naming one turns a rule into a claim about the filesystem | §2, [REPO.md](REPO.md) |
| OpenSpec | **Adopted** as an optional external CLI, wired by `/openspec-install`. It is the third external dependency, so the supply-chain policy [GAPS.md](GAPS.md) deferred is now due | Spec-driven planning the agent follows step by step, where this layer had none. Optional because a product that does not want it should carry nothing but one doc row | [OPENSPEC.md](OPENSPEC.md), §0 |
| OpenSpec install | **Unpinned, resolved live** from `https://github.com/Fission-AI/openspec` each run — no version, package name or install command is recorded here | Their repo is revised by other people; a copy of any of it is stale the moment they change it. The cost is accepted: an unpinned install is not reproducible, and the resolved version goes in the run's report, not into a file | [OPENSPEC.md](OPENSPEC.md) |
| OpenSpec projection | **Reads the repo it runs in**, never a GenericArch checkout, and `openspec-sync.sh` **writes no YAML** — it computes, the command applies | `CLAUDE.md` does not travel and `DECISIONS.md` arrives empty, so a projector reading the base would arrive with its inputs missing. And sed/awk surgery on a block scalar whose indentation is semantic is the least safe part of the bridge | [OPENSPEC.md](OPENSPEC.md), [ADOPTION.md](ADOPTION.md) |
| OpenSpec parser defects | **Revise the script, and file an issue** — `github.com/kalpesh-jetani/GenericArch/issues`, naming the branch. An **issue only**: no branch, no commit, no PR, so §2.11 needs no exception. Limited to `SHAPE-UNRECOGNISED` and an installed CLI returning nothing | Their interface moving makes this repo wrong, and a warning nobody tracks is how a bridge rots. Narrow on purpose: a missing CLI or a repo without OpenSpec files nothing | [OPENSPEC.md](OPENSPEC.md) |
| Version support | **v0.6 is the LTS line** (`GA_LTS_LINE`), current patch `GA_LATEST_VERSION`. Below `GA_INSTALL_FLOOR` = v0.6.0 is deprecated: **removable, never installable** | Deprecating a release must mean "do not put this on anything new", never "you can no longer get it off". Stripping old versions from the supported list would strand every install that has one — and break `ga-roots.sh`, whose output is the uninstall command for older residue | [SHARING.md](SHARING.md), `Scripts/ga-lifecycle.sh` |
| OpenSpec staleness | **`./Scripts/check.sh`**, as a warning that skips when there is no OpenSpec config | The projection is built from `CLAUDE.md` §2 and `DECISIONS.md`, so editing a rule stales it silently. Hanging it off the gate that already runs before a PR removes a habit nobody would keep | [OPENSPEC.md](OPENSPEC.md), [DELIVERY.md](DELIVERY.md) |
| Tool profiles | **`.claude/tools/<tool>.md`** holds what one external platform exposes — attributes, units, reachability, extraction method, scope. One profile per platform; a new input or output **extends** it | The next session otherwise re-reaches the platform to rediscover what it exposes, or infers it. `docs/resources/` answers *why* we adopted a vendor and cannot answer *how to drive it* | [TOOL-PROFILES.md](TOOL-PROFILES.md) |
| Tool-profile provenance | **Observation only.** Every cell comes from a real response; anything unseen is written `not observed` and left there. `--apply` refuses a profile with no observed row | A wrong unit is worse than a missing one because it is trusted. `not observed` is a required entry, not a gap to fill in — without that, someone completes the blanks helpfully and the profile becomes confidently wrong | §2.14, [TOOL-PROFILES.md](TOOL-PROFILES.md) |
| Tool-profile failures | **1 → `suspect`, 2 → `stale` (back to generate, on fresh observation), 3 → retire** via `ga-remove.sh`. A failure is the recorded recipe not working; an authorization prompt is not one | Without a fixed threshold the question is argued every time one fails. A failure has no repair operation of its own on purpose: there is one way a profile comes into existence, and a stale one re-enters it rather than being patched | [TOOL-PROFILES.md](TOOL-PROFILES.md) |
| Meta-commentary | **`.claude/log.md`**, appended by `Scripts/ga-log.sh` — never a skill, command, script, doc or `#` comment. It is **never read to decide anything**; this file is | §10 sends narration to the commit message and §2.11 forbids committing, so the reasoning had no legal home and landed in reusable files, where it rots. Two normative sources would leave one stale, hence the read-nothing rule | [STRUCTURE.md](STRUCTURE.md) |
| OpenSpec precedence | **Installed, OpenSpec is the priority executor for spec-workflow work** — proposing, planning, specs, tasks, archiving. No house skill may claim that vocabulary, whether or not OpenSpec is present. Until `/openspec-install` runs it is not in the repo at all | GenericArch is the existing repo and OpenSpec arrives on demand, so the boundary has to hold *before* it is installed: a description written while it is absent is the one that mis-fires once it is there. A house skill firing on "propose a change" produces a package nobody asked for and skips the spec that was the point. `Scripts/check-skill-triggers.py`'s `SPEC_WORKFLOW` fixtures enforce it either way, which is why they run even when the checker reports OpenSpec absent | [OPENSPEC.md](OPENSPEC.md), [evals](../.claude/skills/tool-profile/evals/README.md) |

## Ask every time — never assume

Presentation pattern (per feature/screen) · persistence engine (only if data is stored) · caching
and offline policy (any remote fetch) · any new external dependency · extracting a package ·
**deployment floors** (before any `platforms:` line — never defaulted).
Options and phrasing: the `new-feature` skill carries the first five; deployment floors are
`Packages/FLOORS.md` in the target. *Which layers exist on day one* is not asked here — it is settled
before this base is installed, by [GenericXCodeSetup](https://github.com/kalpesh-jetani/GenericXCodeSetup).
Record the answer below.

## Do not re-propose

Rejected with reasons already recorded — reopen only with new information, not a fresh preference.

| Rejected | Where the reasoning lives |
|---|---|
| Multi-repo per package *(tried, reversed 2026-08-12)* | §4.2 |
| Tuist · XcodeGen | [REPO.md](REPO.md) |
| Manual composition root · `@Environment`-only DI · third-party container | §2.6 |
| Reducer/TCA presentation | §0 |
| `SmartSense-` · `SSS-` name prefixes | — |
| `AsyncImage` for lists | the image-cache layer ([REPO.md](REPO.md)) |
| Twelve `docs/modules/*.md`, one per package *(deleted 2026-09-04)* | The *Module docs* row above — reinstating them reopens the demand loop |
| Forking OpenSpec's schema or copying its templates into this repo | [OPENSPEC.md](OPENSPEC.md) — a copy of a file other people revise is what rots. Extra guidance goes in their `rules:` keys, which are config we own |
| A GenericArch OpenSpec *store* exposing §2 as generated specs | [OPENSPEC.md](OPENSPEC.md) — §2 is prohibitions, and the spec format wants `SHALL` plus scenarios, so every generated spec would invent untested normative prose. Stores are also beta with no auto-sync |

## Open

| Question | Blocks | Note |
|---|---|---|
| Visual language across iOS 17 / macOS 26 — native-per-platform vs. one owned look | Nothing yet | Only blocks once DesignSystem tokens go beyond platform-neutral (§1.1) |
| macOS 26.6 minimum — verify against real user data | First release | Excludes every Mac that can't run macOS 26 ([GAPS.md](GAPS.md) E1) |
| Whether a fresh install should ship the nine notes at all, given they arrive carrying this base's own example rows | The first note lookup in an adopted repo | Observed 2026-08-22: `PROJECT.md` named `GenericArch-iOS`/`-macOS` targets and `API-MAP.md` a `doo/device` group, in a repo with neither. A note is greppable from install, so it answers wrongly before `/sync-app-notes` ever runs |

---

## Per feature

| Date | Feature | Presentation | Persistence | Caching / offline |
|---|---|---|---|---|
| — | — | — | — | — |
