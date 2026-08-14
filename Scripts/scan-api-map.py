#!/usr/bin/env python3
"""
Scan an app's API surface and join it to the screens that call it.

Read-only. Emits JSON on stdout for /sync-app-notes to render into
.claude/notes/API-MAP.md.

    python3 Scripts/scan-api-map.py <source-root> [Localizable.strings]

Discovers the router enum from the call sites rather than by name, because the
enum a project actually uses is not always the one named "APIRouter" — a repo
can carry a legacy router that still compiles and is never called.
"""
import os, re, sys, json, collections

SRC     = sys.argv[1]
STRINGS = sys.argv[2] if len(sys.argv) > 2 else None

# The call convention. Override per project if the API entry point differs.
CALL_FN = r'callAPI'

def walk(src):
    for dp, dn, fn in os.walk(src):
        if "Pods" in dp or "/build/" in dp or ".xcassets" in dp: continue
        for f in fn:
            if f.endswith(".swift"): yield os.path.join(dp, f)

def strip_comments(t):
    t = re.sub(r'/\*.*?\*/', '', t, flags=re.S)
    return "\n".join("" if l.lstrip().startswith("//") else l for l in t.splitlines())

files = {p: open(p, encoding="utf-8", errors="ignore").read() for p in walk(SRC)}
clean = {p: strip_comments(t) for p, t in files.items()}

# ---- 1. call sites -------------------------------------------------------------
# Scan a window from `callAPI(` so a call spanning lines still yields its method.
sites = collections.defaultdict(list)
for p, t in clean.items():
    for m in re.finditer(CALL_FN + r'\(\s*path:\s*\.(\w+)', t):
        win  = t[m.start(): m.start() + 400]
        meth = re.search(r'method:\s*\.(\w+)', win)
        line = t.count("\n", 0, m.start()) + 1
        sites[m.group(1)].append((p, (meth.group(1) if meth else "?").upper(), line))

# ---- 2. the enum that declares those cases, and its path property ---------------
router = None; best = 0
for p, t in clean.items():
    hits = sum(1 for c in sites if re.search(r'^\s*case\s+' + c + r'\b', t, re.M))
    if hits > best: best, router = hits, p
rt = clean.get(router, "")
enum_name = "?"; bestn = 0
starts = [(m.start(), m.group(1)) for m in re.finditer(r'^enum\s+(\w+)', rt, re.M)]
for i, (pos, name) in enumerate(starts):
    end  = starts[i + 1][0] if i + 1 < len(starts) else len(rt)
    body = rt[pos:end]
    n = sum(1 for c in sites if re.search(r'^\s*case\s+' + c + r'\b', body, re.M))
    if n > bestn: bestn, enum_name = n, name
pm = re.search(r'var\s+(\w*[Pp]ath)\s*:\s*String', rt)
prop = pm.group(1) if pm else "path"

# ---- 3. case -> path literal(s), interpolation normalised to {param} ------------
bm = re.search(r'var\s+' + prop + r'\s*:\s*String\s*\{(.*?)\n    \}\s*\n', rt, re.S)
paths = {}
for chunk in re.split(r'\n\s*case\s+', bm.group(1) if bm else "")[1:]:
    head, _, rest = chunk.partition(":")
    names = [c for c in re.findall(r'[A-Za-z_]\w*', head.split("(")[0])]
    lits  = [l for l in re.findall(r'return\s+"([^"]*)"', rest) if l]
    if not (names and lits): continue
    paths[names[0]] = sorted({re.sub(r'\\\((\w+)\)', r'{\1}', l) for l in lits})

# ---- 4. caller identity + screen title -----------------------------------------
L10N = {}
if STRINGS and os.path.exists(STRINGS):
    for line in open(STRINGS, encoding="utf-8", errors="ignore"):
        m = re.match(r'\s*"([^"]+)"\s*=\s*"([^"]*)"\s*;', line)
        if m: L10N[m.group(1)] = m.group(2)

TITLES = ((re.compile(r'title\s*=\s*localizeFor\(\s*"([^"]+)"'), True),
          (re.compile(r'setNavigationTitle\(\s*(?:title:\s*)?(?:localizeFor\(\s*)?"([^"]+)"'), True),
          (re.compile(r'title\s*=\s*"([^"]+)"'), False))
def title_of(t):
    for rx, localized in TITLES:
        m = rx.search(t)
        if m: return L10N.get(m.group(1), m.group(1)) if localized else m.group(1)
    return None

BASES = (r'UIViewController|BaseViewController|KeyboardNotifBaseViewController|'
         r'BaseNavigationCustomViewController|CardBaseViewController|CardGenericViewController')
def owner(t, p):
    m = re.search(r'class\s+(\w+)\s*:\s*[\w, ]*(?:' + BASES + r')\b', t)
    if m: return m.group(1), "UIKit"
    m = re.search(r'class\s+(\w*ViewModel)\b', t)
    if m: return m.group(1), "ViewModel"
    m = re.search(r'struct\s+(\w+)\s*(?:<[^>]*>)?\s*:\s*View\b', t)   # generics included
    if m: return m.group(1), "SwiftUI"
    return os.path.basename(p)[:-6], "other"

# A ViewModel rarely sets a title; its screen does. Join VM -> the controller
# or SwiftUI view that owns it, so every row can name a screen.
vm_candidates = collections.defaultdict(list)
for p, t in clean.items():
    n, k = owner(t, p)
    if k not in ("UIKit", "SwiftUI"): continue
    for vm in set(re.findall(r'\b(\w+ViewModel)\b', t)):
        vm_candidates[vm].append((n, k, p, title_of(t)))

def pick_owner(vm, vm_file):
    """Prefer the screen in the ViewModel's own folder, then a name-prefix match,
    then anything that references it. Several screens can mention one VM, and the
    first match is wrong as often as not."""
    cands = vm_candidates.get(vm, [])
    if not cands: return None
    stem = vm[:-len("ViewModel")]
    same_dir = [c for c in cands if os.path.dirname(c[2]) == os.path.dirname(vm_file)]
    prefixed = [c for c in cands if c[0].startswith(stem)]
    n, k, p, ti = (same_dir or prefixed or cands)[0]
    return n, k, os.path.relpath(p, SRC), ti

def screen_for(name, kind, t, p):
    """Return (screen name, screen kind, screen file, title) for a caller."""
    if kind == "ViewModel":
        hit = pick_owner(name, p)
        if hit: return hit
    return name, kind, os.path.relpath(p, SRC), title_of(t)

rows = []
for case in sorted(sites):
    callers = []
    for p, meth, ln in sorted(set(sites[case])):
        n, k = owner(clean[p], p)
        sn, sk, sf, st = screen_for(n, k, clean[p], p)
        callers.append(dict(name=n, kind=k, file=os.path.relpath(p, SRC), line=ln,
                            method=meth, screen=sn, screen_kind=sk,
                            screen_file=sf, title=st))
    rows.append(dict(case=case, paths=paths.get(case), callers=callers))

result = dict(source=SRC, router=os.path.relpath(router, SRC) if router else None,
              enum=enum_name, path_property=prop, l10n_keys=len(L10N),
              declared=len(paths), called=len(rows),
              never_called=sorted(set(paths) - set(sites)), rows=rows)

if "--markdown" not in sys.argv:
    json.dump(result, sys.stdout, indent=1); sys.exit(0)

# ---- 5. render the table body /sync-app-notes drops into API-MAP.md ------------
def cell(x): return x if x else "—"
groups = collections.defaultdict(list)
for r in result["rows"]:
    top = (r["paths"][0].split("/")[0] + "/" + r["paths"][0].split("/")[1]
           if r["paths"] and r["paths"][0].count("/") >= 1 else "(unresolved)")
    groups[top].append(r)

for g in sorted(groups):
    print("### `%s…`  — %d endpoints\n" % (g, len(groups[g])))
    print("| Method | Path | Screen | Controller / caller | File |")
    print("|---|---|---|---|---|")
    for r in sorted(groups[g], key=lambda x: (x["paths"] or [""])[0]):
        c = r["callers"][0]
        extra = "" if len(r["callers"]) == 1 else " +%d" % (len(r["callers"]) - 1)
        for pth in (r["paths"] or ["**unresolved**"]):
            # Dense row: no link syntax, no repeated basename — the header declares the root
            # and whoever reports the row renders the link (see /sync-app-notes S3).
            print("| %s | `%s` | %s | %s | %s |" % (
                c["method"], pth, cell(c["title"]), c["screen"] + extra,
                os.path.dirname(c["file"]) + "/"))
    print()
