extends Node3D
## Renders one storey of a generated house from above, with the storeys above
## it hidden, doorways marked red and even light, and saves a PNG. For checking
## what the generator makes; run by hand:
##   godot --path . res://tools/map_view.tscn -- --seed=N --floor=0 --out=C:/path/map.png

const Level := preload("res://scripts/level.gd")


func _ready() -> void:
	var out := "user://map.png"
	var seed_value := 1
	var storey := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--seed="):
			seed_value = arg.trim_prefix("--seed=").to_int()
		elif arg.begins_with("--floor="):
			storey = arg.trim_prefix("--floor=").to_int()
	var level := Level.new(seed_value)
	level.build(self)
	get_node("Roof").queue_free()
	for above in range(storey + 1, Level.FLOORS):
		get_node("Floor%d" % above).queue_free()
	# Even light from above instead of the house's dim lamps.
	for child in find_children("*", "OmniLight3D", true, false):
		child.queue_free()
	for child in find_children("*", "WorldEnvironment", true, false):
		(child as WorldEnvironment).environment.ambient_light_energy = 1.5

	var marker := BoxMesh.new()
	marker.size = Vector3(0.7, 0.5, 0.7)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color.RED
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material = red
	for room in level.room_count():
		if level.floor_of(room) == storey:
			for point in level.doors(room):
				var door := MeshInstance3D.new()
				door.mesh = marker
				door.position = point + Vector3.UP * (Level.WALL_HEIGHT + 0.3)
				add_child(door)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-1.2, 0.3, 0)
	add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = Level.COLUMNS * Level.CELL + 2.0
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.position = Vector3(0, 40, 0)
	camera.rotation.x = -PI / 2.0
	add_child(camera)

	for i in 30:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	print("[map] seed %d floor %d saved %s" % [seed_value, storey, out])
	get_tree().quit()
