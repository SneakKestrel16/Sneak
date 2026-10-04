# Design

Sneak is a co-op physics-looting game in the spirit of R.E.P.O.: players drag fragile valuables
out of a dark house to a truck while a monster hunts them. Voice-cast spells in the style of
YAPYAP and proximity voice chat are planned but not in the first version (decided 2026-10-03).

## Core loop

1. The host builds the house (`scripts/level.gd`): a 3x3 grid of rooms with a doorway in every
   inner wall. Everyone spawns in the south room beside the truck bay.
2. Loot spawns in the other eight rooms (`KINDS` in `scripts/game.gd`). The quota is half the
   house's total value, rounded to $10.
3. Players hold the left mouse button on loot to drag it (`scripts/player.gd`). Every knock
   chips value; at $0 it breaks (`scripts/loot.gd`). Heavy loot needs several players, because
   each holder adds at most 400 N.
4. Loot dropped in the truck bay is banked. Meeting the quota is announced; the run carries on.
5. The monster (`scripts/monster.gd`) walks room to room and chases any player it can see within
   14 m, or 4 m if they are crouching. Walls and loot block its view. A catch sends the player back
   to the truck and drops what they held.

## Network model

Godot high-level multiplayer over ENet, port 7777, up to six players (`scripts/net.gd`).

| Thing | Authority | Replicated properties |
| --- | --- | --- |
| Player body | its own peer | position, rotation, pitch, crouching, held_loot, hold_point |
| Loot physics | host | position, rotation, value |
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
- Pathfinding. The monster walks centre to centre, which passes through doorways; it re-centres
  in its room when a chase leaves it against a wall.
- Shop, upgrades, multiple levels, and a lobby with names.
