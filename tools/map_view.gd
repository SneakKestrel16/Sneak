extends Node3D
## Renders a generated house from above, ceiling off and evenly lit, and saves
## a PNG. For checking what the maze generator makes; run by hand:
##   godot --path . res://tools/map_view.tscn -- --seed=N --out=C:/path/map.png

const Level := preload("res://scripts/level.gd")


func _ready() -> void:
	var out := "user://map.png"
	var seed_value := 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--seed="):
			seed_value = arg.trim_prefix("--seed=").to_int()
	var level := Level.new(seed_value)
	level.build(self, false)
	# Even light from above instead of the house's dark lamps.
	for child in get_children():
		if child is OmniLight3D:
			child.queue_free()
		elif child is WorldEnvironment:
			(child as WorldEnvironment).environment.ambient_light_energy = 1.2
	# Lintels hide doorways from above, so mark each opening.
	var marker := BoxMesh.new()
	marker.size = Vector3(0.9, 3.5, 0.9)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color.RED
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material = red
	for x in Level.COLUMNS:
		for y in Level.ROWS:
			for next in level.neighbours(Vector2i(x, y)):
				var door := MeshInstance3D.new()
				door.mesh = marker
				door.position = level.door_point(Vector2i(x, y), next)
				add_child(door)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-1.2, 0.3, 0)
	add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = Level.ROWS * Level.ROOM + 2.0
	camera.position = Vector3(0, 30, 0)
	camera.rotation.x = -PI / 2.0
	add_child(camera)

	for i in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	print("[map] seed %d saved %s" % [seed_value, out])
	get_tree().quit()
