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
   → Search the active profile for a naming convention
   → Search STYLE-GUIDE.md for a design token
   → Search PROJECT.md for the resolved stack

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

## Examples by task

### Adding a feature

```
1. Search FEATURES.md and NAVIGATION.md: "What features exist? What routes and states do they handle?"
   → Find the module/folder structure the project already uses
   → Find the view/model naming pattern
   → Find how existing features handle their states
2. If not found in notes:
   → Grep for existing features
   → Record the pattern in FEATURES.md
```

### Reviewing code

```
1. Search the active profile's conventions: "What is the naming/layout pattern for this type?"
   → Find access-control, doc-comment and file-layout expectations
2. If a convention is not written down:
   → Grep for examples
   → Record it where the profile keeps its conventions
```

### Styling

```
1. Search STYLE-GUIDE.md, ASSETS-COLORS.md, FONTS.md:
   → Find existing tokens, component variants, spacing/radius patterns
2. If a token is not in the notes:
   → Grep for hard-coded values
   → Record it as a token in ASSETS-COLORS.md or FONTS.md, and index it in STYLE-GUIDE.md
```

### Verifying "is this done?"

```
1. Load the active profile's definition of done
   → Use its checklist directly — no grep needed
2. If it is stale:
   → Record the drift in DECISIONS.md *Open*
   → Update it in the same change that alters the Definition of Done
```

---

## Recording patterns back to notes

**When to update `.claude/notes/`:**
- Adding a new feature → add row to FEATURES.md
- Adding a new route → add row to NAVIGATION.md
- Adding a new screen → update both FEATURES.md and NAVIGATION.md
- Adding a new asset (image, color, font) → update ASSETS-*.md and STYLE-GUIDE.md
- Discovering a naming convention → record it where the active profile keeps its conventions
- Discovering a new token value → update STYLE-GUIDE.md, ASSETS-COLORS.md, or FONTS.md

**Rules for recording:**
1. Path must be exact and verified (the file exists)
2. Description must answer "what is this?" not just "name"
3. Link back to CLAUDE.md for a neutral rule, or the active profile for a stack rule
4. Do it in the same commit as the code change (CLAUDE.md §3)

---

## Token savings over time

**Session 1 (fresh project):**
- Notes are empty or minimal
- Claude calls grep for every lookup
- Tokens: ~high (many grep calls)

**Session 5 (notes are populated):**
- Most lookups hit FEATURES.md, NAVIGATION.md, PROJECT.md
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
2. Check the active profile — is the naming convention documented? If yes, follow it.
3. If not found in notes, grep for examples.
```

---

## The three rules this depends on

The saving above is real only while notes stay **searchable artifacts**. Break any of these and the
index becomes a document, which costs more than the grep it replaced.

1. **Never read a note in full.** Grep it. A `grep -h "HomeScreen" .claude/notes/*.md` costs a
   line; opening `FEATURES.md` costs the file. If you find yourself reading one to answer a question,
   the row was not self-contained — fix the row, don't keep reading.
2. **Never promote a note to a skill.** A skill loads its whole body when it fires and its
   `description:` loads every session; a note is hit once for one line. Size is not a reason to
   convert — a 28 KB note that is only ever grepped costs no more than a 3 KB one, and converting it
   inverts the trade this whole file exists to make.
3. **Maintain by insertion and deletion, not rewriting.** A row appears when the thing appears and
   goes when the thing goes, in the same change (CLAUDE.md §3). `/sync-app-notes` is the only
   wholesale rewrite and only when the user types it.

### What a searchable row looks like

Because the file is never read, the row carries the whole answer:

- **One fact, one line**, ending in `|`. A wrapped row is two grep hits, each meaningless alone.
- **Keyed on the word someone would actually search** — the screen name, the route case, the token,
  the endpoint path. Not a description of it.
- **Path plus a clause saying what is there.** A bare path answers *where* and forces the reader to
  open the file, which is the cost you were avoiding.

```bash
# rows that wrap, across every note
awk '/^\| / && !/\|$/ {print FILENAME":"NR": row does not end in |"}' .claude/notes/*.md

# the lookup a session actually makes — one line back, no file opened
grep -h "<screen-or-route-or-path>" .claude/notes/*.md
```
