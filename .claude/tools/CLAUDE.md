# Tool profiles — rules that only bind here

Scoped rules for `.claude/tools/`. Every file here records what one **external platform**
exposes, and how to reach it. Reference and lifecycle: [TOOL-PROFILES.md](../../docs/TOOL-PROFILES.md).

---

## Boundary

- **Owns:** what each external platform exposes — attribute names, units, reachability,
  extraction method, scope — and how it is reached wired or unwired.
- **May depend on:** nothing. These are observations, not code.
- **Never imports, and never contains:** credentials, tokens or response bodies (CLAUDE.md §8);
  *why* the platform was adopted (that is `docs/resources/`, via `/learn`); any Swift type.

---

## The five rules

**1. Observation only.** Every cell comes from a response actually received. Anything not seen
is written `not observed` and left there — never inferred from the vendor's API, never carried
over from a similar platform, never completed because a value looks obvious. A wrong unit is
worse than a missing one, because a wrong one is trusted.

**2. One profile per platform.** A new requirement needing a different input or output
**extends** the existing profile:

```bash
./Scripts/ga-tool-note.sh <tool> --extend
```

**3. Never read a generated script's body.** The `#@` header is the whole contract, and
`.claude/SCRIPTS.tsv` carries it. When a call fails, read `.genericarch/failures/`, fix the
script, and re-run `./Scripts/claude-utils/register-scripts.sh` (CLAUDE.md §5).

**4. Never `rm` a profile.** Retirement moves it to `.genericarch/safetodelete/` and tombstones
it, so no later run re-creates it (CLAUDE.md §2.15):

```bash
./Scripts/ga-tool-note.sh <tool> --retire --reason "<why>"   # tombstones the profile AND the recipe
./Scripts/ga-tool-note.sh <tool> --revive --apply            # restores both — never just one
```

**5. No meta-commentary in this directory.** A profile records observations and gotchas, not the
story of finding them. Why a decision was taken goes to `.claude/log.md`:

```bash
./Scripts/ga-log.sh --decided "<what>" --why "<reason>" --how "<approach>"
```

---

## What is generated, and by what

| Path | Written by |
|---|---|
| `<tool>.md` — one platform's attribute profile | `./Scripts/ga-tool-note.sh <tool> --apply` |
| `LEDGER.tsv` — status, failure count, verified date | the same script; it is the source of truth |
| `../skills/tool-profile/references/generated-skills-note.md` — the lookup registry | `./Scripts/ga-tool-note.sh --sync`, from the ledger |

`LEDGER.tsv` is the record; the registry note is regenerated from it. Edit the ledger, never the
note.
