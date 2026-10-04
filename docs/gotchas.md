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
- **Fully metallic materials render near-black in the house.** Metal shows reflections, and the
  house has no sky or reflection probes, so gold frames came out dark brown in the first
  showcase render. `Models.METAL` keeps gold and brass at 0.45.
- **`Engine.time_scale` does not add physics steps.** It stretches each step's delta, so
  waiting N physics frames still takes N/60 real seconds but simulates N/60 × scale. The smoke
  test's roam check divides its frame count by the speed-up.
- **`Array.shuffle()` and `randi()` use the global RNG**, which is seeded differently on every
  peer. Anything in house generation must use `Level`'s own seeded RNG (`Level._shuffle`), or
  clients build a different house from the same seed.
- **`AnimatableBody3D.sync_to_physics` ignores transforms set from script.** With it on (the
  default), a cabinet's drawers stayed at the origin and its doors stayed shut while their hinge
  nodes turned, and only a render showed it; the smoke test still passed because it only counted
  items. It is off for cabinet parts, whose tweens already run in the physics step.
- **Spawns can arrive before the spawner exists.** A client must build the game scene before it
  asks for its player; see [Network model](design.md#network-model).

- **A showcase or tool scene with a script error hangs instead of quitting.** Its `_ready` never
  runs, so nothing calls `quit()`, and piping its output through `grep` hides the error until you
  kill it. Pass `--quit-after <frames>` when running tool scenes by hand.

## Blender

- **World matrices go stale while a script builds.** After setting `location` or `rotation_euler`,
  `matrix_world` keeps its old value until the view layer updates, so parenting "keeping the
  world transform" put every part at the origin and measured sizes were nonsense (the brute came
  out 2.9 m tall). `lib._refresh` calls `view_layer.update()` before anything reads a matrix.
- **`bound_box` overstates anything turned.** It is the object's local box, so its corners,
  rotated into the world, stick out past the mesh; a tilted globe ring measured 0.49 m in a
  0.4 m box. `lib.bounds` measures the vertices.
- **Blender's colour fields are linear.** A Principled base colour of 0.16 came back from glTF
  into Godot as 0.44, because Godot converts glTF's linear colours to sRGB. `lib.mat` takes sRGB
  like the GDScript does and converts.
- **Metaball radius is not the surface radius.** A lone ball's surface is at 0.575 of its radius
  (threshold 0.6, stiffness 2, measured in Blender 5.2); `lib.blob` takes surface radii and
  divides.

## Gameplay

- **Doorways must clear the monster's capsule.** The first doors were 2.3 m and the monster's
  collision capsule is 2.4 m, so it stood still under every lintel without touching a *wall*
  (`is_on_wall()` stayed false). That was true of the original 3x3 house too, so its monster
  never left its first room. Found by tracing monster positions in the smoke test; doors are now
  2.6 m and the smoke test fails if a monster passes through fewer than three rooms.
- **Loot spawned in a doorway can seal a dead end.** With random placement, about half of all
  seeds trapped a monster: a piano and three clocks in the only doorway of a dead end, or a heavy
  item it slid along forever. Speed-based stuck checks missed the sliding (it was still moving),
  so stuck now means "no closer to the waypoint", it detours sideways, it shoves loot, and loot
  spawns clear of doorways. Replay a house with `-- --seed=N`; the host logs `[level] seed N`.
- **Two monsters can jam each other on the stairs.** The stair room is one cell wide; a monster
  going up met one coming down and both stalled (a timing-dependent smoke failure). Monsters now
  collide only with layer 1, not each other.

- **Furniture on a monster's way traps it for good.** With rooms furnished, a piano lying on a
  monster's line got pinned against a sofa or a hall wall, and the monster shoved at it forever:
  seeds 11, 12 and 16 left a monster in one or two rooms. Monster routes now cross rooms only by
  their middle, decor and loot keep clear of those lines, pianos stay out of narrow halls, and a
  monster that cannot get round something in three tries roams elsewhere.
- **Yard loot can spawn in the truck bay** and be banked before anyone touches it, which made the
  smoke test's "dragged loot was banked" check see two items (seed 13, once the loot draws
  changed). Loot now spawns at least 4 m from the bay's centre.

## Tooling

- **Tool scenes are not checked by the hooks.** `tools/map_view.gd` kept a removed constant
  (`HOUSE_FLOORS`) and only failed when run by hand. Run `map_view` and `showcase` after
  changing `Level` or the models.

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
- **`Path.read_text()` decodes as cp1252 on Windows.** A script that read UTF-8 GDScript that way
  and wrote it back as UTF-8 turned every `·` into mojibake, worse with each edit. Pass
  `encoding="utf-8"` to both.
