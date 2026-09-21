---
description: Build or test the project through the active stack profile's declared commands
argument-hint: [optional: a target or package the profile understands]
allowed-tools: Bash, Read, Grep
---

```bash
./Scripts/ga-step.sh after install      # sequence gate
```

**Exit 5 means an earlier step has not run.** Say which one, and stop — never pass `--force`. Order
and why: [SEQUENCE.md](/docs/operations/SEQUENCE.md)(../../docs/SEQUENCE.md).

Build the project through the **active stack profile's** declared build and test commands. The layer
fixes no toolchain — a profile (`profiles/<name>/`) declares `build_cmd` and `test_cmd`; with no
profile declared there is nothing to build.

**This command is the sanctioned exception to CLAUDE.md §2.8** — typing it *is* the instruction to
build. Outside it, never build, run or test on your own initiative.

**Arguments:** `$ARGUMENTS` — passed through to the profile's command (e.g. a target or package).

## Steps

1. **Resolve the profile:**

   ```bash
   ./Scripts/detect-toolchain.sh          # what the active profile declares
   ```

   No profile declared → stop and say so; a project declares its stack in `profiles/` at
   `/project-init`, and there is nothing to build until then.

2. **Run the profile's build, then its tests.** Prefer `./Scripts/check.sh` (it runs the profile's
   `check_cmd`) over a hand-rolled invocation. Building validates freely (§2.8); a test run is what
   typing this command consents to.

3. **Report faithfully.** Quote the actual tool output for failures; don't paraphrase. Surface
   warnings as well as errors if the profile treats them as findings.

## Constraints

- Never disable a warning or force a build green. Fix it or report it.
- Running and testing need the user's consent, which typing this command gives for the run it names;
  consent is per request and never standing (§2.8).
