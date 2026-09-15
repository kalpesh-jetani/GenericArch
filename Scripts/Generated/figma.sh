#!/usr/bin/env bash
#@kind      tool
#@platform  macos
#@claude    call
#@purpose   Print the recorded access recipe for Figma — design files, variables and screenshots, reached through the Figma MCP connector, wired and unwired.
#@usage     figma.sh [--unwired] [--attributes]
#@in        --unwired:flag(only the reference-only branch) --attributes:flag(only the attribute table)
#@out       stdout:the recorded call sequence, and what is unreachable without a connector
#@exit      0=printed 1=the profile is missing or has no attribute rows 2=usage
#@effects   read-only. Prints what the profile records; never calls the platform

set -o pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROFILE="$ROOT/.claude/tools/figma.md"
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

printf 'recipe for Figma — design files, variables and screenshots, reached through the Figma MCP connector — recorded, not live. Verify a row before trusting it.\n'
printf 'source: %s\n\n' ".claude/tools/figma.md"

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
