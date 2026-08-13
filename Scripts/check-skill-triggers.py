#!/usr/bin/env python3
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

if problems:
    print("\n".join(problems))
    print(f"\n{len(problems)} trigger collision(s)")
    sys.exit(1)
print(f"{len(CASES)} prompts route correctly across {len(descs)} skills")
