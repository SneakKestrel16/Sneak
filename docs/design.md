# Design

Sneak is a co-op physics-looting game in the spirit of R.E.P.O.: players drag fragile valuables
out of a dark, maze-like house to a truck while monsters hunt them. Voice-cast spells in the style of
YAPYAP and proximity voice chat are planned but not in the first version (decided 2026-10-03).

## Core loop

1. The host rolls a seed and builds the house from it (`scripts/level.gd`); see
   [The house](#the-house). Everyone spawns at the truck bay on the south edge.
2. Loot spawns in every other room, clear of the doorways: one or two items, plus one more in a
   dead end. Value grows 6%
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

A 6x6 grid of 8 m rooms (48 m square). The layout aims to make the way through *not obvious*:

- A randomised depth-first search links the rooms into a maze: exactly one route between any
  two rooms, which leaves long corridors of rooms and dead ends.
- 12% of the walls the maze left solid get a door anyway, adding loops so there is sometimes a
  way around a monster.
- 25% of maze links are a missing wall rather than a door, merging rooms into halls.
- Each doorway sits at a random point along its wall, so you can't see the next door from the
  middle of a room. 60% of rooms are unlit.

Monsters route with `Level.route`: a breadth-first search over the room graph, walking room
centre → a point 0.9 m in front of the door → through it → the next room. Rooms are empty boxes,
so these straight legs are clear except for loot. Monsters shove loot in their way (480 N, enough
to slide the piano, and it can chip value). If one gets no closer to its next waypoint for 1.5 s
it steps 1.6 m aside, alternating sides, and carries on. Loot never spawns within 2.6 m of a
doorway, so the house always starts fully passable; players can still barricade doors with it.

Joining clients build the same house from the seed (`_request_world` → `_receive_world` →
`_client_ready` in `game.gd`), before their player spawns. `tools/map_view.tscn` renders any seed
from above with the doorways marked.

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
