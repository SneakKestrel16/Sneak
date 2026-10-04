# Sneak

Project facts live here; working habits live in the user-level `~/.claude/CLAUDE.md`.

## Answering

Follow the user-level rules: two or three sentences, findings in commits and docs.

## Environment

Windows, Git Bash and PowerShell. Remote: `github.com/SneakKestrel16/Sneak` (public) — never
commit anything sensitive.

## Hard constraints

None recorded yet.

## Build and test

No code yet. `prek run --all-files` (from Git Bash) checks the tree.

## Code style

Enforced by `.editorconfig` and `prek.toml`; add the language's linter config at the repo root
with the first code, with comments saying why each rule or exemption exists. Warnings are errors.

## Where to check facts

`docs/` first (start at `docs/README.md`).

## Documentation discipline

`docs/` is a maintained wiki: index every page, cite sources, mark inference as inference, and
record traps on a `gotchas.md` page per subject.

## Testing discipline

When an integration test fails, check the data before changing the assertion.
