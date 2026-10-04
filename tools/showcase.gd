extends Node3D
## Renders the models under even light and saves a PNG, for checking how they
## look without playing. Not a test; run by hand:
##   godot --path . res://tools/showcase.tscn -- --set=loot --out=C:/path/showcase.png
## Sets: loot (every kind, small finds in front, opened cabinets behind),
## monsters (all four bodies, front and back), decor (every furniture and
## decoration model). --close moves the camera in.

const GAME := preload("res://scripts/game.gd")
const Decor := preload("res://scripts/decor.gd")

var _camera := Camera3D.new()


func _ready() -> void:
	var out := "user://showcase.png"
	var which := "loot"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--set="):
			which = arg.trim_prefix("--set=")
	_camera.fov = 60
	add_child(_camera)
	var width := 20.0
	match which:
		"monsters":
			_monsters()
		"decor":
			width = _decor()
		_:
			_loot()
	if "--close" in OS.get_cmdline_user_args():
		_camera.position = Vector3(-1.0, 1.3, 3.2)
		_camera.rotation.x = -0.32
	_stage(width)

	# Noise textures generate on worker threads; give them time to land.
	for i in 90:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	print("[showcase] saved %s" % out)
	get_tree().quit()


func _loot() -> void:
	var x := -3.2
	var small_x := -1.0
	for kind: Dictionary in GAME.KINDS:
		var small: bool = kind.get("small", false)
		var loot := Loot.new()
		loot.kind = kind["name"]
		loot.size = kind["size"]
		loot.color = kind["color"]
		loot.value = kind["value"].y
		loot.base_value = loot.value
		loot.freeze = true
		if small:
			loot.position = Vector3(small_x, kind["size"].y / 2.0, 1.6)
			small_x += 0.45
		else:
			loot.position = Vector3(x + kind["size"].x / 2.0, kind["size"].y / 2.0, 0)
			x += kind["size"].x + 0.35
		add_child(loot)
	for type in Cabinet.SIZES.size():
		var cabinet := Cabinet.new()
		cabinet.type = type
		cabinet.position = Vector3(-3.4 + type * 1.3, 0, 1.0)
		add_child(cabinet)
		cabinet.set_opened(0xFF, false)
	_camera.position = Vector3(0.6, 1.6, 5.2)
	_camera.rotation.x = -0.2


## Front row facing the camera, back row turned away.
func _monsters() -> void:
	for i in Monster.VARIANTS.size():
		for row in 2:
			var monster := Monster.new()
			monster.variant = i
			monster.position = Vector3(-2.7 + i * 1.8, 0, -2.0 * row)
			monster.rotation.y = PI if row == 0 else 0.0  # Its face is -Z.
			add_child(monster)
			monster.set_physics_process(false)
			monster.set_process(false)
	_camera.position = Vector3(0, 1.5, 4.6)
	_camera.rotation.x = -0.12


## Every decor model in rows, labelled by nothing but order (see decor.json).
func _decor() -> float:
	var x := 0.0
	var z := 0.0
	var row_depth := 0.0
	for entry: Dictionary in Decor.catalogue():
		var size: Vector3 = entry["size"]
		if x + size.x > 12.0:
			x = 0.0
			z -= row_depth + 0.6
			row_depth = 0.0
		var piece := Decor.instance(entry)
		piece.position = Vector3(x + size.x / 2.0 - 6.0, 0, z - size.z / 2.0)
		if entry["place"] == "hang":
			piece.position.y = 1.0
		add_child(piece)
		x += size.x + 0.4
		row_depth = maxf(row_depth, size.z)
	_camera.position = Vector3(0, 7.0, 6.0)
	_camera.rotation.x = -0.75
	return 30.0


func _stage(width: float) -> void:
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(width, 0.1, width)
	var floor_instance := MeshInstance3D.new()
	floor_instance.mesh = floor_mesh
	floor_instance.position = Vector3(0, -0.05, -width / 2.0 + 4.0)
	add_child(floor_instance)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.5, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.18, 0.2, 0.24)
	environment.ambient_light_color = Color(0.5, 0.5, 0.55)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
