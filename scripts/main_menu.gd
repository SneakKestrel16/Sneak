extends Control
## Host or join a co-op run. Run with `-- --host` or `-- --join=ADDRESS` to
## skip the menu, which is how two local copies are tested together.

const GAME := "res://scenes/game.tscn"

var _address: LineEdit


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not Net.args_used:
		Net.args_used = true
		for arg in OS.get_cmdline_user_args():
			if arg == "--host":
				_start(true, "")
				return
			if arg.begins_with("--join="):
				_start(false, arg.trim_prefix("--join="))
				return
	_build()


func _build() -> void:
	var background := ColorRect.new()
	background.color = Color(0.05, 0.05, 0.07)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 420
	column.add_theme_constant_override("separation", 14)
	center.add_child(column)

	var title := Label.new()
	title.text = "SNEAK"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	column.add_child(title)

	var blurb := Label.new()
	blurb.text = "Drag the valuables to the truck. Don't break them. Don't get seen."
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD
	column.add_child(blurb)

	_address = LineEdit.new()
	_address.text = Net.address
	_address.placeholder_text = "Host address"
	column.add_child(_address)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 14)
	column.add_child(buttons)
	var host := Button.new()
	host.text = "Host"
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.pressed.connect(func() -> void: _start(true, _address.text))
	buttons.add_child(host)
	var join := Button.new()
	join.text = "Join"
	join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join.pressed.connect(func() -> void: _start(false, _address.text))
	buttons.add_child(join)

	var status := Label.new()
	status.text = Net.message
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.modulate = Color(1.0, 0.5, 0.4)
	column.add_child(status)

	var help := Label.new()
	help.text = (
		"WASD move · Shift sprint · Ctrl crouch · Space jump\n"
		+ "Hold left mouse to drag loot · Wheel to pull it closer\n"
		+ "Esc frees the mouse · Esc again leaves · Port %d" % Net.port
	)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.modulate = Color(1, 1, 1, 0.6)
	column.add_child(help)
	host.grab_focus()


func _start(hosting: bool, address: String) -> void:
	Net.hosting = hosting
	Net.address = address.strip_edges() if address.strip_edges() != "" else "127.0.0.1"
	Net.message = ""
	# Deferred: this can run from _ready, while the tree is still adding the menu.
	get_tree().change_scene_to_file.call_deferred(GAME)
