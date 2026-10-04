extends RefCounted
## Generates and builds the house from a seed, so every peer builds the same one.
##
## Rooms sit on a COLUMNS x ROWS grid. A randomised depth-first search links
## them into a maze (one route between any two rooms, so plenty of dead ends),
## then a few extra doors add loops and a few walls come down entirely to make
## halls. Doorways sit at a random point along each wall, so the way on is not
## obvious from the middle of a room. Everyone spawns at the truck on the south
## edge; the monsters start in the rooms farthest from it.

const ROOM := 8.0
const COLUMNS := 6
const ROWS := 6
const WALL_HEIGHT := 3.0
const WALL_THICKNESS := 0.3
const DOOR_WIDTH := 1.8
## Clears the monster's 2.4 m capsule; at 2.3 it jammed under every lintel.
const DOOR_HEIGHT := 2.6
const EXTRA_DOORS := 0.12  ## Chance a wall the maze left solid gets a door anyway (loops).
const OPEN_WALLS := 0.25  ## Chance a maze connection is a missing wall instead of a door.
const LIT_ROOMS := 0.4  ## Chance a room has a lamp; the rest need flashlights.
const TRUCK_SIZE := Vector3(4.0, 2.0, 2.4)
const APPROACH := 0.9  ## How far from a doorway walkers line up before going through (m).

const DIRECTIONS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

var spawn_room: Vector2i
var spawn: Vector3  ## Where players appear, just inside the truck bay's room.
var truck: Vector3  ## Centre of the truck bay (extraction zone).

## Connections between neighbouring rooms, keyed by _edge(a, b). A float is a
## door's offset along the wall from its middle; NAN means the wall is gone.
var _links := {}
var _rng := RandomNumberGenerator.new()


func _init(seed_value: int) -> void:
	_rng.seed = seed_value
	spawn_room = Vector2i(floori(COLUMNS / 2.0), ROWS - 1)
	var centre := room_center(spawn_room)
	truck = centre + Vector3(0, 1.0, ROOM / 2.0 - TRUCK_SIZE.z / 2.0 - 0.3)
	spawn = centre + Vector3(0, 0.1, -0.5)
	_carve()


## The centre of a room at floor height.
func room_center(room: Vector2i) -> Vector3:
	return Vector3((room.x + 0.5) * ROOM - _half_x(), 0.0, (room.y + 0.5) * ROOM - _half_z())


## The room whose floor contains point.
func room_at(point: Vector3) -> Vector2i:
	return Vector2i(
		clampi(floori((point.x + _half_x()) / ROOM), 0, COLUMNS - 1),
		clampi(floori((point.z + _half_z()) / ROOM), 0, ROWS - 1)
	)


## Rooms you can walk straight into from room.
func neighbours(room: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for step in DIRECTIONS:
		if _links.has(_edge(room, room + step)):
			result.append(room + step)
	return result


## Steps from the spawn room to every room, walking through doors.
func distances_from(start: Vector2i) -> Dictionary:
	var distance := {start: 0}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var room: Vector2i = queue.pop_front()
		for next in neighbours(room):
			if not distance.has(next):
				distance[next] = distance[room] + 1
				queue.append(next)
	return distance


## Waypoints from a point inside room `from` to the centre of room `to`: line up
## in front of each doorway, step through, and so on. Rooms are empty convex
## boxes, so straight lines between consecutive points are clear (bar loot).
func route(from: Vector2i, to: Vector2i) -> Array[Vector3]:
	var came_from := {from: from}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty() and not came_from.has(to):
		var room: Vector2i = queue.pop_front()
		for next in neighbours(room):
			if not came_from.has(next):
				came_from[next] = room
				queue.append(next)
	var points: Array[Vector3] = []
	if not came_from.has(to):
		return points
	var current := to
	points.push_front(room_center(to))
	while current != from:
		var previous: Vector2i = came_from[current]
		var door := door_point(previous, current)
		var step := Vector3(current.x - previous.x, 0, current.y - previous.y)
		points.push_front(door + step * APPROACH)
		points.push_front(door - step * APPROACH)
		current = previous
	return points


## Builds the house under parent and returns the truck bay. tools/map_view
## leaves the ceiling off to look down on it.
func build(parent: Node3D, ceiling := true) -> Area3D:
	var floor_material := _material(Color(0.32, 0.27, 0.22))
	var wall_material := _material(Color(0.5, 0.47, 0.42))
	var size := Vector3(COLUMNS * ROOM, 0.2, ROWS * ROOM)
	_box(parent, Vector3(0, -0.1, 0), size, floor_material)
	if ceiling:
		_box(parent, Vector3(0, WALL_HEIGHT + 0.1, 0), size, wall_material)

	for x in COLUMNS:
		for y in ROWS:
			var room := Vector2i(x, y)
			# Each room builds its west and north wall; the last column and row
			# also build the outer east and south walls.
			_wall(parent, room, Vector2i.LEFT, wall_material)
			_wall(parent, room, Vector2i.UP, wall_material)
			if x == COLUMNS - 1:
				_wall(parent, room, Vector2i.RIGHT, wall_material)
			if y == ROWS - 1:
				_wall(parent, room, Vector2i.DOWN, wall_material)
			if room == spawn_room or _rng.randf() < LIT_ROOMS:
				var lamp := OmniLight3D.new()
				lamp.position = room_center(room) + Vector3.UP * (WALL_HEIGHT - 0.4)
				lamp.light_color = Color(1.0, 0.8, 0.55)
				lamp.light_energy = 0.7
				lamp.omni_range = 6.5
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
	return _build_truck(parent)


## Links the rooms: a randomised depth-first maze, then extra doors and halls.
func _carve() -> void:
	var visited := {spawn_room: true}
	var stack: Array[Vector2i] = [spawn_room]
	while not stack.is_empty():
		var room: Vector2i = stack.back()
		var options: Array[Vector2i] = []
		for step in DIRECTIONS:
			var next := room + step
			if _inside(next) and not visited.has(next):
				options.append(next)
		if options.is_empty():
			stack.pop_back()
			continue
		var next := options[_rng.randi() % options.size()]
		visited[next] = true
		_links[_edge(room, next)] = NAN if _rng.randf() < OPEN_WALLS else _door_offset()
		stack.append(next)
	for x in COLUMNS:
		for y in ROWS:
			for step: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
				var a := Vector2i(x, y)
				var key := _edge(a, a + step)
				if _inside(a + step) and not _links.has(key) and _rng.randf() < EXTRA_DOORS:
					_links[key] = _door_offset()


func _door_offset() -> float:
	var room_for_it := ROOM / 2.0 - DOOR_WIDTH / 2.0 - 0.6
	return _rng.randf_range(-room_for_it, room_for_it)


## The middle of the opening between neighbouring rooms a and b, on the floor.
func door_point(a: Vector2i, b: Vector2i) -> Vector3:
	var middle := (room_center(a) + room_center(b)) / 2.0
	var offset: float = _links[_edge(a, b)]
	if is_nan(offset):
		return middle
	var along := Vector3.BACK if a.y == b.y else Vector3.RIGHT
	return middle + along * offset


## Builds the wall on one side of room: solid, a doorway, or nothing.
func _wall(parent: Node3D, room: Vector2i, side: Vector2i, material: Material) -> void:
	var other := room + side
	var offset := INF  # Solid.
	if _links.has(_edge(room, other)):
		offset = _links[_edge(room, other)]
		if is_nan(offset):
			return
	var centre := room_center(room) + Vector3(side.x, 0, side.y) * ROOM / 2.0
	var along := Vector3.BACK if side.x != 0 else Vector3.RIGHT
	var across := Vector3(WALL_THICKNESS, 0, WALL_THICKNESS) - along * WALL_THICKNESS
	var up := Vector3.UP * WALL_HEIGHT
	if is_inf(offset):
		_box(parent, centre + up / 2.0, across + along * ROOM + up, material)
		return
	# Two pieces either side of the doorway, and a lintel above it.
	var door_start := offset - DOOR_WIDTH / 2.0
	var door_end := offset + DOOR_WIDTH / 2.0
	for piece: Vector2 in [Vector2(-ROOM / 2.0, door_start), Vector2(door_end, ROOM / 2.0)]:
		var length := piece.y - piece.x
		var middle := centre + along * (piece.x + piece.y) / 2.0
		_box(parent, middle + up / 2.0, across + along * length + up, material)
	var lintel := WALL_HEIGHT - DOOR_HEIGHT
	var lintel_at := centre + along * offset + Vector3.UP * (DOOR_HEIGHT + lintel / 2.0)
	_box(parent, lintel_at, across + along * DOOR_WIDTH + Vector3.UP * lintel, material)


func _build_truck(parent: Node3D) -> Area3D:
	var area := Area3D.new()
	area.position = truck
	var shape := BoxShape3D.new()
	shape.size = TRUCK_SIZE
	var collision := CollisionShape3D.new()
	collision.shape = shape
	area.add_child(collision)
	var plate := MeshInstance3D.new()
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(TRUCK_SIZE.x, 0.02, TRUCK_SIZE.z)
	var plate_material := _material(Color(0.2, 0.9, 0.4))
	plate_material.emission_enabled = true
	plate_material.emission = Color(0.1, 0.6, 0.25)
	plate_mesh.material = plate_material
	plate.mesh = plate_mesh
	plate.position.y = 0.01 - TRUCK_SIZE.y / 2.0
	area.add_child(plate)
	var sign_label := Label3D.new()
	sign_label.text = "TRUCK"
	sign_label.font_size = 96
	sign_label.position = Vector3(0, 0.6, TRUCK_SIZE.z / 2.0 + 0.2)
	sign_label.rotation.y = PI
	area.add_child(sign_label)
	parent.add_child(area)
	return area


func _inside(room: Vector2i) -> bool:
	return room.x >= 0 and room.y >= 0 and room.x < COLUMNS and room.y < ROWS


func _half_x() -> float:
	return COLUMNS * ROOM / 2.0


func _half_z() -> float:
	return ROWS * ROOM / 2.0


## The same key for a-b and b-a.
static func _edge(a: Vector2i, b: Vector2i) -> Vector4i:
	if a.x < b.x or (a.x == b.x and a.y < b.y):
		return Vector4i(a.x, a.y, b.x, b.y)
	return Vector4i(b.x, b.y, a.x, a.y)


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
