# Pofuduk — CLAUDE.md

Keep this file under 150 lines. Details live in:
- `PRD.md` — product requirements
- `ARCHITECTURE.md` — technical architecture
- `PROJECT_STATUS.md` — progress summary (update only changed items)
- `API_INTEGRATIONS.md` — integration details

Also: `ROADMAP.md`, `PRIVACY.md`, `DEVELOPMENT.md`.

Read only the relevant sections of these docs; never copy them here.

## Build (Windows dev machine)
- Core logic: `scripts\swift-core.cmd build` / `scripts\swift-core.cmd test` (sets up MSVC + Swift env).
- iOS app (`Pofuduk/`, `project.yml`) cannot compile on Windows; it needs macOS/Xcode or the GitHub Actions workflow.
- Put new business logic in `PofudukCore` so it stays testable here.

## Working rules (mandatory)

**Tokens & responses**
- Concise, actionable output. No repeated summaries, no obvious explanations, no unrequested docs.

**Code reading**
- Read only task-relevant files. Search (classes/methods/interfaces) before opening large files.
- Skip generated files, dependencies, build outputs, lockfiles. Don't re-read what's in context.

**Implementation**
- One clearly defined task at a time. No unrelated refactors or changes to working features.
- Reuse existing architecture/components. No unneeded abstractions or new dependencies without clear reason.
- Don't implement future-phase features early.

**Commands**
- Filter output to relevant errors/warnings; no full build logs.
- No repeated builds/tests without reason. Targeted tests after small changes; full suite at milestones.

**Context**
- Keep `PROJECT_STATUS.md` short and current.
- Use `/compact` with a focused summary when context grows; recommend `/clear` for unrelated tasks.
- Record essential technical decisions in docs before clearing context.

**Models & agents**
- Sonnet: routine implementation, simple fixes, tests, small refactors.
- Opus: architecture, complex debugging, difficult integrations, cross-module changes.
- No max reasoning effort for simple tasks. Subagents only for independent parallel work.
- Prefer official docs for critical decisions; avoid unnecessary web searches.

**End-of-task report**
1. Implemented
2. Modified files
3. Tests and build results
4. Remaining issues

**Primary rule:** never sacrifice correctness, security, testing or maintainability to save tokens.
