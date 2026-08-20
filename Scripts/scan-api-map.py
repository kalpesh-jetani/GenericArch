#!/usr/bin/env python3
#@kind      tool
#@platform  macos
#@claude    call
#@purpose   Scan sources for endpoints and emit the API-MAP.md inventory rows.
#@usage     python3 Scripts/scan-api-map.py
#@in        none
#@out       stdout:API map rows
#@exit      0=ok
#@effects   read-only
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

# ---- 3b. fallback: many routers, one per feature --------------------------------
# The single-router discovery above assumes what most sample projects do: one enum, one `path`
# switch, one call convention. Real repos also do the opposite — a `*Resources.swift` enum per
# feature, each conforming to a `TargetType`-style protocol, each with its own `path`. On such a repo
# the pass above finds nothing and reports `router: null`, which is honest but useless.
#
# So: when nothing was declared, discover EVERY type that declares a String `path` and read it. No
# call convention is assumed, because there is no single one to assume.
def brace_body(text, open_pos):
    """Text between the brace at/after open_pos and its match. Returns (body, end)."""
    i = text.find("{", open_pos)
    if i < 0: return "", open_pos
    depth = 0
    for j in range(i, len(text)):
        if text[j] == "{": depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0: return text[i + 1:j], j
    return text[i + 1:], len(text)

def literals_by_case(body, cases):
    """Map case -> normalised path literals from a property body, whether it switches or not."""
    out = {}
    if re.search(r'\bswitch\b', body):
        # `case .x, .y: return "…"` and `case .x: "…"` both occur; a branch can hold two literals.
        for m in re.finditer(r'case\s+([^:]+):(.*?)(?=\n\s*(?:case\s|default\s*:|\Z))', body, re.S):
            names = re.findall(r'\.(\w+)', m.group(1))
            lits  = re.findall(r'"([^"]*)"', m.group(2))
            for n in names:
                if lits: out[n] = sorted({re.sub(r'\\\((\w+)\)', r'{\1}', l) for l in lits if l})
    else:
        lits = sorted({re.sub(r'\\\((\w+)\)', r'{\1}', l) for l in re.findall(r'"([^"]*)"', body) if l})
        if lits:
            for c in cases: out[c] = lits
    return out

multi = []
if not paths:
    for p, t in clean.items():
        # Cases and the `path` property are usually in DIFFERENT declarations: `enum X { case … }`
        # and `extension X: TargetType { var path … }`, often the dominant shape in a real app. So
        # this works per FILE and attributes a property to its enclosing `extension X`, falling back
        # to the file's only enum. Scanning enum bodies alone finds nothing here.
        enums = {}
        for em in re.finditer(r'^\s*(?:public\s+|internal\s+|private\s+)?enum\s+(\w+)', t, re.M):
            body, _ = brace_body(t, em.start())
            cases = []
            for cm in re.finditer(r'^\s*case\s+([^\n]+)', body, re.M):
                for c in re.findall(r'\b([a-z]\w*)\b', cm.group(1).split("(")[0]):
                    if c not in cases: cases.append(c)
            if cases: enums[em.group(1)] = cases
        if not enums: continue

        def owner_type(pos):
            """The type a property at `pos` belongs to: nearest preceding `extension X`, else the
            file's only enum. Guessing when a file holds several is how rows get attached to the
            wrong endpoint, so that case is skipped rather than approximated."""
            ext = None
            for xm in re.finditer(r'^\s*extension\s+(\w+)', t, re.M):
                if xm.start() < pos and xm.group(1) in enums: ext = xm.group(1)
            if ext: return ext
            return next(iter(enums)) if len(enums) == 1 else None

        for pm2 in re.finditer(r'var\s+path\s*:\s*String', t):
            who = owner_type(pm2.start())
            if not who: continue
            pbody, _ = brace_body(t, pm2.end())
            pl = literals_by_case(pbody, enums[who])
            if not pl: continue
            ml = {}
            for mm in re.finditer(r'var\s+method\s*:\s*\w+', t):
                if owner_type(mm.start()) != who: continue
                mbody, _ = brace_body(t, mm.end())
                if re.search(r'\bswitch\b', mbody):
                    for m in re.finditer(r'case\s+([^:]+):(.*?)(?=\n\s*(?:case\s|default\s*:|\Z))', mbody, re.S):
                        vm = re.search(r'\.(\w+)', m.group(2))
                        if vm:
                            for n in re.findall(r'\.(\w+)', m.group(1)): ml[n] = vm.group(1).upper()
                else:
                    vm = re.search(r'\.(\w+)', mbody)
                    if vm:
                        for c in enums[who]: ml[c] = vm.group(1).upper()
            for c in enums[who]:
                if c in pl:
                    multi.append(dict(router=os.path.relpath(p, SRC), enum=who, case=c,
                                      paths=pl[c], method=ml.get(c, "?")))

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

# The multi-router pass produces endpoints without callers: no call convention was assumed, so the
# screen pairing is not proven and must not be implied. They are reported separately, and
# `pairing: "unproven"` is what stops a consumer rendering them as if a screen were known.
if multi and not rows:
    # A file that declares a `path` and yielded nothing is the honest gap: a shape this pass still
    # does not read. Naming those files is what lets the next fix be targeted instead of speculative,
    # and stops 90 rows reading as "all of them".
    covered = {m["router"] for m in multi}
    # `var path: String { get }` is a PROTOCOL requirement, not a router — counting it as an
    # unparsed router reports a gap that does not exist.
    def declares_router(t):
        for m in re.finditer(r'var\s+path\s*:\s*String\s*\{', t):
            if not re.match(r'\s*get\b', t[m.end():m.end() + 12]): return True
        return False
    declares = {os.path.relpath(p, SRC) for p, t in clean.items() if declares_router(t)}
    result = dict(source=SRC, router="multiple", enum="per-feature",
                  path_property="path", l10n_keys=len(L10N),
                  declared=len(multi), called=0, pairing="unproven",
                  routers=sorted(covered),
                  unparsed=sorted(declares - covered),
                  never_called=[], rows=multi)
else:
    result = dict(source=SRC, router=os.path.relpath(router, SRC) if router else None,
                  enum=enum_name, path_property=prop, l10n_keys=len(L10N),
                  declared=len(paths), called=len(rows), pairing="proven",
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
