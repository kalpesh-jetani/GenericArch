#!/usr/bin/env python3
"""Stage machine for the guided feature workflow. Read-mostly: the only file it
writes is its own state file under .claude/workflow/.

    python3 Scripts/feature-workflow.py start "<task>"
    python3 Scripts/feature-workflow.py status
    python3 Scripts/feature-workflow.py record --note "<what was gathered>"
    python3 Scripts/feature-workflow.py skip   --reason "<why>"
    python3 Scripts/feature-workflow.py advance --approve | --improve | --auto

The stages live here rather than in the skill so the skill body stays near one
screen (docs/STRUCTURE.md) — a skill's body loads every time it fires, this file
only when it is run.

Each stage names the TOOLS to use. That is the part that makes the workflow
followable: knowing the stage is not the same as knowing how to do it.
"""
import argparse, os, re, sys, datetime, pathlib

STAGES = [
    dict(key="input", title="User Input",
         gather="The request in the user's own words, verbatim. Do not paraphrase into a "
                "solution — that is the next stage.",
         tools=["AskUserQuestion — only if the request is genuinely ambiguous (CLAUDE.md §2.14)"],
         skippable=False),
    dict(key="requirements", title="Requirements",
         gather="What success looks like, concretely. Plus the CLAUDE.md §0 answers this feature "
                "needs: presentation pattern, persistence, caching/offline.",
         tools=["grep -i <feature> docs/DECISIONS.md   # may already be answered — do not re-ask",
                "AskUserQuestion — one message, with a recommendation per question"],
         skippable=False),
    dict(key="resources", title="Resources",
         gather="The Figma frame, screenshot, sample repo, or docs URL. Which existing screen it "
                "should resemble. See the table in .claude/commands/learn.md §1 — it lists what to "
                "ask for per kind of work.",
         tools=["AskUserQuestion — include Skip; a resource that does not exist is a valid answer",
                "Read — for an image or a local sample",
                "WebFetch — for a docs URL"],
         skippable=True),
    dict(key="approaches", title="Plan Approaches",
         gather="Two or three approaches with a recommendation and one clause of reasoning each. "
                "Check what already exists before proposing new code.",
         tools=["./Scripts/find.sh <thing>            # is there already a screen/route/token?",
                "grep -h <term> .claude/notes/*.md     # the index, not the codebase",
                "Read — only the files find.sh pointed at"],
         skippable=False),
    dict(key="suggest", title="Suggest to user",
         gather="The action list, as bullets. One action per line, each starting with a verb, in "
                "the order they will happen. If a bullet needs a sub-clause to be understood, it "
                "is two actions.",
         tools=["— you write this; no tool"],
         skippable=False),
    dict(key="decision", title="Decision",
         gather="Approve · Improve · Auto.",
         tools=['AskUserQuestion with exactly: "Approve", "Improve", '
                '"Auto — skip the rest and continue on recommendations"'],
         skippable=False),
]
KEYS = [s["key"] for s in STAGES]
ROOT = pathlib.Path(os.environ.get("GA_WORKFLOW_ROOT", ".")) / ".claude" / "workflow"


def slug(text):
    s = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return (s or "task")[:60]


def today():
    return datetime.date.today().isoformat()


def state_files():
    return sorted(ROOT.glob("*.md")) if ROOT.is_dir() else []


def load(path):
    """Parse the state file. It is markdown so a human can read it; the machine
    only needs the Stage/Status rows, so parsing stays deliberately shallow."""
    text = path.read_text()
    done = {}
    for m in re.finditer(r"^\| `(\w+)` \| (\S+) \| (.*?) \|$", text, re.M):
        done[m.group(1)] = (m.group(2), m.group(3).strip())
    return text, done


def current(done):
    for k in KEYS:
        if k not in done:
            return k
    return None


def stage(key):
    return next(s for s in STAGES if s["key"] == key)


def render_stage(key, n_done):
    s = stage(key)
    i = KEYS.index(key) + 1
    out = ["", "── Stage %d/%d · %s" % (i, len(STAGES), s["title"]), ""]
    out.append("  Gather")
    for line in _wrap(s["gather"]):
        out.append("    " + line)
    out.append("")
    out.append("  Tools")
    for t in s["tools"]:
        out.append("    " + t)
    if s["skippable"]:
        out.append("")
        out.append("  Skippable — `skip --reason \"…\"` records why, which is the point.")
    out.append("")
    out.append("  Next: record --note \"…\"  (or skip --reason \"…\") completes this stage,")
    out.append("        then advance --approve|--improve|--auto to gate and show the next.")
    return "\n".join(out)


def _wrap(text, width=84):
    words, line, out = text.split(), "", []
    for w in words:
        if len(line) + len(w) + 1 > width:
            out.append(line); line = w
        else:
            line = (line + " " + w).strip()
    if line:
        out.append(line)
    return out


def cmd_start(args):
    task = " ".join(args.task).strip()
    if not task:
        sys.exit("give the task a name: start \"add a settings screen\"")
    ROOT.mkdir(parents=True, exist_ok=True)
    path = ROOT / (slug(task) + ".md")
    if path.exists():
        sys.exit("already started: %s\nrun `status`, or delete it to restart." % path)
    path.write_text(
        "# Workflow — %s\n\n"
        "- **Started:** %s\n"
        "- **Delete this file when the feature ships.** It is a working record, not an inventory.\n\n"
        "| Stage | Status | Note |\n|---|---|---|\n" % (task, today()))
    print("started: %s" % path)
    print(render_stage(KEYS[0], 0))


def _active():
    files = state_files()
    if not files:
        sys.exit("no workflow in progress — run `start \"<task>\"` first.")
    if len(files) > 1:
        sys.exit("more than one workflow open:\n  " + "\n  ".join(str(f) for f in files) +
                 "\nFinish or delete one; parallel workflows hide which decision belongs to which.")
    return files[0]


def cmd_status(args):
    path = _active()
    text, done = load(path)
    key = current(done)
    print("workflow: %s" % path)
    if done:
        print("\n  done so far")
        for k, (st, note) in done.items():
            print("    %-14s %-8s %s" % (k, st, note[:60]))
    if key is None:
        print("\n  All stages complete. Delete %s when the feature ships." % path)
        return
    print(render_stage(key, len(done)))


def _append(path, key, status, note):
    text = path.read_text().rstrip("\n")
    note = (note or "—").replace("|", "/").replace("\n", " ")
    path.write_text(text + "\n| `%s` | %s | %s |\n" % (key, status, note))


def cmd_record(args):
    path = _active()
    _, done = load(path)
    key = current(done)
    if key is None:
        sys.exit("every stage is already recorded.")
    _append(path, key, "recorded", args.note)
    print("recorded %s. Now: advance --approve|--improve|--auto" % key)


def cmd_skip(args):
    path = _active()
    _, done = load(path)
    key = current(done)
    if key is None:
        sys.exit("every stage is already recorded.")
    if not stage(key)["skippable"]:
        sys.exit("stage `%s` is not skippable — it is what makes the rest correct." % key)
    _append(path, key, "SKIPPED", args.reason)
    print("skipped %s: %s" % (key, args.reason))
    nxt = current(load(path)[1])
    print(render_stage(nxt, 0) if nxt else "\n  All stages complete.")


def cmd_advance(args):
    """`record` and `skip` are what complete a stage; advance only gates and displays.
    It must NOT append a row of its own — doing so consumed the *next* stage, because
    current() already points past the one just recorded."""
    path = _active()
    _, done = load(path)
    key = current(done)

    if args.auto:
        # Record the remainder as defaulted, so the file always distinguishes a
        # decision the user made from one taken on their behalf.
        _, done = load(path)
        for k in KEYS:
            if k not in done:
                _append(path, k, "AUTO", "skipped — proceeding on recommendation")
        print("auto: remaining stages recorded as AUTO in %s" % path)
        print("Say so in your next message — the user chose not to review these.")
        return

    if args.improve:
        print("improve: revise the last stage's output, re-run `record`, then advance again.")
        return

    if key is None:
        print("approved. All stages complete — delete %s when the feature ships." % path)
    else:
        print("approved.")
        print(render_stage(key, len(done)))


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("start");   s.add_argument("task", nargs="+"); s.set_defaults(fn=cmd_start)
    s = sub.add_parser("status");  s.set_defaults(fn=cmd_status)
    s = sub.add_parser("record");  s.add_argument("--note", required=True); s.set_defaults(fn=cmd_record)
    s = sub.add_parser("skip");    s.add_argument("--reason", required=True); s.set_defaults(fn=cmd_skip)
    s = sub.add_parser("advance")
    g = s.add_mutually_exclusive_group(required=True)
    g.add_argument("--approve", action="store_true")
    g.add_argument("--improve", action="store_true")
    g.add_argument("--auto", action="store_true")
    s.set_defaults(fn=cmd_advance)
    a = p.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
