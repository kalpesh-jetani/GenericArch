#!/usr/bin/env bash
#@kind      tool
#@platform  macos
#@claude    needs-approval
#@purpose   Scaffold a NEW repo's directory structure from Scaffold/LAYOUT.tsv — app shells, the Core+DIKit floor, and only the layers asked for.
#@usage     ga-scaffold.sh <target-dir> [--with navigation,auth,…] [--all] [--apply] [--list] [--yes]
#@in        target:dir --with:csv(groups from LAYOUT.tsv) --all:flag(every group) --apply:flag(without it, dry run) --list:flag(show the groups and stop) --yes:flag(skip the confirm prompt; same as GA_ASSUME_YES=1, required when there is no tty) --ios:int(iOS floor, default from detect-toolchain) --macos:string(macOS floor, empty for iOS-only)
#@out       stdout:the plan, then what was created; with --apply the tree exists and DECISIONS.md records the choice
#@exit      0=ok 1=target not empty enough|unknown group 2=usage 4=declined at the prompt
#@effects   with --apply: creates directories and files under the TARGET, copies Packages/Core and Packages/DIKit, appends to the target's docs/DECISIONS.md
#@when      new repo structure|scaffold the directories|which layers should exist|starter packages|predefined structure|set up a fresh app|generate the layout|template copy has no layers|no App directory after gh repo create
#
# For a repo that has no structure yet. NEVER for an existing one: an existing repo already answered
# these questions by having a shape, and imposing this one on it is exactly the adoption mistake
# /project-init exists to prevent. install.sh only offers this on a fresh target.
#
# What it is not: a code generator. It creates the layers, the two real packages that form the floor,
# the module doc for each layer taken, and a README where a reader would otherwise guess. The first
# screen is /new-feature's job, not this script's.
set -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=Scripts/ga-lifecycle.sh
. "$HERE/ga-lifecycle.sh"
SRC="$(cd "$HERE/.." && pwd)"
LAYOUT="$SRC/Scaffold/LAYOUT.tsv"
TMPL="$SRC/Scaffold/templates"

TARGET=""; WITH=""; ALL=0; APPLY=0; LIST=0
IOS=""; MACOS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --with)   WITH="${2:-}"; shift 2 || true ;;
    --all)    ALL=1; shift ;;
    --apply)  APPLY=1; shift ;;
    --list)   LIST=1; shift ;;
    --ios)    IOS="${2:-}"; shift 2 || true ;;
    --macos)  MACOS="${2:-}"; shift 2 || true ;;
    # install.sh and uninstall.sh both take --yes, so an operator arrives here expecting it. Without
    # it, `--apply` from a pipe or CI hit the confirm prompt, found no tty, and stopped.
    --yes)    GA_ASSUME_YES=1; export GA_ASSUME_YES; shift ;;
    -h|--help) sed -n '5,8p' "$0"; exit "$GA_EX_USAGE" ;;
    -*)       ga_die "unknown flag: $1" "$GA_EX_USAGE" ;;
    *)        [ -z "$TARGET" ] || ga_die "one target only" "$GA_EX_USAGE"; TARGET="$1"; shift ;;
  esac
done

[ -f "$LAYOUT" ] || ga_die "no Scaffold/LAYOUT.tsv in $SRC — this is not a GenericArch checkout" "$GA_EX_ERR"

groups_all() { awk -F'\t' '!/^#/ && NF>2 {print $3}' "$LAYOUT" | LC_ALL=C sort -u; }

# ── --list ─────────────────────────────────────────────────────────────────
if [ "$LIST" -eq 1 ]; then
  ga_hdr "── Scaffold groups ────────────────────────────────────"
  for g in $(groups_all); do
    n=$(awk -F'\t' -v g="$g" '!/^#/ && $3==g' "$LAYOUT" | grep -c .)
    printf '  %-12s %2s item(s)\n' "$g" "$n"
  done
  echo
  ga_dim "  base is always included. Read Scaffold/ARCHITECTURE-OPTIONS.md before choosing the rest."
  ga_dim "  Recommended: --with navigation,design,storage,messaging,networking"
  exit "$GA_EX_OK"
fi

[ -n "$TARGET" ] || { sed -n '5,6p' "$0" >&2; ga_die "no target given" "$GA_EX_USAGE"; }
[ -d "$TARGET" ] || ga_die "no such directory: $TARGET" "$GA_EX_USAGE"
TARGET="$(cd "$TARGET" && pwd)"
# Scaffolding the repo this script lives in is the NORMAL case — after install, that is where it is
# run from. Only the AUTHORING checkout is off-limits, identified the way ga-step.sh does it. A
# template copy is NOT it: the markers travel with a template, and refusing on their presence alone
# refused the one repo that most needed scaffolding — a new product with only the inherited floor.
if [ "$TARGET" = "$SRC" ] && ga_is_source_checkout "$SRC"; then
  ga_die "the target is the GenericArch checkout itself — scaffold a product repo instead" "$GA_EX_USAGE"
fi

# ── This is for a repo with no shape yet ───────────────────────────────────
# Judged on the PRODUCT's shape, not on any Swift file anywhere: after a fresh install this repo
# already contains Scaffold/seed/, and treating that as "the repo has a structure" would make the
# scaffold refuse the very repo it was installed for.
GA_COMPAT_FOUND=""
for m in "*.xcodeproj" "*.xcworkspace"; do
  hit=$(find "$TARGET" -maxdepth 2 -name "$m" -not -path '*/.git/*' -print -quit 2>/dev/null)
  [ -n "$hit" ] && GA_COMPAT_FOUND="$GA_COMPAT_FOUND ${hit#"$TARGET"/}"
done
for d in Packages App Sources; do
  [ -d "$TARGET/$d" ] && GA_COMPAT_FOUND="$GA_COMPAT_FOUND $d/"
done
hit=$(find "$TARGET" -name '*.swift' -not -path '*/.git/*' -not -path '*/Scaffold/*' \
        -not -path '*/Scripts/*' -not -path "*/$GA_STATE_DIR/*" -print -quit 2>/dev/null)
[ -n "$hit" ] && GA_COMPAT_FOUND="$GA_COMPAT_FOUND ${hit#"$TARGET"/}"
# Two legitimate calls, and the ledger is what tells them apart:
#   first run   — the repo must have no structure of its own
#   adding      — this scaffold already ran here, so of course there is a structure now; --with
#                 <group> later is the documented way to take a layer you skipped
ADDING=0
ga_step_done "$TARGET" scaffold && ADDING=1
#   inherited    a template copy of the base: Packages/Core, Packages/DIKit and the package rules
#                are already here because the copy brought them, and nothing else the layout lists
#                is. That is OUR floor, not a shape this product chose, so it is the adding case —
#                everything present is kept and the missing layers are created.
INHERITED=0
if [ "$ADDING" -eq 0 ] && ga_is_template_copy "$TARGET"; then INHERITED=1; ADDING=1; fi
if [ "$ADDING" -eq 0 ] && [ -n "$GA_COMPAT_FOUND" ]; then
  ga_die "$TARGET already has a structure — found:$GA_COMPAT_FOUND
  This scaffold is for a repo with none. An existing repo keeps its own shape; /project-init
  reconciles the rules against it instead, and /new-feature adds packages one at a time.
  If this structure IS a GenericArch scaffold from elsewhere, say so and re-run:
      ./Scripts/ga-step.sh record scaffold \"scaffolded before this ledger existed\"
  Nothing was written." "$GA_EX_ERR"
fi

# ── Which groups ───────────────────────────────────────────────────────────
SELECTED="base"
if [ "$ALL" -eq 1 ]; then
  SELECTED="$(groups_all | tr '\n' ' ')"
elif [ -n "$WITH" ]; then
  for g in $(printf '%s' "$WITH" | tr ',' ' '); do
    groups_all | grep -qx "$g" || ga_die "unknown group: $g (see --list)" "$GA_EX_ERR"
    SELECTED="$SELECTED $g"
  done
fi
selected_has() { case " $SELECTED " in *" $1 "*) return 0 ;; esac; return 1; }

# ── The floors: detected, never defaulted ──────────────────────────────────
# There is no fallback number here on purpose. A floor a tool picked is a number nobody chose: it
# compiles today and fails on the first shared-code change, and by then it reads as a decision
# (CLAUDE.md §1.1). And an SDK version is not a deployment floor — it says what you can build with,
# never what you must support — so the machine cannot answer this either.
#
# So: the answer comes from the PROJECT, via detect-toolchain.sh, or from the operator via
# --ios/--macos. With neither, generated manifests carry NO platforms line, and the scaffold leaves
# the note that explains how to choose.
# One exception to detecting from the project: in a template copy the manifests being read ARE
# GenericArch's, copied wholesale. Detecting there would launder this repo's floors into every layer
# the product takes and make them look like its own answer, which is the §0 violation the number was
# supposed to avoid. No line is written instead, and --ios/--macos still work.
FLOOR_SRC="none"
if [ "$INHERITED" -eq 1 ] && [ -z "$IOS" ] && [ -z "$MACOS" ]; then
  FLOOR_SRC="none"
elif [ -z "$IOS" ] && [ -z "$MACOS" ] && [ -x "$SRC/Scripts/detect-toolchain.sh" ]; then
  # --root, not a cd. This read "$(cd "$TARGET" && …)" and claimed it scanned the target; it did
  # not — detect-toolchain.sh cd's to its own root, so scaffolding from a checkout into another
  # repo wrote GenericArch's floors into every manifest it generated.
  _dt="$("$SRC/Scripts/detect-toolchain.sh" --markdown --root "$TARGET" 2>/dev/null)"
  # Only rows whose Source column says `project` count. A `machine` row is an SDK, not a floor.
  IOS="$(printf '%s\n' "$_dt" | awk -F'|' '/Minimum iOS/ && $4 ~ /project/ {gsub(/[^0-9.]/,"",$3); print $3}' | head -1)"
  MACOS="$(printf '%s\n' "$_dt" | awk -F'|' '/Minimum macOS/ && $4 ~ /project/ {gsub(/[^0-9.]/,"",$3); print $3}' | head -1)"
  [ -n "$IOS$MACOS" ] && FLOOR_SRC="detected from this repo's manifests"
else
  [ -n "$IOS$MACOS" ] && FLOOR_SRC="given on the command line"
fi

platforms_block() {
  if [ -z "$IOS" ] && [ -z "$MACOS" ]; then
    # No line at all — SPM then applies its own minimums, and the note says how to choose yours.
    printf '    // platforms: not set. Nothing here will choose a deployment floor for you —\n'
    printf '    // ./Scripts/detect-toolchain.sh reports what this repo and this machine say, and\n'
    printf '    // Packages/FLOORS.md explains the asymmetry that decides the numbers (CLAUDE.md §1.1).\n'
    return
  fi
  _p=""
  [ -n "$IOS" ]   && _p=".iOS(.v$IOS)"
  [ -n "$MACOS" ] && _p="${_p:+$_p, }.macOS(\"$MACOS\")"
  printf '    platforms: [%s],\n' "$_p"
}
# The block is passed to awk as a FILE, not with -v: BSD awk rejects a newline inside a -v value and
# exits 2, which silently produced empty manifests until a test caught it.
PLATFORMS_FILE="$(mktemp -t ga-scaffold-platforms)"
platforms_block > "$PLATFORMS_FILE"

render() {   # render <template-name> <package-name> > file
  # The platforms block is substituted, never templated: a template that spells a version ships that
  # version to every repo that uses it.
  awk -v name="$2" -v blkfile="$PLATFORMS_FILE" '
    { gsub(/__NAME__/, name)
      if ($0 == "__PLATFORMS_BLOCK__") {
        while ((getline line < blkfile) > 0) print line
        close(blkfile); next
      }
      print }
  ' "$TMPL/$1.tmpl"
}

# A declared testTarget with no source files does not build. Every package this script creates gets
# one placeholder test, so `swift test` is green from the first commit rather than after a fix.
seed_tests() {   # seed_tests <package-dir> <package-name>
  grep -q testTarget "$1/Package.swift" 2>/dev/null || return 0
  mkdir -p "$1/Tests/$2Tests"
  find "$1/Tests/$2Tests" -name '*.swift' -print -quit 2>/dev/null | grep -q . && return 0
  render source-test-placeholder "$2" > "$1/Tests/$2Tests/${2}PlaceholderTests.swift"
  printf '  %s+%s %s\n' "$GA_DIM" "$GA_OFF" "${1#"$TARGET"/}/Tests/$2Tests/${2}PlaceholderTests.swift"
}

# ── Plan ───────────────────────────────────────────────────────────────────
ga_hdr "GenericArch scaffold"
printf '  into     %s\n' "$TARGET"
printf '  groups   %s%s%s\n' "$GA_BLD" "$SELECTED" "$GA_OFF"
if [ "$INHERITED" -eq 1 ]; then
  printf '  %stemplate copy — the Core+DIKit floor arrived with it; anything present is kept%s\n' \
    "$GA_DIM" "$GA_OFF"
  printf '  %sits Package.swift floors are GenericArch\047s, not yours — reset them, or pass --ios/--macos%s\n' \
    "$GA_YEL" "$GA_OFF"
elif [ "$ADDING" -eq 1 ]; then
  printf '  %sadding to a scaffold that already ran here — anything present is kept%s\n' \
    "$GA_DIM" "$GA_OFF"
fi
if [ -z "$IOS" ] && [ -z "$MACOS" ]; then
  printf '  floors   %snot set%s  %s(nothing to detect yet — no version is written anywhere;\n' \
    "$GA_YEL" "$GA_OFF" "$GA_DIM"
  printf '           Packages/FLOORS.md explains how to choose, /decide records it)%s\n' "$GA_OFF"
else
  printf '  floors   %s%s%s  %s(%s)%s\n' "${IOS:+iOS $IOS}" "${MACOS:+${IOS:+ · }macOS $MACOS}" \
    "" "$GA_DIM" "$FLOOR_SRC" "$GA_OFF"
fi
if [ "$APPLY" -eq 1 ]; then printf '  mode     %sapply%s\n' "$GA_GRN" "$GA_OFF"
else printf '  mode     %sdry run%s — the plan only\n' "$GA_YEL" "$GA_OFF"; fi
echo

PLAN="$(mktemp -t ga-scaffold)"
trap 'rm -f "$PLAN" "$PLATFORMS_FILE"' EXIT INT TERM
while IFS="$(printf '\t')" read -r path kind group source purpose; do
  case "$path" in ''|\#*) continue ;; esac
  selected_has "$group" || continue
  printf '%s\t%s\t%s\t%s\t%s\n' "$path" "$kind" "$group" "$source" "$purpose" >> "$PLAN"
done < "$LAYOUT"

skipped=0
ga_hdr "── Would create ───────────────────────────────────────"
while IFS="$(printf '\t')" read -r path kind group source purpose; do
  if [ -e "$TARGET/$path" ]; then
    printf '  %s·%s %-58s %sexists — kept%s\n' "$GA_YEL" "$GA_OFF" "$path" "$GA_DIM" "$GA_OFF"
    skipped=$((skipped + 1)); continue
  fi
  case "$source" in
    dir)    mark="+ dir " ;;
    copy:*) mark="+ copy" ;;
    tmpl:*) mark="+ new " ;;
    doc:*)  mark="+ doc " ;;
    *)      mark="+ ?   " ;;
  esac
  printf '  %s%s%s %-58s %s%s%s\n' "$GA_GRN" "$mark" "$GA_OFF" "$path" "$GA_DIM" "$purpose" "$GA_OFF"
done < "$PLAN"

echo
printf '%d item(s) · %d already present\n' "$(grep -c . "$PLAN")" "$skipped"
if [ "$APPLY" -eq 0 ]; then
  echo
  ga_dim "Read Scaffold/ARCHITECTURE-OPTIONS.md, then re-run with --apply."
  ga_dim "Layers can be added later: ga-scaffold.sh $TARGET --with <group> --apply"
  exit "$GA_EX_OK"
fi

echo
ga_confirm "Create this structure in $TARGET?" || exit "$GA_EX_ABORT"

# ── Create ─────────────────────────────────────────────────────────────────
ga_hdr "── Creating ───────────────────────────────────────────"
made=0
while IFS="$(printf '\t')" read -r path kind group source purpose; do
  dest="$TARGET/$path"
  [ -e "$dest" ] && continue
  case "$kind" in
    dir)  [ "$source" = "dir" ] && mkdir -p "$dest" ;;
    file) mkdir -p "$(dirname "$dest")" ;;
  esac
  case "$source" in
    dir) : ;;
    copy:*)
      # In an installed repo there is no Packages/ to copy from — the installer left the seed under
      # Scaffold/seed/ instead, so the same LAYOUT row resolves in both places. Checked in that
      # order: the local seed wins, a full checkout still works.
      want="${source#copy:}"
      # The package rules are seeded under a distinct name so nothing loads them from the staging
      # directory as if they applied there. Resolve that alias first, then the plain basename, then a
      # full checkout.
      case "$want" in
        Packages/CLAUDE.md) from="$SRC/Scaffold/seed/PACKAGES-CLAUDE.md" ;;
        *)                  from="$SRC/Scaffold/seed/$(basename "$want")" ;;
      esac
      # Two candidates, not three: the installed seed, then a full checkout's own tree. (There was a
      # third line here that retested the seed path verbatim — it could never change the outcome.)
      [ -e "$from" ] || from="$SRC/$want"
      if [ ! -e "$from" ]; then
        ga_warn "no seed for $want — neither Scaffold/seed/$(basename "$want") nor $want is here; skipped"
        continue
      fi
      mkdir -p "$(dirname "$dest")"
      cp -R "$from" "$dest"
      # The seed packages carry THIS repo's floors. Rewrite them to the target's, or the first
      # shared-code change fails against a floor nobody chose.
      if [ -f "$dest/Package.swift" ]; then
        # The seed carries GENERICARCH's floors. They are this repo's answer to a question the
        # product has not been asked, so they never travel: replaced by the detected ones, or
        # removed outright.
        tmp="$dest/Package.swift.tmp"
        awk -v blkfile="$PLATFORMS_FILE" '
          /^[[:space:]]*platforms:/ {
            while ((getline line < blkfile) > 0) print line
            close(blkfile); next
          }
          { print }
        ' "$dest/Package.swift" > "$tmp" && mv "$tmp" "$dest/Package.swift"
        seed_tests "$dest" "$(basename "$path")"
      fi
      ;;
    tmpl:*)
      name="$(basename "$path" .md)"
      case "$kind" in
        dir)   # a package directory: manifest + the source and test folders it needs to build
          pkg="$(basename "$path")"
          mkdir -p "$dest/Sources/$pkg"
          render "${source#tmpl:}" "$pkg" > "$dest/Package.swift"
          # The placeholder source has to exist before the test that imports it, and LAYOUT.tsv only
          # lists one for some groups — seed both here so no generated package is born broken.
          [ -f "$dest/Sources/$pkg/Placeholder.swift" ] \
            || render source-placeholder "$pkg" > "$dest/Sources/$pkg/Placeholder.swift"
          seed_tests "$dest" "$pkg"
          ;;
        file)
          pkg="$(printf '%s' "$path" | awk -F/ '{for(i=1;i<=NF;i++) if($i=="Sources") {print $(i+1); exit}}')"
          [ -n "$pkg" ] || pkg="$name"
          render "${source#tmpl:}" "$pkg" > "$dest"
          ;;
      esac
      ;;
    doc:*)
      from="$SRC/${source#doc:}"
      if [ -f "$from" ]; then cp "$from" "$dest"
      else
        # Reference docs are fetched, not carried — leave the instruction, not a broken link.
        printf '# %s\n\nNot fetched yet. This doc is reference material, kept upstream:\n\n    %s\n' \
          "$(basename "$dest" .md)" "${source#doc:}" > "$dest"
        ga_warn "left a fetch stub for ${source#doc:}"
      fi
      ;;
  esac
  printf '  %s✓%s %s\n' "$GA_GRN" "$GA_OFF" "$path"
  made=$((made + 1))
done < "$PLAN"

# ── Record the choice ──────────────────────────────────────────────────────
# A scaffold is a set of answers. Unrecorded, the next person re-asks why StorageKit is missing.
DEC="$TARGET/docs/DECISIONS.md"
if [ -f "$DEC" ] && grep -q '^## Settled' "$DEC"; then
  row="| Layers on day one | **$SELECTED** | Scaffolded by \`ga-scaffold.sh\`; iOS floor $IOS${MACOS:+, macOS $MACOS}. Layers not taken are absent on purpose — add one with \`ga-scaffold.sh --with <group>\`, and read \`Scaffold/ARCHITECTURE-OPTIONS.md\` first | — |"
  tmp="$DEC.tmp"
  awk -v row="$row" '
    /^## Settled/ {print; inblock=1; next}
    inblock && /^\| *-+/ {print; print row; inblock=0; next}
    {print}
  ' "$DEC" > "$tmp" && mv "$tmp" "$DEC"
  ga_ok "docs/DECISIONS.md — recorded the layers taken"
else
  ga_warn "no docs/DECISIONS.md with a 'Settled' section — record the layers you took by hand"
fi

echo
ga_ok "$made item(s) created"
# The step the gate is waiting on. Without this, every command after it stays blocked.
if [ -x "$SRC/Scripts/ga-step.sh" ]; then
  if [ "$ADDING" -eq 1 ] && [ "$INHERITED" -eq 0 ]; then
    ga_dim "  step already recorded; added: $SELECTED"
  else
    STEP_NOTE="layers: $SELECTED"
    [ "$INHERITED" -eq 1 ] && STEP_NOTE="$STEP_NOTE (onto a template copy's inherited floor)"
    "$SRC/Scripts/ga-step.sh" record scaffold "$STEP_NOTE" --target "$TARGET" >/dev/null 2>&1 && ga_ok "step recorded: scaffold"
  fi
fi
ga_hdr "── Next ───────────────────────────────────────────────"
cat <<NEXT

  1. ${GA_BLD}/project-init${GA_OFF}   product name, bundle ID, Team ID, languages, permissions
  2. Create the Xcode project yourself and add the packages by path — nothing here generates
     project files, and SPM stays the source of truth (docs/REPO.md)
  3. ${GA_BLD}/new-feature${GA_OFF}    the first screen: protocol, mock, every content state, localized keys

${GA_DIM}Add a layer later:  ./Scripts/ga-scaffold.sh $TARGET --with <group> --apply
Placeholder.swift files exist so each package compiles — delete each with its first real type.${GA_OFF}
NEXT
