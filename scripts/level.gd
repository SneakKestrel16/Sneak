extends RefCounted
## Generates and builds the site from a seed, so every peer builds the same one.
##
## The site is a SITE_COLUMNS x SITE_ROWS grid of CELL-metre cells inside a
## stone wall. Most of it is one big two-storey facility; round it is yard:
## grass, gravel paths from the truck to the facility's doors, trees and lamp
## posts. The truck waits just inside the gate on the south wall, where
## everyone spawns.
##
## Each storey is split recursively (binary space partition) into rooms of
## varying size, each kind with its own floor surface. STAIRWELLS stair rooms
## sit at the same spots on both storeys and no cut ever crosses them. A random
## spanning tree of doors joins the rooms, plus extra doors and wide arches for
## loops, and the facility gets several doors to the yard. Cupboards and
## dressers stand against room walls (`furniture`, built by game.gd), and
## themed furniture and decorations dress each room (`decor`, see decor.gd).
##
## For routing, every yard cell is a room of its own (open to its neighbours),
## so rooms are numbered across storeys and the yard. Every room but a stair
## room is a rectangle whose furniture keeps clear of the straight lines
## monsters walk between its doorways and its middle.

const Models := preload("res://scripts/models.gd")
const Props := preload("res://scripts/props.gd")
const Cabinet := preload("res://scripts/cabinet.gd")
const Decor := preload("res://scripts/decor.gd")

const CELL := 3.0
const SITE_COLUMNS := 34
const SITE_ROWS := 28
const STOREY := 3.4  ## Floor to floor.
const SLAB := 0.2
const WALL_HEIGHT := STOREY - SLAB
const WALL_THICKNESS := 0.2
const DOOR_WIDTH := 1.8
const ARCH_WIDTH := 2.6
## Clears the monster's 2.4 m capsule; at 2.3 it jammed under every lintel.
const DOOR_HEIGHT := 2.6

const FACILITY_SIZE := Vector2i(26, 18)
const FLOORS := 2
const STAIRWELLS := 2  ## One in each half of the facility, so no way upstairs is too far.
const FACILITY_DOORS := 4
const FACILITY_TINT := Color(0.5, 0.5, 0.47)  ## Painted block.
const BORDER := 2  ## Cells of yard between the facility and the stone wall.
const CLEARANCE := 2  ## Cells of yard between the facility and the truck yard.
const TRUCK_YARD := Vector2i(5, 6)  ## Half-width and depth (cells) kept clear around the truck.

const MIN_SIDE := 2  ## Cells. No cut leaves a room narrower than this.
const MAX_AREA := 24  ## Cells. Bigger rooms are always split further.
const STOP_CHANCE := 0.4  ## Chance a room small enough to stay whole does.
const EXTRA_DOORS := 0.35  ## Chance a neighbour pair the tree left apart gets a door anyway.
const ARCHES := 0.2  ## Chance an inside doorway is a wide arch instead.
const LIT_ROOMS := 0.45  ## Chance a room has a lamp; the rest need flashlights.
const STAIR_LENGTH := 5  ## Cells: bottom landing, three of ramp, top landing.
const STAIR_STEPS := 12

const TREES := 0.08  ## Chance a free yard cell gets a tree (if the yard stays connected).
const LAMP_EVERY := 6  ## Path cells between lamp posts.
const PERIMETER_HEIGHT := 3.6
const PERIMETER_THICKNESS := 0.8
const GATE_WIDTH := 5.0

const TRUCK_SIZE := Vector3(4.0, 2.0, 2.4)
const APPROACH := 0.9  ## How far from a doorway walkers line up before going through (m).

const NO_ROOM := -1
const TREE := -2
const OUTDOOR_KINDS: Array[String] = ["yard", "path"]
const FURNITURE := {"small": 1, "medium": 2, "large": 4}  ## Most pieces per room kind.
const DOOR_KEEP := 2.5  ## Furniture stays this far from doorways (m), so routes stay clear.

var spawn_room: int
var spawn: Vector3  ## Where players appear, just north of the truck bay.
var truck: Vector3  ## Centre of the truck bay (extraction zone).
## Cupboards and dressers: {"type": Cabinet.Type, "position": Vector3 (floor,
## middle of footprint), "yaw": float (front faces into the room), "room": int}.
var furniture: Array[Dictionary] = []
## Furniture and decorations that only dress rooms (Decor.place): name,
## position, yaw, room, tint.
var decor: Array[Dictionary] = []

## Per room: {"floor": int, "rect": Rect2i in site cells, "kind": String,
## "building": int (-1 outdoors), "stairwell": int (stair rooms only)}.
## Kinds: "stairs", "hallway", "small", "medium", "large" indoors; "yard" and
## "path" outdoors.
var _rooms: Array[Dictionary] = []
## Per building: {"rect": Rect2i, "floors": int, "tint": Color}. Just the facility.
var _buildings: Array[Dictionary] = []
## Per storey, the room of each cell (y * SITE_COLUMNS + x), NO_ROOM or TREE.
var _cells: Array[PackedInt32Array] = []
## Openings, keyed by _pair(a, b). Doors: {"point", "normal" (lower id to
## higher), "width", "offset"}; yard to yard: {"open": true, "point",
## "normal"}; stairs: {"stairs": true}.
var _links := {}
var _openings := {}  ## Edge key -> door link, for building walls with gaps.
var _adjacent := {}  ## Room id -> Array of linked room ids.
var _stairs: Array[Rect2i] = []  ## Stair rooms' cells, the same on both storeys.
var _paths := {}  ## Yard cells that are gravel paths.
var _trees: Array[Vector2i] = []
var _rng := RandomNumberGenerator.new()


func _init(seed_value: int) -> void:
	_rng.seed = seed_value
	for floor_index in FLOORS:
		var cells := PackedInt32Array()
		cells.resize(SITE_COLUMNS * SITE_ROWS)
		cells.fill(NO_ROOM)
		_cells.append(cells)
	_place_buildings()
	for building in _buildings.size():
		var floors: int = _buildings[building]["floors"]
		for floor_index in floors:
			_split(_buildings[building]["rect"], floor_index, building)
	var exits := _choose_exits()
	_lay_paths(exits)
	_plant_trees(exits)
	_fill_yard()
	_link(exits)
	_place_truck()
	_place_furniture()
	decor = Decor.place(self, _rng)


func room_count() -> int:
	return _rooms.size()


func is_stairs(room: int) -> bool:
	return _rooms[room]["kind"] == "stairs"


func is_outdoors(room: int) -> bool:
	return _rooms[room]["kind"] in OUTDOOR_KINDS


func kind(room: int) -> String:
	return _rooms[room]["kind"]


func floor_of(room: int) -> int:
	return _rooms[room]["floor"]


func floor_height(room: int) -> float:
	return floor_of(room) * STOREY


## The stair rooms, bottom storey first.
func stair_rooms() -> Array[int]:
	var found: Array[int] = []
	for room in _rooms.size():
		if is_stairs(room):
			found.append(room)
	return found


## Stairwell i's stair room on each storey, bottom first.
func stairwell(i: int) -> Array[int]:
	var found: Array[int] = []
	for room in stair_rooms():
		if _rooms[room]["stairwell"] == i:
			found.append(room)
	return found


## Furniture standing in room.
func furniture_in(room: int) -> Array[Dictionary]:
	return furniture.filter(func(piece: Dictionary) -> bool: return piece["room"] == room)


## The room's floor area in world space, x and z.
func room_bounds(room: int) -> Rect2:
	var rect: Rect2i = _rooms[room]["rect"]
	return Rect2(_cell_corner(rect.position), Vector2(rect.size) * CELL)


## Where to stand in a room: its middle, or a landing for the stair room.
func anchor(room: int) -> Vector3:
	if is_stairs(room):
		return _cell_centre(_stair_rect(room).position.x, _landing(room), floor_of(room))
	var middle := room_bounds(room).get_center()
	return Vector3(middle.x, floor_height(room), middle.y)


## The room containing point, judging the storey by its height.
func room_at(point: Vector3) -> int:
	var floor_index := clampi(floori((point.y + 1.0) / STOREY), 0, FLOORS - 1)
	var x := clampi(floori((point.x + _half_x()) / CELL), 0, SITE_COLUMNS - 1)
	var y := clampi(floori((point.z + _half_z()) / CELL), 0, SITE_ROWS - 1)
	var room := _cells[floor_index][y * SITE_COLUMNS + x]
	if room == NO_ROOM:  # Above the yard: only the house has an upper storey.
		room = _cells[0][y * SITE_COLUMNS + x]
	if room == TREE:  # Brushing a trunk: count it as a neighbouring cell.
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := Vector2i(x, y) + step
			if _inside(next) and _room_of(0, next) >= 0:
				return _room_of(0, next)
	return room


## Rooms you can walk straight into from room: through a door, across open
## yard, or up the stairs.
func neighbours(room: int) -> Array:
	return _adjacent.get(room, [])


## Doorway centres of a room, on its floor (not open yard edges).
func doors(room: int) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for next: int in neighbours(room):
		var link: Dictionary = _links[_pair(room, next)]
		if link.has("width"):
			points.append(link["point"])
	return points


## Where monster routes enter and leave room: in front of each doorway or yard
## edge, or the landing for the stairs. Routes run straight between these and
## the room's anchor, so decor keeps clear of those lines.
func approaches(room: int) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for next: int in neighbours(room):
		var link: Dictionary = _links[_pair(room, next)]
		if link.has("stairs"):
			points.append(anchor(room))
		else:
			var normal: Vector3 = link["normal"] if room < next else -link["normal"]
			points.append(link["point"] - normal * APPROACH)
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
## up in front of each doorway or yard edge and step across, or walk landing to
## landing up or down the stairs. Indoor rooms on the way are crossed by their
## anchor, so a route only ever runs between a room's middle and its doorways.
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
		# Cross furnished rooms by their middle, the way their decor leaves clear.
		var crossing := previous != from and not is_stairs(previous) and not is_outdoors(previous)
		if crossing and points[0] != anchor(previous):
			points.push_front(anchor(previous))
		current = previous
	return points


## Builds the site under parent and returns the truck bay. Storeys go in their
## own nodes ("Floor0", "Floor1", then "Roof") so tools/map_view can hide the
## ones above the storey it looks at.
func build(parent: Node3D) -> Area3D:
	var storeys: Array[Node3D] = []
	for floor_index in FLOORS:
		var storey := Node3D.new()
		storey.name = "Floor%d" % floor_index
		parent.add_child(storey)
		storeys.append(storey)
	var roof := Node3D.new()
	roof.name = "Roof"
	parent.add_child(roof)

	_build_grounds(storeys[0])
	var slab_material := Props.plain(Color(0.25, 0.23, 0.21))
	var roof_material := Models.textured(
		Color(0.22, 0.2, 0.2), Vector2.ONE, 0.3, 0.9, 0.0, 0.1, 2.0
	)
	for building in _buildings.size():
		var rect: Rect2i = _buildings[building]["rect"]
		var area := Rect2(_cell_corner(rect.position), Vector2(rect.size) * CELL)
		var floors: int = _buildings[building]["floors"]
		for floor_index in range(1, floors):
			# Stairwells: open over each ramp and bottom landing.
			var pieces: Array[Rect2] = [area]
			for stairs in _stairs:
				var hole := Rect2(
					_cell_corner(stairs.position + Vector2i(0, 1)), Vector2(1, 4) * CELL
				)
				var cut: Array[Rect2] = []
				for piece in pieces:
					cut.append_array(_minus(piece, piece.intersection(hole)))
				pieces = cut
			for piece in pieces:
				var middle := piece.get_center()
				var at := Vector3(middle.x, floor_index * STOREY - SLAB / 2.0, middle.y)
				Props.box(
					storeys[floor_index],
					at,
					Vector3(piece.size.x, SLAB, piece.size.y),
					slab_material
				)
		var top := Vector3(area.get_center().x, floors * STOREY - SLAB / 2.0, area.get_center().y)
		Props.box(roof, top, Vector3(area.size.x + 0.6, SLAB, area.size.y + 0.6), roof_material)
	for floor_index in FLOORS:
		_build_walls(storeys[floor_index], floor_index)
	for room in _rooms.size():
		if not is_outdoors(room):
			_furnish(storeys[floor_of(room)], room)
	Decor.build(self, storeys)
	for stairs in _stairs:
		var stairs_x := _cell_centre(stairs.position.x, 0, 0).x
		var z_low := _cell_corner(Vector2i(0, stairs.end.y - 1)).y
		var z_high := _cell_corner(Vector2i(0, stairs.position.y + 1)).y
		var stairs_width := CELL - WALL_THICKNESS
		Props.stairs(storeys[0], stairs_x, z_low, z_high, stairs_width, STOREY, STAIR_STEPS)
	var half := Vector2(_half_x(), _half_z())
	Props.perimeter(storeys[0], half, PERIMETER_THICKNESS, PERIMETER_HEIGHT, truck.x, GATE_WIDTH)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.02, 0.025, 0.04)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.25, 0.27, 0.35)
	environment.ambient_light_energy = 0.15
	var world := WorldEnvironment.new()
	world.environment = environment
	parent.add_child(world)
	var moon := DirectionalLight3D.new()
	moon.rotation = Vector3(-0.9, 0.6, 0)
	moon.light_color = Color(0.6, 0.7, 1.0)
	moon.light_energy = 0.12
	moon.shadow_enabled = true
	parent.add_child(moon)
	return Props.truck_bay(parent, truck, TRUCK_SIZE)


# Generation ----------------------------------------------------------------


## The facility fills the site north of the truck yard, with yard all round;
## one stairwell goes in each of its halves (west, east).
func _place_buildings() -> void:
	var truck_yard := _truck_yard()
	var facility := Rect2i(Vector2i.ZERO, FACILITY_SIZE)
	facility.position.x = _rng.randi_range(BORDER, SITE_COLUMNS - BORDER - FACILITY_SIZE.x)
	var last_row := truck_yard.position.y - CLEARANCE - FACILITY_SIZE.y
	facility.position.y = _rng.randi_range(BORDER, maxi(BORDER, last_row))
	_buildings.append({"rect": facility, "floors": FLOORS, "tint": FACILITY_TINT})
	var part := floori(FACILITY_SIZE.x / float(STAIRWELLS))
	for i in STAIRWELLS:
		var left := facility.position.x + i * part
		var x := _rng.randi_range(left + 1, left + part - 2)
		var y := _rng.randi_range(facility.position.y, facility.end.y - STAIR_LENGTH - 1)
		_stairs.append(Rect2i(x, y, 1, STAIR_LENGTH))


## The cells kept clear in front of the gate for the truck and spawn.
func _truck_yard() -> Rect2i:
	var middle := floori(SITE_COLUMNS / 2.0)
	var depth := TRUCK_YARD.y
	return Rect2i(middle - TRUCK_YARD.x, SITE_ROWS - depth, TRUCK_YARD.x * 2, depth)


## Splits a building storey into rooms, never cutting through the stair room.
func _split(rect: Rect2i, floor_index: int, building: int) -> void:
	if rect.get_area() <= MAX_AREA and _rng.randf() < STOP_CHANCE:
		_add_leaf(rect, floor_index, building)
		return
	var cuts: Array[Vector2i] = []  # (axis, position)
	var longer := 0 if rect.size.x >= rect.size.y else 1
	for axis in 2:
		for at in range(rect.position[axis] + MIN_SIDE, rect.end[axis] - MIN_SIDE + 1):
			var through_stairs := false
			for stairs in _stairs:
				var inside := stairs.position[axis] < at and at < stairs.end[axis]
				through_stairs = through_stairs or (rect.intersects(stairs) and inside)
			if not through_stairs:
				cuts.append(Vector2i(axis, at))
	if cuts.is_empty():
		_add_leaf(rect, floor_index, building)
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
	_split(first, floor_index, building)
	_split(second, floor_index, building)


## Adds a finished piece as a room. A piece holding a stair room is cut around
## it (left, right, then above and below it), which often leaves hallways; the
## pieces are checked again in case they hold another stairwell.
func _add_leaf(rect: Rect2i, floor_index: int, building: int) -> void:
	var held := -1
	for i in _stairs.size():
		if rect.encloses(_stairs[i]):
			held = i
	if held < 0:
		_add_room(rect, floor_index, building)
		return
	var s := _stairs[held]
	var pieces: Array[Rect2i] = [
		Rect2i(rect.position.x, rect.position.y, s.position.x - rect.position.x, rect.size.y),
		Rect2i(s.end.x, rect.position.y, rect.end.x - s.end.x, rect.size.y),
		Rect2i(s.position.x, rect.position.y, s.size.x, s.position.y - rect.position.y),
		Rect2i(s.position.x, s.end.y, s.size.x, rect.end.y - s.end.y),
	]
	for piece in pieces:
		if piece.has_area():
			_add_leaf(piece, floor_index, building)
	_add_room(s, floor_index, building, "stairs", held)


func _add_room(
	rect: Rect2i, floor_index: int, building: int, room_kind := "", stairwell_index := -1
) -> void:
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
	var room_data := {"floor": floor_index, "rect": rect, "kind": room_kind, "building": building}
	if stairwell_index >= 0:
		room_data["stairwell"] = stairwell_index
	_rooms.append(room_data)
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			_cells[floor_index][y * SITE_COLUMNS + x] = room


## Picks each building's doors to the yard: [room inside, yard cell outside,
## edge]. The facility gets FACILITY_DOORS, on different
## rooms where possible; never the stair room.
func _choose_exits() -> Array:
	var by_building := {}
	for x in SITE_COLUMNS:
		for y in SITE_ROWS:
			var cell := Vector2i(x, y)
			for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
				var next := cell + direction
				if not _inside(next):
					continue
				var a := _room_of(0, cell)
				var b := _room_of(0, next)
				if (a >= 0) == (b >= 0):
					continue  # Both inside or both outside.
				var inside := a if a >= 0 else b
				if is_stairs(inside):
					continue
				var outside := next if a >= 0 else cell
				var options: Array = by_building.get_or_add(_rooms[inside]["building"], [])
				options.append([inside, outside, [0, cell, direction]])
	var exits := []
	for building: int in by_building:
		var options: Array = by_building[building]
		_shuffle(options)
		var wanted := FACILITY_DOORS
		var used_rooms := {}
		for option: Array in options:
			if used_rooms.size() >= wanted:
				break
			if not used_rooms.has(option[0]):
				used_rooms[option[0]] = true
				exits.append(option)
	return exits


## Gravel paths: the shortest way over open ground from the truck to each
## building door.
func _lay_paths(exits: Array) -> void:
	var start := _truck_cell()
	var came_from := {start: start}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		for step: Vector2i in [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]:
			var next := cell + step
			if _inside(next) and _room_of(0, next) == NO_ROOM and not came_from.has(next):
				came_from[next] = cell
				queue.append(next)
	for exit: Array in exits:
		var cell: Vector2i = exit[1]
		while came_from.has(cell) and cell != start:
			_paths[cell] = true
			cell = came_from[cell]


## Trees on open ground, but never on a path, by a door or the truck, and never
## where one would cut part of the yard off.
func _plant_trees(exits: Array) -> void:
	var keep_clear := {}
	for exit: Array in exits:
		var door_cell: Vector2i = exit[1]
		for x in range(-1, 2):
			for y in range(-1, 2):
				keep_clear[door_cell + Vector2i(x, y)] = true
	var truck_yard := _truck_yard().grow(1)
	var open: Array[Vector2i] = []
	for x in SITE_COLUMNS:
		for y in SITE_ROWS:
			var cell := Vector2i(x, y)
			if _room_of(0, cell) == NO_ROOM:
				open.append(cell)
	var candidates: Array = open.duplicate()
	_shuffle(candidates)
	var open_count := open.size()
	for cell: Vector2i in candidates:
		if _paths.has(cell) or keep_clear.has(cell) or truck_yard.has_point(cell):
			continue
		if _rng.randf() >= TREES:
			continue
		_cells[0][cell.y * SITE_COLUMNS + cell.x] = TREE
		if _open_reachable() == open_count - 1:
			open_count -= 1
			_trees.append(cell)
		else:
			_cells[0][cell.y * SITE_COLUMNS + cell.x] = NO_ROOM


## How many open yard cells can be reached from the truck.
func _open_reachable() -> int:
	var start := _truck_cell()
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		for step: Vector2i in [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]:
			var next := cell + step
			if _inside(next) and _room_of(0, next) == NO_ROOM and not seen.has(next):
				seen[next] = true
				queue.append(next)
	return seen.size()


## Every open ground cell becomes a one-cell yard (or path) room.
func _fill_yard() -> void:
	for y in SITE_ROWS:
		for x in SITE_COLUMNS:
			var cell := Vector2i(x, y)
			if _room_of(0, cell) == NO_ROOM:
				var room_kind := "path" if _paths.has(cell) else "yard"
				_add_room(Rect2i(cell, Vector2i.ONE), 0, -1, room_kind)


## Joins rooms: inside each building a random spanning tree of doors (Kruskal)
## plus extra doors for loops; the stairs; every yard cell to its open
## neighbours; and each building's chosen doors to the yard.
func _link(exits: Array) -> void:
	var candidates := {}  # _pair -> Array of [floor, cell, direction]
	for floor_index in FLOORS:
		for x in SITE_COLUMNS:
			for y in SITE_ROWS:
				var cell := Vector2i(x, y)
				for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
					var next := cell + direction
					if not _inside(next):
						continue
					var a := _room_of(floor_index, cell)
					var b := _room_of(floor_index, next)
					if a < 0 or b < 0 or a == b:
						continue
					if is_outdoors(a) and is_outdoors(b):
						var normal := Vector3(direction.x, 0, direction.y)
						var middle := _cell_centre(cell.x, cell.y, 0) + normal * CELL / 2.0
						_links[_pair(a, b)] = {"open": true, "point": middle, "normal": normal}
						_connect(a, b)
					elif not is_outdoors(a) and not is_outdoors(b):
						if _door_allowed(a, cell) and _door_allowed(b, next):
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

	for i in _stairs.size():
		var rooms := stairwell(i)
		_links[_pair(rooms[0], rooms[1])] = {"stairs": true}
		_connect(rooms[0], rooms[1])

	for exit: Array in exits:
		var outside: Vector2i = exit[1]
		_open(_pair(exit[0], _room_of(0, outside)), [exit[2]], false)


## A doorway on one of the given cell edges, at a random point along it, so
## the way on is not obvious from mid-room.
func _open(pair: Vector2i, edges: Array, arches := true) -> void:
	var edge: Array = edges[_rng.randi() % edges.size()]
	var floor_index: int = edge[0]
	var cell: Vector2i = edge[1]
	var direction: Vector2i = edge[2]
	var plain := not arches or is_stairs(pair.x) or is_stairs(pair.y)
	var width := DOOR_WIDTH if plain or _rng.randf() >= ARCHES else ARCH_WIDTH
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
	var stairs := _stair_rect(stair_room)
	return stairs.end.y - 1 if floor_of(stair_room) == 0 else stairs.position.y


func _stair_rect(stair_room: int) -> Rect2i:
	return _stairs[_rooms[stair_room]["stairwell"]]


func _truck_cell() -> Vector2i:
	return Vector2i(floori(SITE_COLUMNS / 2.0), SITE_ROWS - 1)


## The truck parks just inside the gate; players spawn in front of it.
func _place_truck() -> void:
	var south := _half_z() - TRUCK_SIZE.z / 2.0 - 0.4
	var middle := _cell_corner(Vector2i(floori(SITE_COLUMNS / 2.0), 0)).x
	truck = Vector3(middle, 1.0, south)
	spawn = Vector3(middle, 0.1, south - TRUCK_SIZE.z / 2.0 - 2.0)
	spawn_room = room_at(spawn)


## Cupboards and dressers against room walls, front into the room, clear of
## doorways (so monster routes stay clear) and of each other. Hallways and
## stair rooms get none.
func _place_furniture() -> void:
	for room in _rooms.size():
		if not FURNITURE.has(kind(room)):
			continue
		var wanted := _rng.randi_range(0, FURNITURE[kind(room)])
		var bounds := room_bounds(room).grow(-WALL_THICKNESS / 2.0)
		for attempt in wanted * 4:
			if furniture_in(room).size() >= wanted:
				break
			var type := _rng.randi() % Cabinet.SIZES.size()
			var size: Vector3 = Cabinet.SIZES[type]
			var side := _rng.randi() % 4  # West, east, north, south wall.
			var along_x := side >= 2
			var span := bounds.size.x if along_x else bounds.size.y
			if span < size.x + 0.6:
				continue
			var slide := _rng.randf_range(-(span - size.x) / 2.0 + 0.3, (span - size.x) / 2.0 - 0.3)
			var middle := bounds.get_center()
			var at := Vector3.ZERO
			var yaw := 0.0
			match side:
				0:
					at = Vector3(bounds.position.x + size.z / 2.0 + 0.02, 0, middle.y + slide)
					yaw = PI / 2.0
				1:
					at = Vector3(bounds.end.x - size.z / 2.0 - 0.02, 0, middle.y + slide)
					yaw = -PI / 2.0
				2:
					at = Vector3(middle.x + slide, 0, bounds.position.y + size.z / 2.0 + 0.02)
				3:
					at = Vector3(middle.x + slide, 0, bounds.end.y - size.z / 2.0 - 0.02)
					yaw = PI
			at.y = floor_height(room)
			var clear := true
			for door in doors(room):
				clear = clear and at.distance_to(door) >= DOOR_KEEP + size.x / 2.0
			for piece in furniture_in(room):
				var gap: float = (size.x + Cabinet.SIZES[piece["type"]].x) / 2.0 + 0.4
				clear = clear and at.distance_to(piece["position"]) >= gap
			if clear:
				furniture.append({"type": type, "position": at, "yaw": yaw, "room": room})


# Building ------------------------------------------------------------------


## Grass over the whole site, gravel on the paths, trees, lamp posts and a few
## rocks and bushes.
func _build_grounds(parent: Node3D) -> void:
	var size := Vector2(SITE_COLUMNS, SITE_ROWS) * CELL
	var soil := Props.plain(Color(0.2, 0.17, 0.12))
	Props.box(parent, Vector3(0, -0.5, 0), Vector3(size.x + 4.0, 1.0, size.y + 4.0), soil)
	var grass := Models.textured(Color(0.2, 0.3, 0.13), Vector2.ONE, 0.35, 1.0, 0.0, 0.15, 2.5)
	Props.surface(parent, Rect2(-size / 2.0, size), 0.004, grass)
	var gravel := Models.textured(Color(0.45, 0.42, 0.37), Vector2.ONE, 0.3, 1.0, 0.0, 0.4, 1.0)
	var count := 0
	for cell: Vector2i in _paths:
		Props.surface(parent, Rect2(_cell_corner(cell), Vector2.ONE * CELL), 0.008, gravel)
		count += 1
		if count % LAMP_EVERY == 0:
			Props.lamp_post(parent, _cell_centre(cell.x, cell.y, 0) + Vector3(1.0, 0, 1.0))
	for cell in _trees:
		Props.tree(parent, _cell_centre(cell.x, cell.y, 0), _rng.randf_range(4.0, 7.0))
	for i in 40:
		var cell := Vector2i(
			_rng.randi_range(0, SITE_COLUMNS - 1), _rng.randi_range(0, SITE_ROWS - 1)
		)
		var room := _room_of(0, cell)
		if room < 0 or kind(room) != "yard":
			continue
		var jitter := Vector3(_rng.randf_range(-1.2, 1.2), 0, _rng.randf_range(-1.2, 1.2))
		var at := _cell_centre(cell.x, cell.y, 0) + jitter
		Props.lump(parent, at, _rng.randf_range(0.2, 0.5), i % 2 == 1)


## Every building wall on one storey: wherever a building room meets a
## different room or open ground. Runs of plain wall along a grid line merge
## into one box; a cell edge with a doorway gets two jambs and a lintel.
func _build_walls(parent: Node3D, floor_index: int) -> void:
	# axis 0: north-south walls on the line east of column `line`; axis 1:
	# east-west walls south of row `line`.
	for axis in 2:
		var lines := SITE_COLUMNS if axis == 0 else SITE_ROWS
		var length := SITE_ROWS if axis == 0 else SITE_COLUMNS
		var direction := Vector2i.RIGHT if axis == 0 else Vector2i.DOWN
		for line in range(-1, lines):
			var run_start := -1
			var run_material: Material = null
			for i in length + 1:
				var cell := Vector2i(line, i) if axis == 0 else Vector2i(i, line)
				var building := _wall_owner(floor_index, cell, direction) if i < length else -1
				var opening: Dictionary = _openings.get(_edge_key(floor_index, cell, direction), {})
				if building >= 0 and opening.is_empty():
					if run_start < 0:
						run_start = i
						run_material = _wall_material(building, floor_index)
					continue
				if run_start >= 0:
					var span := Vector2i(run_start, i)
					_wall_run(parent, floor_index, axis, line, span, run_material)
					run_start = -1
				if not opening.is_empty():
					var material := _wall_material(building, floor_index)
					_doorway(parent, floor_index, cell, direction, opening, material)


## The building a wall on this cell edge belongs to, or -1 for no wall: two
## cells of the same room, or open ground (yard, trees) on both sides.
func _wall_owner(floor_index: int, cell: Vector2i, direction: Vector2i) -> int:
	var a := _room_of(floor_index, cell) if _inside(cell) else NO_ROOM
	var next := cell + direction
	var b := _room_of(floor_index, next) if _inside(next) else NO_ROOM
	var a_building: int = _rooms[a]["building"] if a >= 0 else -1
	var b_building: int = _rooms[b]["building"] if b >= 0 else -1
	if a == b or (a_building < 0 and b_building < 0):
		return -1
	return a_building if a_building >= 0 else b_building


func _wall_material(building: int, floor_index: int) -> Material:
	var tint: Color = _buildings[building]["tint"]
	if floor_index > 0:
		tint = tint.lerp(Color(0.45, 0.48, 0.52), 0.6)  # Upstairs: cooler wallpaper.
	return Models.textured(tint, Vector2(1, 3), 0.18, 0.9, 0.0, 0.03, 4.0)


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
		Props.box(
			parent,
			Vector3(fixed, y, middle),
			Vector3(WALL_THICKNESS, WALL_HEIGHT, length),
			material
		)
	else:
		Props.box(
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
		Props.box(parent, middle + up / 2.0, across + along * length + up, material)
	var lintel := WALL_HEIGHT - DOOR_HEIGHT
	var lintel_at := centre + along * offset + Vector3.UP * (DOOR_HEIGHT + lintel / 2.0)
	Props.box(parent, lintel_at, across + along * width + Vector3.UP * lintel, material)


## The room's floor surface and maybe a lamp.
func _furnish(parent: Node3D, room: int) -> void:
	var bounds := room_bounds(room)
	if is_stairs(room) and floor_of(room) > 0:
		# Only the top landing has floor; the rest is stairwell.
		bounds = Rect2(bounds.position, Vector2(CELL, CELL))
	var material := _floor_material(kind(room))
	Props.surface(parent, bounds, floor_height(room) + 0.011, material)
	if not is_stairs(room) and _rng.randf() < LIT_ROOMS:
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
			var carpet: Color = carpets[_stairs[0].position.x % carpets.size()]
			return Models.textured(carpet, Vector2.ONE, 0.25, 1.0, 0.0, 0.3, 1.5)
		"small":  # Tile: pale and glossy.
			return Models.textured(Color(0.78, 0.78, 0.74), Vector2.ONE, 0.15, 0.25, 0.0, 0.15, 1.0)
		"hallway":  # Runner: dark worn boards.
			return Models.textured(Color(0.3, 0.2, 0.13), Vector2(1, 8), 0.45, 0.6, 0.0, 0.05, 3.0)
	# Stairs: bare concrete.
	return Models.textured(Color(0.45, 0.45, 0.45), Vector2.ONE, 0.25, 0.95, 0.0, 0.08, 2.0)


# Helpers -------------------------------------------------------------------


func _room_of(floor_index: int, cell: Vector2i) -> int:
	return _cells[floor_index][cell.y * SITE_COLUMNS + cell.x]


func _connect(a: int, b: int) -> void:
	(_adjacent.get_or_add(a, []) as Array).append(b)
	(_adjacent.get_or_add(b, []) as Array).append(a)


## Fisher-Yates with the site's own RNG. Array.shuffle() uses the global RNG,
## which differs per peer, so clients would build a different site.
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
	return cell.x >= 0 and cell.y >= 0 and cell.x < SITE_COLUMNS and cell.y < SITE_ROWS


func _half_x() -> float:
	return SITE_COLUMNS * CELL / 2.0


func _half_z() -> float:
	return SITE_ROWS * CELL / 2.0


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
