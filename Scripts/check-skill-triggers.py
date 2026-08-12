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
    ("add a settings screen", "new-feature"),
    ("scaffold FeatureProfile", "new-feature"),
    ("this button looks wrong in dark mode", "dark-light-mode"),
    ("I added a new color token", "dark-light-mode"),
    ("check the contrast on this card", "dark-light-mode"),
    ("add Arabic support", "rtl-support"),
    ("does this mirror correctly", "rtl-support"),
    ("audit this screen for right to left", "rtl-support"),
    ("ship NetworkKit 2.1", "release-bump"),
    ("bump ImageCache after the cache fix", "release-bump"),
    # sync-app-notes is a COMMAND, not a skill — nothing should fire on this phrasing.
    ("refresh the inventory notes", None),
    ("round the corners on this button", "style-guide"),
    ("tighten the spacing between rows", "style-guide"),
    ("add a destructive variant", "style-guide"),
]

# Stopwords carry no trigger signal. Counting them produced false collisions — the metric was
# wrong, not the descriptions.
STOP = {
    "this", "that", "with", "from", "when", "what", "does", "have", "been", "will", "your",
    "they", "then", "than", "also", "only", "into", "some", "more", "most", "such", "very",
    "just", "like", "over", "under", "after", "before", "correctly", "should", "would",
    "there", "here", "make", "made", "need", "want", "please", "help",
}

def score(prompt: str, desc: str) -> int:
    """Count distinctive prompt terms appearing in a description. Whole-word match —
    substring matching let 'right' hit 'copyright' and inflated every score."""
    words = {w for w in re.findall(r"[a-z]+", prompt.lower()) if len(w) > 3 and w not in STOP}
    return sum(1 for w in words if re.search(rf"\b{re.escape(w)}", desc))

problems = []
for prompt, expected in CASES:
    s = {k: score(prompt, d) for k, d in descs.items()}
    top = max(s.values()) if s else 0
    winners = [k for k, v in s.items() if v == top and v > 0]
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
