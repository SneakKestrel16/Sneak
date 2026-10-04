extends RefCounted
## Builds the house: a 3x3 grid of rooms with a doorway in the middle of every
## inner wall, a ceiling, dim lamps, and the truck bay (the extraction zone) in
## the south room where everyone spawns.
##
## Doorways sit on the line between neighbouring room centres, so anything that
## walks centre to centre (the monster) goes through them without pathfinding.

const ROOM := 10.0
const ROOMS := 3
const HALF := ROOM * ROOMS / 2.0  ## The house spans -HALF..HALF on x and z.
const WALL_HEIGHT := 3.0
const WALL_THICKNESS := 0.3
const DOOR_WIDTH := 2.0
const DOOR_HEIGHT := 2.3

const SPAWN_ROOM := Vector2i(1, 2)
const MONSTER_ROOM := Vector2i(1, 0)
const SPAWN := Vector3(0.0, 0.1, 9.0)
const TRUCK := Vector3(0.0, 1.0, 13.0)
const TRUCK_SIZE := Vector3(4.0, 2.0, 2.4)


## The centre of room (column, row) at floor height.
static func room_center(room: Vector2i) -> Vector3:
	return Vector3(-HALF + (room.x + 0.5) * ROOM, 0.0, -HALF + (room.y + 0.5) * ROOM)


## The room whose floor contains point.
static func room_at(point: Vector3) -> Vector2i:
	return Vector2i(
		clampi(floori((point.x + HALF) / ROOM), 0, ROOMS - 1),
		clampi(floori((point.z + HALF) / ROOM), 0, ROOMS - 1)
	)


## Every room but the spawn room, where loot goes.
static func loot_rooms() -> Array[Vector2i]:
	var rooms: Array[Vector2i] = []
	for x in ROOMS:
		for y in ROOMS:
			if Vector2i(x, y) != SPAWN_ROOM:
				rooms.append(Vector2i(x, y))
	return rooms


## Builds the house under parent and returns the truck bay.
static func build(parent: Node3D) -> Area3D:
	var floor_material := _material(Color(0.32, 0.27, 0.22))
	var wall_material := _material(Color(0.5, 0.47, 0.42))
	var size := HALF * 2.0
	_box(parent, Vector3(0, -0.1, 0), Vector3(size, 0.2, size), floor_material)
	_box(parent, Vector3(0, WALL_HEIGHT + 0.1, 0), Vector3(size, 0.2, size), wall_material)
	for i in ROOMS + 1:
		var line := -HALF + i * ROOM
		var outer := i == 0 or i == ROOMS
		for j in ROOMS:
			var along := -HALF + (j + 0.5) * ROOM
			_wall(parent, Vector3(line, 0, along), true, outer, wall_material)
			_wall(parent, Vector3(along, 0, line), false, outer, wall_material)

	# Some rooms get a dim lamp, the rest stay dark: the flashlight matters.
	var rng := RandomNumberGenerator.new()
	for x in ROOMS:
		for y in ROOMS:
			if Vector2i(x, y) != SPAWN_ROOM and rng.randf() < 0.4:
				continue
			var lamp := OmniLight3D.new()
			lamp.position = room_center(Vector2i(x, y)) + Vector3.UP * (WALL_HEIGHT - 0.4)
			lamp.light_color = Color(1.0, 0.8, 0.55)
			lamp.light_energy = 0.7
			lamp.omni_range = 7.0
			lamp.shadow_enabled = true
			parent.add_child(lamp)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.25, 0.27, 0.35)
	environment.ambient_light_energy = 0.15
	var world := WorldEnvironment.new()
	world.environment = environment
	parent.add_child(world)

	var truck := Area3D.new()
	truck.position = TRUCK
	var shape := BoxShape3D.new()
	shape.size = TRUCK_SIZE
	var collision := CollisionShape3D.new()
	collision.shape = shape
	truck.add_child(collision)
	var plate := MeshInstance3D.new()
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(TRUCK_SIZE.x, 0.02, TRUCK_SIZE.z)
	var plate_material := _material(Color(0.2, 0.9, 0.4))
	plate_material.emission_enabled = true
	plate_material.emission = Color(0.1, 0.6, 0.25)
	plate_mesh.material = plate_material
	plate.mesh = plate_mesh
	plate.position.y = 0.01 - TRUCK_SIZE.y / 2.0
	truck.add_child(plate)
	var sign_label := Label3D.new()
	sign_label.text = "TRUCK"
	sign_label.font_size = 96
	sign_label.position = Vector3(0, 0.6, TRUCK_SIZE.z / 2.0 + 0.3)
	sign_label.rotation.y = PI
	truck.add_child(sign_label)
	parent.add_child(truck)
	return truck


## A wall segment centred on centre, running along z or x. Inner walls get a
## doorway in the middle.
static func _wall(
	parent: Node3D, centre: Vector3, along_z: bool, solid: bool, material: Material
) -> void:
	var axis := Vector3.BACK if along_z else Vector3.RIGHT
	var across := Vector3(WALL_THICKNESS, 0, WALL_THICKNESS) - axis * WALL_THICKNESS
	if solid:
		var full := across + axis * ROOM + Vector3.UP * WALL_HEIGHT
		_box(parent, centre + Vector3.UP * WALL_HEIGHT / 2.0, full, material)
		return
	var side := (ROOM - DOOR_WIDTH) / 2.0
	for sign_of: float in [-1.0, 1.0]:
		var piece := across + axis * side + Vector3.UP * WALL_HEIGHT
		var offset := axis * sign_of * (DOOR_WIDTH + side) / 2.0
		_box(parent, centre + offset + Vector3.UP * WALL_HEIGHT / 2.0, piece, material)
	var lintel_height := WALL_HEIGHT - DOOR_HEIGHT
	var lintel := across + axis * DOOR_WIDTH + Vector3.UP * lintel_height
	_box(parent, centre + Vector3.UP * (DOOR_HEIGHT + lintel_height / 2.0), lintel, material)


static func _box(parent: Node3D, centre: Vector3, size: Vector3, material: Material) -> void:
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


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material
