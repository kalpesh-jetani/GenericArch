# Wrapping a third-party library

- **When to read this:** adding, replacing or removing a vendor dependency. The rule is CLAUDE.md §7;
  this is what satisfies it.
- **The rule, restated:** no feature or infrastructure module imports a vendor directly, and
  **swapping a vendor must touch exactly one target.** If a swap would touch two, the wrapper is
  wrong.

---

## What every wrapper ships

1. **A protocol describing *our* need** — in `Core`, or in `XWrapperInterface` when it would drag a
   vendor type into `Core`. Named for the capability, not the vendor: `CrashReporting`, not
   `SentryService`.
2. **One implementation, in `XWrapper`** — the sole place the vendor is imported. Grep for the vendor
   module name: one hit, one target.
3. **Our types at the boundary.** No vendor enum, error, model or callback signature crosses it. A
   vendor error is mapped to ours; a vendor enum is re-declared. This is the part that decides whether
   a swap is a day or a month.
4. **A `NoOp` and a `Spy`/`Mock`.** `NoOp` for previews, tests and the build where the vendor is
   absent; `Spy` for asserting what was sent without sending it.
5. **`<Vendor>Wrapper.md`** — what we use it for, and **what we deliberately do not**. The second half
   is what stops the next person adopting a feature we rejected on purpose.

## The two-target split

`XWrapperInterface` (no vendor dependency) and `XWrapper` (the vendor dependency) are separate
targets, so a feature links only the interface. Without the split, every feature that touches the
capability pulls the vendor into its own dependency graph — and the "swapping touches one target"
promise quietly stops being true.

## Contract test

The real implementation and the mock satisfy the **same** suite (CLAUDE.md §9). A mock that passes
tests the real one would fail is worse than no mock: it makes every downstream test a false positive.

## Removing a vendor

1. Delete `XWrapper`. The build breaks in exactly one place if the policy held.
2. Keep the protocol and the `NoOp` — features keep compiling while the replacement is written.
3. Record the removal in `docs/DECISIONS.md` *Do not re-propose*, with why. A vendor removed for a
   reason gets re-proposed within a year otherwise.
