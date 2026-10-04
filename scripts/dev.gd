extends CanvasLayer
## Developer mode: a panel for testing without playing a whole run. Spawn any
## loot or monster where you look, steer or freeze the monsters, fly through
## walls, go unseen, open every cabinet, fill the quota, light the house or
## start over on a new site.
##
## Turned on by the main menu's "Developer mode" box or `-- --dev`, and only on
## the host, which owns everything the panel changes (docs/design.md#network-model).
## F1 shows or hides it and frees the mouse; Esc hides it.

const Level := preload("res://scripts/level.gd")
const GAME := preload("res://scripts/game.gd")

var game: Node3D  ## The game scene (scripts/game.gd), set before this is added.

var _panel: PanelContainer
var _status: Label
var _loot_kind: OptionButton
var _monster_kind: OptionButton
var _status_left := 0.0
var _lit := false


func _ready() -> void:
	layer = 10
	_panel = PanelContainer.new()
	_panel.position = Vector2(16, 64)
	_panel.custom_minimum_size = Vector2(330, 0)
	_panel.visible = false
	add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(330, 760)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)

	_heading(column, "DEVELOPER MODE  (F1)")
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 13)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	column.add_child(_status)

	_heading(column, "Spawn where you look")
	_loot_kind = OptionButton.new()
	for kind: Dictionary in GAME.KINDS:
		_loot_kind.add_item(kind["name"])
	column.add_child(_loot_kind)
	_button(column, "Spawn loot", _spawn_loot)
	_monster_kind = OptionButton.new()
	for variant in Monster.VARIANTS:
		_monster_kind.add_item(variant)
	column.add_child(_monster_kind)
	_button(column, "Spawn monster", _spawn_monster)

	_heading(column, "Monsters")
	_toggle(column, "Freeze all", _freeze_monsters)
	_button(column, "Send all to me", _summon_monsters)
	_button(column, "Calm all for 30 s", _calm_monsters)
	_button(column, "Remove all", _remove_monsters)

	_heading(column, "Me")
	_toggle(column, "Unseen (monsters ignore me)", func(on: bool) -> void: _me().unseen = on)
	_toggle(column, "Fly through walls (Space up, Ctrl down)", _fly)
	_toggle(
		column,
		"Run three times as fast",
		func(on: bool) -> void: _me().speed_scale = 3.0 if on else 1.0
	)
	_button(column, "Teleport to the truck", func() -> void: _teleport(game.level.spawn))
	_button(column, "Teleport to the farthest room", _teleport_far)
	_button(column, "Teleport to the most valuable loot", _teleport_to_loot)
	_button(column, "Get caught", func() -> void: _me().caught(game.level.spawn))

	_heading(column, "World")
	_button(column, "Open every cupboard and drawer", func() -> void: game.open_everything())
	_button(column, "Bank $100", func() -> void: game.add_banked(100))
	_button(
		column, "Meet the quota", func() -> void: game.add_banked(maxi(game.quota - game.banked, 0))
	)
	_toggle(column, "Light everything", _light)
	var speeds := HBoxContainer.new()
	column.add_child(speeds)
	for speed: float in [0.25, 1.0, 3.0]:
		var label := "Time x%s" % speed
		_button(speeds, label, func() -> void: Engine.time_scale = speed)

	_heading(column, "Site")
	_button(column, "Restart this site", func() -> void: _restart(game.site_seed()))
	_button(column, "New site", func() -> void: _restart(randi()))


func _process(delta: float) -> void:
	_status_left -= delta
	if not _panel.visible or _status_left > 0.0:
		return
	_status_left = 0.25
	var me := _me()
	if me == null or game.level == null:
		return
	var room: int = game.level.room_at(me.global_position)
	var kind: String = game.level.kind(room)
	var theme: String = game.level.themes.get(room, "-")
	_status.text = (
		"seed %d · %d fps\nroom %d: %s, %s, floor %d\nat %.1f, %.1f, %.1f\nmonsters %d · loot %d"
		% [
			game.site_seed(),
			Engine.get_frames_per_second(),
			room,
			kind,
			theme,
			game.level.floor_of(room),
			me.global_position.x,
			me.global_position.y,
			me.global_position.z,
			_monsters().size(),
			get_tree().get_nodes_in_group("loot").size(),
		]
	)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_F1:
		_show(not _panel.visible)
		get_viewport().set_input_as_handled()
	elif _panel.visible and event.is_action_pressed("ui_cancel"):
		_show(false)
		get_viewport().set_input_as_handled()


func _show(on: bool) -> void:
	_panel.visible = on
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED
	_status_left = 0.0


func _me() -> Player:
	return game.get_node_or_null("Players/%d" % multiplayer.get_unique_id()) as Player


func _monsters() -> Array[Monster]:
	var found: Array[Monster] = []
	for node in game.get_node("Monsters").get_children():
		if node is Monster:
			found.append(node as Monster)
	return found


func _spawn_loot() -> void:
	game.spawn_loot_at(_loot_kind.selected, _me().aim_point(6.0) + Vector3.UP * 0.6)


func _spawn_monster() -> void:
	var at := _me().aim_point(8.0)
	game.spawn_monster_at(_monster_kind.selected, Vector3(at.x, _me().global_position.y, at.z))


func _freeze_monsters(on: bool) -> void:
	for monster in _monsters():
		monster.set_physics_process(not on)


func _summon_monsters() -> void:
	var room: int = game.level.room_at(_me().global_position)
	for monster in _monsters():
		monster.hunt(room)


func _calm_monsters() -> void:
	for monster in _monsters():
		monster.calm(30.0)


func _remove_monsters() -> void:
	for monster in _monsters():
		monster.queue_free()  # The spawner removes it on every peer.


func _fly(on: bool) -> void:
	_me().flying = on


func _teleport(at: Vector3) -> void:
	var me := _me()
	me.global_position = at + Vector3.UP * 0.2
	me.velocity = Vector3.ZERO


func _teleport_far() -> void:
	var level: Level = game.level
	var distance := level.distances_from(level.room_at(_me().global_position))
	var far := -1
	for room: int in distance:
		if level.is_outdoors(room) or level.is_stairs(room):
			continue
		if far < 0 or distance[room] > distance[far]:
			far = room
	if far >= 0:
		_teleport(level.anchor(far))


func _teleport_to_loot() -> void:
	var best: Loot = null
	for node in get_tree().get_nodes_in_group("loot"):
		var loot := node as Loot
		if best == null or loot.value > best.value:
			best = loot
	if best:
		var level: Level = game.level
		_teleport(level.anchor(level.room_at(best.global_position)))


func _light(on: bool) -> void:
	for node in game.find_children("*", "WorldEnvironment", true, false):
		var environment := (node as WorldEnvironment).environment
		if not _lit:
			environment.set_meta("dark_energy", environment.ambient_light_energy)
		environment.ambient_light_energy = 1.2 if on else environment.get_meta("dark_energy")
	_lit = on


func _restart(seed_value: int) -> void:
	Engine.time_scale = 1.0
	Net.seed_override = seed_value
	Net.restart()


func _heading(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.modulate = Color(1.0, 0.85, 0.45)
	parent.add_child(label)


func _button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE  # Keys keep moving the player.
	button.pressed.connect(action)
	parent.add_child(button)


func _toggle(parent: Control, text: String, action: Callable) -> void:
	var box := CheckBox.new()
	box.text = text
	box.focus_mode = Control.FOCUS_NONE
	box.toggled.connect(action)
	parent.add_child(box)
