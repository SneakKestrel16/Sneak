# Sneak

Project facts live here; working habits live in the user-level `~/.claude/CLAUDE.md`.

## Answering

Follow the user-level rules: two or three sentences, findings in commits and docs.

## Environment

Windows, Git Bash and PowerShell. Remote: `github.com/SneakKestrel16/Sneak` (public) — never
commit anything sensitive. Godot 4.7 (winget) with GDScript, everything built in code with
minimal `.tscn` files, like the sibling Nelbrenn project. Python tools live in `.venv`
(CPython 3.13.16 via uv).

## Hard constraints

- Online co-op from day one: the host owns loot and monsters; each peer owns only its player.
  See `docs/design.md#network-model` before adding anything that moves.
- First version is R.E.P.O.-style looting; voice spells and voice chat come later.
- Every peer builds the house from the host's seed; anything random in the layout must come
  from `Level`'s own RNG, in the same order on every peer.

## Build and test

- Set up tools: `uv venv --python 3.13.16 .venv` then
  `uv pip install --python .venv/Scripts/python.exe -r tools/requirements.txt`.
- `bash tools/check.sh` imports the project headless and runs `tests/smoke.tscn`.
- `prek run --all-files` (from Git Bash) runs everything, including the smoke test.
- See the models without playing: `godot --path . res://tools/showcase.tscn -- --out=<png>`
  renders every loot kind and the monster to a PNG (opens a window briefly).
- See a generated house from above: `godot --path . res://tools/map_view.tscn -- --seed=N
  --out=<png>` (doorways marked red).
- Replay a house: add `--seed=N` after `--` (the host logs `[level] seed N`); works for the
  game and `tests/smoke.tscn`.
- Two local players: run the game twice with `-- --host` and `-- --join=127.0.0.1`.

## Code style

Enforced by `.editorconfig`, gdformat/gdlint (GDScript), ruff/pyrefly (Python under
`tools/`) and Godot's warning levels in `project.godot`. Warnings are errors.

## Where to check facts

`docs/` first (start at `docs/README.md`).

## Documentation discipline

`docs/` is a maintained wiki: index every page, cite sources, mark inference as inference, and
record traps on a `gotchas.md` page per subject.

## Testing discipline

When an integration test fails, check the data before changing the assertion.
