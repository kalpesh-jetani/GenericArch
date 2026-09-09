#!/usr/bin/env bash
#@kind      tool
#@platform  macos
#@claude    call
#@purpose   Find an external platform's attribute profile, or scaffold, extend, unregister and retire one.
#@usage     ga-tool-note.sh --find <tool> | <tool> [--extend] [--observe "a|unit|acc|method|scope"]... [--apply] | <tool> --fail --cause T | <tool> --unregister|--retire --reason T | <tool> --revive [--apply] | --list | --sync
#@in        tool:slug --observe:string(repeatable, 5 pipe-separated fields; "not observed" is valid) --platform:string --via:string --wired:enum(connector reference-only) --apply:flag(without it, dry run) --find:slug --extend:flag --fail:flag --cause:string --unregister:flag --retire:flag --revive:flag(restores both tombstoned paths) --reason:string(required to retire) --list:flag --sync:flag
#@out       stdout:the profile and recipe paths on a hit; the rows it would write on a miss; the ledger for --list
#@exit      0=ok 1=no profile for this tool|stale|retired|nothing observed 2=usage 4=declined at the prompt
#@effects   with --apply: writes .claude/tools/<tool>.md, Scripts/Generated/<tool>.sh, LEDGER.tsv and the four index rows; --retire delegates to ga-remove.sh
#@when      profile for this tool|external platform attributes|is this connector recorded|which tools are profiled|connector not configured|retire a tool profile|revive a retired profile|what does this tool expose

set -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=Scripts/ga-lifecycle.sh
. "$HERE/ga-lifecycle.sh"

TARGET="$(cd "$HERE/.." && pwd)"
LEDGER=".claude/tools/LEDGER.tsv"
REGISTRY=".claude/skills/tool-profile/references/generated-skills-note.md"
MAP=".claude/MAP.tsv"
INDEX=".claude/INDEX.md"

TOOL=""; APPLY=0; MODE=""; PLATFORM=""; VIA=""; WIRED="connector"
CAUSE=""; REASON=""; OBS_N=0
OBS_FILE="${TMPDIR:-/tmp}/ga-tool-obs.$$"
: > "$OBS_FILE"
trap 'rm -f "$OBS_FILE" "$OBS_FILE".rows "$OBS_FILE".map "$OBS_FILE".idx' EXIT

while [ $# -gt 0 ]; do
  case "$1" in
    --find)       MODE="find"; TOOL="${2:-}"; shift 2 ;;
    --list)       MODE="list"; shift ;;
    --sync)       MODE="sync"; shift ;;
    --extend)     MODE="extend"; shift ;;
    --fail)       MODE="fail"; shift ;;
    --unregister) MODE="unregister"; shift ;;
    --retire)     MODE="retire"; shift ;;
    --revive)     MODE="revive"; shift ;;
    --observe)    printf '%s\n' "${2:-}" >> "$OBS_FILE"; OBS_N=$((OBS_N + 1)); shift 2 ;;
    --platform)   PLATFORM="${2:-}"; shift 2 ;;
    --via)        VIA="${2:-}"; shift 2 ;;
    --wired)      WIRED="${2:-}"; shift 2 ;;
    --cause)      CAUSE="${2:-}"; shift 2 ;;
    --reason)     REASON="${2:-}"; shift 2 ;;
    --apply)      APPLY=1; shift ;;
    --target)     TARGET="${2:-}"; shift 2 ;;
    -h|--help)    sed -n '2,12p' "$0"; exit "$GA_EX_USAGE" ;;
    -*)           ga_die "unknown argument: $1" "$GA_EX_USAGE" ;;
    *)            [ -z "$TOOL" ] || ga_die "one tool at a time (got '$TOOL' and '$1')" "$GA_EX_USAGE"
                  TOOL="$1"; shift ;;
  esac
done

cd "$TARGET" || ga_die "no such directory: $TARGET" "$GA_EX_USAGE"
[ -n "$MODE" ] || MODE="generate"

slug_of() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' \
  | sed 's/[^a-z0-9]\{1,\}/-/g; s/^-//; s/-$//' | cut -c1-40; }

ensure_ledger() {
  [ -f "$LEDGER" ] && return
  mkdir -p .claude/tools
  {
    printf '#\tGenericArch external-platform ledger — the source of truth for .claude/tools/.\n'
    printf '#\tThe registry note is regenerated from this file: ga-tool-note.sh --sync\n'
    printf '#\tstatus: active | suspect | stale | retired\n'
    printf '#\ttool\tprofile\tscript\twired\tcreated\tlast_verified\tfailures\tstatus\n'
  } > "$LEDGER"
}

row_of()  { awk -F'\t' -v t="$1" '$1!~/^#/ && $1==t' "$LEDGER" 2>/dev/null | head -1; }
field()   { printf '%s' "$1" | awk -F'\t' -v n="$2" '{print $n}'; }
set_field() {
  awk -F'\t' -v OFS='\t' -v t="$1" -v n="$2" -v v="$3" \
    '$1!~/^#/ && $1==t { $n = v } { print }' "$LEDGER" > "$LEDGER.tmp" \
    && mv "$LEDGER.tmp" "$LEDGER"
}

# Replace everything between two marker lines with the contents of a rows file.
replace_span() {
  _f="$1"; _open="$2"; _close="$3"; _rows="$4"
  [ -f "$_f" ] || return 0
  grep -qF -- "$_open" "$_f" || return 0
  awk -v o="$_open" -v c="$_close" -v r="$_rows" '
    index($0, o) { print; while ((getline line < r) > 0) print line; close(r); skip = 1; next }
    index($0, c) { skip = 0 }
    !skip { print }
  ' "$_f" > "$_f.tmp" && mv "$_f.tmp" "$_f"
}

profile_path() { printf '.claude/tools/%s.md' "$1"; }
script_path()  { printf 'Scripts/Generated/%s.sh' "$1"; }

# ── find ──────────────────────────────────────────────────────────────────
if [ "$MODE" = "find" ]; then
  [ -n "$TOOL" ] || ga_die "--find needs a tool name" "$GA_EX_USAGE"
  TOOL="$(slug_of "$TOOL")"
  ensure_ledger
  r="$(row_of "$TOOL")"
  if [ -z "$r" ]; then
    printf 'no profile for "%s"\n' "$TOOL"
    if ga_tombstoned "$TARGET" "$(profile_path "$TOOL")" 2>/dev/null; then
      printf 'RETIRED — do not resurrect it. Reason: %s\n' \
        "$(ga_tombstone_reason "$TARGET" "$(profile_path "$TOOL")" 2>/dev/null)"
    else
      printf 'generate one only after a successful use:\n  ./Scripts/ga-tool-note.sh %s\n' "$TOOL"
    fi
    exit "$GA_EX_ERR"
  fi
  st="$(field "$r" 8)"
  case "$st" in
    retired) printf 'RETIRED\t%s\tdo not resurrect\n' "$TOOL"; exit "$GA_EX_ERR" ;;
    stale)   printf 'STALE\t%s\t%s failures — re-observe and regenerate, do not trust the rows\n' \
               "$TOOL" "$(field "$r" 7)"; exit "$GA_EX_ERR" ;;
  esac
  printf 'profile\t%s\n' "$(field "$r" 2)"
  printf 'recipe\t%s\n'  "$(field "$r" 3)"
  printf 'wired\t%s\tstatus\t%s\tverified\t%s\n' "$(field "$r" 4)" "$st" "$(field "$r" 6)"
  [ "$st" = "suspect" ] && printf 'SUSPECT — %s failure so far; check the row you rely on\n' "$(field "$r" 7)"
  exit "$GA_EX_OK"
fi

# ── list ──────────────────────────────────────────────────────────────────
if [ "$MODE" = "list" ]; then
  ensure_ledger
  n=$(awk -F'\t' '$1!~/^#/' "$LEDGER" | grep -c . || true)
  [ "$n" -eq 0 ] && { printf 'no profiles yet\n'; exit "$GA_EX_OK"; }
  printf '%-18s %-14s %-9s %-8s %s\n' TOOL WIRED FAILURES STATUS VERIFIED
  awk -F'\t' '$1!~/^#/ {printf "%-18s %-14s %-9s %-8s %s\n", $1, $4, $7, $8, $6}' "$LEDGER"
  exit "$GA_EX_OK"
fi

# ── sync ──────────────────────────────────────────────────────────────────
do_sync() {
  ensure_ledger
  reg="$OBS_FILE.rows"; mapr="$OBS_FILE.map"; idx="$OBS_FILE.idx"
  : > "$reg"; : > "$mapr"; : > "$idx"

  # A row must carry what is there, not just where (STRUCTURE.md). The clause is the profile's
  # own Platform line, so it stays true when the profile is extended.
  awk -F'\t' '$1!~/^#/ && ($8=="active" || $8=="suspect" || $8=="stale") {print $1"\t"$2"\t"$3"\t"$4"\t"$6"\t"$8}' "$LEDGER" \
  | while IFS="$(printf '\t')" read -r t prof rec wired ver st; do
      what="$(sed -n 's|^- \*\*Platform:\*\* *||p' "$prof" 2>/dev/null | head -1)"
      case "$what" in ''|'<'*) what="attributes, units and connectivity" ;; esac
      n="$(awk -F'|' '/^\| / && $0 !~ /^\|---/ && $0 !~ /Unit \/ type/' "$prof" 2>/dev/null | grep -c . || true)"
      printf '| %s | [`%s.md`](../../../tools/%s.md) — %s | `%s` | %s | %s | %s |\n' \
        "$t" "$t" "$t" "$what" "$rec" "$wired" "$st" "$ver" >> "$reg"
      printf '%s\ttool\texternal platform connector %s attribute unit accessibility extraction scope wired unwired\tReaching %s — %s (%s attributes recorded)\n' \
        "$prof" "$t" "$t" "$what" "$n" >> "$mapr"
      printf '| %s | [`tools/%s.md`](tools/%s.md) — %s | %s | %s |\n' \
        "$t" "$t" "$t" "$what" "$wired" "$st" >> "$idx"
    done

  [ -s "$reg" ] || printf '| — | — | — | — | — | — |\n' > "$reg"
  [ -s "$idx" ] || printf '| — | — | — | — |\n' > "$idx"
  replace_span "$REGISTRY" 'GA:ROWS —'  'GA:ROWS-END'  "$reg"
  replace_span "$MAP"      'GA:TOOLS —' 'GA:TOOLS-END' "$mapr"
  replace_span "$INDEX"    'GA:TOOLS —' 'GA:TOOLS-END' "$idx"

  printf 'synced\t%s\t%s\t%s\n' "$REGISTRY" "$MAP" "$INDEX"
}
[ "$MODE" = "sync" ] && { do_sync; exit "$GA_EX_OK"; }

# ── everything below needs a tool ─────────────────────────────────────────
[ -n "$TOOL" ] || ga_die "which tool? see --list, or -h" "$GA_EX_USAGE"
TOOL="$(slug_of "$TOOL")"
[ -n "$TOOL" ] || ga_die "tool name has no usable characters" "$GA_EX_USAGE"
ensure_ledger
PROFILE="$(profile_path "$TOOL")"
RECIPE="$(script_path "$TOOL")"
ROW="$(row_of "$TOOL")"

# ── fail ──────────────────────────────────────────────────────────────────
if [ "$MODE" = "fail" ]; then
  [ -n "$ROW" ] || ga_die "no profile for '$TOOL' to fail" "$GA_EX_ERR"
  [ -n "$CAUSE" ] || ga_die "--fail needs --cause: what the recorded recipe got wrong" "$GA_EX_USAGE"
  n=$(( $(field "$ROW" 7) + 1 ))
  case "$n" in
    1) st="suspect" ;;
    2) st="stale" ;;
    *) st="stale" ;;
  esac
  set_field "$TOOL" 7 "$n"
  set_field "$TOOL" 8 "$st"
  [ -x "$HERE/ga-handoff.sh" ] \
    && "$HERE/ga-handoff.sh" "$RECIPE" 1 --cause "$CAUSE" --file "$PROFILE" >/dev/null 2>&1 || true
  do_sync >/dev/null
  printf 'failure %s recorded\t%s\tstatus=%s\n' "$n" "$TOOL" "$st"
  case "$n" in
    1) printf 'still usable, flagged. Check the row you rely on before trusting it\n' ;;
    2) printf 'STALE — the rows are no longer trusted. Re-observe and regenerate:\n  ./Scripts/ga-tool-note.sh %s --apply --observe "..."\n' "$TOOL" ;;
    *) printf 'THIRD failure — propose retiring it, and ask first:\n  ./Scripts/ga-tool-note.sh %s --retire --reason "<why>"\n' "$TOOL" ;;
  esac
  printf 'report (if written): .genericarch/failures/ — read that, never the script\n'
  exit "$GA_EX_OK"
fi

# ── unregister ────────────────────────────────────────────────────────────
if [ "$MODE" = "unregister" ]; then
  [ -n "$ROW" ] || ga_die "no profile for '$TOOL' to unregister" "$GA_EX_ERR"
  if [ "$APPLY" -eq 0 ]; then
    printf 'would drop the index rows for %s and keep both files:\n  %s\n  %s\n' "$TOOL" "$PROFILE" "$RECIPE"
    printf 're-run with --apply\n'
    exit "$GA_EX_OK"
  fi
  set_field "$TOOL" 8 "dormant"
  do_sync >/dev/null
  printf 'unregistered\t%s\tfiles kept, index rows dropped\n' "$TOOL"
  printf 'the recipe script still carries a SCRIPTS.tsv row until you remove the file — retire it instead if that is what you meant\n'
  exit "$GA_EX_OK"
fi

# ── retire ────────────────────────────────────────────────────────────────
if [ "$MODE" = "retire" ]; then
  [ -n "$REASON" ] || ga_die "--retire needs --reason: it becomes the do-not-re-propose row" "$GA_EX_USAGE"
  cmd="./Scripts/ga-remove.sh $PROFILE $RECIPE --untracked --reason \"$REASON\" --apply"
  if [ "$APPLY" -eq 0 ]; then
    printf 'retiring %s moves both files to .genericarch/safetodelete/ and tombstones them.\n' "$TOOL"
    printf 'ga-remove.sh is needs-approval, so ask before running:\n  %s\n' "$cmd"
    printf 'then: ./Scripts/ga-tool-note.sh --sync && ./Scripts/ga-reseal.sh --apply\n'
    exit "$GA_EX_OK"
  fi
  "$HERE/ga-remove.sh" "$PROFILE" "$RECIPE" --untracked --reason "$REASON" --apply
  rc=$?
  [ "$rc" -eq 0 ] || exit "$rc"
  set_field "$TOOL" 8 "retired"
  do_sync >/dev/null
  "$HERE/claude-utils/register-scripts.sh" >/dev/null 2>&1 || true
  printf 'retired\t%s\tmoved to .genericarch/safetodelete/, tombstoned\n' "$TOOL"
  exit "$GA_EX_OK"
fi

# ── revive ────────────────────────────────────────────────────────────────
# Symmetric with --retire: it tombstoned two paths, so this restores two.
if [ "$MODE" = "revive" ]; then
  if [ "$APPLY" -eq 0 ]; then
    printf 'would restore both paths and re-index %s:\n' "$TOOL"
    for _t in "$PROFILE" "$RECIPE"; do
      ga_tombstoned "$TARGET" "$_t" 2>/dev/null \
        && printf '  %s  (tombstoned: %s)\n' "$_t" "$(ga_tombstone_reason "$TARGET" "$_t" 2>/dev/null)" \
        || printf '  %s  (not tombstoned — nothing to do)\n' "$_t"
    done
    printf 're-run with --apply\n'
    exit "$GA_EX_OK"
  fi
  _did=0
  for _t in "$PROFILE" "$RECIPE"; do
    ga_tombstoned "$TARGET" "$_t" 2>/dev/null || continue
    "$HERE/ga-remove.sh" --revive "$_t" --apply || exit $?
    _did=$((_did + 1))
  done
  [ "$_did" -eq 0 ] && { printf 'nothing tombstoned for %s\n' "$TOOL" >&2; exit "$GA_EX_ERR"; }
  [ -n "$ROW" ] && set_field "$TOOL" 8 active
  do_sync >/dev/null
  "$HERE/claude-utils/register-scripts.sh" >/dev/null 2>&1 || true
  printf 'revived\t%s\t%s path(s) restored, rows re-indexed\n' "$TOOL" "$_did"
  exit "$GA_EX_OK"
fi

# ── generate | extend ─────────────────────────────────────────────────────
# --retire tombstones the profile AND the recipe, so the gate has to ask about both. Checking only
# the profile let a half-revive re-create a recipe that was still tombstoned.
for _t in "$PROFILE" "$RECIPE"; do
  ga_tombstoned "$TARGET" "$_t" 2>/dev/null || continue
  printf '%s was RETIRED — %s is tombstoned, so nothing was written.\n' "$TOOL" "$_t" >&2
  printf 'reason: %s\n' "$(ga_tombstone_reason "$TARGET" "$_t" 2>/dev/null)" >&2
  printf 'reversing that is a decision, and it takes both paths:\n' >&2
  printf '  ./Scripts/ga-tool-note.sh %s --revive --apply\n' "$TOOL" >&2
  exit "$GA_EX_ERR"
done

if [ "$MODE" = "extend" ] && [ -z "$ROW" ]; then
  ga_die "no profile for '$TOOL' to extend — generate it first" "$GA_EX_ERR"
fi

# Rule 3: a row is OBSERVED only when the attribute was actually retrieved — Accessible is not
# "not observed". A unit learned from a tool contract proves the shape, never that the platform
# was reached, so contract rows alone can never satisfy the gate.
OBSERVED=0
CONTRACT=0
if [ "$OBS_N" -gt 0 ]; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    n=$(printf '%s' "$line" | awk -F'|' '{print NF}')
    [ "$n" -eq 5 ] || ga_die "--observe needs 5 pipe-separated fields (attribute|unit|accessible|method|scope), got $n in: $line" "$GA_EX_USAGE"
    u=$(printf '%s' "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$2); print $2}')
    a=$(printf '%s' "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$3); print $3}')
    if [ "$a" != "not observed" ]; then
      OBSERVED=$((OBSERVED + 1))
    elif [ "$u" != "not observed" ]; then
      CONTRACT=$((CONTRACT + 1))
    fi
  done < "$OBS_FILE"
fi

TODAY="$(date +%Y-%m-%d)"
rowsfile="$OBS_FILE.rows"
if [ "$OBS_N" -gt 0 ]; then
  awk -F'|' -v d="$TODAY" 'NF==5 {
    for (i = 1; i <= 5; i++) { gsub(/^ +| +$/, "", $i) }
    prov = (($3 != "not observed") ? d : (($2 != "not observed") ? "contract" : "—"))
    printf "| %s | %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5, prov }' "$OBS_FILE" > "$rowsfile"
else
  printf '| <attribute, as the platform names it> | not observed | not observed | not observed | not observed | — |\n' > "$rowsfile"
fi

if [ "$APPLY" -eq 0 ]; then
  printf '── would write %s\n' "$PROFILE"
  printf '   platform: %s\n' "${PLATFORM:-<--platform not given>}"
  printf '   via:      %s\n' "${VIA:-<--via not given>}"
  printf '   wired:    %s\n' "$WIRED"
  printf '   rows (%s retrieved, %s contract-only, %s of %s total):\n' \
    "$OBSERVED" "$CONTRACT" "$((OBSERVED + CONTRACT))" "$OBS_N"
  sed 's/^/     /' "$rowsfile"
  printf '── would write %s  (recipe, #@claude call, read-only)\n' "$RECIPE"
  printf '── would add rows to %s, %s, %s, %s\n' "$LEDGER" "$REGISTRY" "$MAP" "$INDEX"
  if [ "$OBSERVED" -eq 0 ]; then
    printf '\n--apply will REFUSE: nothing observed yet. Pass at least one --observe whose unit is real.\n'
  else
    printf '\nre-run with --apply\n'
  fi
  exit "$GA_EX_OK"
fi

if [ "$OBSERVED" -eq 0 ]; then
  printf 'refusing to write a profile with nothing retrieved.\n' >&2
  printf 'a platform that was never successfully used gets no file — that is the rule, not a limitation.\n' >&2
  [ "$CONTRACT" -gt 0 ] && printf '%s row(s) carry a unit from a tool contract, which proves the shape but not that the platform answered.\n' "$CONTRACT" >&2
  printf 'pass what a real response actually showed:\n' >&2
  printf '  --observe "attribute|unit|yes|the call and its field|per record"\n' >&2
  exit "$GA_EX_ERR"
fi

mkdir -p .claude/tools Scripts/Generated

if [ "$MODE" = "extend" ] && [ -f "$PROFILE" ]; then
  # An attribute already present as "not observed" is FILLED IN, not duplicated. Anything new
  # is appended before Connectivity.
  awk -v r="$rowsfile" '
    function key(line,   a, k) { split(line, a, "|"); k = a[2]; gsub(/^[ \t]+|[ \t]+$/, "", k); return k }
    BEGIN {
      while ((getline line < r) > 0) { nk = key(line); repl[nk] = line; order[++n] = nk }
      close(r)
    }
    /^\| / && $0 !~ /^\|---/ && $0 !~ /Unit \/ type/ {
      k = key($0)
      split($0, f, "|"); u = f[3]; gsub(/^[ \t]+|[ \t]+$/, "", u)
      if (k in repl && !used[k] && u == "not observed") {
        print repl[k]; used[k] = 1; next
      }
    }
    /^## Connectivity$/ && !flushed {
      for (i = 1; i <= n; i++) if (!used[order[i]]) { print repl[order[i]]; used[order[i]] = 1 }
      print ""
      flushed = 1
    }
    { print }
  ' "$PROFILE" > "$PROFILE.tmp" \
    || ga_die "could not extend $PROFILE — it is unchanged" "$GA_EX_ERR"
  [ -s "$PROFILE.tmp" ] || ga_die "refusing to write an empty $PROFILE" "$GA_EX_ERR"
  mv "$PROFILE.tmp" "$PROFILE"
  sed "s|^- \*\*Status:\*\*.*|- **Status:** active · failures 0 · **Last verified:** $TODAY|" \
    "$PROFILE" > "$PROFILE.tmp" && mv "$PROFILE.tmp" "$PROFILE"
  set_field "$TOOL" 6 "$TODAY"
  set_field "$TOOL" 7 0
  set_field "$TOOL" 8 active
  do_sync >/dev/null
  printf 'extended\t%s\t%s new row(s)\n' "$PROFILE" "$OBS_N"
  exit "$GA_EX_OK"
fi

{
  printf '# %s\n\n' "${PLATFORM:-$TOOL}"
  printf -- '- **Platform:** %s\n' "${PLATFORM:-<what kind of system, and what it holds>}"
  printf -- '- **Reached via:** %s\n' "${VIA:-<connector tool names, or what was pasted>}"
  printf -- '- **Read it when** extracting one of the attributes below, or deciding whether one is reachable\n'
  printf -- '- **Recipe:** `./%s` — the call sequence, wired and unwired\n' "$RECIPE"
  printf -- '- **Status:** active · failures 0 · **Last verified:** %s\n' "$TODAY"
  printf -- '\nEvery row below was observed in a real response. `not observed` means exactly that and is\n'
  printf -- 'left alone until it is actually seen — see [TOOL-PROFILES.md](../../docs/TOOL-PROFILES.md).\n'
  printf -- '\n---\n\n## Attributes\n\n'
  printf -- '| Attribute | Unit / type | Accessible | Extraction method | Scope | Observed |\n'
  printf -- '|---|---|---|---|---|---|\n'
  cat "$rowsfile"
  printf -- '\n## Connectivity\n\n'
  printf -- '**Wired** — %s\n\n' "${VIA:-<which connector tools, and what each needs as input>}"
  printf -- '**Unwired** — <what is still obtainable from a pasted reference, what must be asked for,\n'
  printf -- 'and what is simply unreachable>\n'
  printf -- '\n## Usage notes and gotchas\n\n'
  printf -- '<what cost a wrong turn the first time — a unit that is not what it looks like, a scope that\n'
  printf -- 'is per-account not per-record, a value only present after another call>\n'
} > "$PROFILE"

cat > "$RECIPE" <<'RECIPE'
#!/usr/bin/env bash
#@kind      tool
#@platform  macos
#@claude    call
#@purpose   Print the recorded access recipe for @@PLATFORM@@, wired and unwired.
#@usage     @@TOOL@@.sh [--unwired] [--attributes]
#@in        --unwired:flag(only the reference-only branch) --attributes:flag(only the attribute table)
#@out       stdout:the recorded call sequence, and what is unreachable without a connector
#@exit      0=printed 1=the profile is missing or has no attribute rows 2=usage
#@effects   read-only. Prints what the profile records; never calls the platform

set -o pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROFILE="$ROOT/@@PROFILE@@"
WANT=all

case "${1:-}" in
  --unwired)    WANT=unwired ;;
  --attributes) WANT=attributes ;;
  -h|--help)    sed -n '2,11p' "$0"; exit 2 ;;
  '')           ;;
  *)            printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
esac

if [ ! -f "$PROFILE" ]; then
  printf 'no profile at %s — it was retired or never written\n' "$PROFILE" >&2
  exit 1
fi

printf 'recipe for @@PLATFORM@@ — recorded, not live. Verify a row before trusting it.\n'
printf 'source: %s\n\n' "@@PROFILE@@"

if [ "$WANT" = all ] || [ "$WANT" = attributes ]; then
  printf '── attributes  (attribute · unit · extraction · scope)\n'
  ROWS="$(awk -F'|' '
    /^\|---/ { next }
    /Unit \/ type/ { next }
    /^\| / {
      for (i = 2; i <= 6; i++) { gsub(/^[ \t]+|[ \t]+$/, "", $i) }
      if ($2 == "" || $2 ~ /^</ || $2 == "—") next
      printf "  %-30s %-16s %-34s %s\n", $2, $3, $5, $6
    }
  ' "$PROFILE")"
  if [ -z "$ROWS" ]; then
    printf '  none recorded — the profile carries no attribute row\n' >&2
    exit 1
  fi
  printf '%s\n\n' "$ROWS"
fi

if [ "$WANT" = all ] || [ "$WANT" = unwired ]; then
  printf '── connectivity  (wired, and what a pasted reference still reaches)\n'
  awk '/^## Connectivity$/ { f = 1; next } /^## / { f = 0 } f' "$PROFILE" \
    | sed '/^$/d; s/^/  /'
  printf '\n── gotchas\n'
  awk '/^## Usage notes/ { f = 1; next } /^## / { f = 0 } f' "$PROFILE" \
    | sed '/^$/d; s/^/  /'
fi
RECIPE

sed -i '' \
  -e "s|@@PLATFORM@@|$(printf '%s' "${PLATFORM:-$TOOL}" | sed 's/[&|\\]/\\\\&/g')|g" \
  -e "s|@@PROFILE@@|$PROFILE|g" \
  -e "s|@@TOOL@@|$TOOL|g" \
  "$RECIPE"

chmod +x "$RECIPE"

if [ -z "$ROW" ]; then
  printf '%s\t%s\t%s\t%s\t%s\t%s\t0\tactive\n' \
    "$TOOL" "$PROFILE" "$RECIPE" "$WIRED" "$TODAY" "$TODAY" >> "$LEDGER"
else
  set_field "$TOOL" 6 "$TODAY"
  set_field "$TOOL" 7 0
  set_field "$TOOL" 8 active
fi

do_sync >/dev/null
"$HERE/claude-utils/register-scripts.sh" >/dev/null 2>&1 \
  || ga_warn "register-scripts.sh rejected the generated header — fix $RECIPE and re-run it"

printf 'written\t%s\n' "$PROFILE"
printf 'written\t%s\n' "$RECIPE"
printf 'indexed\t%s %s %s %s\n' "$LEDGER" "$REGISTRY" "$MAP" "$INDEX"
printf '%s retrieved, %s contract-only, %s left as not observed\n' \
  "$OBSERVED" "$CONTRACT" "$((OBS_N - OBSERVED - CONTRACT))"
printf 'fill the Connectivity and gotcha sections from what you actually saw, then:\n'
printf '  ./Scripts/ga-reseal.sh --apply\n'
