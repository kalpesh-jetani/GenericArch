# CLAUDE.md — profiles/

A **stack profile** declares what a project is built with — platform, language(s), build system and
design pattern — so the layer drives the right toolchain instead of hard-assuming one. The layer
ships **no profile**; a project authors one here when it adopts the layer, and the active one is
recorded in `.genericarch/PROFILE.tsv`.

- **Owns:** the definition of each stack profile a project authors — identity, detection markers,
  source globs, toolchain commands, note taxonomy and scaffold templates.
- **May depend on:** nothing. A profile is data plus templates the layer reads; it sources no script
  and reaches into no other profile.
- **Never imports:** another profile, or any project code. The layer selects one active profile;
  profiles never reference each other.

Rules true only inside this directory:

- **One directory per profile**, named `<platform>-<language>`. **Nothing is a default, and no
  example ships** — the layer names no ecosystem anywhere, so there is nothing here to copy.
  Until a profile is declared the layer runs stack-neutral and stack-specific commands report
  "no profile declared".
- **A profile is declarative.** `profile.tsv` holds `key<TAB>value` rows read with the standard
  `awk -F'\t' '$1!~/^#/'` idiom. No executable logic beyond `scaffold/` templates. Read it through
  `ga_profile_get`, never by re-detecting.
- **Observation, not aspiration.** A profile describes a stack the layer actually drives. Never add a
  profile whose toolchain commands are not wired and exercised — an aspirational profile is a
  confidently wrong one.
- **`detect_marker_<path>` rows are the only detection there is.** Each names a file or directory
  whose presence proves this stack; a profile matches when every one of them exists. The layer
  carries no build-marker table of its own, so a profile that declares no markers is simply never
  matched — which is correct, not a gap.
