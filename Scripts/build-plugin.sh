#!/usr/bin/env bash
# Generate a publishable Claude Code plugin from the canonical .claude/ sources.
#
#   ./Scripts/build-plugin.sh            # writes dist/genericarch/
#   ./Scripts/build-plugin.sh 0.2.0      # sets the version
#
# The plugin is GENERATED, never hand-maintained. `.claude/skills` and `.claude/commands` stay the
# single source of truth — a hand-copied plugin drifts, and a doc that drifts is worse than none.
#
# Ships only the tooling layer. CLAUDE.md and docs/ deliberately stay out: those are a product's
# rules, and a plugin that overwrote them would stop each product setting its own (docs/SHARING.md).
set -o pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.1.0}"
OUT="dist/genericarch"
GRN=$'\033[32m'; DIM=$'\033[2m'; BLD=$'\033[1m'; OFF=$'\033[0m'

rm -rf "$OUT"
mkdir -p "$OUT/.claude-plugin"

# Plugin layout expects skills/ and commands/ at the plugin root — not under .claude/.
cp -R .claude/skills   "$OUT/skills"
cp -R .claude/commands "$OUT/commands"

cat > "$OUT/.claude-plugin/plugin.json" <<JSON
{
  "name": "genericarch",
  "description": "Apple-platform app architecture for iPhone/iPad/Mac from one codebase — SwiftUI, Swift 6 strict concurrency, SPM only. Adds skills for scaffolding features, dark mode and RTL verification, package releases, and inventory notes; commands for build, verify, decide, gaps, and project adoption.",
  "version": "$VERSION",
  "author": { "name": "GenericArch" },
  "homepage": "https://github.com/kalpesh-jetani/GenericArch",
  "keywords": ["swift", "swiftui", "ios", "macos", "architecture", "spm"]
}
JSON

# A marketplace entry so a team can host this for `/plugin marketplace add`.
cat > "$OUT/.claude-plugin/marketplace.json" <<JSON
{
  "name": "genericarch-marketplace",
  "owner": { "name": "kalpesh-jetani" },
  "plugins": [
    {
      "name": "genericarch",
      "source": "./",
      "description": "Apple-platform app architecture skills and commands."
    }
  ]
}
JSON

cat > "$OUT/README.md" <<'MD'
# GenericArch — Claude Code plugin

Skills and commands from the GenericArch Apple-platform architecture. **Generated** by
`Scripts/build-plugin.sh` — edit the sources in `.claude/` of the GenericArch repo, not here.

## What it adds

| Skill | Fires when |
|---|---|
| `new-feature` | Adding a feature or screen |
| `dark-light-mode` | A colour or asset changes, or something looks wrong in dark |
| `rtl-support` | Adding a locale, or verifying mirroring |
| `release-bump` | Releasing an extracted package |

| Command | Does |
|---|---|
| `/project-init` | Initialize a fresh repo, or adopt this structure into an existing one |
| `/verify` | Walk the Definition of Done against the working diff |
| `/gaps` | Triage the gap list — derived from code on an existing repo |
| `/decide` | Record a settled decision |
| `/upgrade-stack` | Reconcile project settings with the machine — asks twice |
| `/sync-app-notes` | Rebuild the seven inventories from a filesystem scan |
| `/build` | Build, test, or archive a stage |

## What it does NOT add

`CLAUDE.md`, `docs/`, `.claude/notes/`, or any Swift code. Those are a product's own rules, design
notes, and state. Get them with `Scripts/adopt.sh` from the GenericArch repo, or by using it as a
template for a new repo.

Because of that split, the commands reference `docs/…` paths that only exist once the docs are
adopted. The skills work standalone; `/verify`, `/decide`, and `/gaps` need their target files.
MD

echo "${GRN}built${OFF} $OUT ${DIM}(version $VERSION)${OFF}"
echo "  skills:   $(ls "$OUT/skills" | wc -l | tr -d ' ')"
echo "  commands: $(ls "$OUT/commands" | wc -l | tr -d ' ')"
echo
cat <<NEXT
${BLD}To publish${OFF}
  cd $OUT && git init && git add -A && git commit -m "genericarch plugin $VERSION"
  gh repo create kalpesh-jetani/genericarch-plugin --public --source=. --push

${BLD}To install in any repo${OFF}
  /plugin marketplace add kalpesh-jetani/genericarch-plugin
  /plugin install genericarch

${DIM}Verify the manifest field names against the Claude Code plugin docs for your version before
publishing — the schema is set by the tool, not by this repo.${OFF}
NEXT
