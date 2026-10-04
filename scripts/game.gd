extends Node3D
## One co-op run. Hosts or joins (Net); the host rolls the site's seed, and
## each joining client builds the same site from it before asking for its
## player. The host spawns players, loot and monsters through
## MultiplayerSpawners so late joiners get them too, and fills cupboards and
## drawers as they are opened. Bank loot in the truck until the quota is met.
## How authority is split between peers is in docs/design.md.

const Level := preload("res://scripts/level.gd")

const MONSTERS := 3
const DOOR_CLEARANCE := 2.6  ## Loot spawns at least this far from a doorway, so none is blocked.
const BIG_ROOM := 120.0  ## Square metres; rooms this big get an extra item.
## Extra value per step (room or yard cell) away from the truck, so deep runs pay.
const DEPTH_BONUS := 0.02
const YARD_LOOT := 0.02  ## Chance an open yard cell has something worth taking.
const QUOTA_SHARE := 0.5  ## Share of the loot lying out that the quota asks for.
const EMPTY_CHANCE := 0.2  ## Chance an opened door or drawer holds nothing.
## Value is a min..max range. One player holds up to Loot.MAX_FORCE (400 N),
## so the piano (70 kg, ~690 N to lift) takes two. "small" kinds are only found
## in cupboards and drawers, in one of their "tints". "fragility" scales the
## value lost per knock (default 1).
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
	{
		"name": "gem",
		"size": Vector3(0.12, 0.12, 0.12),
		"mass": 0.1,
		"value": Vector2i(250, 500),
		"color": Color(0.85, 0.1, 0.25),
		"tints": [Color(0.85, 0.1, 0.25), Color(0.1, 0.75, 0.35), Color(0.15, 0.35, 0.95)],
		"small": true,
		"fragility": 0.3,  # Hard stone: knocks barely mark it.
	},
	{
		"name": "necklace",
		"size": Vector3(0.22, 0.04, 0.2),
		"mass": 0.2,
		"value": Vector2i(180, 400),
		"color": Color(0.85, 0.66, 0.2),
		"tints": [Color(0.85, 0.66, 0.2), Color(0.8, 0.8, 0.82)],
		"small": true,
		"fragility": 0.5,
	},
	{
		"name": "book",
		"size": Vector3(0.18, 0.05, 0.25),
		"mass": 0.8,
		"value": Vector2i(20, 90),
		"color": Color(0.45, 0.12, 0.1),
		"tints": [Color(0.45, 0.12, 0.1), Color(0.12, 0.2, 0.4), Color(0.15, 0.3, 0.15)],
		"small": true,
		"fragility": 0.2,
	},
	{
		"name": "vial",
		"size": Vector3(0.06, 0.16, 0.06),
		"mass": 0.15,
		"value": Vector2i(120, 260),
		"color": Color(0.3, 0.9, 0.5),
		"tints": [Color(0.3, 0.9, 0.5), Color(0.8, 0.2, 0.9), Color(0.95, 0.6, 0.1)],
		"small": true,
		"fragility": 3.0,  # Glass: handle with care.
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
	"interact": KEY_E,
}

var banked := 0
var quota := 0
var level: Level  ## Built once the seed is known (at once on the host).

var _seed := 0
var _next_loot := 0  ## Loot node names must be unique for replication.
var _host_rng := RandomNumberGenerator.new()  ## What cabinets hold; host only.
var _cabinets: Array[Cabinet] = []

var _players: MultiplayerSpawner
var _loot: MultiplayerSpawner
var _monsters: MultiplayerSpawner
var _score: Label
var _message: Label
var _message_left := 0.0
var _prompt: Label


func _ready() -> void:
	add_to_group("hud")
	for action: String in CONTROLS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var key := InputEventKey.new()
			key.physical_keycode = CONTROLS[action]
			InputMap.action_add_event(action, key)

	_players = _spawner("Players", _spawn_player)
	_loot = _spawner("Loot", _spawn_loot)
	_monsters = _spawner("Monsters", _spawn_monster)
	_build_hud()

	multiplayer.peer_connected.connect(func(id: int) -> void: print("[net] peer %d joined" % id))
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func() -> void: _request_world.rpc_id(1))

	var error := Net.start()
	if error != OK:
		var reason := "Could not start the session (%s)." % error_string(error)
		if Net.hosting and error == ERR_CANT_CREATE:
			reason = "Port %d is already in use. Is another Sneak still running?" % Net.port
		Net.stop.call_deferred(reason)
		return
	if multiplayer.is_server():
		_seed = randi()
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--seed="):
				_seed = arg.trim_prefix("--seed=").to_int()  # Replays a house, e.g. a failing test.
		print("[level] seed %d" % _seed)
		_build_level()
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


## Shows a hint under the crosshair, or hides it with "".
func prompt(text: String) -> void:
	_prompt.text = text


## Asks the host to open a cabinet's door or drawer (called by the local player).
func request_open(cabinet: int, part: int) -> void:
	_request_open.rpc_id(1, cabinet, part)


## Shows text in the middle of the screen for a few seconds.
func flash(text: String, seconds := 3.0) -> void:
	_message.text = text
	_message_left = seconds


func _build_level() -> void:
	level = Level.new(_seed)
	level.build(self).body_entered.connect(_on_truck_body_entered)
	var holder := Node3D.new()
	holder.name = "Cabinets"
	add_child(holder)
	for i in level.furniture.size():
		var piece := level.furniture[i]
		var cabinet := Cabinet.new()
		cabinet.name = "Cabinet%d" % i
		cabinet.index = i
		cabinet.type = piece["type"]
		cabinet.position = piece["position"]
		cabinet.rotation.y = piece["yaw"]
		holder.add_child(cabinet)
		_cabinets.append(cabinet)


## Loot lies out in every room but the stairs: more in dead ends, worth more
## the deeper it is; a little in the yard. Cupboards and drawers are filled when
## opened. Monsters start in the indoor rooms farthest from the truck.
func _host_setup() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	_host_rng.seed = _seed + 1
	var big := _kinds(false)
	var distance := level.distances_from(level.spawn_room)
	var total := 0
	for room: int in distance:
		if room == level.spawn_room or level.is_stairs(room) or level.kind(room) == "path":
			continue
		var area := level.room_bounds(room).get_area()
		var count := 1 + rng.randi() % 2 + (1 if area >= BIG_ROOM else 0)
		count += 1 if level.neighbours(room).size() == 1 else 0  # Dead ends pay.
		if level.is_outdoors(room):
			count = 1 if rng.randf() < YARD_LOOT else 0
		for i in count:
			var kind: int = big[rng.randi() % big.size()]
			var values: Vector2i = KINDS[kind]["value"]
			var depth: int = distance[room]
			var value := roundi(rng.randi_range(values.x, values.y) * (1.0 + DEPTH_BONUS * depth))
			var data := {
				"name": "Loot%d" % _next_loot,
				"kind": kind,
				"value": value,
				"position": _clear_spot(rng, room),
			}
			_loot.spawn(data)
			total += value
			_next_loot += 1
	_set_score(0, roundi(total * QUOTA_SHARE / 10.0) * 10)

	var far_first: Array = distance.keys().filter(
		func(room: int) -> bool: return not level.is_stairs(room) and not level.is_outdoors(room)
	)
	far_first.sort_custom(func(a: int, b: int) -> bool: return distance[a] > distance[b])
	for i in MONSTERS:
		_monsters.spawn({"name": "Monster%d" % i, "position": level.anchor(far_first[i])})
	_players.spawn(_player_data(1))


## A random point in room, at least DOOR_CLEARANCE from its doorways and clear
## of furniture. A piano spawned in a dead end's only doorway sealed it,
## monsters included.
func _clear_spot(rng: RandomNumberGenerator, room: int) -> Vector3:
	var bounds := level.room_bounds(room).grow(-1.0)
	var spot := Vector3.ZERO
	for attempt in 20:
		var x := rng.randf_range(bounds.position.x, bounds.end.x)
		var z := rng.randf_range(bounds.position.y, bounds.end.y)
		spot = Vector3(x, level.floor_height(room), z)
		var clear := true
		for door in level.doors(room):
			if spot.distance_to(door) < DOOR_CLEARANCE:
				clear = false
		for piece in level.furniture_in(room):
			if spot.distance_to(piece["position"]) < 1.5:
				clear = false
		if clear:
			break
	return spot + Vector3.UP


func _player_data(id: int) -> Dictionary:
	var row := _players.get_parent().get_child_count() - 1  # Minus the spawner.
	return {"id": id, "position": level.spawn + Vector3(float(row % 4) - 1.5, 0, 0)}


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


# Spawn functions run on every peer, maybe before that peer has built the house,
# so everything they need comes in the spawn data.
func _spawn_player(data: Dictionary) -> Node:
	var id: int = data["id"]
	var player := Player.new()
	player.name = str(id)
	player.position = data["position"]
	Net.replicate(player, ["position", "rotation", "pitch", "crouching", "held_loot", "hold_point"])
	player.set_multiplayer_authority(id)
	print("[spawn] player %d" % id)
	return player


func _spawn_loot(data: Dictionary) -> Node:
	var kind: Dictionary = KINDS[data["kind"]]
	var loot := Loot.new()
	loot.name = data["name"]
	loot.position = data["position"]
	loot.kind = kind["name"]
	loot.size = kind["size"]
	loot.mass = kind["mass"]
	loot.color = data.get("color", kind["color"])
	loot.fragility = kind.get("fragility", 1.0)
	loot.base_value = data["value"]
	loot.value = data["value"]
	# On change: most loot sits still, and there is a lot of it.
	var on_change := SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE
	Net.replicate(loot, ["position", "rotation", "value"], on_change)
	return loot


func _spawn_monster(data: Dictionary) -> Node:
	var monster := Monster.new()
	monster.name = data["name"]
	monster.position = data["position"]
	monster.level = level  # Null on a client that has not built yet; clients never think.
	Net.replicate(monster, ["position", "rotation"])
	return monster


## Joining, step 1: a connected client asks for the site's seed and which
## cabinet doors and drawers are already open.
@rpc("any_peer", "reliable")
func _request_world() -> void:
	var opened := PackedInt32Array()
	for cabinet in _cabinets:
		opened.append(cabinet.opened)
	_receive_world.rpc_id(multiplayer.get_remote_sender_id(), _seed, opened)


## Step 2: the client builds the same site, then asks for its player, so it
## never spawns over a floor that is not there yet.
@rpc("authority", "reliable")
func _receive_world(seed_value: int, opened: PackedInt32Array) -> void:
	_seed = seed_value
	_build_level()
	for i in opened.size():
		_cabinets[i].set_opened(opened[i], false)
	_client_ready.rpc_id(1)


## Step 3: the host spawns the player and sends the score.
@rpc("any_peer", "reliable")
func _client_ready() -> void:
	var id := multiplayer.get_remote_sender_id()
	_players.spawn(_player_data(id))
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


@rpc("any_peer", "call_local", "reliable")
func _request_open(cabinet: int, part: int) -> void:
	if not multiplayer.is_server() or cabinet < 0 or cabinet >= _cabinets.size():
		return
	var target := _cabinets[cabinet]
	var bit := 1 << part
	if part < 0 or part >= target.part_count() or (target.opened & bit) != 0:
		return
	_set_cabinet.rpc(cabinet, target.opened | bit)
	# Fill it once the door has swung or the drawer slid out.
	var fill := _fill_cabinet.bind(cabinet, part)
	get_tree().create_timer(Cabinet.OPEN_TIME + 0.1).timeout.connect(fill)


@rpc("authority", "call_local", "reliable")
func _set_cabinet(cabinet: int, mask: int) -> void:
	_cabinets[cabinet].set_opened(mask, true)


## Puts small valuables (gems, necklaces, books, vials) in a freshly opened
## door or drawer, sometimes nothing. Host only.
func _fill_cabinet(cabinet: int, part: int) -> void:
	if _host_rng.randf() < EMPTY_CHANCE:
		return
	var spots := _cabinets[cabinet].content_spots(part)
	var small := _kinds(true)
	for i in _host_rng.randi_range(1, spots.size()):
		var kind: int = small[_host_rng.randi() % small.size()]
		var info: Dictionary = KINDS[kind]
		var values: Vector2i = info["value"]
		var tints: Array = info["tints"]
		var size: Vector3 = info["size"]
		var data := {
			"name": "Loot%d" % _next_loot,
			"kind": kind,
			"value": _host_rng.randi_range(values.x, values.y),
			"position": spots[i] + Vector3.UP * (size.y / 2.0 + 0.01),
			"color": tints[_host_rng.randi() % tints.size()],
		}
		_loot.spawn(data)
		_next_loot += 1


## Indexes into KINDS of the small (cabinet) kinds, or of the rest.
static func _kinds(small: bool) -> Array[int]:
	var found: Array[int] = []
	for i in KINDS.size():
		if KINDS[i].get("small", false) == small:
			found.append(i)
	return found


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

	_prompt = Label.new()
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.position.y += 36
	_prompt.add_theme_font_size_override("font_size", 22)
	hud.add_child(_prompt)

	var hint := Label.new()
	hint.text = "Hold LMB: drag · Wheel: distance · E: open · Ctrl: sneak · Esc: mouse / leave"
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.position.y -= 40
	hint.modulate = Color(1, 1, 1, 0.5)
	hud.add_child(hint)
