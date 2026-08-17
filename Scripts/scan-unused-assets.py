#!/usr/bin/env python3
#@kind      tool
#@platform  macos
#@claude    call
#@purpose   Report asset-catalog entries no source file references.
#@usage     python3 Scripts/scan-unused-assets.py
#@in        none
#@out       stdout:unused asset list
#@exit      0=ok
#@effects   read-only
#@when      unused assets|assets nobody references|dead images
"""Imagesets with no reference anywhere. Read-only.
   python3 Scripts/scan-unused-assets.py [root]
Output is a list of CANDIDATES, never a verdict - runtime-composed names are
invisible to any static scan. Four failure modes are encoded here deliberately;
before changing the matching, read docs/SCAN-TRAPS.md."""
import os, re, glob, collections, sys
ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
names = {os.path.basename(p)[:-9]: p for p in glob.glob(ROOT + "/**/*.imageset", recursive=True)}
corpus = {}
for dp, dn, fn in os.walk(ROOT):
    # TRAP 2: the catalog's own Contents.json contains the asset's name — including
    # .xcassets makes every asset look referenced by itself.
    if "Pods" in dp or "/build/" in dp or ".xcassets" in dp: continue
    for f in fn:
        if f.endswith((".swift", ".storyboard", ".xib", ".m", ".h", ".plist", ".strings", ".json")):
            p = os.path.join(dp, f)
            corpus[p] = open(p, encoding="utf-8", errors="ignore").read()
for n in sorted(names):
    # TRAP 1: refs are written "background_2.png" — a boundary that includes '.' never matches.
    # TRAP 3: names contain spaces ("Doo logo colored") — token-splitting never matches either.
    #         A bounded LITERAL search handles both.
    pat = re.compile(r'(?<![A-Za-z0-9_])' + re.escape(n) + r'(?![A-Za-z0-9_])')
    if not any(pat.search(t) for t in corpus.values()):
        print("UNREFERENCED\t%s\t%s" % (n, names[n]))
