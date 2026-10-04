extends RefCounted
## Generates and builds the house from a seed, so every peer builds the same one.
##
## The house is FLOORS storeys on a COLUMNS x ROWS grid of CELL-metre cells.
## Each storey is split recursively (binary space partition) into rooms of
## varying size: large halls, medium and small rooms, and narrow hallways, each
## with its own floor surface. A stair room sits at the same spot on every
## storey; nothing is ever cut through it. Neighbouring rooms are joined by a
## random spanning tree of doors (so every room is reachable) plus extra doors
## and wide arches, which gives loops rather than a maze. Everyone spawns at the
## truck in a ground-floor room on the south edge.
##
## Rooms are numbered across all storeys. Every room but the stair room is an
## empty rectangle, so a straight line between two points in one is clear.

const Models := preload("res://scripts/models.gd")

const CELL := 3.0
const COLUMNS := 16
const ROWS := 12
const FLOORS := 2
const STOREY := 3.4  ## Floor to floor.
const SLAB := 0.2
const WALL_HEIGHT := STOREY - SLAB
const WALL_THICKNESS := 0.2
const DOOR_WIDTH := 1.8
const ARCH_WIDTH := 2.6
## Clears the monster's 2.4 m capsule; at 2.3 it jammed under every lintel.
const DOOR_HEIGHT := 2.6
const MIN_SIDE := 2  ## Cells. No cut leaves a room narrower than this.
const MAX_AREA := 24  ## Cells. Bigger rooms are always split further.
const STOP_CHANCE := 0.4  ## Chance a room small enough to stay whole does.
const EXTRA_DOORS := 0.35  ## Chance a neighbour pair the tree left apart gets a door anyway.
const ARCHES := 0.2  ## Chance a doorway is a wide arch instead.
const LIT_ROOMS := 0.45  ## Chance a room has a lamp; the rest need flashlights.
const STAIR_LENGTH := 5  ## Cells: bottom landing, three of ramp, top landing.
const STAIR_STEPS := 12
const TRUCK_SIZE := Vector3(4.0, 2.0, 2.4)
const APPROACH := 0.9  ## How far from a doorway walkers line up before going through (m).

var spawn_room: int
var spawn: Vector3  ## Where players appear, just north of the truck bay.
var truck: Vector3  ## Centre of the truck bay (extraction zone).

## Per room: {"floor": int, "rect": Rect2i in cells, "kind": String}. Kinds are
## "stairs", "hallway", "small", "medium" and "large".
var _rooms: Array[Dictionary] = []
var _cells: Array[PackedInt32Array] = []  ## Per storey, room id of each cell (y * COLUMNS + x).
## Openings, keyed by _pair(a, b). Doors: {"point", "normal" (lower id to
## higher), "width", "offset"}. Stairs: {"stairs": true}.
var _links := {}
var _openings := {}  ## Edge key -> door link, for building walls with gaps.
var _adjacent := {}  ## Room id -> Array of linked room ids.
var _stairs: Rect2i  ## The stair room's cells, the same on every storey.
var _rng := RandomNumberGenerator.new()


func _init(seed_value: int) -> void:
	_rng.seed = seed_value
	var x := _rng.randi_range(1, COLUMNS - 2)
	var y := _rng.randi_range(0, ROWS - STAIR_LENGTH - 1)
	_stairs = Rect2i(x, y, 1, STAIR_LENGTH)
	for floor_index in FLOORS:
		var cells := PackedInt32Array()
		cells.resize(COLUMNS * ROWS)
		_cells.append(cells)
		_split(Rect2i(0, 0, COLUMNS, ROWS), floor_index)
	_link()
	_place_truck()


## The stair rooms, bottom storey first.
func stair_rooms() -> Array[int]:
	var found: Array[int] = []
	for room in _rooms.size():
		if is_stairs(room):
			found.append(room)
	return found


func room_count() -> int:
	return _rooms.size()


func is_stairs(room: int) -> bool:
	return _rooms[room]["kind"] == "stairs"


func kind(room: int) -> String:
	return _rooms[room]["kind"]


func floor_of(room: int) -> int:
	return _rooms[room]["floor"]


func floor_height(room: int) -> float:
	return floor_of(room) * STOREY


## The room's floor area in world space, x and z.
func room_bounds(room: int) -> Rect2:
	var rect: Rect2i = _rooms[room]["rect"]
	return Rect2(_cell_corner(rect.position), Vector2(rect.size) * CELL)


## Where to stand in a room: its middle, or a landing for the stair room.
func anchor(room: int) -> Vector3:
	if is_stairs(room):
		return _cell_centre(_stairs.position.x, _landing(room), floor_of(room))
	var middle := room_bounds(room).get_center()
	return Vector3(middle.x, floor_height(room), middle.y)


## The room containing point, judging the storey by its height.
func room_at(point: Vector3) -> int:
	var floor_index := clampi(floori((point.y + 1.0) / STOREY), 0, FLOORS - 1)
	var x := clampi(floori((point.x + _half_x()) / CELL), 0, COLUMNS - 1)
	var y := clampi(floori((point.z + _half_z()) / CELL), 0, ROWS - 1)
	return _cells[floor_index][y * COLUMNS + x]


## Rooms you can walk straight into from room, through a door or up the stairs.
func neighbours(room: int) -> Array:
	return _adjacent.get(room, [])


## Doorway centres of a room, on its floor.
func doors(room: int) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for next: int in neighbours(room):
		var link: Dictionary = _links[_pair(room, next)]
		if link.has("point"):
			points.append(link["point"])
	return points


## Steps from start to every room.
func distances_from(start: int) -> Dictionary:
	var distance := {start: 0}
	var queue: Array[int] = [start]
	while not queue.is_empty():
		var room: int = queue.pop_front()
		for next: int in neighbours(room):
			if not distance.has(next):
				distance[next] = distance[room] + 1
				queue.append(next)
	return distance


## Waypoints from a point inside room `from` to the anchor of room `to`: line
## up in front of each doorway and step through, or walk landing to landing up
## or down the stairs.
func route(from: int, to: int) -> Array[Vector3]:
	var came_from := {from: from}
	var queue: Array[int] = [from]
	while not queue.is_empty() and not came_from.has(to):
		var room: int = queue.pop_front()
		for next: int in neighbours(room):
			if not came_from.has(next):
				came_from[next] = room
				queue.append(next)
	var points: Array[Vector3] = []
	if not came_from.has(to):
		return points
	points.push_front(anchor(to))
	var current := to
	while current != from:
		var previous: int = came_from[current]
		var link: Dictionary = _links[_pair(previous, current)]
		if link.has("stairs"):
			points.push_front(anchor(current))
			points.push_front(anchor(previous))
		else:
			var normal: Vector3 = link["normal"] if previous < current else -link["normal"]
			points.push_front(link["point"] + normal * APPROACH)
			points.push_front(link["point"] - normal * APPROACH)
		current = previous
	return points


## Builds the house under parent and returns the truck bay. Each storey goes in
## its own node ("Floor0", "Floor1", ..., then "Roof") so tools/map_view can
## hide the ones above the storey it looks at.
func build(parent: Node3D) -> Area3D:
	var size := Vector2(COLUMNS, ROWS) * CELL
	var slab_material := _plain(Color(0.25, 0.23, 0.21))
	for floor_index in FLOORS:
		var storey := Node3D.new()
		storey.name = "Floor%d" % floor_index
		parent.add_child(storey)
		var base := floor_index * STOREY
		var hole := Rect2()
		if floor_index > 0:
			# The stairwell: over the ramp and the bottom landing.
			var corner := _cell_corner(_stairs.position + Vector2i(0, 1))
			hole = Rect2(corner, Vector2(1, STAIR_LENGTH - 1) * CELL)
		for piece in _minus(Rect2(-size / 2.0, size), hole):
			var centre := Vector3(piece.get_center().x, base - SLAB / 2.0, piece.get_center().y)
			_box(storey, centre, Vector3(piece.size.x, SLAB, piece.size.y), slab_material)
		_build_walls(storey, floor_index)
		for room in _rooms.size():
			if floor_of(room) == floor_index:
				_furnish(storey, room)
		if floor_index == 0:
			_build_stairs(storey)
	var roof := Node3D.new()
	roof.name = "Roof"
	parent.add_child(roof)
	var top := Vector3(0, FLOORS * STOREY - SLAB / 2.0, 0)
	_box(roof, top, Vector3(size.x, SLAB, size.y), _plain(Color(0.3, 0.28, 0.26)))

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


# Generation ----------------------------------------------------------------


## Splits rect into rooms, never cutting through the stair room.
func _split(rect: Rect2i, floor_index: int) -> void:
	if rect.get_area() <= MAX_AREA and _rng.randf() < STOP_CHANCE:
		_add_leaf(rect, floor_index)
		return
	var cuts: Array[Vector2i] = []  # (axis, position)
	var longer := 0 if rect.size.x >= rect.size.y else 1
	for axis in 2:
		for at in range(rect.position[axis] + MIN_SIDE, rect.end[axis] - MIN_SIDE + 1):
			var through_stairs := (
				rect.intersects(_stairs) and _stairs.position[axis] < at and at < _stairs.end[axis]
			)
			if not through_stairs:
				cuts.append(Vector2i(axis, at))
	if cuts.is_empty():
		_add_leaf(rect, floor_index)
		return
	# Mostly cut across the longer side, so rooms stay roughly square.
	var across: Array[Vector2i] = []
	for cut in cuts:
		if cut.x == longer:
			across.append(cut)
	if not across.is_empty() and _rng.randf() < 0.8:
		cuts = across
	var cut := cuts[_rng.randi() % cuts.size()]
	var first := rect
	var second := rect
	first.size[cut.x] = cut.y - rect.position[cut.x]
	second.position[cut.x] = cut.y
	second.size[cut.x] = rect.end[cut.x] - cut.y
	_split(first, floor_index)
	_split(second, floor_index)


## Adds a finished piece as a room. A piece holding the stair room is cut around
## it (left, right, then above and below it), which often leaves hallways.
func _add_leaf(rect: Rect2i, floor_index: int) -> void:
	if not rect.encloses(_stairs):
		_add_room(rect, floor_index)
		return
	var s := _stairs
	var pieces: Array[Rect2i] = [
		Rect2i(rect.position.x, rect.position.y, s.position.x - rect.position.x, rect.size.y),
		Rect2i(s.end.x, rect.position.y, rect.end.x - s.end.x, rect.size.y),
		Rect2i(s.position.x, rect.position.y, s.size.x, s.position.y - rect.position.y),
		Rect2i(s.position.x, s.end.y, s.size.x, rect.end.y - s.end.y),
	]
	for piece in pieces:
		if piece.has_area():
			_add_room(piece, floor_index)
	_add_room(s, floor_index, "stairs")


func _add_room(rect: Rect2i, floor_index: int, room_kind := "") -> void:
	if room_kind == "":
		var short := mini(rect.size.x, rect.size.y)
		var long := maxi(rect.size.x, rect.size.y)
		if short == 1 or (short == 2 and long >= 6):
			room_kind = "hallway"
		elif rect.get_area() <= 4:
			room_kind = "small"
		elif rect.get_area() >= 15:
			room_kind = "large"
		else:
			room_kind = "medium"
	var room := _rooms.size()
	_rooms.append({"floor": floor_index, "rect": rect, "kind": room_kind})
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			_cells[floor_index][y * COLUMNS + x] = room


## Joins neighbouring rooms: a random spanning tree first (Kruskal), so every
## room on a storey is reachable, then extra doors for loops, then the stairs.
func _link() -> void:
	var candidates := {}  # _pair -> Array of [floor, cell, direction]
	for floor_index in FLOORS:
		for x in COLUMNS:
			for y in ROWS:
				var cell := Vector2i(x, y)
				for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
					var next := cell + direction
					if not _inside(next):
						continue
					var a := _room_of(floor_index, cell)
					var b := _room_of(floor_index, next)
					if a != b and _door_allowed(a, cell) and _door_allowed(b, next):
						var edges: Array = candidates.get_or_add(_pair(a, b), [])
						edges.append([floor_index, cell, direction])

	var pairs: Array = candidates.keys()
	_shuffle(pairs)
	var group := range(_rooms.size())  # Union-find parents.
	for pair: Vector2i in pairs:
		var a := _root(group, pair.x)
		var b := _root(group, pair.y)
		if a != b:
			group[a] = b
			_open(pair, candidates[pair])
		elif _rng.randf() < EXTRA_DOORS:
			_open(pair, candidates[pair])

	for room in _rooms.size():
		if is_stairs(room) and floor_of(room) > 0:
			var below := _room_of(floor_of(room) - 1, _stairs.position)
			_links[_pair(below, room)] = {"stairs": true}
			_connect(below, room)


## A doorway through one of the walls a and b share, at a random cell edge and
## a random point along it, so the way on is not obvious from mid-room.
func _open(pair: Vector2i, edges: Array) -> void:
	var edge: Array = edges[_rng.randi() % edges.size()]
	var floor_index: int = edge[0]
	var cell: Vector2i = edge[1]
	var direction: Vector2i = edge[2]
	var stairs := is_stairs(pair.x) or is_stairs(pair.y)
	var width := ARCH_WIDTH if not stairs and _rng.randf() < ARCHES else DOOR_WIDTH
	var slack := (CELL - WALL_THICKNESS - width) / 2.0 - 0.05
	var along := Vector3.BACK if direction.x != 0 else Vector3.RIGHT
	var offset := _rng.randf_range(-slack, slack)
	var normal := Vector3(direction.x, 0, direction.y)
	var point := _cell_centre(cell.x, cell.y, floor_index) + normal * CELL / 2.0 + along * offset
	if _room_of(floor_index, cell) != pair.x:
		normal = -normal  # Always from the lower-numbered room; see route().
	var link := {"point": point, "normal": normal, "width": width, "offset": offset}
	_links[pair] = link
	_openings[_edge_key(floor_index, cell, direction)] = link
	_connect(pair.x, pair.y)


## The stair room only has doors off its landing: the bottom one on the ground
## floor, the top one upstairs. Elsewhere the ramp or the stairwell is in the way.
func _door_allowed(room: int, cell: Vector2i) -> bool:
	return not is_stairs(room) or cell.y == _landing(room)


func _landing(stair_room: int) -> int:
	return _stairs.end.y - 1 if floor_of(stair_room) == 0 else _stairs.position.y


## The truck goes in the ground-floor room on the south edge nearest the middle
## that is big enough for it and the players behind it.
func _place_truck() -> void:
	var best_gap := INF
	for room in _rooms.size():
		var rect: Rect2i = _rooms[room]["rect"]
		var fits := rect.size.x >= 2 and rect.size.y >= 2
		if floor_of(room) != 0 or rect.end.y != ROWS or not fits or is_stairs(room):
			continue
		var gap := absf(rect.get_center().x - COLUMNS / 2.0)
		if gap < best_gap:
			best_gap = gap
			spawn_room = room
	var bounds := room_bounds(spawn_room)
	var south := bounds.end.y - WALL_THICKNESS / 2.0
	truck = Vector3(bounds.get_center().x, 1.0, south - TRUCK_SIZE.z / 2.0 - 0.2)
	spawn = Vector3(truck.x, 0.1, truck.z - TRUCK_SIZE.z / 2.0 - 1.5)


# Building ------------------------------------------------------------------


## Every wall on one storey: wherever neighbouring cells belong to different
## rooms, plus the outside. Runs of plain wall along a grid line merge into one
## box; a cell edge with a doorway gets two jambs and a lintel.
func _build_walls(parent: Node3D, floor_index: int) -> void:
	var tint := Color(0.5, 0.47, 0.42) if floor_index == 0 else Color(0.43, 0.46, 0.5)
	var material := Models.textured(tint, Vector2(1, 3), 0.15, 0.9, 0.0, 0.03, 4.0)
	# axis 0: north-south walls on the line east of column `line`; axis 1:
	# east-west walls south of row `line`. Line -1 is the outer west/north wall.
	for axis in 2:
		var lines := COLUMNS if axis == 0 else ROWS
		var length := ROWS if axis == 0 else COLUMNS
		var direction := Vector2i.RIGHT if axis == 0 else Vector2i.DOWN
		for line in range(-1, lines):
			var run_start := -1
			for i in length + 1:
				var cell := Vector2i(line, i) if axis == 0 else Vector2i(i, line)
				var is_wall := i < length and _is_wall(floor_index, cell, direction)
				var opening: Dictionary = _openings.get(_edge_key(floor_index, cell, direction), {})
				if is_wall and opening.is_empty():
					if run_start < 0:
						run_start = i
					continue
				if run_start >= 0:
					_wall_run(parent, floor_index, axis, line, Vector2i(run_start, i), material)
					run_start = -1
				if not opening.is_empty():
					_doorway(parent, floor_index, cell, direction, opening, material)


func _is_wall(floor_index: int, cell: Vector2i, direction: Vector2i) -> bool:
	var next := cell + direction
	if not _inside(cell) or not _inside(next):
		return _inside(cell) or _inside(next)
	return _room_of(floor_index, cell) != _room_of(floor_index, next)


## Plain wall along a grid line, over cells span.x to span.y (exclusive).
func _wall_run(
	parent: Node3D, floor_index: int, axis: int, line: int, span: Vector2i, material: Material
) -> void:
	var fixed := (line + 1) * CELL - (_half_x() if axis == 0 else _half_z())
	var from := span.x * CELL - (_half_z() if axis == 0 else _half_x())
	var middle := from + (span.y - span.x) * CELL / 2.0
	var length := (span.y - span.x) * CELL + WALL_THICKNESS
	var y := floor_index * STOREY + WALL_HEIGHT / 2.0
	if axis == 0:
		_box(
			parent,
			Vector3(fixed, y, middle),
			Vector3(WALL_THICKNESS, WALL_HEIGHT, length),
			material
		)
	else:
		_box(
			parent,
			Vector3(middle, y, fixed),
			Vector3(length, WALL_HEIGHT, WALL_THICKNESS),
			material
		)


## One cell edge with an opening: a jamb either side and a lintel above.
func _doorway(
	parent: Node3D,
	floor_index: int,
	cell: Vector2i,
	direction: Vector2i,
	opening: Dictionary,
	material: Material
) -> void:
	var along := Vector3.BACK if direction.x != 0 else Vector3.RIGHT
	var across := Vector3(WALL_THICKNESS, 0, WALL_THICKNESS) - along * WALL_THICKNESS
	var centre := _cell_centre(cell.x, cell.y, floor_index)
	centre += Vector3(direction.x, 0, direction.y) * CELL / 2.0
	var offset: float = opening["offset"]
	var width: float = opening["width"]
	var up := Vector3.UP * WALL_HEIGHT
	var half := CELL / 2.0
	for piece: Vector2 in [
		Vector2(-half, offset - width / 2.0), Vector2(offset + width / 2.0, half)
	]:
		var length := piece.y - piece.x
		var middle := centre + along * (piece.x + piece.y) / 2.0
		_box(parent, middle + up / 2.0, across + along * length + up, material)
	var lintel := WALL_HEIGHT - DOOR_HEIGHT
	var lintel_at := centre + along * offset + Vector3.UP * (DOOR_HEIGHT + lintel / 2.0)
	_box(parent, lintel_at, across + along * width + Vector3.UP * lintel, material)


## The room's floor surface and maybe a lamp.
func _furnish(parent: Node3D, room: int) -> void:
	var bounds := room_bounds(room)
	if is_stairs(room) and floor_of(room) > 0:
		# Only the top landing has floor; the rest is stairwell.
		bounds = Rect2(bounds.position, Vector2(CELL, CELL))
	var surface := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(bounds.size.x, 0.02, bounds.size.y)
	surface.mesh = mesh
	surface.material_override = _floor_material(kind(room))
	var middle := bounds.get_center()
	surface.position = Vector3(middle.x, floor_height(room) + 0.011, middle.y)
	parent.add_child(surface)

	if room == spawn_room or (not is_stairs(room) and _rng.randf() < LIT_ROOMS):
		var lamp := OmniLight3D.new()
		lamp.position = anchor(room) + Vector3.UP * (WALL_HEIGHT - 0.4)
		lamp.light_color = Color(1.0, 0.8, 0.55)
		lamp.light_energy = 0.8
		lamp.omni_range = clampf(maxf(bounds.size.x, bounds.size.y) * 0.7, 5.0, 11.0)
		lamp.shadow_enabled = true
		parent.add_child(lamp)


func _floor_material(room_kind: String) -> StandardMaterial3D:
	match room_kind:
		"large":  # Parquet: tight wood grain.
			return Models.textured(Color(0.5, 0.33, 0.18), Vector2(1, 6), 0.4, 0.45, 0.0, 0.06, 2.0)
		"medium":  # Carpet: soft, one colour per house.
			var carpets := [Color(0.45, 0.15, 0.15), Color(0.2, 0.3, 0.45), Color(0.3, 0.38, 0.22)]
			var carpet: Color = carpets[_stairs.position.x % carpets.size()]
			return Models.textured(carpet, Vector2.ONE, 0.25, 1.0, 0.0, 0.3, 1.5)
		"small":  # Tile: pale and glossy.
			return Models.textured(Color(0.78, 0.78, 0.74), Vector2.ONE, 0.15, 0.25, 0.0, 0.15, 1.0)
		"hallway":  # Runner: dark worn boards.
			return Models.textured(Color(0.3, 0.2, 0.13), Vector2(1, 8), 0.45, 0.6, 0.0, 0.05, 3.0)
	# Stairs: bare concrete.
	return Models.textured(Color(0.45, 0.45, 0.45), Vector2.ONE, 0.25, 0.95, 0.0, 0.08, 2.0)


## The ramp that players and monsters walk on, plus visual steps, rising north
## from the bottom landing to the top landing over three cells.
func _build_stairs(parent: Node3D) -> void:
	var x := _cell_centre(_stairs.position.x, 0, 0).x
	var z_low := _cell_corner(Vector2i(0, _stairs.end.y - 1)).y
	var z_high := _cell_corner(Vector2i(0, _stairs.position.y + 1)).y
	var run := z_low - z_high
	var width := CELL - WALL_THICKNESS
	var angle := atan2(STOREY, run)
	var ramp := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, SLAB, Vector2(run, STOREY).length())
	var collision := CollisionShape3D.new()
	collision.shape = shape
	ramp.add_child(collision)
	ramp.rotation.x = angle
	var normal := Vector3(0, cos(angle), sin(angle))
	ramp.position = Vector3(x, STOREY / 2.0, (z_low + z_high) / 2.0) - normal * SLAB / 2.0
	parent.add_child(ramp)

	var concrete := _floor_material("stairs")
	var depth := run / STAIR_STEPS
	for i in STAIR_STEPS:
		# Step tops sit half a riser above the ramp at their front edge, so feet
		# on the smooth ramp look like they are on the steps.
		var height := (i + 0.5) * STOREY / STAIR_STEPS
		var step := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(width, height, depth)
		step.mesh = mesh
		step.material_override = concrete
		step.position = Vector3(x, height / 2.0, z_low - (i + 0.5) * depth)
		parent.add_child(step)


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
	var plate_material := _plain(Color(0.2, 0.9, 0.4))
	plate_material.emission_enabled = true
	plate_material.emission = Color(0.1, 0.6, 0.25)
	plate_mesh.material = plate_material
	plate.mesh = plate_mesh
	plate.position.y = 0.03 - TRUCK_SIZE.y / 2.0
	area.add_child(plate)
	var sign_label := Label3D.new()
	sign_label.text = "TRUCK"
	sign_label.font_size = 96
	sign_label.position = Vector3(0, 0.6, TRUCK_SIZE.z / 2.0 + 0.1)
	sign_label.rotation.y = PI
	area.add_child(sign_label)
	parent.add_child(area)
	return area


# Helpers -------------------------------------------------------------------


func _room_of(floor_index: int, cell: Vector2i) -> int:
	return _cells[floor_index][cell.y * COLUMNS + cell.x]


func _connect(a: int, b: int) -> void:
	(_adjacent.get_or_add(a, []) as Array).append(b)
	(_adjacent.get_or_add(b, []) as Array).append(a)


## Fisher-Yates with the house's own RNG. Array.shuffle() uses the global RNG,
## which differs per peer, so clients would build a different house.
func _shuffle(items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var held: Variant = items[i]
		items[i] = items[j]
		items[j] = held


func _cell_corner(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * CELL - _half_x(), cell.y * CELL - _half_z())


func _cell_centre(x: int, y: int, floor_index: int) -> Vector3:
	var corner := _cell_corner(Vector2i(x, y))
	return Vector3(corner.x + CELL / 2.0, floor_index * STOREY, corner.y + CELL / 2.0)


func _inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < COLUMNS and cell.y < ROWS


func _half_x() -> float:
	return COLUMNS * CELL / 2.0


func _half_z() -> float:
	return ROWS * CELL / 2.0


## The same key for a-b and b-a.
static func _pair(a: int, b: int) -> Vector2i:
	return Vector2i(mini(a, b), maxi(a, b))


static func _edge_key(floor_index: int, cell: Vector2i, direction: Vector2i) -> Vector4i:
	return Vector4i(floor_index, cell.x, cell.y, 0 if direction.x != 0 else 1)


static func _root(group: Array, room: int) -> int:
	while group[room] != room:
		room = group[room]
	return room


## rect with hole cut out, as up to four rectangles.
static func _minus(rect: Rect2, hole: Rect2) -> Array[Rect2]:
	var pieces: Array[Rect2] = []
	if not hole.has_area():
		pieces.append(rect)
		return pieces
	for piece: Rect2 in [
		Rect2(rect.position.x, rect.position.y, hole.position.x - rect.position.x, rect.size.y),
		Rect2(hole.end.x, rect.position.y, rect.end.x - hole.end.x, rect.size.y),
		Rect2(hole.position.x, rect.position.y, hole.size.x, hole.position.y - rect.position.y),
		Rect2(hole.position.x, hole.end.y, hole.size.x, rect.end.y - hole.end.y),
	]:
		if piece.has_area():
			pieces.append(piece)
	return pieces


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


static func _plain(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material
