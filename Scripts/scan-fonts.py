#!/usr/bin/env python3
#@kind      tool
#@platform  macos
#@claude    call
#@purpose   Scan for font files and registration; emit inventory rows.
#@usage     python3 Scripts/scan-fonts.py
#@in        none
#@out       stdout:font rows; stderr:one line per file skipped as unparseable
#@exit      0=ok
#@effects   read-only
"""PostScript + family names read from each font's `name` table. Read-only.
   python3 Scripts/scan-fonts.py [root]
Never infer these from the filename - a mismatch fails silently at runtime."""
import glob, struct, sys
ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
skipped = []
for p in sorted(glob.glob(ROOT + "/**/*.ttf", recursive=True) + glob.glob(ROOT + "/**/*.otf", recursive=True)):
    # A font extension is not a promise of a parseable sfnt. Git-LFS pointers, placeholder
    # stubs and truncated binaries all carry one, and any of them used to abort the run and
    # cost the whole FONTS inventory. Name the file and keep going instead.
    try:
        d = open(p, "rb").read()
        off = next(struct.unpack(">I", d[12+i*16+8:12+i*16+12])[0]
                   for i in range(struct.unpack(">H", d[4:6])[0])
                   if d[12+i*16:12+i*16+4] == b"name")
        cnt, so = struct.unpack(">HH", d[off+2:off+6])
    except (struct.error, StopIteration, IndexError, OSError):
        skipped.append(p)
        continue
    fam = ps = None
    for i in range(cnt):
        try:
            pid, eid, lid, nid, ln, no = struct.unpack(">HHHHHH", d[off+6+i*12: off+18+i*12])
        except struct.error:
            break
        s = d[off+so+no: off+so+no+ln]
        try: txt = s.decode("utf-16-be") if pid == 3 else s.decode("latin1")
        except Exception: continue
        if nid == 1 and not fam: fam = txt
        if nid == 6 and not ps:  ps  = txt
    print("%s\tfamily=%s\tpostscript=%s" % (p.split("/")[-1], fam, ps))
for q in skipped:
    sys.stderr.write("skipped, not a parseable font: %s\n" % q)
