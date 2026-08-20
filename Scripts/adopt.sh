#!/usr/bin/env bash
#@kind      tool
#@platform  macos
#@claude    call
#@purpose   Copy the product-independent tooling layer into another repo.
#@usage     adopt.sh <target-dir> [--apply]
#@in        target:dir --apply:flag(without it, dry run)
#@out       stdout:plan; with --apply, files written into the target
#@exit      0=ok 1=unaccounted file|missing ref|bad target 2=usage
#@effects   writes into the TARGET repo when --apply
# Copy the REUSABLE BASE of GenericArch into another repo — and nothing else.
#
#   ./Scripts/adopt.sh /path/to/TargetRepo            # dry run (default)
#   ./Scripts/adopt.sh /path/to/TargetRepo --apply
#
# Why a script instead of `cp -R`: this repo holds two different things. The base travels; this
# product's state must not. Copying wholesale gives the target GenericArch's decisions, its route
# table, and its gap statuses as if they were its own — the single most common adoption mistake.
#
# Nothing is ever overwritten. Existing files are reported and skipped, so the target's own
# CLAUDE.md, skills, and commands survive untouched.
set -o pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
GA_SRC_URL="${GA_SRC_URL:-https://github.com/kalpesh-jetani/GenericArch}"
# Must be a ref raw.githubusercontent can resolve: an exact tag, a branch, or a full SHA.
# `git describe` yields v0.1.0-15-g97afd51, which is none of those and 404s on every fetch.
GA_SRC_REF="${GA_SRC_REF:-$(git -C "$SRC" describe --tags --exact-match 2>/dev/null \
                           || git -C "$SRC" rev-parse HEAD 2>/dev/null || echo main)}"
GA_RAW="${GA_SRC_URL#https://github.com/}"
GA_RAW="https://raw.githubusercontent.com/$GA_RAW/$GA_SRC_REF"

RED=$'\033[31m'; YEL=$'\033[33m'; GRN=$'\033[32m'; DIM=$'\033[2m'; BLD=$'\033[1m'; OFF=$'\033[0m'

TARGET="${1:-}"
APPLY=0
QUIET_NEXT=0
WITH_LINT=0
WITH_META=0
FRESH=0
WITH_ARCH=0
for a in "$@"; do
  [ "$a" = "--apply" ] && APPLY=1
  # install.sh prints advice matched to fresh-vs-existing; ours would contradict it.
  [ "$a" = "--quiet-next" ] && QUIET_NEXT=1
  [ "$a" = "--with-lint" ] && WITH_LINT=1
  [ "$a" = "--with-meta" ] && WITH_META=1
  # install.sh passes this for a repo with no structure yet. It is the ONE difference between the
  # two installs: the predefined module material — the scaffold layout, its templates and the
  # architecture notes — is exactly what a new repo needs and exactly what an existing one must not
  # be given.
  [ "$a" = "--fresh" ] && FRESH=1
  [ "$a" = "--with-architecture" ] && WITH_ARCH=1
done
[ "${1:-}" = "--apply" ] && { echo "${RED}pass the target path first${OFF}"; exit 2; }

if [ -z "$TARGET" ]; then
  cat <<USAGE
usage: ./Scripts/adopt.sh <target-repo> [--apply]

Copies the reusable base into <target-repo>. Dry run unless --apply is given.
USAGE
  exit 2
fi
[ -d "$TARGET" ] || { echo "${RED}no such directory: $TARGET${OFF}"; exit 1; }
TARGET="$(cd "$TARGET" && pwd)"
[ "$TARGET" = "$SRC" ] && { echo "${RED}target is GenericArch itself${OFF}"; exit 1; }

# ── What travels ───────────────────────────────────────────────────────────
# Rules, design docs, agent tooling, enforcement. Product-independent.
BASE="
.claude/skills
.claude/commands
.claude/INDEX.md
.claude/MAP.tsv
.claude/SCRIPTS.tsv
Scripts/check.sh
Scripts/check-skill-triggers.py
Scripts/detect-toolchain.sh
Scripts/adopt.sh
Scripts/build-plugin.sh
Scripts/find.sh
Scripts/notes-staleness.sh
Scripts/sync-notes.sh
Scripts/ga-handoff.sh
Scripts/scan-colors.py
Scripts/scan-fonts.py
Scripts/scan-unused-assets.py
Scripts/scan-api-map.py
Scripts/check-note-links.py
Scripts/detect-capabilities.sh
Scripts/claude-utils
Scripts/memory-add.py
Scripts/verify-memory.sh
Scripts/find-script.sh
Scripts/session-script.sh
Scripts/adopt-review.sh
Scripts/ga-lifecycle.sh
Scripts/ga-step.sh
Scripts/ga-remove.sh
Scripts/ga-reseal.sh
uninstall.sh
"

# ── Optional groups — off by default, and that is the point ────────────────
# Both were unconditional, and both cost more than they returned in the one adoption that proved it.
#
# lint: .swiftlint.yml/.swiftformat encode GenericArch's §2 conventions. A product that declined
# those rules gets a config that flags its whole codebase, so it deletes it — and the next install
# puts it back. That file flipped in/out four times in eight commits. Opt in when the rules were
# adopted.
#
# meta: Scripts/claude-workflows is the CLAUDE.md-editing pipeline — tooling for authoring this
# layer, not for building a product with it. Eleven scripts, eleven SCRIPTS.tsv rows every lookup
# greps past.
OPTIONAL_LINT=".swiftlint.yml .swiftformat"
OPTIONAL_META="Scripts/claude-workflows"
# The new-repo set. Not "optional" in the same sense — it is decided by what the target IS, not by
# preference, which is why install.sh derives it from the compatibility gate rather than asking.
OPTIONAL_FRESH="Scaffold Scripts/ga-scaffold.sh"
# ── The architecture layer ─────────────────────────────────────────────────
# Not a subset of the tooling — a different thing. `new-feature` scaffolds Packages/Features with
# ContentState and a DIKit registration; `/review` checks the §2 rules. Both are useful exactly when
# the product adopted this architecture, and inapplicable when it did not: in a repo with no
# Packages/, new-feature produces a package the app cannot consume, and /review reports violations of
# rules the product recorded as declined.
#
# So it travels with the NEW-repo install (starting from this base IS the consent) or on an explicit
# --with-architecture, which /project-init offers after the rule-conflict table — the point where
# consent is actually given. An existing repo arrives lean and has nothing to decline afterwards.
OPTIONAL_ARCH=".claude/skills/new-feature .claude/commands/review.md"
OPTIONAL_ALL="$OPTIONAL_LINT $OPTIONAL_META $OPTIONAL_FRESH $OPTIONAL_ARCH"
[ "$WITH_LINT" -eq 1 ] && BASE="$BASE
$(printf '%s\n' $OPTIONAL_LINT)"
[ "$WITH_META" -eq 1 ] && BASE="$BASE
$(printf '%s\n' $OPTIONAL_META)"
[ "$FRESH" -eq 1 ] && BASE="$BASE
$(printf '%s\n' $OPTIONAL_FRESH)"
# Starting a repo from this base is itself the decision to use this architecture.
[ "$FRESH" -eq 1 ] && WITH_ARCH=1
[ "$WITH_ARCH" -eq 1 ] && BASE="$BASE
$(printf '%s\n' $OPTIONAL_ARCH)"

# ── What must NOT travel, and why ──────────────────────────────────────────
# Each is this product's state. Carrying it into another repo makes the target's docs lie.
EXCLUDED="
CLAUDE.md|the target's rules are its own — /project-init reconciles instead of overwriting
docs/DECISIONS.md|THIS product's answers — an empty one is created instead (see Scaffolded)
docs/GAPS.md|gap statuses are per-product — an empty one is created instead (see Scaffolded)
Packages|this product's code
App|this product's app shells
README.md|the target has its own
.claude/settings.json|permissions are per-machine consent — /project-init merges, never copies
.claude-plugin|the target is not a plugin; build-plugin.sh generates one if it wants to be
.gitignore|the target has its own; merge by hand if needed
install.sh|installing again means fetching again — ./bootstrap.sh does that from the pinned ref
bootstrap.sh|the entry point lives upstream, not in every consumer (curl one-liner in the README)
Scripts/ga-roundtrip.sh|tests install.sh, which does not travel — it belongs where the base is authored
OPERATORS-GUIDE.md|maps THIS repo's files, most of which do not travel; a target gets genericarch.installation.md
"

# ── Nothing may fall through the lists ─────────────────────────────────────
# A file added later and not listed here is invisible at adopt time — it only surfaces when a
# command references it in someone else's repo. So: fail loudly rather than skip silently.
# .claude/CANDIDATES.tsv is scaffolded for the same reason as .claude/memory: the recurrence
# history is THIS repo's, and a target that inherits our candidate rows would see promotions it
# never earned. The target gets the header and an empty ledger.
SCAFFOLDED="docs/DECISIONS.md docs/GAPS.md .claude/notes docs/resources .claude/memory .claude/CANDIDATES.tsv"
# Reference material — listed in genericarch.installation.md and fetched when actually read.
# Not copied: reference docs a consumer may never open, that go stale the moment upstream moves.
# No count here on purpose — a literal number in a comment is what rotted last time.
REFERENCED="docs/STRUCTURE.md docs/CONVENTIONS.md docs/DONE.md docs/REPO.md docs/DELIVERY.md
docs/patterns docs/PERFORMANCE.md docs/ADOPTION.md docs/SHARING.md docs/PATTERN-SEARCH.md
docs/SCAN-TRAPS.md docs/CLAUDE-TASKS.md docs/modules docs/INSTALL-MANIFEST.md
docs/SEQUENCE.md docs/BUILD-PROCESS.md docs/DEPLOYMENT-PROCESS.md docs/PROJECT-SETTINGS.md"
# BASE is newline-separated and EXCLUDED is "path|reason" — flatten both to a space-delimited
# list of bare paths before matching, or every entry looks unaccounted for.
KNOWN=" $(echo $BASE) $(echo $REFERENCED) $(printf '%s\n' "$EXCLUDED" | sed 's/|.*//' | tr '\n' ' ') $SCAFFOLDED $OPTIONAL_ALL "
unaccounted=""
for f in $(ls -d docs/*.md docs/modules docs/patterns docs/resources .claude/INDEX.md .claude/*.tsv \
                 .claude/memory Scripts/* .swiftlint.yml .swiftformat .gitignore \
                 install.sh uninstall.sh bootstrap.sh README.md CLAUDE.md OPERATORS-GUIDE.md Scaffold \
                 .claude/skills .claude/commands .claude/notes \
                 Packages App 2>/dev/null); do
  case "$KNOWN" in *" $f "*) continue ;; esac
  unaccounted="$unaccounted $f"
done
if [ -n "$unaccounted" ]; then
  echo
  echo "${RED}✗ these are in neither BASE, EXCLUDED nor SCAFFOLDED — they would be silently skipped${OFF}"
  for f in $unaccounted; do echo "    $f"; done
  echo "  ${DIM}Add each to one of the three lists in this script, then re-run.${OFF}"
  exit 1
fi

# ── Referenced docs must exist AT THE PINNED REF, not just on disk ─────────
# REFERENCED files are never copied — they are fetched later from $GA_RAW/<path>. A file that is
# only in the working tree resolves fine here and 404s for every consumer. Committed-ness is the
# thing being checked, so check it against the ref, not the filesystem.
if git -C "$SRC" rev-parse --verify --quiet "$GA_SRC_REF" >/dev/null 2>&1; then
  unpushed=""
  for item in $REFERENCED; do
    if git -C "$SRC" cat-file -e "$GA_SRC_REF:$item" 2>/dev/null; then
      continue                                   # a file, present at the ref
    fi
    if git -C "$SRC" ls-tree -r --name-only "$GA_SRC_REF" -- "$item" 2>/dev/null | grep -q .; then
      # a directory: every entry on disk must also be at the ref
      for leaf in $(cd "$SRC" && find "$item" -type f -name '*.md' 2>/dev/null); do
        git -C "$SRC" cat-file -e "$GA_SRC_REF:$leaf" 2>/dev/null || unpushed="$unpushed $leaf"
      done
    else
      unpushed="$unpushed $item"
    fi
  done
  if [ -n "$unpushed" ]; then
    echo
    echo "${RED}✗ these are referenced but do not exist at $GA_SRC_REF${OFF}"
    for f in $unpushed; do echo "    $f"; done
    echo "  ${DIM}They are fetched, never copied — every consumer would get a 404.${OFF}"
    echo "  ${DIM}Commit and push them, then re-run with GA_SRC_REF set to a ref that has them.${OFF}"
    [ "$APPLY" -eq 1 ] && exit 1
    echo "  ${YEL}(dry run — this would abort with --apply)${OFF}"
  fi
fi

echo
echo "${BLD}GenericArch → adopt${OFF}"
echo "  from  $SRC"
echo "  into  $TARGET"
[ "$APPLY" -eq 1 ] && echo "  mode  ${GRN}APPLY${OFF}" || echo "  mode  ${YEL}dry run${OFF} (add --apply to write)"
echo

if [ ! -d "$TARGET/.git" ]; then
  echo "${YEL}⚠ target is not a git repository — you won't be able to review or revert this${OFF}"
fi

copied=0; skipped=0; collided=0

# Expand a directory into its immediate entries so collisions are per-item: one pre-existing
# command must not block the others in the same directory.
expand() {
  if [ -d "$SRC/$1" ]; then
    for e in "$SRC/$1"/*; do
      [ -e "$e" ] && echo "$1/$(basename "$e")"
    done
  else
    echo "$1"
  fi
}

# What an unselected group would have brought. BASE lists whole directories — .claude/skills,
# .claude/commands — so removing one entry from a group cannot be done by editing BASE; a directory
# entry would bring it back. Subtracting at the leaf is the only place that holds for every group.
SKIP=""
[ "$WITH_ARCH" -eq 0 ] && SKIP="$SKIP $OPTIONAL_ARCH"
skipped_group() {
  for _s in $SKIP; do
    [ "$1" = "$_s" ] && return 0
    case "$1" in "$_s"/*) return 0 ;; esac
  done
  return 1
}

copy_one() {
  item="$1"; dest="$TARGET/$item"
  if skipped_group "$item"; then
    printf '  %s·%s %-46s %snot taken — --with-architecture brings it%s\n' \
      "$DIM" "$OFF" "$item" "$DIM" "$OFF"
    return
  fi
  if [ -e "$dest" ]; then
    printf '  %scollision%s  %s %s(exists — skipped, yours is kept)%s\n' "$YEL" "$OFF" "$item" "$DIM" "$OFF"
    collided=$((collided + 1)); return
  fi
  printf '  %s+%s %s\n' "$GRN" "$OFF" "$item"
  copied=$((copied + 1))
  if [ "$APPLY" -eq 1 ]; then
    mkdir -p "$(dirname "$dest")"
    cp -R "$SRC/$item" "$dest"
  fi
}

echo "${BLD}── Would copy ──────────────────────────────────────────${OFF}"
for item in $BASE; do
  [ -e "$SRC/$item" ] || { echo "  ${YEL}missing in source: $item${OFF}"; continue; }
  OLDIFS="$IFS"; IFS=$'\n'
  for leaf in $(expand "$item"); do
    IFS="$OLDIFS"; copy_one "$leaf"; IFS=$'\n'
  done
  IFS="$OLDIFS"
done

# MAP.tsv is the router, and outside this repo most of its docs/ rows are not on disk. Stamp the
# pinned base in so a grep hit carries its own recovery path — otherwise resolving a row means
# knowing to open a second file, which is exactly the lookup the map exists to remove.
if [ "$APPLY" -eq 1 ] && [ -f "$TARGET/.claude/MAP.tsv" ]; then
  if ! grep -q '^# FETCH-BASE:' "$TARGET/.claude/MAP.tsv"; then
    tmp="$TARGET/.claude/MAP.tsv.tmp"
    { printf '# FETCH-BASE:\t%s\n' "$GA_RAW"
      printf '# \tcurl -fsSL --create-dirs "$FETCH_BASE/<path>" -o "<path>"\n'
      cat "$TARGET/.claude/MAP.tsv"
    } > "$tmp" && mv "$tmp" "$TARGET/.claude/MAP.tsv"
  fi
  # A row whose file is not on disk here is a FETCH, and the reader cannot tell which rows those
  # are without stat-ing each one. In the adoption that prompted this, 22 of 60 rows were dangling
  # — every hit on one cost a lookup, a decision, and sometimes a network fetch, for a document
  # describing a module the product does not have. Suffix the kind so a grep hit says so itself.
  tmp="$TARGET/.claude/MAP.tsv.tmp"
  awk -F'\t' -v OFS='\t' -v tgt="$TARGET" '
    /^#/ || NF < 2 { print; next }
    {
      cmd = "test -e \"" tgt "/" $1 "\""
      if (system(cmd) != 0 && $2 !~ /:remote$/) $2 = $2 ":remote"
      print
    }
  ' "$TARGET/.claude/MAP.tsv" > "$tmp" && mv "$tmp" "$TARGET/.claude/MAP.tsv"
  # Without the architecture layer, the module and pattern rows are dead: nothing in the target can
  # ever satisfy them, and a :remote mark only converts a dead lookup into a network fetch for a doc
  # describing a layer that will not exist. Drop them. --with-architecture (or /learn) brings the
  # rows back with the layer they describe.
  if [ "$WITH_ARCH" -eq 0 ]; then
    tmp="$TARGET/.claude/MAP.tsv.tmp"
    awk -F'\t' '/^#/ || NF < 2 {print; next} $2 !~ /^(module|pattern)/ {print}' \
      "$TARGET/.claude/MAP.tsv" > "$tmp" && mv "$tmp" "$TARGET/.claude/MAP.tsv"
    printf '  %s~%s .claude/MAP.tsv %s— module and pattern rows dropped (no architecture layer here)%s\n' \
      "$YEL" "$OFF" "$DIM" "$OFF"
  fi
  remote=$(awk -F'\t' '$2 ~ /:remote$/' "$TARGET/.claude/MAP.tsv" | grep -c . || true)
  [ "$remote" -gt 0 ] && printf '  %s~%s .claude/MAP.tsv %s— %s row(s) marked :remote (fetch, not on disk)%s\n' \
    "$YEL" "$OFF" "$DIM" "$remote" "$OFF"
fi

# SCRIPTS.tsv is generated from THIS repo's Scripts/, so it advertises every script we have —
# including the optional groups the target did not ask for. A doc row can be marked :remote and
# fetched; a script row cannot. It is a dead row: grepped on every lookup, pointing at a file that
# is not there. Drop them, and say how many.
if [ "$APPLY" -eq 1 ] && [ -f "$TARGET/.claude/SCRIPTS.tsv" ]; then
  tmp="$TARGET/.claude/SCRIPTS.tsv.tmp"
  awk -F'\t' -v tgt="$TARGET" '
    /^#/ || NF < 2 { print; next }
    { cmd = "test -e \"" tgt "/" $1 "\""
      if (system(cmd) == 0) print; else dropped++ }
    END { if (dropped) print "#\tPRUNED-AT-INSTALL:\t" dropped " row(s) for scripts this repo did not install" }
  ' "$TARGET/.claude/SCRIPTS.tsv" > "$tmp" && mv "$tmp" "$TARGET/.claude/SCRIPTS.tsv"
  pruned=$(grep -c '^#	PRUNED-AT-INSTALL' "$TARGET/.claude/SCRIPTS.tsv" || true)
  if [ "$pruned" -gt 0 ]; then
    n=$(sed -n 's/^#	PRUNED-AT-INSTALL:	\([0-9]*\) .*/\1/p' "$TARGET/.claude/SCRIPTS.tsv")
    printf '  %s~%s .claude/SCRIPTS.tsv %s— %s dead row(s) pruned (script not installed here)%s\n' \
      "$YEL" "$OFF" "$DIM" "$n" "$OFF"
  fi
fi

echo
echo "${BLD}── Referenced, not copied (genericarch.installation.md) ─${OFF}"
referenced=0
OLDIFS="$IFS"; IFS=$'\n'
for item in $(echo $REFERENCED | tr ' ' '\n'); do
  IFS="$OLDIFS"
  for leaf in $(expand "$item"); do
    printf '  %s→%s %s\n' "$DIM" "$OFF" "$leaf"
    referenced=$((referenced + 1))
  done
  IFS=$'\n'
done
IFS="$OLDIFS"
printf '  %s%d file(s) — fetched on demand, never stale%s\n' "$DIM" "$referenced" "$OFF"

if [ "$APPLY" -eq 1 ]; then
  MAN="$TARGET/genericarch.installation.md"
  {
    echo "# GenericArch — installed reference"
    echo
    echo "Reference material is **not copied into this repo**. It is listed below and fetched when"
    echo "something actually needs it, so nothing goes stale and the repo stays uncluttered."
    echo
    echo "> ## A missing \`docs/…\` link is a fetch instruction, not a broken link"
    echo ">"
    echo "> The installed skills and commands link to these documents by relative path. Those paths"
    echo "> resolve **after** you fetch — that is the design. When a link under \`docs/\` does not"
    echo "> exist locally, fetch it to that exact path and continue; do not treat it as missing, and"
    echo "> do not guess the content from the filename."
    echo ">"
    echo "> Fetch only what the task needs. Fetching all $referenced defeats the point."
    echo
    echo "- **Source:** \`$GA_SRC_URL\`"
    echo "- **Pinned to:** \`$GA_SRC_REF\`"
    echo "- **Installed:** files under \`.claude/\` and \`Scripts/\` — those must be local to work."
    echo
    echo "## Fetch one"
    echo
    echo '```bash'
    echo "curl -fsSL \"\$GA_RAW/<path>\" -o <path>     # GA_RAW=$GA_RAW"
    echo '```'
    echo
    echo "Fetch into the same relative path so links between docs keep resolving. Delete it again"
    echo "afterwards if you do not want it tracked — the manifest is the durable record."
    echo
    echo "## Available"
    echo
    echo "| Document | What's there | Read it when |"
    echo "|---|---|---|"
    for item in $(echo $REFERENCED | tr ' ' '\n'); do
      for leaf in $(expand "$item"); do
        title=$(head -1 "$SRC/$leaf" | sed 's/^#* *//')
        when=$(grep -m1 -- '- \*\*When to read this:\*\*' "$SRC/$leaf" 2>/dev/null \
               | sed 's/.*When to read this:\*\* *//' | cut -c1-90)
        [ -z "$when" ] && when=$(sed -n '3p' "$SRC/$leaf" | cut -c1-90)
        printf '| `%s` | %s | %s |\n' "$leaf" "$title" "$when"
      done
    done
  } > "$MAN"
  printf '  %s+%s genericarch.installation.md %s— the index; the only file added%s\n' "$GRN" "$OFF" "$DIM" "$OFF"
fi

# ── The seed packages, for a new repo only ─────────────────────────────────
# Core and DIKit are real, tested packages, and a new repo wants them as its floor. They cannot be
# installed straight into the target's Packages/ — the manifest would then own the product's own
# package layer, and uninstall would delete it. So they travel under Scaffold/seed/ and ga-scaffold.sh
# copies them OUT into Packages/, where they belong to the product and nothing here tracks them.
if [ "$FRESH" -eq 1 ]; then
  echo
  echo "${BLD}── Seed packages (Scaffold/seed → the product copies them out) ──${OFF}"
  # The scoped package rules travel with the seed for the same reason the packages do: ga-scaffold
  # copies them OUT into the product's Packages/, where they belong to the product.
  #
  # Seeded as PACKAGES-CLAUDE.md, never as CLAUDE.md: a file with that exact name sitting inside the
  # consumer's tree is one the harness may load as real, scoped rules — from a staging directory that
  # describes packages the product has not created yet.
  for pkg in Packages/Core Packages/DIKit Packages/CLAUDE.md:PACKAGES-CLAUDE.md; do
    as="${pkg##*:}"; pkg="${pkg%%:*}"
    [ "$as" = "$pkg" ] && as="$(basename "$pkg")"
    [ -e "$SRC/$pkg" ] || { echo "  ${YEL}missing in source: $pkg${OFF}"; continue; }
    dest_rel="Scaffold/seed/$as"
    if [ -e "$TARGET/$dest_rel" ]; then
      printf '  %scollision%s  %s %s(exists — kept)%s\n' "$YEL" "$OFF" "$dest_rel" "$DIM" "$OFF"
      collided=$((collided + 1))
    else
      printf '  %s+%s %s %s(from %s)%s\n' "$GRN" "$OFF" "$dest_rel" "$DIM" "$pkg" "$OFF"
      copied=$((copied + 1))
      if [ "$APPLY" -eq 1 ]; then
        mkdir -p "$TARGET/Scaffold/seed"
        cp -R "$SRC/$pkg" "$TARGET/$dest_rel"
      fi
    fi
  done
fi

echo
echo "${BLD}── Optional, off unless asked for ──────────────────────${OFF}"
for pair in "--with-lint|$OPTIONAL_LINT|only if the target adopted GenericArch's §2 conventions" \
            "--with-meta|$OPTIONAL_META|the CLAUDE.md authoring pipeline — not needed to build a product" \
            "--fresh|$OPTIONAL_FRESH|the predefined structure and seed packages — a NEW repo only" \
            "--with-architecture|$OPTIONAL_ARCH|only once the product adopted §2/§3 — /project-init offers it"; do
  flag="${pair%%|*}"; rest="${pair#*|}"; items="${rest%%|*}"; why="${rest#*|}"
  case "$flag" in
    --with-lint) on=$WITH_LINT ;;
    --with-meta) on=$WITH_META ;;
    --fresh)     on=$FRESH ;;
    --with-architecture) on=$WITH_ARCH ;;
  esac
  if [ "$on" -eq 1 ]; then
    printf '  %s+%s %-12s %s %s(requested)%s\n' "$GRN" "$OFF" "$flag" "$items" "$DIM" "$OFF"
  else
    printf '  %s·%s %-12s %s%s — %s%s\n' "$DIM" "$OFF" "$flag" "$DIM" "$items" "$why" "$OFF"
  fi
done

echo
echo "${BLD}── Deliberately NOT copied ─────────────────────────────${OFF}"
OLDIFS="$IFS"; IFS=$'\n'
for line in $EXCLUDED; do
  [ -z "$line" ] && continue
  name="${line%%|*}"; why="${line#*|}"
  printf '  %s−%s %-22s %s%s%s\n' "$DIM" "$OFF" "$name" "$DIM" "$why" "$OFF"
  skipped=$((skipped + 1))
done
IFS="$OLDIFS"

# ── Scaffolded: created empty in the target, never copied from here ────────
# /decide, /gaps and /project-init all write to these. Without them the commands have nowhere to
# go; with our copies the target inherits this product's decisions. So: create, don't copy.
echo
echo "${BLD}── Created empty (never copied) ────────────────────────${OFF}"
scaffolded=0
for pair in "docs/DECISIONS.md|the target records its own decisions here — /decide" \
            "docs/GAPS.md|the target triages its own gaps here — /gaps" \
            ".claude/notes|every inventory, prose kept and data rows blanked" \
            ".claude/memory|Claude's in-repo memory — the index only; our memories are ours"; do
  f="${pair%%|*}"; why="${pair#*|}"
  if [ -e "$TARGET/$f" ]; then
    printf '  %scollision%s  %s %s(exists — kept)%s\n' "$YEL" "$OFF" "$f" "$DIM" "$OFF"
  else
    printf '  %s+%s %s %s— %s%s\n' "$GRN" "$OFF" "$f" "$DIM" "$why" "$OFF"
    scaffolded=$((scaffolded + 1))
  fi
done

if [ "$APPLY" -eq 1 ] && [ ! -e "$TARGET/.claude/notes" ]; then
  mkdir -p "$TARGET/.claude"
  cp -R "$SRC/.claude/notes" "$TARGET/.claude/notes"
  # Keep every heading, rule and commented example; blank only filled data rows. A row is data if
  # it has 3+ cells and is not the header or its separator.
  for n in "$TARGET"/.claude/notes/*.md; do
    python3 - "$n" <<'PY'
import re, sys, pathlib

def is_sep(t):
    return bool(re.fullmatch(r"\|[\s\-:|]+\|", t))

p = pathlib.Path(sys.argv[1])
lines = p.read_text().splitlines()
out = []
for i, line in enumerate(lines):
    st = line.strip()
    row = st.startswith("|") and st.endswith("|") and st.count("|") >= 3
    if not row:
        out.append(line); continue
    nxt = lines[i + 1].strip() if i + 1 < len(lines) else ""
    header = is_sep(nxt)                    # a header is the row above the separator
    placeholder = all(c.strip() in ("", "—", "-") for c in st.strip("|").split("|"))
    if header or is_sep(st) or placeholder:
        out.append(line)                    # structure — keep
    elif out and out[-1].strip() and is_sep(out[-1].strip()):
        out.append(re.sub(r"[^|]+", " — ", st))   # first data row → one blank placeholder
    # any further data row is this product's state — dropped
p.write_text("\n".join(out) + "\n")
PY
  done
fi

# Scaffolded, not copied — docs/SHARING.md §3: "our memories are ours". The contract prose (the
# format, the type table, what may not be stored) is what travels; the index ROWS are this
# product's facts and must not. A verbatim copy leaves the target with rows pointing at memory
# files that were deliberately not copied, which Scripts/verify-memory.sh reports as orphan-row
# on the target's very first run.
if [ "$APPLY" -eq 1 ] && [ ! -e "$TARGET/.claude/memory" ]; then
  mkdir -p "$TARGET/.claude/memory"
  awk '
    /^## Index/      { inindex = 1 }
    inindex && /^\|/ {
      if (!seeded) {
        print "| Memory | What it holds |"
        print "|---|---|"
        print "| — | — |"
        seeded = 1
      }
      next
    }
    { print }
  ' "$SRC/.claude/memory/INDEX.md" > "$TARGET/.claude/memory/INDEX.md"
fi

# Same rule for the candidate ledger: header travels, rows do not. Copying our rows would hand
# the target a promotable candidate it never used in a single session of its own.
if [ "$APPLY" -eq 1 ] && [ ! -e "$TARGET/.claude/CANDIDATES.tsv" ]; then
  mkdir -p "$TARGET/.claude"
  grep '^#' "$SRC/.claude/CANDIDATES.tsv" > "$TARGET/.claude/CANDIDATES.tsv"
fi

if [ "$APPLY" -eq 1 ]; then
  mkdir -p "$TARGET/docs"
  [ -e "$TARGET/docs/DECISIONS.md" ] || cat > "$TARGET/docs/DECISIONS.md" <<'DEC'
# Decisions

Settled choices. **Read this before asking a CLAUDE.md §0 question** — it may already be answered.
Add a row when a §0 decision is made; never remove one.

## Settled — follow these, don't re-derive

| Scope | Decision | Why | Detail |
|---|---|---|---|
| — | — | — | — |

## Ask every time — never assume

Presentation pattern (per feature/screen) · persistence engine (only if data is stored) · caching
and offline policy (any remote fetch) · any new external dependency · extracting a package.
Options and phrasing: CLAUDE.md §0. Record the answer here with `/decide`.

## Do not re-propose

Rejected with reasons recorded — reopen only with new information, not a fresh preference.

| Rejected | Where the reasoning lives |
|---|---|
| — | — |

## Open

| Question | Blocks | Note |
|---|---|---|
| — | — | — |

---

## Per feature

| Date | Feature | Presentation | Persistence | Caching / offline |
|---|---|---|---|---|
| — | — | — | — | — |
DEC
  [ -e "$TARGET/docs/GAPS.md" ] || cat > "$TARGET/docs/GAPS.md" <<'GAP'
# Gaps

What this architecture does not cover **for this product**, as decisions to make rather than a
backlog to burn down. Run `/gaps` to triage.

`/gaps` behaves differently by repo state: on an existing repo it derives each status from the code
without asking; on a fresh one it asks per item. Absence of evidence is not always a decision — no
StoreKit means the product doesn't monetise, but no crash reporting is a **missing safeguard**,
reported as a risk rather than silently skipped.

## Status legend

| Status | Meaning | Gets re-raised? |
|---|---|---|
| ✅ **Applied** | Landed. The row records where | No |
| ▶ **Open** | Needs a decision | Yes, by `/gaps` |
| ⏸ **Deferred** | Tracked, with a named revisit trigger | Only when the trigger fires |
| ⛔ **Skipped** | Decided against. Also recorded in DECISIONS.md *Do not re-propose* | **No** |

**Skip is a real answer.** Most capabilities should end up Skipped for any given product.

## ▶ Open

| Item | Cost of skipping | Status |
|---|---|---|
| Feature flags / remote config | No kill switch — a bad release is only fixable by another release | ▶ |
| Crash reporting + dSYM upload | Crash reports unreadable, unrecoverable after the fact | ▶ |
| SwiftLint / SwiftFormat config | Rules stay review-only and decay | ▶ |
| Analytics event taxonomy | Events accrete ad-hoc and become unqueryable | ▶ |
| Auth flows · IAP · CloudKit · widgets · search · haptics · biometrics | — | ▶ |

Run `/gaps` to work through these; it fills in what your code already answers.

## Recording an answer

- **Adopt** → do the work, move the row to Applied with where it landed.
- **Defer** → ⏸ and **name the trigger**. A deferral with no trigger is an Open item pretending.
- **Skip** → ⛔ **and** a DECISIONS.md *Do not re-propose* row. Both, or it comes back.

Never delete a row. The value is knowing what was considered and declined.
GAP
fi

echo
echo "${BLD}────────────────────────────────────────────────────────${OFF}"
printf '%d copied · %d referenced · %d created empty · %d collision(s) kept · %d excluded\n' \
  "$copied" "$referenced" "$scaffolded" "$collided" "$skipped"

if [ "$APPLY" -eq 0 ]; then
  echo
  echo "Dry run only. Re-run with ${BLD}--apply${OFF} to write."
  exit 0
fi

# Only the scripts invoked as ./Scripts/… need the bit; the scan-*.py and check-note-links.py
# are run via `python3 Scripts/…`. cp -R already preserves mode — this is belt-and-braces.
chmod +x "$TARGET/Scripts/check.sh" "$TARGET/Scripts/detect-toolchain.sh" \
         "$TARGET/Scripts/find.sh" "$TARGET/Scripts/notes-staleness.sh" \
         "$TARGET/Scripts/detect-capabilities.sh" 2>/dev/null
[ "$QUIET_NEXT" -eq 1 ] && exit 0
cat <<NEXT

${BLD}Next, in the target repo${OFF}

  1. ${BLD}/project-init${OFF}   Detects an existing repo and follows docs/ADOPTION.md — reads its
                    CLAUDE.md, builds the rule-conflict
                    table, and asks per conflict. Keeps their rules by default — nothing is
                    overwritten without an explicit yes.

  2. ${BLD}/gaps${OFF}           Derives each gap's status from the target's own code instead of asking,
                    and reports missing safeguards as risks.

  3. ${BLD}./Scripts/detect-toolchain.sh${OFF}
                    Reads the target's own stack from its project settings, and the machine for
                    the rest. Whatever CLAUDE.md ends up saying comes from this, not from
                    GenericArch's numbers. If it reports a mismatch, ${BLD}/upgrade-stack${OFF}
                    reviews it and asks twice before changing anything.

  4. ${BLD}./Scripts/check.sh${OFF}
                    Expect failures on an existing codebase — that is the point. Triage them in
                    /project-init as "keep theirs", "new code only", or "migrate".

${DIM}No CLAUDE.md was written. The target's rules stay the target's until it decides otherwise.${OFF}
NEXT
