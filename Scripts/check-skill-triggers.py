#!/usr/bin/env python3
#@kind      tool
#@platform  macos
#@claude    call
#@purpose   Route a corpus of prompts against skill descriptions to catch trigger-vocabulary collisions.
#@usage     python3 Scripts/check-skill-triggers.py
#@in        none
#@out       stdout:N prompts route correctly across M skills
#@exit      0=all route correctly 1=a mis-route
#@effects   read-only. Run after ANY skill description edit
"""Detects trigger collisions between skill descriptions.

Descriptions are always-on context and are what makes a skill fire. Two skills matching the same
phrasing means neither fires predictably — and nothing else in the repo catches that. Run after
editing any skill description.
"""
import re, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
descs = {}
for p in sorted((ROOT / ".claude/skills").glob("*/SKILL.md")):
    m = re.search(r"^description: (.+)$", p.read_text(), re.M)
    if m:
        descs[p.parent.name] = m.group(1).lower()

# prompt -> the skill that should win. "AMBIGUOUS" means a tie is acceptable.
CASES = [
    ("create a new settings screen", "new-feature"),
    ("scaffold FeatureProfile", "new-feature"),
    # These belong to patterns in docs/patterns/ that are not promoted. Until they are,
    # no skill should claim them — a survivor absorbing them is the mis-fire to prevent.
    ("this button looks wrong in dark mode", None),
    ("I added a new color token", None),
    ("check the contrast on this card", None),
    ("add Arabic support", None),
    ("does this mirror correctly", None),
    # "screen" legitimately belongs to new-feature; with rtl-support unpromoted, the designed
    # outcome is that it fires and redirects to docs/patterns/rtl-support.md.
    ("audit this screen for right to left", "new-feature"),
    ("ship NetworkKit 2.1", None),
    ("bump ImageCache after the cache fix", None),
    # sync-app-notes is a COMMAND, not a skill — nothing should fire on this phrasing.
    ("refresh the inventory notes", None),
    ("review my diff before I push", None),   # /review is a command
    # The everyday cases — these are what a developer actually types.
    ("fix this crash on the profile screen", "debug"),
    ("why is the screen blank", "debug"),
    ("this string shows as the raw key", "debug"),
    ("the custom font renders as system font", "debug"),
    ("push works in dev but is silent in testflight", "debug"),
    ("add an email field to the signup request", None),
    ("add an error case for rate limiting", None),
    ("support one more parameter on that endpoint", None),
    ("round the corners on this button", None),
    ("tighten the spacing between rows", None),
        ("mark this complete", None),
    ("wrap up the auth work", None),
    # Pin what the description trim changed. The first two prove a kept trigger phrase still
    # fires; the rest prove a REMOVED word no longer over-claims — "layout", "protocol", "mock"
    # and "ContentState case" were all in new-feature's description and pulled unrelated work in.
    ("start the settings module", "new-feature"),
    ("it crashed on launch", "debug"),
    ("fix the layout on this card", None),
    ("add a protocol and a mock for this service", None),
    ("handle one more content state here", None),
    # tool-profile: capturing what an external platform exposes. No vendor is named — a fixture
    # naming one asserts the project uses it, and pins phrasing nobody types once it does not.
    ("i just connected this ticket tracker", "tool-profile"),
    ("first time using this connector", "tool-profile"),
    ("do we have a profile for this tool yet", "tool-profile"),
    ("this connector is not configured, here is the reference", "tool-profile"),
    # /learn's territory: what we take from a vendor, not how to drive a platform.
    ("note what we take from this vendor and what we reject", None),
]

# Stopwords carry no trigger signal. Counting them produced false collisions — the metric was
# wrong, not the descriptions.
STOP = {
    "this", "that", "with", "from", "when", "what", "does", "have", "been", "will", "your",
    "they", "then", "than", "also", "only", "into", "some", "more", "most", "such", "very",
    "just", "like", "over", "under", "after", "before", "correctly", "should", "would",
    "there", "here", "make", "made", "need", "want", "please", "help",
    "the", "and", "for", "not", "but", "you", "its", "one", "two", "our", "any", "can",
}

def _terms(text: str) -> set:
    return {w for w in re.findall(r"[a-z]+", text.lower()) if len(w) > 2 and w not in STOP}


WEAK = {"new", "wrong", "fix", "add", "more", "other", "work", "works", "case", "support"}


def _weak_alone(prompt: str, desc: str) -> bool:
    """True when the only thing matched was a generic word."""
    matched = [w for w in _terms(prompt) if re.search(rf"\b{re.escape(w)}", desc)]
    return len(matched) == 1 and matched[0] in WEAK


def score(prompt: str, desc: str, descs: dict) -> float:
    """Weight each matched term by how few descriptions contain it.

    Counting every word equally made 'screen' (in two descriptions) worth as much as 'crash'
    (in one), so 'fix this crash on the profile screen' tied. A term shared by many skills
    carries little signal about which one to pick; a term unique to one carries most of it.
    """
    total = 0.0
    for w in _terms(prompt):
        if not re.search(rf"\b{re.escape(w)}", desc):
            continue                        # this description does not claim the term
        holders = sum(1 for d in descs.values() if re.search(rf"\b{re.escape(w)}", d))
        total += 1.0 / holders              # unique term = 1.0, shared by three = 0.33
    return round(total, 3)

problems = []
for prompt, expected in CASES:
    s = {k: score(prompt, d, descs) for k, d in descs.items()}
    top = max(s.values()) if s else 0
    # A single shared word is not a trigger. Require a real match — one uniquely-owned term
    # (1.0) or several shared ones — before treating a skill as firing at all.
    FIRE = 1.0
    winners = [k for k, v in s.items() if v >= FIRE and top - v < 0.15]
    # A lone generic word is coincidence, not a trigger: "I added a NEW color token" is not a
    # scaffolding request, and "after the cache FIX" is not a bug report. Such a word counts only
    # alongside a specific one.
    winners = [k for k in winners if not _weak_alone(prompt, descs[k])]
    if expected is None:
        # Must match no skill — it is a user-typed command.
        if winners:
            problems.append(f"LEAKED {prompt!r} → {winners} (should match no skill)")
        continue
    if len(winners) > 1 and expected != "AMBIGUOUS":
        problems.append(f"TIE  {prompt!r} → {winners} (want {expected})")
    elif winners and winners[0] != expected and expected != "AMBIGUOUS":
        problems.append(f"WRONG {prompt!r} → {winners[0]} (want {expected})")

# ── The OpenSpec boundary ──────────────────────────────────────────────────
# A product that installs OpenSpec gets a dozen openspec-* skills in .claude/skills/, so they enter
# `descs` above on their own and compete with ours for the same phrasing (docs/OPENSPEC.md).
#
# Asserting WHICH of theirs should win would pin wording we do not control and cannot predict, and
# it would go stale on their next release. So assert only the two things that are actually ours to
# keep true, in both directions. Both hold whether or not OpenSpec is installed here: with none
# present the winner lists are empty and every assertion passes trivially.
HOUSE = {"debug", "new-feature", "tool-profile"}

# Spec-workflow language. None of ours may claim it — a scaffolding skill that fires on "propose a
# change" produces a package nobody asked for and skips the spec that was the point.
SPEC_WORKFLOW = [
    "propose a change for magic-link login",
    "archive the completed change",
    "apply the tasks from the plan",
    "write the delta spec for this capability",
    "verify the change against its spec",
    "explore options before we commit to a plan",
]

# Our language. None of theirs may claim it — these are Swift package and debugging jobs, and no
# amount of spec workflow does them.
HOUSE_WORK = [
    "create a new settings screen",
    "scaffold FeatureProfile",
    "fix this crash on the profile screen",
    "why is the screen blank",
]


def _winners(prompt: str) -> list:
    s = {k: score(prompt, d, descs) for k, d in descs.items()}
    top = max(s.values()) if s else 0
    w = [k for k, v in s.items() if v >= 1.0 and top - v < 0.15]
    return [k for k in w if not _weak_alone(prompt, descs[k])]


for prompt in SPEC_WORKFLOW:
    stolen = [k for k in _winners(prompt) if k in HOUSE]
    if stolen:
        problems.append(f"STOLEN {prompt!r} → {stolen} (a house skill claimed spec-workflow language)")

for prompt in HOUSE_WORK:
    stolen = [k for k in _winners(prompt) if k.startswith("openspec-")]
    if stolen:
        problems.append(f"STOLEN {prompt!r} → {stolen} (an OpenSpec skill claimed house work)")

if problems:
    print("\n".join(problems))
    print(f"\n{len(problems)} trigger collision(s)")
    sys.exit(1)
_total = len(CASES) + len(SPEC_WORKFLOW) + len(HOUSE_WORK)
_os_n = sum(1 for k in descs if k.startswith("openspec-"))
_os_note = f", {_os_n} of them OpenSpec's" if _os_n else " (OpenSpec not installed here)"
print(f"{_total} prompts route correctly across {len(descs)} skills{_os_note}")
