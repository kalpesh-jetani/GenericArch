#!/usr/bin/env python3
#@kind      tool
#@platform  macos
#@claude    call
#@purpose   Verify every path referenced by a note exists on disk.
#@usage     python3 Scripts/check-note-links.py
#@in        none
#@out       stdout:checked N paths, M missing
#@exit      0=all exist 1=missing paths
#@effects   read-only
#@when      do note links resolve|broken link in a note|missing path in notes
"""Every path in .claude/notes/ resolves. Read-only; exits non-zero on a miss.
   python3 Scripts/check-note-links.py
Skips fenced code and HTML comments: an illustrative path in an example is not a
broken link, and flagging it trains you to ignore the checker."""
import re, os, glob
def prose(t):
    t = re.sub(r'```.*?```', '', t, flags=re.S)
    return re.sub(r'<!--.*?-->', '', t, flags=re.S)
bad = tot = 0
for f in sorted(glob.glob(".claude/notes/*.md")):
    base = os.path.dirname(f)          # links are relative to the NOTE, not to cwd
    t = prose(open(f).read())
    for pat in (r'\[[^\]]+\]\(([^)#]+?)(?::\d+)?\)', r'click \w+ "([^"]+)"'):
        for m in re.finditer(pat, t):
            p = m.group(1)
            if p.startswith(("http", "mailto")): continue
            tot += 1
            if not (os.path.exists(os.path.join(base, p)) or os.path.exists(p)):
                bad += 1; print("MISSING  %-22s -> %s" % (os.path.basename(f), p))
print("checked %d paths, %d missing" % (tot, bad))
# The #@exit header and this file's own docstring both promise non-zero on a miss. Without this
# the promise was cosmetic: a CI job or a caller branching on $? passed while notes pointed at
# files that no longer existed.
raise SystemExit(1 if bad else 0)
