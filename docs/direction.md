# Direction

Where Sneak stands, where it is heading, and in what order. [Design](design.md) says how the game
works today; this page says what to build next and why. Written 2026-10-03 from the repository as
of commit `51e1d2c`. The milestone order below is a proposal, not a decision: anything not marked
*decided* is open until the user settles it.

## The goal

A co-op horror-looting game for a few friends: R.E.P.O.'s physics looting (drag fragile
valuables out under a quota while monsters hunt you), later joined by YAPYAP-style voice-cast
spells and proximity voice chat. Online co-op is a hard constraint from the first line of code,
not a feature to retrofit (decided; see [Network model](design.md#network-model)).

## Where it stands

Built and covered by the smoke test (`tests/smoke.gd`):

- **Co-op session.** ENet host/join for up to six, host-authoritative loot, monsters and
  furniture; each peer owns its player. Late joiners build the site from the seed.
- **The site.** A seeded, walled 102 x 84 m compound: one two-storey facility of BSP rooms with
  varied floors, two stairwells, a yard with paths, trees and lamps, and a truck bay. Every room
  is reachable and every room is passable at spawn.
- **Looting.** Drag with the mouse, several holders for heavy items, value chipped by knocks and
  scaled by fragility, banking in the truck, a quota of half the value lying out.
- **Furniture.** Cupboards and dressers open for everyone and reveal small valuables.
- **Monsters.** Three roam room-to-room routes, see players (less when crouching), chase, and
  send a caught player back to the truck.
- **Tools.** `showcase` renders models; `map_view` renders a seed from above; prek runs format,
  lint and the smoke test.

What the loop lacks (from [Design](design.md#core-loop) and a search of `scripts/`):

- **No end to a run.** Meeting the quota is announced and "the run carries on"; nothing ends it,
  wins it or loses it.
- **No stakes.** Being caught costs only the walk back and what you held. There is no health,
  death, spectating or timer.
- **No sound at all.** No footsteps, monster cues, loot impacts or ambience. A stealth game with
  monsters that hunt by sight alone is missing half its information (inference: no `Audio*` node
  appears anywhere in `scripts/`).
- **Monsters only see.** They do not hear noise, so crouching and careful carrying matter less
  than they should.
- **No progression.** No shop, upgrades, money between runs or multiple levels (listed under
  [Not in the first version](design.md#not-in-the-first-version)).
- **No lobby.** Players have no names, and the host starts straight into a site.

## Principles

These follow from decisions already in the docs and the commit history.

1. **Every slice is playable co-op.** A feature is not done until host and client both see it,
   including a late joiner.
2. **The seed builds the world.** Layout and props come from `Level`'s RNG in the same order on
   every peer; anything that moves comes from the host.
3. **The smoke test grows with the game.** Each feature adds a check that fails when it breaks,
   and a render (`showcase`, `map_view`) whenever the change is visual.
4. **The loop before the content.** A finished short run beats a bigger site with no ending; the
   last three commits grew the site, so the next ones should close the loop.
5. **Voice later, but not blocked.** Nothing built now should assume input comes only from keys,
   so spells can bind to the same actions later.

## Milestones

Proposed order. Each one is small enough to be one or two commits and ends in something to play.

### 1. A run that ends

Extraction makes the loop whole: the run ends when everyone is back at the truck with the quota
met, or fails when everyone is down or time runs out. Needs a host-owned run state (playing,
extracted, failed) broadcast like the score, a results screen with banked value per run, and
back to the menu or a new seed. Open question: a timer, or only the monsters as pressure?

### 2. Stakes when caught

Health with downed players, revive by a teammate, and spectating while down, instead of the free
trip back to the truck. Open question: does a catch down you outright, or hurt you (R.E.P.O.
uses health; inference from the genre, not checked against the game)?

### 3. Sound

Footsteps by surface (the floors already differ by room kind), loot impacts scaled by damage,
monster idle and chase cues, door and drawer sounds, ambience. Positional `AudioStreamPlayer3D`s,
played on every peer from replicated state, so no new network traffic. Needs a source of
free-to-use sounds, or generated ones; record their licences in `docs/`.

### 4. Monsters that hear

Sprinting, impacts and opening furniture make noise events on the host; a monster within range
goes to investigate the spot before resuming its route. This is what makes crouching, carrying
gently and choosing when to open a cupboard into decisions. Extend the smoke test with a scripted
noise that draws a monster.

### 5. Lobby and between-run loop

A lobby with names and a ready check, then money carried between runs, a shop with a few
upgrades (stronger grip, stamina, a brighter flashlight), and rising quotas. Variety in sites
(other building kinds or themes) fits here, since the generator can already produce them.

### 6. Voice

Proximity voice chat first, since it serves every player in every run; then voice-cast spells
with offline speech recognition (a Vosk plugin is the candidate named in
[Design](design.md#not-in-the-first-version)). Both need a spike to prove mic capture and
recognition work in Godot 4.7 on Windows before planning further.

## Not planned

- **Public matchmaking.** Movement is trusted to each client, which is fine among friends and
  would need host validation first ([Network model](design.md#network-model)).
- **Hand-made levels.** The generator is the level design; new places come from new rules.

## Open questions

- How long should a run be? This sets the site size, the quota and the timer, if any.
- Is the site big enough already? The last three commits each grew it; play-testing with two
  players would settle whether the next run needs more room or more danger.
- Does the game end after a set number of runs, or go on with rising quotas like R.E.P.O.?
