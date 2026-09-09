# Figma — design files, variables and screenshots, reached through the Figma MCP connector

- **Platform:** Figma — design files, variables and screenshots, reached through the Figma MCP connector
- **Reached via:** connector mcp__…figma__* — wired and authenticated (verified by whoami)
- **Read it when** extracting one of the attributes below, or deciding whether one is reachable
- **Recipe:** `./Scripts/Generated/figma.sh` — the call sequence, wired and unwired
- **Status:** active · failures 0 · **Last verified:** 2026-09-09

Every row below was observed in a real response. `not observed` means exactly that and is
left alone until it is actually seen — see [TOOL-PROFILES.md](../../docs/TOOL-PROFILES.md).

---

## Attributes

| Attribute | Unit / type | Accessible | Extraction method | Scope | Observed |
|---|---|---|---|---|---|
| account handle | string | yes | whoami, field handle | per account | 2026-09-09 |
| account email | string | yes | whoami, field email | per account | 2026-09-09 |
| plan key | team::<int> | yes | whoami, field plans[].key | per account | 2026-09-09 |
| plan tier | string | yes | whoami, field plans[].tier | per account | 2026-09-09 |
| plan seat | string | yes | whoami, field plans[].seat | per account | 2026-09-09 |
| fileKey | 22-128 chars, [0-9a-zA-Z] | not observed | get_metadata contract; the /design/<fileKey>/ URL segment | per file | contract |
| nodeId | <int>:<int> or <int>-<int> | not observed | get_metadata contract; the ?node-id= query param | per node | contract |
| page list | guid + name | not observed | get_metadata with fileKey and nodeId omitted | per file | contract |
| frame aspect ratio | not observed | not observed | not observed | not observed | — |

## Connectivity

**Wired.** The connector answered on 2026-09-09; `whoami` returned a handle, an email and one
plan, so authentication is live and no OAuth step is pending. `whoami` is also the documented
call for diagnosing a permission or rate-limit failure — reach for it before assuming a file is
missing.

**Unwired** — when the connector is absent and a file URL was pasted instead, two things are
still obtainable from the URL alone, because they are literal segments of it:

- `fileKey` — the segment after `/design/`. For a branch URL,
  `/design/<fileKey>/branch/<branchKey>/…`, the **branchKey is the key to use**, not the fileKey.
- `nodeId` — the `?node-id=` query parameter, url-decoded, with `-` normalised to `:`.

Everything else needs either the connector or the user: a rendered frame, an exported asset, and
any measurement taken from one (a frame's aspect ratio included) must be asked for as a
screenshot or an export.

## Usage notes and gotchas

- **Three URL kinds are not interchangeable.** `get_metadata` is documented as design-file only
  (`/design/`); FigJam (`/board/`), Slides (`/slides/`) and Make (`/make/`) are unsupported. A
  pasted board URL will fail for that reason, not because the file is missing.
- **Omit `nodeId` rather than guessing one.** With `fileKey` alone the call is documented to
  return the top-level page list, which is how you find a real node id. An invented or empty
  `nodeId` is rejected by the schema pattern.
- **`whoami` returns PII** — a handle and an email. The values must never be copied into this
  file, a log, or a commit; only their shapes are recorded above (CLAUDE.md §8).
- **`whoami`'s response carries a trailing `resource_link`** to a rate-limits document alongside
  the JSON body, so a strict JSON parse of the whole response fails. Parse the object, not the
  stream.
- **`frame aspect ratio` is deliberately blank.** The obvious guess is that `get_screenshot`
  returns it, and no call here has shown that. `--extend` fills the row in when one does.
