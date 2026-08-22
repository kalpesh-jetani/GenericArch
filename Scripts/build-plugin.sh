#!/usr/bin/env bash
#@kind      tool
#@platform  macos
#@claude    call
#@purpose   Generate the publishable Claude Code plugin from .claude/skills and .claude/commands.
#@usage     build-plugin.sh [version]
#@in        version:semver(default: the version in .claude-plugin/plugin.json)
#@out       dist/genericarch/:dir(plugin.json,marketplace.json,skills,commands,README.md)
#@exit      0=built
#@effects   writes dist/ (gitignored)
# Generate a publishable Claude Code plugin from the canonical .claude/ sources.
#
#   ./Scripts/build-plugin.sh            # writes dist/genericarch/ at the manifest's version
#   ./Scripts/build-plugin.sh 0.7.0      # overrides the version for this build
#
# The plugin is GENERATED, never hand-maintained. `.claude/skills` and `.claude/commands` stay the
# single source of truth — a hand-copied plugin drifts, and a doc that drifts is worse than none.
#
# Its NAME and DESCRIPTION come from .claude-plugin/plugin.json for the same reason. A second copy
# lived here and drifted: it still advertised a Swift version this repo refuses to state from memory
# (CLAUDE.md §1), and listed dark-mode, RTL and release skills that only ever existed as patterns
# under docs/patterns/. Whoever browsed the marketplace read that copy, not the accurate one.
#
# Ships only the tooling layer. CLAUDE.md and docs/ deliberately stay out: those are a product's
# rules, and a plugin that overwrote them would stop each product setting its own (docs/SHARING.md).
set -o pipefail
cd "$(dirname "$0")/.."

MANIFEST=".claude-plugin/plugin.json"
[ -f "$MANIFEST" ] || { echo "cannot build: $MANIFEST is missing" >&2; exit 1; }
VERSION="${1:-$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$MANIFEST")}"
OUT="dist/genericarch"
GRN=$'\033[32m'; DIM=$'\033[2m'; BLD=$'\033[1m'; OFF=$'\033[0m'

rm -rf "$OUT"
mkdir -p "$OUT/.claude-plugin"

# Plugin layout expects skills/ and commands/ at the plugin root — not under .claude/.
cp -R .claude/skills   "$OUT/skills"
cp -R .claude/commands "$OUT/commands"

python3 - "$MANIFEST" "$VERSION" > "$OUT/.claude-plugin/plugin.json" <<'PY'
import json, sys
manifest = json.load(open(sys.argv[1]))
manifest["version"] = sys.argv[2]
print(json.dumps(manifest, indent=2))
PY

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

# The two tables listed skills and commands by hand, and both were wrong: three patterns from
# docs/patterns/ were advertised as skills, `debug` was missing, five of the twelve commands were
# absent, and /sync-app-notes claimed seven inventories where there are nine. This is the public
# face of the plugin, so it is generated from the same frontmatter the tool itself reads.
python3 - "$OUT" > "$OUT/README.md" <<'PY'
import glob, os, sys

out = sys.argv[1]

def described(path):
    """Return the frontmatter `description:` of a skill or command file."""
    body, desc = open(path).read(), None
    if body.startswith('---'):
        for line in body.split('---', 2)[1].splitlines():
            if line.startswith('description:'):
                desc = line.split(':', 1)[1].strip()
    return desc or '(no description)'

skills = sorted(glob.glob(f'{out}/skills/*/SKILL.md'))
cmds   = sorted(glob.glob(f'{out}/commands/*.md'))

print("""# GenericArch — Claude Code plugin

Skills and commands from the GenericArch Apple-platform architecture. **Generated** by
`Scripts/build-plugin.sh` — edit the sources in `.claude/` of the GenericArch repo, not here.

## What it adds
""")
print(f'{len(skills)} skill(s) — they activate from their description, you never type them:\n')
print('| Skill | Fires when |'); print('|---|---|')
for f in skills:
    print(f'| `{os.path.basename(os.path.dirname(f))}` | {described(f)} |')
print(f'\n{len(cmds)} command(s) — you type these:\n')
print('| Command | Does |'); print('|---|---|')
for f in cmds:
    print(f'| `/{os.path.basename(f)[:-3]}` | {described(f)} |')
print("""
## What it does NOT add

`CLAUDE.md`, `docs/`, `.claude/notes/`, or any Swift code. Those are a product's own rules, design
notes, and state. Get them by installing GenericArch into the repo — `install.sh` or `bootstrap.sh`,
which record a manifest so the install stays reversible. Copying the tree instead (a fork, or the
template the repo no longer offers) skips that record and there is nothing for `uninstall.sh` to
prove ownership against.

Because of that split, the commands reference `docs/…` paths that only exist once the docs are
adopted. The skills work standalone; `/verify`, `/decide`, and `/gaps` need their target files.""")
PY

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
