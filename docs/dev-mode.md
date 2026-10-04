# Developer mode

A panel for testing without playing a whole run (`scripts/dev.gd`, added 2026-10-04).

## Turning it on

Tick **Developer mode** in the main menu before hosting, or start with `-- --dev` (for example
`godot --path . -- --host --dev`). It only appears on the host: the host owns loot, monsters and
the score ([Network model](design.md#network-model)), so everything the panel does happens there
and replicates as usual. Clients joining a dev-mode host see the results but no panel.

In game, **F1** shows or hides the panel and frees the mouse; **Esc** hides it.

## What it does

| Section | Action | How |
| --- | --- | --- |
| Status | Seed, frame rate, the room you are in (number, kind, decor theme, storey), position, monster and loot counts. | Read from `Level` and the scene. |
| Spawn | Any loot kind, at its top value, where you look. | `game.spawn_loot_at` |
| Spawn | Any of the four monster bodies where you look. | `game.spawn_monster_at` |
| Monsters | Freeze all, send all to your room, calm them for 30 s, remove all. | `Monster.hunt`, `Monster.calm`, physics off |
| Me | Unseen (monsters ignore you), fly through walls, run three times as fast. | `Player.unseen`, `flying`, `speed_scale` |
| Me | Teleport to the truck, the farthest room, or the room of the most valuable loot; get caught. | |
| World | Open every cupboard and drawer (filled as usual), bank $100, meet the quota, light everything, time x0.25 / x1 / x3. | `game.open_everything`, `game.add_banked` |
| Site | Restart this site or build a new one. | `Net.seed_override`, `Net.restart` |

Restarting closes the session and hosts again, so any clients are dropped.

The smoke test builds the panel and checks the spawns and banking through the same functions.

## Adding an action

Put anything that changes the shared game on the host side in `game.gd` (or the node it
concerns) as a public function, and give it a button or check box in `dev.gd` with `_button` or
`_toggle`. Keep RNG out of it, or use the host's RNG, never `Level`'s: the site must stay the same
on every peer.
