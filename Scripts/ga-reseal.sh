#!/usr/bin/env bash
#@kind      tool
#@platform  macos
#@claude    call
#@purpose   Re-hash manifest records for installed files that later commands edited, so uninstall can still prove ownership and remove them.
#@usage     ga-reseal.sh [--apply] [--target DIR]
#@in        --apply:flag(without it, dry run) --target:dir(default: the repo above Scripts/)
#@out       stdout:table(path,state) of drifted, missing and clean records; with --apply the manifest is rewritten in place
#@exit      0=nothing drifted or reseal applied 1=drift found in dry run 2=usage
#@effects   with --apply: rewrites the sha256 of drifted records in .genericarch/manifest-<version>.json
#@when      uninstall left files behind|why is this file protected|after project-init|after sync-app-notes|manifest drift|reseal|orphan on uninstall
#
# uninstall.sh only removes a file whose hash still matches its manifest record — that is the whole
# ownership contract. But /project-init, /sync-app-notes and /gaps all rewrite installed files in
# place, and every such edit silently turns a removable file into a permanent orphan. That is how
# one uninstall removed 4 files out of 110 and reported nothing.
#
# Reseal says: these edits are ours, keep them removable. Run it as the last step of any command
# that rewrites installed files.
set -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=Scripts/ga-lifecycle.sh
. "$HERE/ga-lifecycle.sh"

TARGET="$(cd "$HERE/.." && pwd)"
APPLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --apply)  APPLY=1; shift ;;
    --target) TARGET="$(cd "${2:-}" 2>/dev/null && pwd)" || ga_die "no such directory: ${2:-}" "$GA_EX_USAGE"; shift 2 ;;
    *)        ga_die "usage: ga-reseal.sh [--apply] [--target DIR]" "$GA_EX_USAGE" ;;
  esac
done

MANIFEST=""
for m in $(ga_manifest_find "$TARGET"); do MANIFEST="$m"; done
[ -n "$MANIFEST" ] || { ga_info "no manifest in ${TARGET##*/} — nothing to reseal"; exit "$GA_EX_OK"; }

MAP="$(mktemp -t ga-reseal)"
trap 'rm -f "$MAP" "$MAP.new"' EXIT INT TERM

drift=0; missing=0; clean=0
ga_hdr "── Reseal: $(basename "$MANIFEST") ─────────────────────"
echo
while IFS= read -r rec; do
  rel="$(ga_json_field "$rec" path)"
  act="$(ga_json_field "$rec" action)"
  rsha="$(ga_json_field "$rec" sha256)"
  case "$act" in skipped) continue ;; esac
  if [ ! -e "$TARGET/$rel" ]; then
    # Gone from disk but still claimed by the manifest: the next install re-creates it. That is a
    # decision that was never recorded — ga-remove.sh is the tool, not a reseal.
    printf '  %s?%s %-46s %sdeleted by hand — declare it: ga-remove.sh %s --reason "..."%s\n' \
      "$GA_YEL" "$GA_OFF" "$rel" "$GA_DIM" "$rel" "$GA_OFF"
    missing=$((missing + 1)); continue
  fi
  dsha="$(ga_sha256 "$TARGET/$rel")"
  if [ "$dsha" = "$rsha" ]; then clean=$((clean + 1)); continue; fi
  printf '  %s~%s %-46s %sedited since install%s\n' "$GA_YEL" "$GA_OFF" "$rel" "$GA_DIM" "$GA_OFF"
  printf '%s\t%s\n' "$rel" "$dsha" >> "$MAP"
  drift=$((drift + 1))
done <<EOF
$(ga_manifest_records "$MANIFEST")
EOF

echo
printf '  %s clean · %s edited · %s deleted-by-hand\n' "$clean" "$drift" "$missing"

if [ "$drift" -eq 0 ]; then
  [ "$missing" -gt 0 ] && ga_warn "nothing to reseal, but $missing record(s) point at files that are gone — see above"
  exit "$GA_EX_OK"
fi

if [ "$APPLY" -eq 0 ]; then
  echo
  ga_warn "dry run — add --apply to reseal $drift record(s)"
  exit "$GA_EX_ERR"
fi

awk -v mapfile="$MAP" '
  BEGIN {
    FS="\t"
    while ((getline line < mapfile) > 0) { split(line, a, "\t"); want[a[1]] = a[2] }
  }
  {
    line = $0
    if (match(line, /"path": "[^"]*"/)) {
      # `"path": "` is 9 chars, and the match includes the closing quote: value starts at +9 and
      # runs for RLENGTH-10. Off by one here silently rewrites nothing while reporting success.
      p = substr(line, RSTART + 9, RLENGTH - 10)
      if (p in want && match(line, /"sha256": "[^"]*"/)) {
        line = substr(line, 1, RSTART - 1) "\"sha256\": \"" want[p] "\"" substr(line, RSTART + RLENGTH)
      }
    }
    print line
  }
' "$MANIFEST" > "$MAP.new" && mv "$MAP.new" "$MANIFEST"

# Verify rather than assert: re-hash every path we claimed to reseal and fail loudly if the
# manifest still disagrees. A reseal that silently rewrote nothing is worse than no reseal — it
# reports the files as removable when uninstall will still refuse them.
still=0
while IFS="$(printf '\t')" read -r rel dsha; do
  [ -n "$rel" ] || continue
  rec="$(ga_manifest_record_for "$MANIFEST" "$rel")"
  [ "$(ga_json_field "$rec" sha256)" = "$dsha" ] || { ga_warn "not resealed: $rel"; still=$((still + 1)); }
done < "$MAP"
[ "$still" -eq 0 ] || ga_die "$still record(s) did not take — the manifest is unchanged for them" "$GA_EX_ERR"

ga_ok "resealed $drift record(s) — these files are removable again"
ga_dim "  Commit the manifest with the change that edited them, not separately."
