extends Node3D
## One co-op run. Builds the house, hosts or joins (Net), then the host spawns
## players, loot and the monster through MultiplayerSpawners so late joiners
## get them too. Bank loot in the truck until the quota is met.
## How authority is split between peers is in docs/design.md.

const Level := preload("res://scripts/level.gd")

const LOOT_PER_ROOM := 3
const QUOTA_SHARE := 0.5  ## Share of the house's total value the quota asks for.
## Value is a min..max range. One player holds up to Loot.MAX_FORCE (400 N),
## so the piano (70 kg, ~690 N to lift) takes two.
const KINDS: Array[Dictionary] = [
	{
		"name": "vase",
		"size": Vector3(0.35, 0.55, 0.35),
		"mass": 2.0,
		"value": Vector2i(150, 300),
		"color": Color(0.3, 0.55, 0.9),
	},
	{
		"name": "painting",
		"size": Vector3(1.0, 0.8, 0.08),
		"mass": 4.0,
		"value": Vector2i(80, 200),
		"color": Color(0.85, 0.7, 0.3),
	},
	{
		"name": "crate",
		"size": Vector3(0.7, 0.7, 0.7),
		"mass": 15.0,
		"value": Vector2i(40, 120),
		"color": Color(0.55, 0.38, 0.2),
	},
	{
		"name": "grandfather clock",
		"size": Vector3(0.5, 1.7, 0.4),
		"mass": 30.0,
		"value": Vector2i(200, 400),
		"color": Color(0.4, 0.25, 0.15),
	},
	{
		"name": "piano",
		"size": Vector3(1.6, 1.1, 0.7),
		"mass": 70.0,
		"value": Vector2i(500, 800),
		"color": Color(0.1, 0.1, 0.1),
	},
]
const CONTROLS := {
	"move_forward": KEY_W,
	"move_back": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"sprint": KEY_SHIFT,
	"crouch": KEY_CTRL,
	"jump": KEY_SPACE,
}

var banked := 0
var quota := 0

var _players: MultiplayerSpawner
var _loot: MultiplayerSpawner
var _monsters: MultiplayerSpawner
var _score: Label
var _message: Label
var _message_left := 0.0


func _ready() -> void:
	add_to_group("hud")
	for action: String in CONTROLS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var key := InputEventKey.new()
			key.physical_keycode = CONTROLS[action]
			InputMap.action_add_event(action, key)

	var truck := Level.build(self)
	truck.body_entered.connect(_on_truck_body_entered)
	_players = _spawner("Players", _spawn_player)
	_loot = _spawner("Loot", _spawn_loot)
	_monsters = _spawner("Monsters", _spawn_monster)
	_build_hud()

	multiplayer.peer_connected.connect(func(id: int) -> void: print("[net] peer %d joined" % id))
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func() -> void: _client_ready.rpc_id(1))

	var error := Net.start()
	if error != OK:
		var reason := "Could not start the session (%s)." % error_string(error)
		if Net.hosting and error == ERR_CANT_CREATE:
			reason = "Port %d is already in use. Is another Sneak still running?" % Net.port
		Net.stop.call_deferred(reason)
		return
	if multiplayer.is_server():
		_host_setup()
	else:
		flash("Connecting to %s:%d..." % [Net.address, Net.port], 10.0)


func _process(delta: float) -> void:
	_message_left -= delta
	_message.visible = _message_left > 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Net.stop("")


## Shows text in the middle of the screen for a few seconds.
func flash(text: String, seconds := 3.0) -> void:
	_message.text = text
	_message_left = seconds


func _host_setup() -> void:
	var rng := RandomNumberGenerator.new()
	var total := 0
	var index := 0
	for room in Level.loot_rooms():
		for i in LOOT_PER_ROOM:
			var kind := rng.randi() % KINDS.size()
			var values: Vector2i = KINDS[kind]["value"]
			var value := rng.randi_range(values.x, values.y)
			var spot := Vector3(rng.randf_range(-3.5, 3.5), 1.0, rng.randf_range(-3.5, 3.5))
			(
				_loot
				. spawn(
					{
						"name": "Loot%d" % index,
						"kind": kind,
						"value": value,
						"position": Level.room_center(room) + spot,
					}
				)
			)
			total += value
			index += 1
	_set_score(0, roundi(total * QUOTA_SHARE / 10.0) * 10)
	_monsters.spawn(Level.room_center(Level.MONSTER_ROOM))
	_players.spawn(1)


func _spawner(container_name: String, spawn: Callable) -> MultiplayerSpawner:
	var container := Node3D.new()
	container.name = container_name
	add_child(container)
	var spawner := MultiplayerSpawner.new()
	# Explicit name: auto-generated ones differ between peers and replication matches by path.
	spawner.name = "Spawner"
	spawner.spawn_function = spawn
	container.add_child(spawner)
	spawner.spawn_path = NodePath("..")
	return spawner


func _spawn_player(id: int) -> Node:
	var player := Player.new()
	player.name = str(id)
	player.position = Level.SPAWN + Vector3(float(id % 5) - 2.0, 0, 0)
	Net.replicate(player, ["position", "rotation", "pitch", "crouching", "held_loot", "hold_point"])
	player.set_multiplayer_authority(id)
	print("[spawn] player %d" % id)
	return player


func _spawn_loot(data: Dictionary) -> Node:
	var kind: Dictionary = KINDS[data["kind"]]
	var loot := Loot.new()
	loot.name = data["name"]
	loot.position = data["position"]
	loot.size = kind["size"]
	loot.mass = kind["mass"]
	loot.color = kind["color"]
	loot.base_value = data["value"]
	loot.value = data["value"]
	Net.replicate(loot, ["position", "rotation", "value"])
	return loot


func _spawn_monster(at: Vector3) -> Node:
	var monster := Monster.new()
	monster.name = "Monster"
	monster.position = at
	Net.replicate(monster, ["position", "rotation"])
	return monster


## A joining client asks for its player once its copy of the game is built,
## so spawns never arrive before its spawners exist.
@rpc("any_peer", "reliable")
func _client_ready() -> void:
	var id := multiplayer.get_remote_sender_id()
	_players.spawn(id)
	_set_score.rpc_id(id, banked, quota)
	_welcome.rpc_id(id)


## Clears the "Connecting..." message on the client that just joined.
@rpc("authority", "reliable")
func _welcome() -> void:
	flash("Joined. Find the loot, bring it to the truck.")


@rpc("authority", "call_local", "reliable")
func _set_score(new_banked: int, new_quota: int) -> void:
	var was_met := quota > 0 and banked >= quota
	banked = new_banked
	quota = new_quota
	_score.text = "Banked $%d / $%d" % [banked, quota]
	if quota > 0 and banked >= quota and not was_met:
		flash("Quota met! Keep looting or call it a night.")


func _on_truck_body_entered(body: Node3D) -> void:
	var loot := body as Loot
	if not multiplayer.is_server() or loot == null or loot.is_queued_for_deletion():
		return
	_set_score.rpc(banked + loot.value, quota)
	loot.queue_free()


func _on_peer_disconnected(id: int) -> void:
	print("[net] peer %d left" % id)
	var player := _players.get_node_or_null("../%d" % id)
	if multiplayer.is_server() and player:
		player.queue_free()


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	add_child(hud)
	_score = Label.new()
	_score.position = Vector2(24, 18)
	_score.add_theme_font_size_override("font_size", 28)
	hud.add_child(_score)

	var crosshair := Label.new()
	crosshair.text = "·"
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.add_theme_font_size_override("font_size", 32)
	hud.add_child(crosshair)

	_message = Label.new()
	_message.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_message.position.y = 120
	_message.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_message.add_theme_font_size_override("font_size", 36)
	_message.visible = false
	hud.add_child(_message)

	var hint := Label.new()
	hint.text = "Hold LMB: drag · Wheel: distance · Ctrl: sneak · Esc: mouse / leave"
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.position.y -= 40
	hint.modulate = Color(1, 1, 1, 0.5)
	hud.add_child(hint)
