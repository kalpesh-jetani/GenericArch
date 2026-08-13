# Pattern Search: Using `.claude/notes/` to reduce token spend

**Goal**: Claude searches `.claude/notes/` inventories first before calling grep, reducing tokens
per session by building up a searchable index of the codebase structure.

---

## The pattern

Every skill should follow this sequence:

```
1. "Is X in .claude/notes/<relevant-file>.md?"
   → Search FEATURES.md for a feature
   → Search NAVIGATION.md for a route
   → Search CONVENTIONS.md for a naming pattern
   → Search STYLE-GUIDE.md for a design token
   → Search PROJECT.md for a target or capability

2. If found:
   Use the path and description directly. Zero grep.

3. If NOT found:
   → Call grep or the normal search tool
   → Record the pattern in the relevant .claude/notes/ file
   → Include in the same commit as the code change

4. Over time:
   .claude/notes/ becomes more complete
   → More future lookups hit the notes
   → Less token spend per session
```

---

## Examples by skill

### `/new-feature`

```
When adding a feature:
1. Search FEATURES.md: "What features exist? What states do they handle?"
   → Find the Feature<Name>/ folder structure pattern
   → Find the View, ViewModel, Model naming pattern
   → Find how ContentState is used in existing features
2. If not found in notes:
   → Grep for existing features
   → Record the pattern in FEATURES.md
```

### `/code-review`

```
When reviewing code:
1. Search CONVENTIONS.md: "What's the naming pattern for this type?"
   → Find access control rules (public/internal/private)
   → Find doc comment style
   → Find file layout expectations
2. If convention not in notes:
   → Grep for examples
   → Record the pattern in CONVENTIONS.md
```

### `/style-guide`

```
When styling:
1. Search STYLE-GUIDE.md, ASSETS-COLORS.md, FONTS.md:
   → Find existing tokens
   → Find component variants
   → Find spacing/radius/motion patterns
2. If token not in notes:
   → Grep for hardcoded values
   → Record as a new token in ASSETS-COLORS.md or FONTS.md
   → Add to STYLE-GUIDE.md if it's a reusable pattern
```

### `/verify`

```
When checking "is this done?":
1. Load DONE.md from notes
   → Use its checklist directly
   → No grep needed — DONE.md is the source of truth
2. If DONE.md is stale:
   → Record the drift in DECISIONS.md *Open*
   → Update DONE.md in the same PR that changes the Definition of Done
```

---

## Recording patterns back to notes

**When to update `.claude/notes/`:**
- Adding a new feature → add row to FEATURES.md
- Adding a new route → add row to NAVIGATION.md
- Adding a new screen → update both FEATURES.md and NAVIGATION.md
- Adding a new asset (image, color, font) → update ASSETS-*.md and STYLE-GUIDE.md
- Discovering a naming convention → update CONVENTIONS.md
- Discovering a new token value → update STYLE-GUIDE.md, ASSETS-COLORS.md, or FONTS.md

**Rules for recording:**
1. Path must be exact and verified (the file exists)
2. Description must answer "what is this?" not just "name"
3. Link back to CLAUDE.md when the pattern is a rule: "See CLAUDE.md §2.1 — features never import each other"
4. Do it in the same commit as the code change (CLAUDE.md §5)

---

## Token savings over time

**Session 1 (fresh project):**
- Notes are empty or minimal
- Claude calls grep for every lookup
- Tokens: ~high (many grep calls)

**Session 5 (notes are populated):**
- Most lookups hit FEATURES.md, NAVIGATION.md, CONVENTIONS.md
- Grep only for edge cases
- Tokens: ~50% of Session 1 (notes are in context, grep is rare)

**Session 20 (notes are comprehensive):**
- Almost all lookups hit notes
- Grep almost never needed
- Tokens: ~20% of Session 1 (searchable index is mature)

The longer the project runs with this discipline, the cheaper it gets to understand the codebase.

---

## For skill authors

When writing or updating a skill:

1. Start with: "Grep `.claude/MAP.tsv` for the relevant `.claude/notes/` file. Is the pattern there?"
2. If yes: use it directly, cite it
3. If no: fall back to grep, then update the notes
4. Document the search pattern in the skill so the next author knows what to check first

Example pattern in a skill:

```markdown
## Search first

**Before searching code:**
1. Check FEATURES.md — is the feature listed? If yes, use the file path from the notes.
2. Check CONVENTIONS.md — is the naming pattern documented? If yes, follow it.
3. If not found in notes, grep for examples.
```
