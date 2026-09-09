# Decision log

**For the reader, not for Claude.** What was decided, why, when, and by what approach. It is
**never read to decide anything** — that is `docs/DECISIONS.md`, which is normative and is read
before every §0 question. This file is the story of arriving there.

Append-only, one section per session, written only by:

```bash
./Scripts/ga-log.sh --decided "<what>" --why "<reason>" --how "<approach>"
```

Meta-commentary belongs here and nowhere else — not in a skill, a command, a script, a doc or a
`#` comment. Those carry the rule; this carries the reasoning
([STRUCTURE.md](../docs/STRUCTURE.md)).

---

## 2026-09-09

- **Decided:** One always-on skill (tool-profile) with per-platform bodies under .claude/tools/, not one skill per platform
  **Why:** Skill descriptions are always-on context and compete for triggers; N generated descriptions would be N collision surfaces introduced by machine. STRUCTURE.md: every word in a description competes
  **How:** The per-platform files are the variant layer the Claude skill guidelines recommend (SKILL.md = workflow + selection, references = variants), so a new platform adds a file, never a skill
  *(2026-09-09T11:13:25Z)*

- **Decided:** The registry moved from .claude/skills/generated-skills-note.md to .claude/skills/tool-profile/references/generated-skills-note.md
  **Why:** A bare .md at the skills root is discovered by nothing — verified: the loader, check-skill-triggers.py and build-plugin.sh all glob skills/*/SKILL.md. references/ is the canonical on-demand location in the Claude skill guidelines, which is what the original path was trying to achieve
  **How:** Filename kept; link depths rewritten to ../../../tools/; every pointer repointed and revalidated
  *(2026-09-09T11:13:25Z)*

- **Decided:** Per-platform profiles stay in .claude/tools/, not inside the skill's references/
  **Why:** The guidelines' variant pattern would put them in references/, but adopt.sh ships .claude/skills wholesale — generated product content inside a shipped skill directory becomes indistinguishable from shipped files and breaks install/uninstall ownership
  **How:** SKILL.md carries an explicit read-this-when table pointing at .claude/tools/, satisfying progressive disclosure without crossing the install boundary
  *(2026-09-09T11:13:25Z)*

- **Decided:** Local replace_span helper instead of ga_block_present/append/strip from ga-lifecycle.sh
  **Why:** Those functions are named in the library's #@out list but their signatures are not documented anywhere, and reading the body to find out is what CLAUDE.md 5 forbids. Calling them blind would be guessing, which rule 3 rules out
  **How:** Local awk span replacement using the same GA:ROWS marker convention sync-notes.sh already uses
  *(2026-09-09T11:13:25Z)*

- **Decided:** Failure thresholds fixed at 1=suspect, 2=stale, 3=retire
  **Why:** Without a recorded threshold the question gets argued at every failure. 2 is where a pattern beats an anecdote, mirroring session-script.sh's second-distinct-session promotion gate
  **How:** Recorded as a Settled row in docs/DECISIONS.md so it is not re-litigated
  *(2026-09-09T11:13:25Z)*

- **Decided:** Version bumped to v0.6.3 in the v0.6 LTS line, not v0.7.0
  **Why:** The repo's own precedent decides it: v0.6.1 and v0.6.2 each ADDED shipped scripts to a ga_known_paths arm and stayed patches in the LTS line, and v0.6.2 even deleted twelve docs as a patch. Opening v0.7 would be a policy change to GA_LTS_LINE and README's support table, which is not what adding a capability requires
  **How:** New v0.6.3 arm = v0.6.2 plus exactly .claude/tools, ga-tool-note.sh, ga-log.sh; verified by diffing the two arms
  *(2026-09-09T11:23:04Z)*

- **Decided:** Observed provenance has three values, and only a dated row satisfies the --apply gate
  **Why:** The first real profile exposed the flaw: three rows whose unit came from the connector's tool DEFINITION were stamped with today's date and counted as observed, so a profile could have been assembled entirely from contracts without ever reaching the platform — precisely what rule 3 exists to prevent
  **How:** Observed is now derived: a date when Accessible is real, 'contract' when only the shape is known, '—' when nothing is. The gate counts retrieved rows only, and reports how many contract rows it refused
  *(2026-09-09T11:23:04Z)*

- **Decided:** The Figma connector profile records attribute shapes only, never the values
  **Why:** whoami returns a handle and an email. CLAUDE.md §8 bars PII from logs, and .claude/tools/CLAUDE.md bars response bodies from profiles, so the useful fact is that the field exists and where it comes from
  **How:** Recorded 'account email | string | yes | whoami, field email | per account'; verified by grepping every tracked file for the real values
  *(2026-09-09T11:23:04Z)*

- **Decided:** Description tuned against a 20-query trigger set: added 'or MCP server' and 'here is the URL', removed the word 'call'
  **Why:** Measured, not guessed. 'call' was an incidental word that leaked the api-map notes prompt; the description had no vocabulary at all for a pasted design URL, which is half the scope list. Proxy score went 15/20 to 17/20 with the repo's 44 fixtures still green
  **How:** Copied the repo's own IDF scorer against the 20 queries, diagnosed the exact matching word per failure, changed only what a diagnosis justified
  *(2026-09-09T11:48:04Z)*

- **Decided:** 'mockup' cannot appear in a skill description here
  **Why:** The trigger scorer matches by prefix, so \b mock hits 'mockup' and steals new-feature's 'add a protocol and a mock' fixture. It broke the suite the moment it was added
  **How:** Dropped from the description; kept in the SKILL body's scope table, which is not a trigger surface
  *(2026-09-09T11:48:04Z)*

- **Decided:** Three of the 20 trigger queries are left failing on purpose
  **Why:** One needs three unique words to out-score new-feature's legitimate 'start/settings/screen' claim; one references a recorded fact without naming the concept, which word-overlap cannot reach; one fires on 'connector', the skill's central noun, and the body's scope step catches it. Fixing any would mean stuffing incidental vocabulary
  **How:** Documented rather than patched. The model-based optimizer measures actual triggering and would handle all three better than word overlap
  *(2026-09-09T11:48:04Z)*

- **Decided:** Optimizer rerun with --num-workers 2, --runs-per-query 2, --max-iterations 3
  **Why:** The first run died in iteration 2 with 'RuntimeError: claude -p exited 1' while 24 claude workers ran concurrently. A single claude -p smoke test passed before and after, so the cause is rate limiting under concurrency, not auth — and this session had already hit a session limit once
  **How:** Capped concurrency, halved runs per query, and moved the log out of the session scratchpad, which a session restart had already wiped once
  *(2026-09-09T15:31:09Z)*

- **Decided:** The 20-query trigger eval set is tracked at .claude/skills/tool-profile/evals/
  **Why:** It is a reusable fixture for a shipped skill, the same class as Scripts/check-skill-triggers.py. A skill's own directory is already a home, so this needed no new STRUCTURE.md home — and the crash proved the point: the scratchpad copy vanished, the tracked one did not
  **How:** evals/trigger-eval.json plus a README recording the three failures left in on purpose, so nobody re-fixes them by stuffing the description
  *(2026-09-09T15:31:09Z)*

- **Decided:** Shipped the imperative description; rejected the optimizer's own winner
  **Why:** Its winner scored 12/16 on held-out but failed the repo gate with 4 collisions including a STOLEN against OpenSpec, and named four vendors the project may never use. The synthesis kept what was measured to work — imperative framing and an exclusion clause — and scored 13/16, better than both. De-vendoring improved held-out recall 50 to 62 percent, so the vendor names were overfitting
  **How:** Reworded around every collision: vendor to published API documentation, fields to attributes and units, dropped mockup and link. Verified against both gates before applying
  *(2026-09-09T15:41:18Z)*

- **Decided:** Measured debug and new-feature; shipped neither rewrite
  **Why:** Only tool-profile improved held-out score (11/16 to 13/16), so only it was applied. debug rose on train and stayed flat on held-out, which is the signature of fitting the eval queries; new-feature moved off 0 percent but gained a single run and still misses seven of eight positives
  **How:** Both drafts pass the gate at 44/44 and are recorded in each skill's evals README with their numbers and the verdict, so the next attempt starts from them without believing they were validated
  *(2026-09-09T16:08:53Z)*

- **Decided:** new-feature's 0-percent recall is probably not a vocabulary problem
  **Why:** The baseline fired on none of ten positives including a near-verbatim quote of its own trigger phrase, and an imperative rewrite only reached 12 percent. Per the skill-creator guidance the model does not consult skills for work it thinks it can just do, and scaffolding files is exactly that — so it improvises a package without reading the section 2 rules
  **How:** Recorded as an untested hypothesis in the evals README: the lever is the cost of not consulting, not more trigger words
  *(2026-09-09T16:08:53Z)*

- **Decided:** Stopped tuning new-feature's description; the defect is not in the wording
  **Why:** Three framings — house style, imperative, and cost-of-improvising — all landed inside the noise band: held-out recall 0, 12 and 0 percent, train never past 15/24, precision 100 throughout. The model declines ordinary scaffolding requests however the description is written
  **How:** Recorded all three with their numbers in the evals README and left the question it raises open: a skill that cannot fire is arguably a command, which is a section 0 decision and touches CLAUDE.md 2.13
  *(2026-09-09T16:17:40Z)*

- **Decided:** adopt.sh scaffolds .claude/tools instead of copying it, and blanks the generated tool rows in MAP.tsv, INDEX.md and the registry note
  **Why:** Adding .claude/tools to BASE leaked this repo's own figma profile into every adopting product — the profile, the ledger row marked active and verified, and rows in all four index surfaces. A consumer would have held a verified profile no session of theirs ever observed, which is the failure rule 3 exists to prevent and a new instance of the still-open DECISIONS question about the nine notes shipping with this base's example rows
  **How:** Reused the .claude/notes scaffolding path rather than inventing a second mechanism: component doc verbatim, header-only ledger, no profile; spans blanked between the generator's own markers so hand-written rows survive
  *(2026-09-09T16:37:14Z)*

- **Decided:** docs/TOOL-PROFILES.md is REFERENCED, Scripts/Generated is EXCLUDED
  **Why:** adopt.sh exited 1 on every adoption because both were in none of its three lists — the accountability gate is designed to fail loudly rather than skip silently, and it did. TOOL-PROFILES.md is prose a human wrote, so it belongs with STRUCTURE.md and CONVENTIONS.md as fetched-on-demand; generated recipe scripts describe platforms the target never reached
  **How:** One entry into each list that matches what the thing is; verified by running adopt.sh against a temp target, which now exits 0
  *(2026-09-09T16:37:14Z)*

- **Decided:** ga-tool-note.sh gained --revive, and the tombstone gate now checks both paths
  **Why:** Executing the revive branch for the first time exposed it: retire tombstones the profile and the recipe, but the gate only checked the profile and the docs said revive takes one path. Reviving only the profile let generate re-create a recipe that was still tombstoned — a file on disk the install machinery believed was declined
  **How:** The gate loops over both paths; --revive delegates to ga-remove.sh for each tombstoned one, then re-syncs and re-registers. Verified in a disposable copy: 2 tombstones to 0, both files back, four surfaces re-indexed
  *(2026-09-09T16:39:46Z)*
