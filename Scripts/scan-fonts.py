#!/usr/bin/env python3
"""PostScript + family names read from each font's `name` table. Read-only.
   python3 Scripts/scan-fonts.py [root]
Never infer these from the filename - a mismatch fails silently at runtime."""
import glob, struct, sys
ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
for p in sorted(glob.glob(ROOT + "/**/*.ttf", recursive=True) + glob.glob(ROOT + "/**/*.otf", recursive=True)):
    d = open(p, "rb").read()
    off = next(struct.unpack(">I", d[12+i*16+8:12+i*16+12])[0]
               for i in range(struct.unpack(">H", d[4:6])[0])
               if d[12+i*16:12+i*16+4] == b"name")
    cnt, so = struct.unpack(">HH", d[off+2:off+6])
    fam = ps = None
    for i in range(cnt):
        pid, eid, lid, nid, ln, no = struct.unpack(">HHHHHH", d[off+6+i*12: off+18+i*12])
        s = d[off+so+no: off+so+no+ln]
        try: txt = s.decode("utf-16-be") if pid == 3 else s.decode("latin1")
        except Exception: continue
        if nid == 1 and not fam: fam = txt
        if nid == 6 and not ps:  ps  = txt
    print("%s\tfamily=%s\tpostscript=%s" % (p.split("/")[-1], fam, ps))
