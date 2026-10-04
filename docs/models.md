# Models

How the game's 3D models are made: Python scripts drive Blender headless, export binary glTF
into `assets/models/`, and Godot dresses the imported surfaces in its own generated textures.
Nothing is modelled by hand, so every model can be rebuilt and changed in code like the rest of
the game.

## Building

Blender 5.2 LTS is installed to `C:\Program Files\Blender Foundation\Blender 5.2\` and is not
on PATH. From the repository root:

```bash
"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/blender/build.py
```

That rebuilds every model and rewrites `assets/models/decor.json`. Add model names after `--`
(e.g. `-- stalker vase sofa`) to rebuild only those; the catalogue is then left alone. Godot
imports the `.glb` files on its next start or `godot --headless --import`; commit the generated
`.import` files with them.

Look at the result in Godot, which is the look that counts, with the showcase:

```bash
godot --path . res://tools/showcase.tscn -- --set=monsters --out=C:/path/monsters.png
```

Sets: `loot` (add `--close` for the small finds), `monsters` and `decor`.

## Scripts

| Script | Makes | Into |
| --- | --- | --- |
| `tools/blender/lib.py` | Shared primitives (box, cylinder, lathe, tube, metaball `blob`, curved `sheet`), materials, joining and export. | |
| `tools/blender/monsters.py` | The four monster bodies. | `assets/models/monsters/` |
| `tools/blender/loot.py` | One model per loot kind. | `assets/models/loot/` |
| `tools/blender/decor.py` | Furniture and decorations, and their catalogue. | `assets/models/decor/`, `decor.json` |

Type stubs for `bpy` come from `fake-bpy-module-5.2` in `tools/requirements.txt`, so pyrefly
checks the scripts without Blender.

## Conventions

- **Axes.** Scripts work in Blender's axes (Z up) with every model facing -Y. The glTF exporter
  turns that into Godot's Y up, facing +Z.
- **Origins.** Loot is centred on its collision box (`KINDS` in `scripts/game.gd`), and
  `loot.py` reports any model that pokes out of its box. Monsters stand on their origin. Decor
  is moved so its origin is on the floor (or at its bottom, for things hung on walls) in the
  middle of its footprint.
- **Colours are sRGB**, as in the GDScript. `lib.mat` stores them linear, the way Blender and
  glTF expect, and Godot's importer turns them back.
- **Material names choose the look.** `Models.dress` (`scripts/models.gd`) replaces every
  imported material by a generated noise texture with a bump map, chosen by the part of the
  name before the first underscore: `wood`, `lacquer`, `metal`, `glaze`, `fabric`, `leather`,
  `stone`, `marble`, `paper`, `flesh`, `bone` and `plastic` are noise presets (`PRESETS`);
  `glow`, `glass`, `gem`, `plain` and `canvas` are special. Colour, roughness and metal come
  from the Blender material. Names starting `tint_` take the item's colour instead (a gem's
  stone, a book's cover, a sofa's fabric).
- **No UVs.** Textures are projected in each model's own space (triplanar), so the scripts
  export no texture coordinates.
- **One mesh per joint.** Before export, `lib.consolidate` joins the meshes under each empty,
  so a monster arrives as one mesh per animated joint and loot and decor as one mesh each.

## Monsters

Four bodies, picked per monster as `(seed + index) % 4` (`game.gd`), so a run shows three
different ones; they share one collision capsule and one behaviour for now. Godot animates them
by node name (`Monster` in `scripts/monster.gd`): `leg_N` swing in turn about their own X axis,
`arm_N` dangle and then reach in a chase, `torso` leans, `head` looks about and `float` bobs. An
empty named `eyes` marks where the monster looks from and gets a glow light; the wraith's
lantern has a `light` empty.

| Body | What it is |
| --- | --- |
| stalker | Gaunt and hunched, arms to its knees, ribs and spine ridges showing, long toothed jaw. |
| crawler | Six chitin legs, a pale sac of a body, a human torso and a cracked porcelain face of six eyes. Its legs pivot about a vertical axis, so they stride sideways like a spider's. |
| wraith | A floating, ragged shroud with nothing in its hood but two eyes, bone hands and a lantern. |
| brute | A hulking butcher in a stained apron with a sack over its head and a cleaver. |

The crawler's eyes are 1.6 m up, not 2.3 m, so it notices players from lower down; the
behaviour is otherwise the same.

## Loot

Every kind in `KINDS` has a model. The first version's nine kinds were rebuilt with more detail,
and seven were added (2026-10-04): bust, candelabra, globe and gramophone lie out in rooms; goblet,
pocket watch and idol are small finds in cupboards and drawers. Their values, masses and
fragility are first guesses for play-testing, not tuned.

## Decor

54 pieces in `decor.json`, placed by `scripts/decor.gd` from the level's RNG, so every peer
furnishes the same site. Each indoor room takes a theme from its kind, then a rug, floor pieces
and things on the walls of that theme:

| Room kind | Themes |
| --- | --- |
| large | living, dining, library, storage |
| medium | bedroom, office, kitchen, lab |
| small | bathroom, storage |
| hallway | hall |

A piece's `place` says how it goes in: `wall` (back to a wall), `corner`, `free` (anywhere clear),
`rug` (flat in the middle, grown toward half the room) or `hang` (on a wall at `mount` metres, no
collision). Pieces marked `anywhere` (boxes, barrels, shelves, plants...) sometimes stand free too.
A room tries for one floor piece per 6 m² (5 in small rooms, 12 in halls) and one hung thing per
7 m of wall, give or take; most pieces appear at most twice per room, clutter four times and set
pieces (a fireplace, a bathtub, a double bed) once. About 1,300 to 1,600 pieces furnish a site.

Rules that keep the game playable:

- Solid pieces stay `ROUTE_CLEARANCE` (0.7 m) clear of every line from a room's middle to the
  points in front of its doorways (`Level.approaches`), since monster routes cross rooms only
  along those lines ([The site](design.md#the-site)), and 1.2 m from doorways. The smoke test
  walks those lines and fails if any point is inside a piece.
- One-cell halls (under 4 m wide) get only pieces at most 0.45 m deep, against the walls.
- Loot never spawns inside a piece or on a monster line.
- Pieces farther than 35 m from the camera are not drawn (`DRAW_DISTANCE`), which cut the objects
  drawn by about 60% in test views. Frame rate there was about 40 either way, with or without
  decor (RTX 5070, 1600x900, 2026-10-04), so what limits it is something else; unmeasured.

Pieces are static: only the cupboards and dressers (`scripts/cabinet.gd`) open.

## Sources

The shapes are original, built from primitives in the scripts; no outside assets are used.
Measurements (a seat at 0.46 m, a counter at 0.9 m, a door at 2.1 m) are typical furniture
sizes from general knowledge, not from a reference.
