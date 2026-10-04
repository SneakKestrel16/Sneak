extends Node3D
## Renders every loot kind and the monster under even light and saves a PNG,
## for checking how models look without playing. Not a test; run by hand:
##   godot --path . res://tools/showcase.tscn -- --out=C:/path/showcase.png

const GAME := preload("res://scripts/game.gd")


func _ready() -> void:
	var out := "user://showcase.png"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")

	var x := -3.2
	for kind: Dictionary in GAME.KINDS:
		var loot := Loot.new()
		loot.kind = kind["name"]
		loot.size = kind["size"]
		loot.color = kind["color"]
		loot.value = kind["value"].y
		loot.base_value = loot.value
		loot.freeze = true
		loot.position = Vector3(x + kind["size"].x / 2.0, kind["size"].y / 2.0, 0)
		add_child(loot)
		x += kind["size"].x + 0.35
	var monster := Monster.new()
	monster.position = Vector3(x + 0.6, 0, 0.3)
	monster.rotation.y = PI * 0.85  # Turn its face (-Z) toward the camera.
	add_child(monster)
	monster.set_physics_process(false)

	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(20, 0.1, 10)
	var floor_instance := MeshInstance3D.new()
	floor_instance.mesh = floor_mesh
	floor_instance.position.y = -0.05
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
	var camera := Camera3D.new()
	camera.position = Vector3(0.6, 1.6, 5.2)
	camera.rotation.x = -0.2
	camera.fov = 60
	add_child(camera)

	# Noise textures generate on worker threads; give them time to land.
	for i in 90:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	print("[showcase] saved %s" % out)
	get_tree().quit()
