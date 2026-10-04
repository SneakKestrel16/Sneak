# Design

Sneak is a co-op physics-looting game in the spirit of R.E.P.O.: players drag fragile valuables
out of a dark, walled two-storey facility, and the cupboards and drawers inside it, to a truck
while monsters hunt them. Voice-cast spells in the style of YAPYAP and proximity voice chat are planned
but not in the first version (decided 2026-10-03).

## Core loop

1. The host rolls a seed and builds the site from it (`scripts/level.gd`); see
   [The site](#the-site). Everyone spawns at the truck bay inside the south gate.
2. Loot lies out in every room but the stairs, clear of doorways and furniture: one or two items,
   one more in rooms of 120 m² or more, and one more in a dead end; and in 2% of yard cells. Value
   grows 2% per step (room or yard cell) away from the truck, so deep runs pay (`_host_setup` in
   `scripts/game.gd`). The quota is half the value lying out, rounded to $10, so what is found in
   furniture is extra.
3. Cupboards (two doors over shelves) and dressers (three drawers) stand against room walls. Look
   at a shut door or drawer and press E: it opens for everyone, and once open, the host puts one
   to three small valuables in it (20% are empty): gems, necklaces, books or vials. They stay
   open, so nothing ever closes on loot. See [Furniture](#furniture).
4. Players hold the left mouse button on loot to drag it (`scripts/player.gd`). Every knock
   chips value; at $0 it breaks (`scripts/loot.gd`). Heavy loot needs several players, because
   each holder adds at most 400 N.
5. Loot dropped in the truck bay is banked. Meeting the quota is announced; the run carries on.
6. Three monsters (`scripts/monster.gd`) start in the indoor rooms farthest from the truck. They
   roam along routes 3 to 16 steps (rooms or yard cells) long and chase any player they can see
   within 14 m, or 4 m if the player is crouching. Walls, trees and loot block their view. A
   catch sends the player back to the truck and drops what they held.

## The site

A walled site on a 34x28 grid of 3 m cells (102 x 84 m), generated from a seed in
`scripts/level.gd`, with the props in `scripts/props.gd`. History: a 3x3 house, then a 6x6
maze (too maze-like, per the user), then one two-storey house of varied rooms, then a compound
of a house and outbuildings, then this single big facility, which the user preferred to several
small buildings (all 2026-10-04).

- **Stone wall.** 3.6 m high, 0.8 m thick, pillars every 9 m, round the whole site. The truck
  bay is just inside a shut iron gate in the middle of the south wall; players spawn north of it.
- **The facility.** One two-storey building, 26x18 cells (78 x 54 m), with 2 cells of yard
  between it and the wall and 2 between it and the truck yard. Four doors to the yard, on
  different rooms. Painted block walls; upstairs walls are cooler.
- **Rooms of varying size.** Each building storey is split recursively (binary space
  partition): cuts mostly go across the longer side, never leave a side under 2 cells, and stop
  at random once a piece is 24 cells or less. Rooms are classed by shape: *hallway* (1 cell wide,
  or 2 wide and 6+ long), *small* (up to 4 cells), *large* (15+), otherwise *medium*.
- **Different floors.** Each kind has its own surface, projected in world space so it tiles the
  same in any size of room: parquet in large rooms, carpet (one colour per site) in medium ones,
  pale tile in small ones, dark boards in hallways, concrete on the stairs.
- **Doors.** Inside, a random spanning tree of doors joins every room, then 35% of
  the other neighbouring pairs get a door too, so there are loops rather than a maze. 20% of
  inside doorways are wide arches. Each sits on a random cell edge of the shared wall, at a random
  point along it.
- **Stairs.** Two stairwells, one in each half (west, east) so no way upstairs is too far. Each is
  a 1 x 5 cell stair room at the same place on both storeys, and no cut ever crosses it: bottom landing, a 9 m ramp (20.7°, smooth collision under visual steps),
  top landing. Its only doors are off the bottom landing downstairs and the top landing upstairs.
- **Yard.** Grass round the facility. Gravel paths follow the shortest way from the truck to every
  door, with a lamp post every sixth path cell. 8% of other yard cells get a tree (never
  on a path, by a door or near the truck, and never where it would cut part of the yard off), plus
  scattered rocks and bushes. 2% of yard cells have loot lying out.
- **Light.** A dim blue moon over everything; 45% of rooms have a lamp; the rest need
  flashlights.

For routing, every yard cell is a room of its own, open to its yard neighbours (about 600 of the
site's 700-odd rooms). Monsters route with `Level.route`: a breadth-first search over rooms, lining up 0.9 m in front of
each doorway and stepping through, or walking landing to landing on the stairs. Every room but the
stair room is an empty rectangle, so these straight legs are clear except for loot. Monsters
shove loot in their way (480 N, enough to slide the piano, and it can chip value). If one gets no
closer to its next waypoint for 1.5 s it steps 1.6 m aside, alternating sides. Monsters are on
collision layer 2 and only collide with layer 1, so two never jam each other on the stairs. Loot
never spawns within 2.6 m of a doorway or in the stair room, so the house always starts fully
passable; players can still barricade doors with it.

Joining clients build the same house from the seed (`_request_world` → `_receive_world` →
`_client_ready` in `game.gd`), before their player spawns. `tools/map_view.tscn` renders any seed
and storey from above with the doorways marked.

## Furniture

`scripts/cabinet.gd`, placed by `Level._place_furniture` and built by `game.gd` on every peer from
the seed (`Cabinets/Cabinet<N>`). Up to 1 piece in small rooms, 2 in medium and 4 in large, none
in hallways or stair rooms. Each stands against a wall facing into the room, at least 2.5 m plus
half its width from any doorway (so monster routes, which line up 0.9 m in front of doors, stay
clear) and 0.4 m from other pieces.

- **Cupboard** 1.0 x 2.0 x 0.55 m: two doors that swing out 105° over two shelves.
- **Dresser** 1.2 x 1.0 x 0.5 m: three open-top drawers that slide out 60% of their depth.

Doors and drawers are `AnimatableBody3D`s with their own collision, tagged with meta `cabinet` and
`part` for the player's look-at ray. Opening is host-authoritative: the player asks
(`request_open` → `_request_open`), the host sets the part's bit and broadcasts the cabinet's
open mask (`_set_cabinet`), and after the 0.5 s animation fills the part (`_fill_cabinet`) with
small kinds from `KINDS` through the loot spawner. Late joiners get every mask with the seed and
snap those parts open. Small items use continuous collision so they cannot tunnel through a
drawer bottom, and `fragility` scales knock damage: vials 3x, necklaces 0.5x, gems 0.3x, books
0.2x.


## Network model

Godot high-level multiplayer over ENet, port 7777, up to six players (`scripts/net.gd`).

| Thing | Authority | Replicated properties |
| --- | --- | --- |
| Player body | its own peer | position, rotation, pitch, crouching, held_loot, hold_point |
| Loot physics | host | position, rotation, value (only when changed: there is a lot of loot) |
| Monster | host | position, rotation |
| Banked total and quota | host | sent by the `_set_score` RPC |

The host spawns everything through `MultiplayerSpawner`s with custom spawn functions, so late
joiners receive what already exists. A joining client builds its own copy of the house first,
then asks the host for its player (`_client_ready`), so spawns never arrive before its spawners
exist. Players never move loot directly: they publish *which* loot they hold and *where* it should
go, and the host applies the force. Clients freeze their loot copies.

Movement is trusted to each client. That is fine for co-op among friends and would need host
validation before any public matchmaking.

## Not in the first version

- Voice-cast spells (YAPYAP). Needs offline speech recognition, e.g. a Vosk plugin.
- Proximity voice chat. Needs mic capture streamed over the network with distance falloff.
- Shop, upgrades, multiple levels, and a lobby with names.
