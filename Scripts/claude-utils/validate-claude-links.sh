#!/usr/bin/env bash
#@kind      util
#@platform  macos
#@claude    call
#@purpose   Resolve every internal link and anchor in a markdown file. Never touches the network.
#@usage     validate-claude-links.sh <file> [--quiet]
#@in        file:path
#@out       stdout:tsv-ish(line,kind,dest,reason) + xed hints
#@exit      0=all resolve 1=broken links 2=usage
#@effects   read-only
#@when      broken links in a doc|do the links resolve|check anchors
# Cross-phase: resolve every internal link in a markdown document.
#
#   ./Scripts/claude-utils/validate-claude-links.sh <file> [--quiet]
#
# Checks, per link:
#   #anchor        a heading in this file normalises to that slug
#   path           the file or directory exists, relative to this document
#   path#anchor    both — the file exists AND carries that heading
#   http(s)://     SKIPPED. Reaching the network would make a lint run depend on
#                  connectivity, and a 403 from a site that blocks robots is not
#                  a broken link. Counted and reported, never fetched.
#
# Exit 0 clean · 1 broken links · 2 usage.
#
# Anchor slugs follow the GitHub rule: lowercase, drop anything that is not a
# letter, digit, space, underscore or hyphen, then spaces to hyphens. Getting
# this subtly wrong is worse than not checking, so it is defined in exactly one
# place — md_sections() in _common.sh — and shared with the audit phase.
. "$(dirname "$0")/_common.sh"

usage_text() { usage_from "$0"; }

QUIET=0; FILE=''
while [ $# -gt 0 ]; do
  case "$1" in
    --quiet|-q) QUIET=1; shift ;;
    -h|--help)  usage "$EX_OK" ;;
    -*)         die "unknown argument: $1" "$EX_USAGE" ;;
    *)          [ -z "$FILE" ] || die "one file at a time" "$EX_USAGE"
                FILE="$1"; shift ;;
  esac
done

[ -n "$FILE" ] || usage
[ -r "$FILE" ] || die "cannot read $FILE" "$EX_USAGE"

BASE="$(cd "$(dirname "$FILE")" && pwd)"
TMP="${TMPDIR:-/tmp}/ga-links.$$"
mkdir -p "$TMP" || die "cannot create temp dir"
trap 'rm -rf "$TMP"' EXIT INT TERM

# Slugs this document offers.
md_sections "$FILE" | cut -f4 | sort -u > "$TMP/own-slugs"

# Every link, with its line: inline [t](d) plus reference definitions [t]: d.
awk '
  /^[ \t]*(```|~~~)/ { fence = !fence; next }
  fence { next }
  {
    tmp = $0
    while (match(tmp, /\]\([^)]*\)/)) {
      d = substr(tmp, RSTART + 2, RLENGTH - 3)
      tmp = substr(tmp, RSTART + RLENGTH)
      # Strip a markdown link title: [t](path "Title")
      sub(/[ \t]+"[^"]*"$/, "", d)
      if (d != "") printf "%d\t%s\n", FNR, d
    }
  }
  /^[ \t]*\[[^]]+\]:[ \t]*[^ \t]/ {
    d = $0
    sub(/^[ \t]*\[[^]]+\]:[ \t]*/, "", d)
    sub(/[ \t].*$/, "", d)
    if (d != "") printf "%d\t%s\n", FNR, d
  }
' "$FILE" > "$TMP/links"

TOTAL=$(wc -l < "$TMP/links" | tr -d ' ')
: > "$TMP/broken"
EXTERNAL=0; CHECKED=0

while IFS='	' read -r line dest; do
  [ -n "$dest" ] || continue
  case "$dest" in
    http://*|https://*|mailto:*|tel:*)
      EXTERNAL=$((EXTERNAL + 1)); continue ;;
  esac

  CHECKED=$((CHECKED + 1))
  path="${dest%%#*}"
  frag=''
  case "$dest" in *#*) frag="${dest#*#}" ;; esac

  if [ -z "$path" ]; then
    # Same-document anchor.
    if [ -n "$frag" ] && ! grep -qxF "$frag" "$TMP/own-slugs"; then
      printf '%s\tanchor\t%s\tno heading in this file slugs to #%s\n' "$line" "$dest" "$frag" >> "$TMP/broken"
    fi
    continue
  fi

  # URL-decode the commonest escape so "My%20Doc.md" resolves.
  decoded=$(printf '%s' "$path" | sed 's/%20/ /g')
  case "$decoded" in
    /*) resolved="$decoded" ;;
    *)  resolved="$BASE/$decoded" ;;
  esac

  if [ ! -e "$resolved" ]; then
    printf '%s\tpath\t%s\tno such file: %s\n' "$line" "$dest" "$decoded" >> "$TMP/broken"
    continue
  fi

  if [ -n "$frag" ] && [ -f "$resolved" ]; then
    case "$resolved" in
      *.md|*.markdown)
        if ! md_sections "$resolved" | cut -f4 | grep -qxF "$frag"; then
          printf '%s\tanchor\t%s\t%s has no heading slugging to #%s\n' \
            "$line" "$dest" "$decoded" "$frag" >> "$TMP/broken"
        fi ;;
    esac
  fi
done < "$TMP/links"

BROKEN=$(wc -l < "$TMP/broken" | tr -d ' ')

if [ "$QUIET" -eq 0 ]; then
  hdr "links — $(basename "$FILE")"
  info "$TOTAL total · $CHECKED resolvable · $EXTERNAL external (not fetched)"
fi

if [ "$BROKEN" -gt 0 ]; then
  printf '\n'
  awk -F'\t' -v r="$RED" -v o="$OFF" \
    '{printf "  %sline %-5s%s %-34s %s\n", r, $1, o, $3, $4}' "$TMP/broken"
  printf '\n'
  # Open the first one at its line, so a fix starts in the right place.
  dim "$(xed_hint "$FILE" "$(head -1 "$TMP/broken" | cut -f1)")"
  printf '\n'
  die "$BROKEN broken link(s)" "$EX_ERR"
fi

[ "$QUIET" -eq 0 ] && ok "all $CHECKED internal link(s) resolve"
exit "$EX_OK"
