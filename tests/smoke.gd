extends Node
## Headless smoke test, run by tools/check.sh. Hosts a session, drags one loot
## item into the truck with a scripted grab, and checks it was banked and the
## monster exists. Exits 0 on pass, 1 on fail.

const Level := preload("res://scripts/level.gd")

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
	_check(game.get_node_or_null("Monsters/Monster") != null, "monster spawned")
	if _check(player != null and loot != null, "host spawned a player and loot"):
		# Stop the player's own input from clearing the grab, then hold the
		# loot above the truck, starting from beside it in the spawn room.
		player.set_physics_process(false)
		loot.global_position = Level.TRUCK + Vector3(3.0, 0.0, -2.5)
		player.held_loot = loot.name
		player.hold_point = Level.TRUCK
		var value := loot.value
		for i in 240:
			await get_tree().physics_frame
		var banked: int = game.get("banked")
		_check(
			banked > 0 and banked <= value, "dragged loot was banked ($%d of $%d)" % [banked, value]
		)
		_check(not is_instance_valid(loot), "banked loot was removed")
	print("SMOKE FAIL" if _failed else "SMOKE PASS")
	get_tree().quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> bool:
	print(("ok   " if ok else "FAIL ") + what)
	_failed = _failed or not ok
	return ok
