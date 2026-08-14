#!/usr/bin/env python3
#@kind      tool
#@platform  macos
#@claude    call
#@purpose   Append a memory to .claude/memory/ with frontmatter and index it.
#@usage     python3 Scripts/memory-add.py --type T --name N --description D [body]
#@in        type:project|feedback|reference name:slug description:str body:text
#@out       .claude/memory/<name>.md + an INDEX.md row
#@exit      0=written 2=usage
#@effects   writes .claude/memory/
"""Write one repo memory and its index row, atomically.

    python3 Scripts/memory-add.py --name <slug> --type project|reference|feedback \\
            --description "<one line>" --body "<the fact>"

Doing this by hand means getting the frontmatter right AND remembering the index
row. The second is what gets forgotten, and .claude/memory/INDEX.md is explicit
that "a memory with no row is a memory nobody finds" — so this does both or
neither.

`type: user` is refused: who a developer is, and how they like to work, is
per-person and stays in Claude's machine-local store. Committing it pushes one
developer's preferences onto everyone who clones the repo.
"""
import argparse, os, pathlib, re, sys

TYPES = ("project", "reference", "feedback")
MEM = pathlib.Path(os.environ.get("GA_MEMORY_ROOT", ".")) / ".claude" / "memory"
ROW = re.compile(r"^\| +— +\| +— +\|$", re.M)          # the placeholder row


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--name", required=True, help="short-kebab-case-slug")
    p.add_argument("--type", required=True)
    p.add_argument("--description", required=True, help="one line — scanned for relevance")
    p.add_argument("--body", required=True)
    p.add_argument("--holds", help="index-row summary; defaults to --description")
    a = p.parse_args()

    if a.type == "user":
        sys.exit("refused: `user` memories are per-person and never committed.\n"
                 "They belong in Claude's machine-local store, not in the repo.")
    if a.type not in TYPES:
        sys.exit("--type must be one of: %s" % ", ".join(TYPES))
    if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", a.name):
        sys.exit("--name must be short-kebab-case: got %r" % a.name)

    index = MEM / "INDEX.md"
    if not index.is_file():
        sys.exit("no %s — this repo has not adopted the memory layout." % index)

    target = MEM / (a.name + ".md")
    if target.exists():
        sys.exit("%s already exists — edit it, or pick another name.\n"
                 "Updating beats duplicating: two memories on one fact drift apart." % target)

    body = a.body.strip()
    if a.type in ("feedback", "project") and "**Why:**" not in body:
        body += ("\n\n**Why:** \n**How to apply:** ")

    target.write_text(
        "---\nname: %s\ndescription: %s\nmetadata:\n  type: %s\n---\n\n%s\n"
        % (a.name, a.description, a.type, body))

    holds = (a.holds or a.description).replace("|", "/")
    row = "| `%s.md` | %s |\n" % (a.name, holds)
    text = index.read_text()
    if ROW.search(text):
        text = ROW.sub(row.rstrip("\n"), text, count=1)     # replace the placeholder
    else:
        # Insert after the last REAL table row. Scanning backwards for a line starting
        # with "|" finds the commented-out example instead, which buries the row inside
        # <!-- --> where nothing can see it — so stop at the first comment marker.
        lines = text.rstrip("\n").split("\n")
        limit = next((i for i, l in enumerate(lines) if l.lstrip().startswith("<!--")), len(lines))
        cut = limit
        for i in range(limit - 1, -1, -1):
            if lines[i].startswith("|"):
                cut = i + 1
                break
        lines.insert(cut, row.rstrip("\n"))
        text = "\n".join(lines) + "\n"
    index.write_text(text)

    print("wrote   %s" % target)
    print("indexed %s" % index)
    if a.type in ("feedback", "project") and "**Why:** \n" in target.read_text():
        print("\n⚠ Why/How-to-apply are empty — fill them in, or the memory is a fact "
              "nobody can act on.")


if __name__ == "__main__":
    main()
