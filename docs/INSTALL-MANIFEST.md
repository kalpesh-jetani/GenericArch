# Install manifest — the record uninstall.sh trusts

Format reference for `.genericarch/manifest-v<version>.json`, written by `install.sh` and read by
`uninstall.sh`.

- **When to read this:** inspecting what an install actually did, debugging an uninstall that kept
  files you expected it to remove, or changing either script.

`install.sh` writes this file **last, and only on full success**, so its presence is itself the
proof that the install completed. `uninstall.sh` reads it and nothing else: no globbing, no
guessing from a file list, no `rm -rf` on a path that did not come from here.

---

## Why a manifest and not a file list

A hardcoded list says what a release *ships*. It cannot answer the only question that matters when
removing files: **is this exact file on disk still the one we put there, or has someone edited it?**
Only a recorded hash answers that, and the answer decides whether a file is deleted or defended.

So ownership is proven, never assumed. Three consequences follow, and they are the whole contract:

| Situation | What uninstall does |
|---|---|
| Hash matches the record | GenericArch's, unmodified → removed |
| Hash differs from the record | **You edited it** → kept, listed, reason given |
| Path not in the manifest | Not ours → never read, never touched |

A timestamp may corroborate ownership. It never decides it — **a content-hash mismatch always wins
and always protects the file.** Timestamps change for reasons that have nothing to do with content
(`cp`, a checkout, a backup restore), so trusting one to authorise a deletion would delete files it
had no business touching.

---

## Top level

| Field | Type | What it is |
|---|---|---|
| `schema` | int | Format version of **this file's shape**. `uninstall.sh` keys its parser off it. Bumped only when the layout changes — never for a GenericArch release |
| `genericarch_version` | string | The release installed, e.g. `v0.2.0`. `uninstall.sh <version>` is validated against this |
| `target` | string | Absolute path of the repo installed into, as resolved at install time |
| `source_ref` | string | Git commit of the GenericArch checkout the files came from — the exact provenance a tag name cannot give you |
| `installed_at` | string | UTC ISO-8601, one value for the whole run |
| `installer` | string | Which script wrote it |
| `state_dir` | string | Where GenericArch keeps its own state, relative to `target` |
| `files` | array | One record per path, below |

## Per-file records

Every record is **exactly one line** of the file. That is deliberate: the format has to be both
valid JSON and parseable by one `awk`, because a stock macOS box has no `jq` and an installer that
needs a dependency installed first is not an installer.

| Field | Type | What it is |
|---|---|---|
| `path` | string | Relative to `target`. Always forward-slashed, never absolute |
| `action` | string | `created` · `modified` · `skipped` — see below |
| `sha256` | string | Hash of the content **as installed**. For `modified`, that means *after* the managed block was appended |
| `installed_at` | string | The path's mtime at install time, UTC ISO-8601 |
| `backup` | string \| null | For `modified`: where the untouched original was copied. `null` otherwise |
| `original_sha256` | string \| null | For `modified`: hash of the file **before** install. What a restore is verified against, so "restored byte-for-byte" is checked rather than claimed |
| `version` | string | The release that installed this path |

### The three actions

- **`created`** — GenericArch owns this path. Removed on uninstall if the hash still matches.

  It means *owned*, not *freshly written this run*. A re-install re-asserts ownership of a path it
  installed earlier, and adopts a path already byte-identical to what it ships — identical content
  **is** the proof of ownership the contract asks for. Without this, a second install would disown
  everything the first one put there, and uninstall would then clean up nothing.

- **`modified`** — the path existed and GenericArch appended a delimited managed block to it. The
  original is at `backup`, hashed in `original_sha256`. The only file in the current release with
  this action is `.gitignore`.

- **`skipped`** — the path existed with content that is not ours. **Never written, never removed.**
  Recorded so the plan can show what was left alone and why.

---

## Managed config blocks

Where GenericArch must add lines to a file the repo already owns, they go between these markers and
nowhere else:

```
# >>> GenericArch managed block — do not edit; removed by uninstall.sh >>>
.claude/claude-tasks/
dist/
# <<< GenericArch managed block <<<
```

Two properties come from the delimiters. The block is **idempotent** — a re-install finds it and
appends nothing, so entries never accumulate. And it is **removable without a diff**: uninstall
deletes the marked span and every surrounding line stays byte-identical.

Restoring has a primary path and a fallback:

1. **Restore the backup** and verify against `original_sha256`. Byte-exact by construction. Used
   whenever the file is untouched since install and the backup is present.
2. **Strip just the block.** Used when the backup is gone, or when *you edited the file after
   install* — there, restoring the backup would throw your edits away, so only GenericArch's lines
   come out. One known limitation: the strip is line-based, so a file that had **no trailing
   newline** before install gains one. `uninstall.sh` says so when it takes this path.

---

## Example

An install into a repo that already had its own `.gitignore` and its own skill:

```json
{
  "schema": 1,
  "genericarch_version": "v0.2.0",
  "target": "/Users/you/Code/MyApp",
  "source_ref": "5196c2e5b9d0a1f4c8e2b7a3d6f091ac4e8b12d7",
  "installed_at": "2026-08-18T09:47:02Z",
  "installer": "install.sh",
  "state_dir": ".genericarch",
  "files": [
    {"path": ".claude/MAP.tsv", "action": "created", "sha256": "9f2b1c...", "installed_at": "2026-08-18T09:47:02Z", "backup": null, "original_sha256": null, "version": "v0.2.0"},
    {"path": "Scripts/check.sh", "action": "created", "sha256": "4ad81e...", "installed_at": "2026-08-18T09:47:02Z", "backup": null, "original_sha256": null, "version": "v0.2.0"},
    {"path": ".swiftlint.yml", "action": "skipped", "sha256": "c07f33...", "installed_at": "2026-03-02T11:20:44Z", "backup": null, "original_sha256": null, "version": "v0.2.0"},
    {"path": ".gitignore", "action": "modified", "sha256": "718cf1...", "installed_at": "2026-08-18T09:47:02Z", "backup": ".genericarch/backups/gitignore.v0.2.0.bak", "original_sha256": "eff00d...", "version": "v0.2.0"}
  ]
}
```

Reading that back: `MAP.tsv` and `check.sh` are ours and go on uninstall. `.swiftlint.yml` was
already yours — its `installed_at` predates the run, and it is never touched. `.gitignore` gained
the managed block and its original is recoverable and verifiable.

---

## Reading it without jq

```bash
grep '"path":' .genericarch/manifest-v0.2.0.json | wc -l          # how many paths recorded
grep '"action": "skipped"' .genericarch/manifest-v0.2.0.json      # what was left alone
grep '"action": "modified"' .genericarch/manifest-v0.2.0.json     # what got a managed block
```

To re-verify an install by hand — every line should print `ok`:

```bash
grep '"path":' .genericarch/manifest-v0.2.0.json \
  | sed -e 's/.*"path": "//' -e 's/".*//' \
  | while read -r p; do
      printf '%s  %s\n' "$([ -f "$p" ] && shasum -a 256 "$p" | awk '{print $1}' || echo MISSING)" "$p"
    done
```

## When there is no manifest

If `install.sh` was killed mid-run or blocked by the compatibility gate, there may be files but no
manifest. `uninstall.sh` falls back to the known file list for the requested version — but that list
only **narrows the search**, it never authorises a removal. Each candidate is still proven by
hashing it against the blob that release actually shipped, read from a reference checkout with
`git cat-file` (no checkout switch, no network):

```bash
./uninstall.sh v0.2.0 --target /path/to/repo --base /path/to/GenericArch
```

With no reference checkout, ownership cannot be proven, so **nothing is removed** and the script
says so. Files GenericArch *generates* rather than copies — the `.claude/notes/` inventories,
`docs/DECISIONS.md`, `docs/GAPS.md`, `genericarch.installation.md` — have no shipped blob to compare
against, so a fallback uninstall keeps them and lists them. That is the safe outcome, and the reason
the manifest is worth writing.
