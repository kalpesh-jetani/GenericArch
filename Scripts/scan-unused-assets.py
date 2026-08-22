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
invisible to any static scan. Five failure modes are encoded here deliberately;
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
def symbol(n):
    """Xcode's generated ImageResource name for an asset: separators dropped, first component
    lowercased, the rest capitalised. `radio_checked` -> `radioChecked`. Returns "" when the
    name yields no usable identifier."""
    parts = [p for p in re.split(r"[^A-Za-z0-9]+", n) if p]
    if not parts:
        return ""
    head = parts[0]
    sym = head[:1].lower() + head[1:] + "".join(p[:1].upper() + p[1:] for p in parts[1:])
    return "_" + sym if sym[:1].isdigit() else sym

for n in sorted(names):
    # TRAP 1: refs are written "background_2.png" — a boundary that includes '.' never matches.
    # TRAP 3: names contain spaces ("Doo logo colored") — token-splitting never matches either.
    #         A bounded LITERAL search handles both.
    pats = [re.compile(r'(?<![A-Za-z0-9_])' + re.escape(n) + r'(?![A-Za-z0-9_])')]
    # TRAP 5: Xcode 15+ generates a camelCased ImageResource symbol per asset, and modern call
    #         sites use it — `Image(.radioChecked)`, `Image(on ? .radioChecked : .radioUnchecked)`.
    #         None of those contain the literal "radio_checked". Searching only the literal
    #         reported 11 live assets dead out of 24 on one app: a 46% false-positive rate on what
    #         is, in effect, a deletion proposal. Anchored on the leading dot so a same-named local
    #         variable does not silently absolve an asset.
    sym = symbol(n)
    if sym:
        pats.append(re.compile(r'\.' + re.escape(sym) + r'(?![A-Za-z0-9_])'))
    if not any(p.search(t) for p in pats for t in corpus.values()):
        print("UNREFERENCED\t%s\t%s" % (n, names[n]))
