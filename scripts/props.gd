extends RefCounted
## Pieces of the site that level.gd places: the stone perimeter wall and gate,
## trees, lamp posts, rocks, the stair ramp, the truck bay, and the box and
## surface helpers everything is built from. Purely geometry: where things go
## is decided in level.gd, from the site's seeded RNG.

const Models := preload("res://scripts/models.gd")


## A solid box: collision plus mesh.
static func box(parent: Node3D, centre: Vector3, size: Vector3, material: Material) -> void:
	var body := StaticBody3D.new()
	body.position = centre
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	body.add_child(instance)
	parent.add_child(body)


## A thin, non-colliding floor covering over area (x, z) at height y.
static func surface(parent: Node3D, area: Rect2, y: float, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(area.size.x, 0.02, area.size.y)
	var middle := area.get_center()
	Models.part(parent, mesh, material, Vector3(middle.x, y, middle.y))


static func plain(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material


## The stone wall round a site spanning -half..half, with pillars every 9 m,
## and a shut iron gate of width gate_width centred on gate_x in the south wall.
static func perimeter(
	parent: Node3D, half: Vector2, thickness: float, height: float, gate_x: float, gate_width: float
) -> void:
	var stone := Models.textured(Color(0.42, 0.4, 0.37), Vector2.ONE, 0.45, 0.95, 0.0, 0.25, 1.5)
	var t := thickness
	var y := height / 2.0
	box(parent, Vector3(0, y, -half.y - t / 2.0), Vector3(half.x * 2.0 + t * 2.0, height, t), stone)
	box(parent, Vector3(-half.x - t / 2.0, y, 0), Vector3(t, height, half.y * 2.0), stone)
	box(parent, Vector3(half.x + t / 2.0, y, 0), Vector3(t, height, half.y * 2.0), stone)
	# South wall in two parts either side of the gate.
	var south_z := half.y + t / 2.0
	var west := (gate_x - gate_width / 2.0) - (-half.x - t)
	var east := (half.x + t) - (gate_x + gate_width / 2.0)
	box(parent, Vector3(-half.x - t + west / 2.0, y, south_z), Vector3(west, height, t), stone)
	box(parent, Vector3(half.x + t - east / 2.0, y, south_z), Vector3(east, height, t), stone)
	var pillar := Vector3(t + 0.4, height + 0.4, t + 0.4)
	for x in range(-int(half.x), int(half.x) + 1, 9):
		for z: float in [-half.y - t / 2.0, half.y + t / 2.0]:
			if z > 0 and absf(x - gate_x) < gate_width:
				continue
			box(parent, Vector3(x, pillar.y / 2.0, z), pillar, stone)

	# The gate is shut: collision is one invisible box, with iron bars to see.
	var gate := StaticBody3D.new()
	gate.position = Vector3(gate_x, y, south_z)
	var shape := BoxShape3D.new()
	shape.size = Vector3(gate_width, height, 0.3)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	gate.add_child(collision)
	var iron := plain(Color(0.08, 0.08, 0.09))
	iron.metallic = 0.4
	var bars := int(gate_width / 0.25)
	for i in bars + 1:
		var bar_x := -gate_width / 2.0 + i * gate_width / bars
		Models.part(gate, _cylinder(0.03, 0.03, height), iron, Vector3(bar_x, 0, 0))
	for bar_y: float in [-y + 0.4, y - 0.4]:
		var rail := BoxMesh.new()
		rail.size = Vector3(gate_width, 0.08, 0.08)
		Models.part(gate, rail, iron, Vector3(0, bar_y, 0))
	parent.add_child(gate)


## A conifer: a trunk you bump into and three layers of foliage you see.
static func tree(parent: Node3D, at: Vector3, height: float) -> void:
	var bark := Models.textured(Color(0.25, 0.18, 0.12), Vector2(1, 4), 0.4, 0.9)
	var leaves := Models.textured(Color(0.12, 0.22, 0.1), Vector2.ONE, 0.4, 0.9, 0.0, 0.08)
	var trunk := StaticBody3D.new()
	trunk.position = at
	var shape := CylinderShape3D.new()
	shape.radius = 0.35
	shape.height = height
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = height / 2.0
	trunk.add_child(collision)
	Models.part(trunk, _cylinder(0.2, 0.35, height), bark, Vector3.UP * height / 2.0)
	for layer in 3:
		var crown := _cylinder(0.0, 1.8 - layer * 0.45, 2.0)
		Models.part(trunk, crown, leaves, Vector3.UP * (height * 0.55 + layer * 1.1))
	parent.add_child(trunk)


## A dark pole with a warm, shadow-casting lamp on top.
static func lamp_post(parent: Node3D, at: Vector3) -> void:
	Models.part(
		parent, _cylinder(0.06, 0.09, 3.2), plain(Color(0.1, 0.1, 0.1)), at + Vector3.UP * 1.6
	)
	var lamp := OmniLight3D.new()
	lamp.position = at + Vector3.UP * 3.1
	lamp.light_color = Color(1.0, 0.75, 0.45)
	lamp.light_energy = 0.9
	lamp.omni_range = 9.0
	lamp.shadow_enabled = true
	parent.add_child(lamp)
	var glow := plain(Color(1.0, 0.8, 0.5))
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.75, 0.45)
	glow.emission_energy_multiplier = 3.0
	Models.part(parent, _sphere(0.15), glow, at + Vector3.UP * 3.25)


## A rock or a bush, to see only.
static func lump(parent: Node3D, at: Vector3, radius: float, bush: bool) -> void:
	var material := (
		Models.textured(Color(0.12, 0.22, 0.1), Vector2.ONE, 0.4, 0.9, 0.0, 0.08)
		if bush
		else Models.textured(Color(0.4, 0.4, 0.38), Vector2.ONE, 0.4, 0.95, 0.0, 0.2)
	)
	Models.part(parent, _sphere(radius), material, at)


## The ramp that players and monsters walk on, plus visual steps, rising north
## (towards -z) from z_low at the floor to z_high at height rise.
static func stairs(
	parent: Node3D, x: float, z_low: float, z_high: float, width: float, rise: float, steps: int
) -> void:
	var run := z_low - z_high
	var angle := atan2(rise, run)
	var thickness := 0.2
	var ramp := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, thickness, Vector2(run, rise).length())
	var collision := CollisionShape3D.new()
	collision.shape = shape
	ramp.add_child(collision)
	ramp.rotation.x = angle
	var normal := Vector3(0, cos(angle), sin(angle))
	ramp.position = Vector3(x, rise / 2.0, (z_low + z_high) / 2.0) - normal * thickness / 2.0
	parent.add_child(ramp)

	var concrete := Models.textured(
		Color(0.45, 0.45, 0.45), Vector2.ONE, 0.25, 0.95, 0.0, 0.08, 2.0
	)
	var depth := run / steps
	for i in steps:
		# Step tops sit half a riser above the ramp at their front edge, so feet
		# on the smooth ramp look like they are on the steps.
		var height := (i + 0.5) * rise / steps
		var mesh := BoxMesh.new()
		mesh.size = Vector3(width, height, depth)
		Models.part(parent, mesh, concrete, Vector3(x, height / 2.0, z_low - (i + 0.5) * depth))


## The glowing extraction zone; loot that enters it is banked.
static func truck_bay(parent: Node3D, at: Vector3, size: Vector3) -> Area3D:
	var area := Area3D.new()
	area.position = at
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	area.add_child(collision)
	var plate := BoxMesh.new()
	plate.size = Vector3(size.x, 0.02, size.z)
	var glow := plain(Color(0.2, 0.9, 0.4))
	glow.emission_enabled = true
	glow.emission = Color(0.1, 0.6, 0.25)
	Models.part(area, plate, glow, Vector3.UP * (0.03 - size.y / 2.0))
	var sign_label := Label3D.new()
	sign_label.text = "TRUCK"
	sign_label.font_size = 96
	sign_label.position = Vector3(0, 0.6, -size.z / 2.0 - 0.1)
	sign_label.rotation.y = PI  # Read from the north, where players spawn.
	area.add_child(sign_label)
	parent.add_child(area)
	return area


static func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	return mesh


static func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 1.4
	return mesh
