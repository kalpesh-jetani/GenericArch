#!/usr/bin/env bash
# Bootstrap the CLAUDE.md task pipeline: locate projects, record where each
# one's CLAUDE.md lives, and detect the per-project config the later phases need
# (source language, test command, component and API source roots).
#
#   ./Scripts/claude-utils/init-claude-env.sh                  # register this repo, then list
#   ./Scripts/claude-utils/init-claude-env.sh --add talentsure ~/code/talentsure
#   ./Scripts/claude-utils/init-claude-env.sh --scan ~/code     # every CLAUDE.md under a tree
#   ./Scripts/claude-utils/init-claude-env.sh --list
#   ./Scripts/claude-utils/init-claude-env.sh --remove talentsure
#
# Writes only .claude/claude-tasks/projects.tsv. Detection is best-effort and
# recorded, never enforced — phase 7 prints the test command it found and lets
# you correct it, because guessing wrong about how a project builds is cheap to
# fix and expensive to hide.
. "$(dirname "$0")/_common.sh"

usage_text() {
  sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
}

# detect_test_cmd <root> — how this project runs its tests, or empty.
detect_test_cmd() {
  if [ -f "$1/Package.swift" ]; then
    printf 'swift test --package-path .'
  elif ls "$1"/*.xcodeproj "$1"/*.xcworkspace >/dev/null 2>&1; then
    printf 'xcodebuild test -scheme <scheme> -destination "platform=iOS Simulator,name=iPhone 15"'
  elif [ -f "$1/package.json" ]; then
    printf 'npm test'
  elif [ -f "$1/pyproject.toml" ] || [ -f "$1/pytest.ini" ] || [ -f "$1/setup.cfg" ]; then
    printf 'pytest'
  elif [ -f "$1/go.mod" ]; then
    printf 'go test ./...'
  elif [ -f "$1/Cargo.toml" ]; then
    printf 'cargo test'
  fi
}

# detect_source_glob <root> — the extension phase 7 greps to check that symbols
# documented in CLAUDE.md actually exist in the code.
detect_source_glob() {
  if [ -f "$1/Package.swift" ] || ls "$1"/*.xcodeproj >/dev/null 2>&1; then printf '*.swift'
  elif [ -f "$1/package.json" ]; then printf '*.ts'
  elif [ -f "$1/go.mod" ]; then printf '*.go'
  elif [ -f "$1/Cargo.toml" ]; then printf '*.rs'
  elif [ -f "$1/pyproject.toml" ]; then printf '*.py'
  else printf '*'
  fi
}

registry_init() {
  mkdir -p "$TASKS_ROOT" || die "cannot create $TASKS_ROOT"
  [ -f "$REGISTRY" ] && return 0
  printf '# name\troot\tclaude_md\ttest_cmd\tsource_glob\n' > "$REGISTRY"
  dim "created $REGISTRY"
}

# add_project <name> <path>
add_project() {
  name="$(slugify "$1")"
  check_id "$name" "project name"
  [ -d "$2" ] || die "no such directory: $2"
  root="$(cd "$2" && pwd)"

  claude_md="$root/CLAUDE.md"
  if [ ! -f "$claude_md" ]; then
    # A project with no CLAUDE.md is still worth registering — task type
    # `add-section` on a fresh file is legitimate. Record the path it WOULD be.
    warn "$name has no CLAUDE.md yet — recording the path it would take"
  fi

  test_cmd="$(detect_test_cmd "$root")"
  glob="$(detect_source_glob "$root")"

  registry_init
  tmp="$REGISTRY.tmp.$$"
  grep -v "^$name	" "$REGISTRY" > "$tmp" 2>/dev/null || : > "$tmp"
  printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$root" "$claude_md" "$test_cmd" "$glob" >> "$tmp"
  { grep '^#' "$tmp"; grep -v '^#' "$tmp" | sort -t'	' -k1,1; } > "$REGISTRY"
  rm -f "$tmp"

  ok "registered $name"
  info "root       $root"
  info "CLAUDE.md  $claude_md$([ -f "$claude_md" ] || printf ' (absent)')"
  info "tests      ${test_cmd:-— none detected}"
  info "sources    $glob"
}

remove_project() {
  [ -f "$REGISTRY" ] || die "no registry to remove from" "$EX_PRECOND"
  grep -q "^$1	" "$REGISTRY" || die "not registered: $1" "$EX_USAGE"
  tmp="$REGISTRY.tmp.$$"
  grep -v "^$1	" "$REGISTRY" > "$tmp"
  mv "$tmp" "$REGISTRY"
  ok "removed $1"
  dim "task artifacts under $TASKS_ROOT/$1 were left alone — delete them by hand if you meant to"
}

scan_tree() {
  [ -d "$1" ] || die "no such directory: $1"
  hdr "scanning $1 for CLAUDE.md"
  found=0
  # maxdepth 4 keeps this from walking a whole home directory. Prune the usual
  # heavy directories; a CLAUDE.md inside node_modules is not a project.
  for f in $(find "$1" -maxdepth 4 -name CLAUDE.md -type f \
               -not -path '*/node_modules/*' -not -path '*/.build/*' \
               -not -path '*/.git/*' -not -path '*/dist/*' 2>/dev/null); do
    d="$(dirname "$f")"
    add_project "$(basename "$d")" "$d"
    found=$((found + 1))
  done
  [ "$found" -eq 0 ] && warn "no CLAUDE.md found under $1 (searched 4 levels deep)"
  return 0
}

list_projects() {
  [ -f "$REGISTRY" ] || die "no registry yet — run without arguments to create one" "$EX_PRECOND"
  hdr "registered projects"
  awk -F'\t' '!/^#/ {
    printf "  %-16s %s\n", $1, $2
    printf "  %-16s CLAUDE.md: %s\n", "", ($3 == "" ? "—" : $3)
    printf "  %-16s tests:     %s\n\n", "", ($4 == "" ? "—" : $4)
  }' "$REGISTRY"
  n=$(count_rows "$REGISTRY")
  dim "$n project(s) · $REGISTRY"
}

# ── Arguments ──────────────────────────────────────────────────────────────
[ $# -eq 0 ] && {
  registry_init
  add_project "$(basename "$(ga_home)")" "$(ga_home)"
  list_projects
  exit "$EX_OK"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --add)
      [ $# -ge 3 ] || die "--add needs <name> <path>" "$EX_USAGE"
      add_project "$2" "$3"; shift 3 ;;
    --scan)
      [ $# -ge 2 ] || die "--scan needs <dir>" "$EX_USAGE"
      registry_init; scan_tree "$2"; shift 2 ;;
    --remove)
      [ $# -ge 2 ] || die "--remove needs <name>" "$EX_USAGE"
      remove_project "$2"; shift 2 ;;
    --list) list_projects; shift ;;
    -h|--help) usage "$EX_OK" ;;
    *) die "unknown argument: $1" "$EX_USAGE" ;;
  esac
done
