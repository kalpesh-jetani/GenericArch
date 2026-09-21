# Changelog

Releases of the GenericArch base. A version is a tag; `install.sh` records it in the target's
manifest and `uninstall.sh` validates against it, so a release name is load-bearing rather than
decorative.

---

## v0.7.0

The theme: **tech-stack-agnostic development layer with shared memory.**

Converted GenericArch to a universal development environment manager that works with any tech stack.

### Key changes

- **Stack profiles:** Projects now declare their language, build system, and test framework via `profiles/<name>/CLAUDE.md`
- **Platform-neutral:** All platform-specific code, scripts, and documentation removed. Machinery works identically for Node.js, Java, Go, Python, Rust, and any other tech stack
- **Lifecycle unification:** Three-phase adoption (`install` → `/project-init` → `/sync-app-notes` → `ready`) works across all stacks
- **Memory system:** `.claude/memory/` syncs with project state for persistent Claude context across sessions
- **Documentation restructured:** Organized into `adoption/`, `operations/`, `reference/`, `patterns/`, and `decisions/` hubs with no stack-specific assumptions

---

## v0.6.3

Base release before tech-stack generalization.

---
