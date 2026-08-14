#!/usr/bin/env python3
"""Colour tokens -> NAME<tab>ANY/LIGHT<tab>DARK. Read-only.
   python3 Scripts/scan-colors.py [root]
Colorsets store components as float strings or 0x hex; both normalise to #RRGGBB."""
import json, os, glob, sys
ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
def hexof(c):
    def v(x):
        x = x.strip()
        return int(x, 16) if x.startswith("0x") else (round(float(x)*255) if "." in x else int(x))
    return "#%02X%02X%02X" % (v(c["red"]), v(c["green"]), v(c["blue"])), float(c.get("alpha", "1"))
for p in sorted(glob.glob(ROOT + "/**/*.colorset", recursive=True)):
    j = json.load(open(os.path.join(p, "Contents.json")))
    out = {}
    for e in j.get("colors", []):
        if not e.get("color"): continue
        h, a = hexof(e["color"]["components"])
        lum = next((x.get("value") for x in (e.get("appearances") or []) if x.get("key") == "luminosity"), "any")
        out[lum] = h + ("" if abs(a-1) < 1e-3 else " @%d%%" % round(a*100))
    print("%s\t%s\t%s" % (os.path.basename(p)[:-9], out.get("any") or out.get("light", "-"), out.get("dark", "-")))
