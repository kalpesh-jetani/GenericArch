#!/usr/bin/env bash
# PHASE 5 · EDIT — apply the planned edits as exact-literal replacements,
# preserving formatting, tracking what changed, and backing up first.
#
#   ./Scripts/claude-workflows/05-apply-claude-edits.sh <project> <task-id>            # dry run
#   ./Scripts/claude-workflows/05-apply-claude-edits.sh <project> <task-id> --approve
#   ./Scripts/claude-workflows/05-apply-claude-edits.sh <project> <task-id> --approve --force
#
# Writes 05-applied.tsv and 05-backup/. WITHOUT --approve it changes nothing and
# prints what it would do — that is the default on purpose.
#
# The approval gate is not ceremony. When the target is a CLAUDE.md, it is loaded
# into every future session of that project, so an edit there changes how every
# later response behaves, indefinitely. docs/STRUCTURE.md makes that the user's
# call, and a script that auto-applied would be the one path around the rule.
#
# --force skips the digest check. The check exists because the plan's OLD text
# was matched against the file as it stood at phase 2; if the file moved since,
# a match at the same offset is a coincidence, not the same edit.
. "$(dirname "$0")/../claude-utils/_common.sh"

usage_text() { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; }

[ $# -ge 2 ] || usage
case "$1" in -h|--help) usage "$EX_OK" ;; esac

PROJECT="$1"; TASK_ID="$2"; shift 2
check_id "$PROJECT" "project name"; check_id "$TASK_ID" "task id"

APPROVE=0; FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --approve) APPROVE=1; shift ;;
    --force)   FORCE=1; shift ;;
    -h|--help) usage "$EX_OK" ;;
    *)         die "unknown argument: $1" "$EX_USAGE" ;;
  esac
done

FILE_ENV="$(need_artifact "$PROJECT" "$TASK_ID" 02-file.env 2)"
PLAN="$(need_artifact "$PROJECT" "$TASK_ID" 04-plan.tsv 4)"
DIR="$(task_dir "$PROJECT" "$TASK_ID")"
TARGET="$(kv_get "$FILE_ENV" TARGET)"
WANT_DIGEST="$(kv_get "$FILE_ENV" DIGEST)"

PLANNED=$(count_rows "$PLAN")
[ "$PLANNED" -gt 0 ] || die "the plan is empty — nothing to apply" "$EX_PRECOND"

need_cmd python3

# ── dry run ────────────────────────────────────────────────────────────────
if [ "$APPROVE" -eq 0 ]; then
  hdr "Phase 5 · edit — DRY RUN (nothing written)"
  info "target  $TARGET"
  info "edits   $PLANNED"
  printf '\n'
  awk -F'\t' '!/^#/ {printf "  %d. %-12s %s\n", NR-1, $2, $1; if ($6 != "") printf "     %s\n", $6}' "$PLAN"
  if [ -f "$DIR/04-outline.md" ]; then
    printf '\n'
    dim "full outline: $DIR/04-outline.md"
  fi
  printf '\n'
  warn "This edits $(basename "$TARGET"), which is loaded into every session of that
    project. Re-run with --approve once you have read the outline."
  exit "$EX_APPROVAL"
fi

# ── preconditions ──────────────────────────────────────────────────────────
[ -f "$TARGET" ] || die "target vanished since phase 2: $TARGET" "$EX_PRECOND"
[ -w "$TARGET" ] || die "target is not writable: $TARGET" "$EX_PRECOND"

if [ -n "$WANT_DIGEST" ] && [ "$FORCE" -eq 0 ]; then
  if command -v shasum >/dev/null 2>&1; then
    HAVE=$(shasum -a 256 "$TARGET" | awk '{print $1}')
  elif command -v sha256sum >/dev/null 2>&1; then
    HAVE=$(sha256sum "$TARGET" | awk '{print $1}')
  else
    HAVE="$WANT_DIGEST"
  fi
  [ "$HAVE" = "$WANT_DIGEST" ] || die "the target changed since phase 2 was run.
    The plan was matched against the older content, so applying it now could edit
    the wrong place. Re-run phases 2-4, or pass --force if you are certain.
      expected $WANT_DIGEST
      found    $HAVE" "$EX_PRECOND"
fi

# ── backup ─────────────────────────────────────────────────────────────────
# Own backup rather than relying on git: phase 2 may have found the file already
# dirty, in which case a git-based undo would also discard unrelated work.
BACKUP_DIR="$DIR/05-backup"
mkdir -p "$BACKUP_DIR" || die "cannot create $BACKUP_DIR"
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="$BACKUP_DIR/$(basename "$TARGET").$STAMP.bak"
cp -p "$TARGET" "$BACKUP" || die "backup failed — refusing to edit without one"
printf '%s\n' "$BACKUP" > "$BACKUP_DIR/latest"

APPLIED="$DIR/05-applied.tsv"
printf '# n\tsection\taction\tresult\tdelta_lines\tnote\n' > "$APPLIED"

# ── apply ──────────────────────────────────────────────────────────────────
# All-or-nothing, in one python process: edits are applied to an in-memory copy
# and the file is written only if every one of them succeeded. A half-applied
# plan is the worst outcome — it leaves a document that matches neither the
# before nor the after, and no phase downstream can tell which.
python3 - "$TARGET" "$PLAN" "$APPLIED" <<'PY'
import sys, io, re

target, plan_path, applied_path = sys.argv[1], sys.argv[2], sys.argv[3]

raw = open(target, 'rb').read()
try:
    text = raw.decode('utf-8')
except UnicodeDecodeError as e:
    sys.exit("target is not valid UTF-8: %s" % e)

# Formatting facts to preserve: line endings and whether the file ends in a
# newline. Both are invisible in a diff viewer and both break tooling if changed.
crlf = '\r\n' in text
if crlf:
    text = text.replace('\r\n', '\n')
had_final_nl = text.endswith('\n')


def read_payload(path):
    if path in ('', '—'):
        return None
    body = open(path, encoding='utf-8').read()
    # Match phase 4's rule: a lone trailing newline on a single-line payload is
    # an artifact of how it was written, not part of the intended match.
    if body.endswith('\n') and body.count('\n') == 1:
        body = body[:-1]
    return body


def headings(s):
    """(level, line_index, title) for every ATX heading outside a code fence."""
    out, fence = [], False
    for i, line in enumerate(s.split('\n')):
        if re.match(r'^[ \t]*(```|~~~)', line):
            fence = not fence
            continue
        if fence:
            continue
        m = re.match(r'^(#{1,6})[ \t]+(.*?)[ \t]*#*[ \t]*$', line)
        if m:
            out.append((len(m.group(1)), i, m.group(2).strip()))
    return out


def section_bounds(s, title):
    """(start_line, end_line_exclusive) of the named section, subsections
    included. Recomputed per edit: a prior edit shifts every line after it."""
    hs = headings(s)
    for idx, (lvl, ln, t) in enumerate(hs):
        if t == title:
            end = len(s.split('\n'))
            for lvl2, ln2, _ in hs[idx + 1:]:
                if lvl2 <= lvl:
                    end = ln2
                    break
            return ln, end
    return None


rows, results = [], []
with open(plan_path, encoding='utf-8') as fh:
    for line in fh:
        if line.startswith('#') or not line.strip():
            continue
        f = line.rstrip('\n').split('\t')
        while len(f) < 6:
            f.append('')
        rows.append(f)

for n, (section, action, old_p, new_p, _occ, note) in enumerate(rows, 1):
    old = read_payload(old_p)
    new = read_payload(new_p)
    before_lines = text.count('\n')

    if action in ('replace', 'delete'):
        if old is None:
            sys.exit("edit %d (%s): %s needs OLD text" % (n, section, action))
        c = text.count(old)
        if c == 0:
            sys.exit("edit %d (%s): OLD text no longer present — nothing applied" % (n, section))
        if c > 1:
            sys.exit("edit %d (%s): OLD text matches %d times — nothing applied" % (n, section, c))
        text = text.replace(old, new if action == 'replace' else '', 1)

    elif action in ('append', 'insert-after'):
        b = section_bounds(text, section)
        if b is None:
            sys.exit("edit %d: no section %r — nothing applied" % (n, section))
        start, end = b
        lines = text.split('\n')
        block = new.split('\n')
        if action == 'insert-after':
            at = start + 1                      # straight after the heading line
        else:
            at = end                            # end of the section, before the next heading
            # Land before the blank lines that separate sections, so the
            # appended block belongs to this section rather than floating.
            while at > start + 1 and lines[at - 1].strip() == '':
                at -= 1
        if at < len(lines) and lines[at - 1].strip() != '' and block[0].strip() != '':
            block = [''] + block
        if at < len(lines) and lines[at:at + 1] and lines[at].strip() != '' and block[-1].strip() != '':
            block = block + ['']
        lines[at:at] = block
        text = '\n'.join(lines)

    elif action == 'new-section':
        after = ''
        m = re.search(r'after:\s*(.+?)\s*$', note or '')
        if m:
            after = m.group(1)
        block = new.split('\n')
        if after:
            b = section_bounds(text, after)
            if b is None:
                sys.exit("edit %d: note says after:%r but no such section — nothing applied" % (n, after))
            lines = text.split('\n')
            at = b[1]
            lines[at:at] = block + ['']
            text = '\n'.join(lines)
        else:
            if not text.endswith('\n'):
                text += '\n'
            text += '\n' + new.rstrip('\n') + '\n'
    else:
        sys.exit("edit %d: unknown action %r" % (n, action))

    delta = text.count('\n') - before_lines
    results.append((n, section, action, 'applied', delta, note))

# Restore the formatting facts recorded before editing.
if had_final_nl and not text.endswith('\n'):
    text += '\n'
elif not had_final_nl:
    text = text.rstrip('\n')
if crlf:
    text = text.replace('\n', '\r\n')

# Single write, after every edit succeeded. Temp-then-rename so an interrupted
# write cannot truncate the original.
tmp = target + '.tmp.apply'
with io.open(tmp, 'w', encoding='utf-8', newline='') as fh:
    fh.write(text)
import os
os.replace(tmp, target)

with open(applied_path, 'a', encoding='utf-8') as fh:
    for r in results:
        fh.write('%d\t%s\t%s\t%s\t%+d\t%s\n' % r)
PY
RC=$?

if [ "$RC" -ne 0 ]; then
  # The python side is all-or-nothing, so the file should be untouched — but
  # restore anyway. A backup that is never used costs nothing; a corrupted
  # CLAUDE.md costs a session.
  cp -p "$BACKUP" "$TARGET" 2>/dev/null
  state_set "$PROJECT" "$TASK_ID" 5 failed "restored from backup"
  die "apply failed — target restored from $BACKUP
    Nothing was changed. Fix the plan and re-run phase 4." "$EX_ERR"
fi

if command -v shasum >/dev/null 2>&1; then
  NEW_DIGEST=$(shasum -a 256 "$TARGET" | awk '{print $1}')
elif command -v sha256sum >/dev/null 2>&1; then
  NEW_DIGEST=$(sha256sum "$TARGET" | awk '{print $1}')
else
  NEW_DIGEST=''
fi

ENV="$DIR/05-apply.env"
: > "$ENV"
kv_set "$ENV" APPLIED_AT  "$(now)"
kv_set "$ENV" TARGET      "$TARGET"
kv_set "$ENV" BACKUP      "$BACKUP"
kv_set "$ENV" EDITS       "$PLANNED"
kv_set "$ENV" DIGEST_BEFORE "$WANT_DIGEST"
kv_set "$ENV" DIGEST_AFTER  "$NEW_DIGEST"

state_set "$PROJECT" "$TASK_ID" 5 done "$PLANNED edits applied"

hdr "Phase 5 · edit — applied"
awk -F'\t' '!/^#/ {printf "  %s. %-12s %-28s %s lines\n", $1, $3, substr($2,1,28), $5}' "$APPLIED"
printf '\n'
info "backup  $BACKUP"
ok "$PLANNED edit(s) applied to $(basename "$TARGET")"
dim "undo:   ./Scripts/claude-utils/rollback-claude.sh $PROJECT $TASK_ID"
dim "next:   run-task.sh $PROJECT $TASK_ID 6"
