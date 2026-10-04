# Gotchas

Traps hit while building Sneak, with what fixed them.

## Godot

- **A test scene that changes scene kills itself.** `change_scene_to_file` frees the current
  scene, and a test run as `godot res://tests/smoke.tscn` *is* the current scene. Its coroutine
  dies and the process never quits. `tests/smoke.gd` adds the game beside itself instead, and
  `tools/check.sh` passes `--quit-after` so a broken test fails instead of hanging.
- **Godot prints script errors and still exits 0.** `tools/check.sh` fails on any `ERROR:` or
  `WARNING:` line, not just the exit code. The warnings set to error level live in the `[debug]`
  section of `project.godot`.
- **Name every node that replication or RPCs touch.** Nodes created in code get names like
  `@MultiplayerSpawner@163`, and the counter differs between host and client. Replication
  matches nodes by path, so the client logs `Node not found` and `Parameter "spawner" is null`
  and never sees anything spawn. `game.gd` names spawners `Spawner`; `Net.replicate` names
  synchronizers `Sync`.
- **`change_scene_to_file` from `_ready` errors** with "Parent node is busy adding/removing
  children". Call it deferred, as `main_menu.gd` does for `--host`/`--join`.
- **Spawns can arrive before the spawner exists.** A client must build the game scene before it
  asks for its player; see [Network model](design.md#network-model).

## Tooling

- **gdformat writes CRLF on Windows.** Files it reformats come back with CRLF line endings, which
  the `mixed-line-ending` hook then rewrites, and exact-match edits on them fail. Run
  `sed -i 's/
$//'` on what it touched, or let the hook fix them before committing.

- **uv cannot make its minor-version Python links here.** `uv python install 3.13` downloads
  the interpreter, then fails with "Missing expected target directory for Python minor version
  link". Ask for the exact patch version (`--python 3.13.16`), which skips the link. Seen
  2026-10-03 with uv 0.12.23.
- **serena does not build on Python 3.14.** Its pinned pyyaml has no 3.14 wheel, so the MCP
  server is registered with `uvx --python 3.13`.
