extends Node
## Headless smoke test, run by tools/check.sh. Hosts a session; checks every
## room of the maze is reachable, drags one loot item into the truck with a
## scripted grab, and checks the monsters roam through several rooms rather
## than sticking. Exits 0 on pass, 1 on fail.

const Level := preload("res://scripts/level.gd")

const ROAM_SECONDS := 40.0  ## Simulated, at ROAM_SPEEDUP times real time.
const ROAM_SPEEDUP := 4.0
const CLIMB_SECONDS := 8.0  ## Real time; the ramp is 9.6 m at 1.8 m/s.
const ROAM_ROOMS := 3  ## Rooms each monster must pass through in that time.

var _failed := false


func _ready() -> void:
	# Add the game beside this node rather than changing scene: a scene change
	# would free this node (the current scene) and the test would never quit.
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(game)
	get_tree().set_deferred("current_scene", game)
	for i in 10:
		await get_tree().physics_frame
	var player := game.get_node_or_null("Players/1") as Player
	# The first item one player can lift: the piano needs two by design, so picking
	# whatever spawned first made this test fail at random.
	var loot: Loot = null
	var gravity := ProjectSettings.get_setting("physics/3d/default_gravity") as float
	for node in get_tree().get_nodes_in_group("loot"):
		var candidate := node as Loot
		if candidate.mass * gravity < Loot.MAX_FORCE:
			loot = candidate
			break
	var level: Level = game.get("level")
	var reachable := level.distances_from(level.spawn_room).size()
	var rooms := level.room_count()
	_check(reachable == rooms, "every room is reachable (%d of %d)" % [reachable, rooms])
	_check(game.get_node_or_null("Monsters/Monster2") != null, "all three monsters spawned")
	if _check(player != null and loot != null, "host spawned a player and loot"):
		# Stop the player's own input from clearing the grab, then hold the
		# loot above the truck, starting from beside it in the spawn room.
		player.set_physics_process(false)
		var truck: Vector3 = game.get("level").truck
		loot.global_position = truck + Vector3(1.2, 0.0, -2.5)
		player.held_loot = loot.name
		player.hold_point = truck
		var value := loot.value
		for i in 240:
			await get_tree().physics_frame
		var banked: int = game.get("banked")
		_check(
			banked > 0 and banked <= value, "dragged loot was banked ($%d of $%d)" % [banked, value]
		)
		_check(not is_instance_valid(loot), "banked loot was removed")

	# Park the player out of sight so the monsters roam instead of chasing.
	player.global_position = level.truck + Vector3(0, 0.5, 0)
	var visited := {}
	Engine.time_scale = ROAM_SPEEDUP
	# time_scale stretches each physics step rather than adding steps.
	for i in roundi(ROAM_SECONDS * Engine.physics_ticks_per_second / ROAM_SPEEDUP):
		await get_tree().physics_frame
		for node in game.get_node("Monsters").get_children():
			var monster := node as Monster
			if monster:
				var seen: Dictionary = visited.get_or_add(monster.name, {})
				seen[level.room_at(monster.global_position)] = true
	Engine.time_scale = 1.0

	# The stairs: walk a monster from the bottom landing to upstairs.
	var climber := game.get_node("Monsters/Monster0") as Monster
	var stairs := level.stair_rooms()
	climber.global_position = level.anchor(stairs[0]) + Vector3.UP * 0.2
	climber.set("_route", level.route(stairs[0], stairs[1]))
	climber.set("_rest_left", 1000.0)  # Do not chase anyone meanwhile.
	for i in roundi(CLIMB_SECONDS * Engine.physics_ticks_per_second):
		await get_tree().physics_frame
	var upstairs := level.floor_of(level.room_at(climber.global_position))
	_check(
		upstairs == 1, "a monster climbed the stairs (now at y %.1f)" % climber.global_position.y
	)
	for monster_name: String in visited:
		var count: int = visited[monster_name].size()
		_check(count >= ROAM_ROOMS, "%s roamed through %d rooms" % [monster_name, count])
	print("SMOKE FAIL" if _failed else "SMOKE PASS")
	get_tree().quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> bool:
	print(("ok   " if ok else "FAIL ") + what)
	_failed = _failed or not ok
	return ok
