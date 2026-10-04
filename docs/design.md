# Design

Sneak is a co-op physics-looting game in the spirit of R.E.P.O.: players drag fragile valuables
out of a dark two-storey house to a truck while monsters hunt them. Voice-cast spells in the style of
YAPYAP and proximity voice chat are planned but not in the first version (decided 2026-10-03).

## Core loop

1. The host rolls a seed and builds the house from it (`scripts/level.gd`); see
   [The house](#the-house). Everyone spawns at the truck bay on the south edge.
2. Loot spawns in every room but the truck's and the stairs, clear of the doorways: one or two
   items, one more in rooms of 120 m² or more, and one more in a dead end. Value grows 6%
   per room away from the truck, so deep runs pay (`_host_setup` in `scripts/game.gd`). The quota
   is half the house's total value, rounded to $10.
3. Players hold the left mouse button on loot to drag it (`scripts/player.gd`). Every knock
   chips value; at $0 it breaks (`scripts/loot.gd`). Heavy loot needs several players, because
   each holder adds at most 400 N.
4. Loot dropped in the truck bay is banked. Meeting the quota is announced; the run carries on.
5. Two monsters (`scripts/monster.gd`) start in the rooms farthest from the truck. They roam
   along routes two to six rooms long and chase any player they can see within 14 m, or 4 m if
   the player is crouching. Walls and loot block their view. A catch sends the player back to
   the truck and drops what they held.

## The house

Two storeys on a 16x12 grid of 3 m cells (48 x 36 m), generated from a seed in
`scripts/level.gd`. Replaced a 6x6 grid maze on 2026-10-04, which the user found too maze-like;
the aim now is a building you explore room by room.

- **Rooms of varying size.** Each storey is split recursively (binary space partition): cuts
  mostly go across the longer side, never leave a side under 2 cells, and stop at random once a
  piece is 24 cells or less. Rooms are classed by shape: *hallway* (1 cell wide, or 2 wide and
  6+ long), *small* (up to 4 cells), *large* (15+), otherwise *medium*.
- **Different floors.** Each kind has its own surface, projected in world space so it tiles the
  same in any size of room: parquet in large rooms, carpet (one colour per house) in medium ones,
  pale tile in small ones, dark boards in hallways, concrete on the stairs. Ground and upper
  storeys have different wall colours.
- **Doors.** A random spanning tree of doors joins every room on a storey, then 35% of the other
  neighbouring pairs get a door too, so there are loops rather than a maze. 20% of doorways are
  wide arches. Each sits on a random cell edge of the shared wall, at a random point along it.
- **Stairs.** A 1 x 5 cell stair room sits at the same place on both storeys and no cut ever
  crosses it: bottom landing, a 9 m ramp (20.7°, smooth collision under visual steps), top
  landing. Its only doors are off the bottom landing downstairs and the top landing upstairs.
- **Light.** 45% of rooms have a lamp; the rest need flashlights.

Monsters route with `Level.route`: a breadth-first search over rooms, lining up 0.9 m in front of
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
