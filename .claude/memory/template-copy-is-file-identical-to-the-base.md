---
name: template-copy-is-file-identical-to-the-base
description: A `gh repo create --template` copy of this repo is byte-identical to the authoring checkout — no file can tell them apart, only git history can, which is why two marker-based checks silently broke the whole template install path
metadata:
  type: project
---

`docs/SHARING.md`'s **Never travels** list (`Packages/`, `App/`, `.claude-plugin/`, `README.md`,
`CLAUDE.md`) describes what **`install.sh`/`adopt.sh`** copy. GitHub's template feature obeys none of
it: it copies every **tracked** file. So in `MyApp`, created from the template, `.claude-plugin/`,
`Scripts/adopt.sh`, `Scaffold/` and `Packages/` are all present — and two places had read exactly
that as *"this directory is GenericArch itself"*:

- `ga-step.sh derive_steps` recorded `install` **and** `scaffold` as not-applicable, so
  `/project-init` cleared its gate with no structure behind it;
- `ga-scaffold.sh`'s self-target guard then refused the repo outright — *"the target is the
  GenericArch checkout itself"*.

Net effect for anyone following README path A: a product holding the `Core`+`DIKit` floor, **no
`App/`, no layers**, and no command that would add them. Fixed 2026-08-21 with
`ga_is_source_checkout` / `ga_is_template_copy` in `Scripts/ga-lifecycle.sh`, which key on **history**
— a release tag merged into `HEAD` — and fall back to the directory name only when there is no git at
all.

Two traps worth keeping:

- The safe default when the signal is missing is **product**, not base. A product misread as the base
  is silently blocked; the base misread as a product still has to pass a confirm prompt.
- A template copy also inherits this repo's *answers* — the seed `platforms:` floors, and a
  `.gitignore` that ignores `.genericarch/` (correct here, wrong in a product). `ga-scaffold.sh`
  therefore refuses to detect floors from a template copy's own manifests: it would launder this
  repo's `macOS("26.6")` into a new layer as if the product had chosen it (CLAUDE.md §0).

**Why:** the base and a product built from it are the same bytes at t=0, so identity is a question
about history, never about files — and getting it wrong fails in the direction nobody tests, a
brand-new repo nobody has yet.

**How to apply:** never add a third "is this GenericArch?" check from file presence — call
`ga_is_source_checkout`. When something must be true of the base and false of a product, ask what a
template copy would carry before choosing the signal. See [[claude-md-section-numbers-are-load-bearing]]
for the other case where a cheap-looking marker was load-bearing repo-wide.
