#!/usr/bin/env bash
#@kind      tool
#@platform  any
#@claude    call
#@purpose   Extract, record and validate the project's declared stack profile — the four answers the declare-profile step records into .genericarch/PROFILE.tsv.
#@usage     ga-profile.sh --extract|--show|--check|--set KEY VALUE|--declare-none REASON [--root DIR]
#@in        --extract:flag(derive the answers from the codebase) --show:flag(what is declared now) --check:flag(validate the projection) --set:kv(KEY VALUE — one row) --declare-none:str(reason this repo has no stack) --root:dir(default: the repo above Scripts/)
#@out       stdout:for extract, key<TAB>value<TAB>evidence rows; for show/check, a report
#@exit      0=ok 1=check found a problem 2=usage
#@effects   --set and --declare-none write .genericarch/PROFILE.tsv; --extract/--show/--check are read-only
#@when      what stack is this|declare the profile|which profile matches|is the profile valid|set a profile key|no stack profile
#
# The declare-profile step records four answers: tech-stack, architecture, dependency manager(s)
# and build system. All four are optional and all four are revisable — --set is how a later session
# corrects one without re-running the step.
#
# What --extract will and will not claim: the layer detects NO ecosystem. It carries no table of
# build markers, because such a table is stack content — it would be permanently incomplete and
# would decide, for every consumer, which ecosystems the layer treats as first-class. The only
# thing --extract can observe is a profile the project itself authored, through the
# detect_marker_* rows in profiles/<name>/profile.tsv. Everything else is printed `not observed`,
# which means ask — never guess. Architecture is always `not observed`: no scan establishes it.
set -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=Scripts/ga-lifecycle.sh
. "$HERE/ga-lifecycle.sh"

MODE=""; ROOT=""; K=""; V=""; REASON=""
while [ $# -gt 0 ]; do
  case "$1" in
    --extract)      MODE=extract; shift ;;
    --show)         MODE=show; shift ;;
    --check)        MODE=check; shift ;;
    --set)          ga_need_val "$@"; MODE=set; K="$2"; V="${3:-}"
                    [ -n "$V" ] || ga_die "--set needs KEY and VALUE" "$GA_EX_USAGE"
                    shift 3 ;;
    --declare-none) ga_need_val "$@"; MODE=declare-none; REASON="$2"; shift 2 ;;
    --root)         ga_need_val "$@"; ROOT="$2"; shift 2 ;;
    -h|--help)      MODE=""; break ;;
    *)              ga_die "unknown argument: $1" "$GA_EX_USAGE" ;;
  esac
done

if [ -z "$MODE" ]; then
  sed -n '5,7p' "$0" | sed 's/^#@[a-z]*  */  /' >&2
  exit "$GA_EX_USAGE"
fi

if [ -n "$ROOT" ]; then
  ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || ga_die "no such directory" "$GA_EX_USAGE"
else
  ROOT="$(cd "$HERE/.." && pwd)"
fi
PROJECTION="$(ga_profile_projection_path "$ROOT")"

row() { printf '%s\t%s\t%s\n' "$1" "$2" "$3"; }

case "$MODE" in

  extract)
    # The layer recognises no ecosystem. The ONLY thing it can observe is a profile this project
    # authored: profiles/<name>/profile.tsv lists the files that prove its stack in detect_marker_*
    # rows, and a profile whose markers are all present is a match. Everything else is the user's
    # to answer — a built-in table of build markers would be stack content, and would decide for
    # every consumer which ecosystems are first-class.
    MATCH=""; MATCH_N=0
    for pdef in "$ROOT"/profiles/*/profile.tsv; do
      [ -f "$pdef" ] || continue
      pname="$(basename "$(dirname "$pdef")")"
      want=0; have=0
      while IFS="$(printf '\t')" read -r pk _; do
        case "$pk" in detect_marker_*) ;; *) continue ;; esac
        want=$((want + 1))
        [ -e "$ROOT/${pk#detect_marker_}" ] && have=$((have + 1))
      done < "$pdef"
      if [ "$want" -gt 0 ] && [ "$have" -eq "$want" ]; then
        MATCH="$pname"; MATCH_N=$((MATCH_N + 1))
      fi
    done

    if [ "$MATCH_N" -eq 1 ]; then
      MDEF="$(ga_profile_def_path "$ROOT" "$MATCH")"
      row active "$MATCH" "every detect_marker_* in profiles/$MATCH/profile.tsv is present"
      # Read the matched definition directly: ga_profile_get resolves through the ACTIVE profile,
      # and nothing is active yet — that is the row this step is about to write.
      for k in platform language language_version dependency_managers build_system build_command; do
        v="$(awk -F'\t' -v k="$k" '$1!~/^#/ && $1==k {print $2; exit}' "$MDEF")"
        [ -n "$v" ] && row "$k" "$v" "declared by profiles/$MATCH/profile.tsv"
      done
    elif [ "$MATCH_N" -gt 1 ]; then
      row active "not observed" "$MATCH_N profiles match their markers — ask which one"
    else
      for k in platform language dependency_managers build_system; do
        row "$k" "not observed" "no authored profile matches this tree — ask"
      done
    fi
    row architecture "not observed" "no scan establishes this — ask"
    ;;

  show)
    if [ ! -f "$PROJECTION" ]; then
      echo "no stack profile declared — run /declare-profile"
      exit "$GA_EX_OK"
    fi
    awk -F'\t' '$1!~/^#/ && NF>=2 {printf "  %-22s %s\n", $1, $2}' "$PROJECTION"
    ;;

  set)
    ga_profile_set "$ROOT" "$K" "$V"
    ga_ok "$K = $V"
    ga_dim "  ${PROJECTION#"$ROOT"/} — commit it, so every clone reads the same answer"
    ;;

  declare-none)
    # `declared`, never `active`. Every reader of ga_profile_active tests for an EMPTY value to mean
    # "no stack here"; writing active=none would send all of them hunting for profiles/none/.
    ga_profile_set "$ROOT" declared none
    ga_profile_set "$ROOT" declared_reason "$REASON"
    ga_ok "declared: no stack profile — $REASON"
    ga_dim "  ${PROJECTION#"$ROOT"/} — commit it, so every clone reads the same answer"
    ;;

  check)
    rc=0
    if [ ! -f "$PROJECTION" ]; then
      ga_warn "no ${PROJECTION#"$ROOT"/} — the stack question has not been answered (run /declare-profile)"
      exit "$GA_EX_ERR"
    fi

    BAD="$(awk -F'\t' '$1!~/^#/ && NF!=0 && NF!=2 {print NR": "$0}' "$PROJECTION")"
    if [ -n "$BAD" ]; then
      ga_warn "malformed row(s) — every line is key<TAB>value:"
      printf '%s\n' "$BAD" >&2
      rc=1
    fi

    DECL="$(ga_profile_declared "$ROOT")"
    if [ -z "$DECL" ]; then
      ga_warn "no \`declared\` row — the projection exists but nothing recorded an answer"
      rc=1
    else
      ga_ok "declared: $DECL"
    fi

    ACTIVE="$(ga_profile_active "$ROOT")"
    if [ -n "$ACTIVE" ]; then
      DEF="$(ga_profile_def_path "$ROOT" "$ACTIVE")"
      if [ -f "$DEF" ]; then
        ga_ok "active profile '$ACTIVE' → ${DEF#"$ROOT"/}"
      else
        ga_warn "active profile '$ACTIVE' has no ${DEF#"$ROOT"/}"
        rc=1
      fi
    fi

    # The one way two developers diverge. The projection is the shared answer, so an uncommitted
    # one means the next clone gets asked again and may answer differently.
    # Warn, never fail. Committing is the user's act (CLAUDE.md §2.2 forbids Claude doing it), so
    # failing here would leave the declare-profile step unable to close on its first run — gated on
    # something the only party running it is not allowed to perform.
    if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
      if ! git -C "$ROOT" ls-files --error-unmatch "$PROJECTION" >/dev/null 2>&1; then
        ga_warn "${PROJECTION#"$ROOT"/} is not tracked by git — commit it, or each clone declares its own stack"
      elif [ -n "$(git -C "$ROOT" status --porcelain -- "$PROJECTION" 2>/dev/null)" ]; then
        ga_warn "${PROJECTION#"$ROOT"/} has uncommitted changes — commit them so every clone agrees"
      fi
    fi
    exit "$rc"
    ;;
esac
exit "$GA_EX_OK"
