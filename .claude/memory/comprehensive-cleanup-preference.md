---
name: comprehensive_cleanup_preference
description: For cleanup/removal tasks, map all findings first, fix all at once, commit once—not incrementally
metadata:
  type: feedback
---

## Comprehensive one-pass cleanup, not incremental

When tasked with cleanup or removal ("until it's cleaned", "remove all X", "no specific tech-stack prerequisites"), do not iterate:
- ❌ Edit file → commit → search again → find more → edit → commit (creates noise, invites backtracking)
- ✓ Map exhaustively → fix all → commit once (binary completeness)

**Why:** The directive required *absolute* completeness, not good-faith effort. User iterated 4 times because incremental fixes left gaps. Final precision commit removed an accidental substring match that would be invisible in piecemeal review but caught in exhaustive scanning. Iterative approach signals incomplete understanding of the scope.

**How to apply:**
1. Start with comprehensive mapping: `find . -type f -print0 | xargs -0 grep -l <all-patterns>` across every directory and file type
2. Create a complete list of all findings before touching anything
3. Execute all fixes in one batch (or a few well-organized batches)
4. Commit once with a complete summary
5. Interpret "cleaned" as a binary requirement—zero references, zero false positives, even accidental substrings

**Pattern:** Cleanup task iteration cycles typically follow:
- Cycle 1: Remove direct code/config references (largest set)
- Cycle 2: Remove build artifact exclusions, prune lists
- Cycle 3: Remove accidental substring matches
- Cycle 4: Confirm zero references—done

User's patience was a teaching signal: the bar was absolute, not negotiable.
