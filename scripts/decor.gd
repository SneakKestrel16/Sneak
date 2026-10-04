extends RefCounted
## Furniture and decorations that only dress the rooms: made in Blender
## (tools/blender/decor.py), which lists every model with its measured size and
## where it goes in assets/models/decor.json.
##
## Each indoor room gets a theme for its kind (THEMES), then pieces of that
## theme: a rug in the middle, pieces along the walls, in corners or standing
## free, and things hung on the walls. Placement draws on the level's RNG in a
## fixed order, so every peer furnishes the same site. Nothing solid goes
## where a monster walks: within ROUTE_CLEARANCE of the straight lines between
## a room's anchor and the points in front of its doorways (Level.approaches),
## which is all a monster route ever crosses a room by (Level.route).

const Models := preload("res://scripts/models.gd")
const Level := preload("res://scripts/level.gd")
const Cabinet := preload("res://scripts/cabinet.gd")

const CATALOGUE := "res://assets/models/decor.json"
## Room kind -> the themes a room of that kind may take.
const THEMES := {
	"large": ["living", "dining", "library", "storage"],
	"medium": ["bedroom", "office", "kitchen", "lab"],
	"small": ["bathroom", "storage"],
	"hallway": ["hall"],
}
## Floor area (m²) per floor piece, by room kind; the count varies by a quarter
## either way. Halls are narrow, so they get fewer.
const AREA_PER_PIECE := {"large": 6.0, "medium": 6.0, "small": 5.0, "hallway": 12.0}
const WALL_PER_HANG := 7.0  ## Metres of wall per thing hung on it, at most.
const RUG_CHANCE := 0.6
## Monster capsule radius (0.5 m) plus room to pass; solid pieces stay this far
## from monster lines.
const ROUTE_CLEARANCE := 0.7
const DOOR_KEEP := 1.2  ## Floor pieces stay this far from a doorway's centre (m).
const GAP := 0.2  ## Between pieces.
## Pieces farther from the camera than this are not drawn: with walls between,
## they could not be seen anyway, and they doubled the draw calls.
const DRAW_DISTANCE := 35.0
## Rooms narrower than this (one-cell halls) only get shallow pieces against
## the walls, so a monster can still get round loot in the middle.
const NARROW := 4.0
const NARROW_DEPTH := 0.45
## Most of any one piece in a room is two; these clutter pieces go up to four,
## and the set pieces only once.
const REPEATABLE: Array[String] = [
	"armchair",
	"bookcase",
	"potted_plant",
	"radiator",
	"filing_cabinet",
	"metal_shelf",
	"lab_shelf",
	"box_stack",
	"barrel",
	"server_rack",
	"sacks"
]
const UNIQUE: Array[String] = [
	"fireplace", "bathtub", "toilet", "stove", "fridge", "bed_double", "vanity", "dining_set"
]

static var _catalogue: Array[Dictionary] = []
static var _by_name := {}


## Every decor model: name, size (Vector3: width, height, depth), place,
## themes, solid, and maybe tints and mount. See tools/blender/decor.py.
static func catalogue() -> Array[Dictionary]:
	if _catalogue.is_empty():
		var entries: Array = JSON.parse_string(FileAccess.get_file_as_string(CATALOGUE))
		for item: Dictionary in entries:
			var size: Array = item["size"]
			item["size"] = Vector3(size[0], size[1], size[2])
			_catalogue.append(item)
			_by_name[item["name"]] = item
	return _catalogue


static func entry(piece_name: String) -> Dictionary:
	catalogue()
	return _by_name.get(piece_name, {})


## A piece, origin on the floor (or at its bottom, for hanging ones) in the
## middle of its footprint, front toward +Z. Solid pieces get a box to bump
## into. tint indexes the entry's tints; -1 keeps the modelled colours.
static func instance(piece: Dictionary, tint := -1) -> Node3D:
	var size: Vector3 = piece["size"]
	var colour := Color.TRANSPARENT
	if tint >= 0:
		var rgb: Array = piece["tints"][tint]
		colour = Color(rgb[0], rgb[1], rgb[2])
	var model := Models.model("decor/" + piece["name"], 0.6, colour)
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		(mesh as GeometryInstance3D).visibility_range_end = DRAW_DISTANCE
	if not piece.get("solid", false):
		return model
	var body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = size.y / 2.0
	body.add_child(collision)
	body.add_child(model)
	return body


## Builds every placed piece into its storey's node.
static func build(level: Level, storeys: Array[Node3D]) -> void:
	for piece in level.decor:
		var node := instance(entry(piece["name"]), piece["tint"])
		node.position = piece["position"]
		node.rotation.y = piece["yaw"]
		node.scale = Vector3.ONE * piece.get("scale", 1.0)
		storeys[level.floor_of(piece["room"])].add_child(node)


## Whether point (with margin round it) is inside a solid piece in room.
static func blocks(level: Level, room: int, point: Vector3, margin: float) -> bool:
	for piece in level.decor:
		if piece["room"] == room and entry(piece["name"]).get("solid", false):
			if _footprint(piece).grow(margin).has_point(Vector2(point.x, point.z)):
				return true
	return false


## How far point is from the nearest line monsters cross room by; INF in
## rooms without decor (the yard and the stairs), which are left open.
static func line_distance(level: Level, room: int, point: Vector3) -> float:
	if not THEMES.has(level.kind(room)):
		return INF
	var middle := Vector2(level.anchor(room).x, level.anchor(room).z)
	var at := Vector2(point.x, point.z)
	var nearest := INF
	for door in level.approaches(room):
		var closest := Geometry2D.get_closest_point_to_segment(at, middle, Vector2(door.x, door.z))
		nearest = minf(nearest, closest.distance_to(at))
	return nearest


## Chooses a theme for each indoor room and places its pieces. Returns
## dictionaries of name, position, yaw, room and tint.
static func place(level: Level, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var placed: Array[Dictionary] = []
	for room in level.room_count():
		var kind := level.kind(room)
		if not THEMES.has(kind):
			continue
		var themes: Array = THEMES[kind]
		var theme: String = themes[rng.randi() % themes.size()]
		var options := catalogue().filter(
			func(candidate: Dictionary) -> bool: return theme in candidate["themes"]
		)
		var room_pieces: Array[Dictionary] = []
		_place_rug(level, rng, room, options, room_pieces)
		var size := level.room_bounds(room).size
		var area_share: float = size.x * size.y / AREA_PER_PIECE[kind]
		var count := roundi(area_share * rng.randf_range(0.75, 1.25))
		var floor_options := options.filter(
			func(candidate: Dictionary) -> bool:
				return candidate["place"] in ["wall", "corner", "free"]
		)
		_place_some(level, rng, room, floor_options, count, room_pieces)
		var hang_options := options.filter(
			func(candidate: Dictionary) -> bool: return candidate["place"] == "hang"
		)
		var hangs := roundi(2.0 * (size.x + size.y) / WALL_PER_HANG * rng.randf_range(0.5, 1.0))
		_place_some(level, rng, room, hang_options, hangs, room_pieces)
		placed.append_array(room_pieces)
	return placed


static func _place_rug(
	level: Level, rng: RandomNumberGenerator, room: int, options: Array, pieces: Array[Dictionary]
) -> void:
	var rugs := options.filter(
		func(candidate: Dictionary) -> bool: return candidate["place"] == "rug"
	)
	if rugs.is_empty() or rng.randf() >= RUG_CHANCE:
		return
	var rug: Dictionary = rugs[rng.randi() % rugs.size()]
	var size: Vector3 = rug["size"]
	var bounds := level.room_bounds(room)
	# Lay its long side along the room's.
	var yaw := 0.0 if (size.x >= size.z) == (bounds.size.x >= bounds.size.y) else PI / 2.0
	var at := level.anchor(room) + Vector3.UP * 0.012  # Just above the floor surface.
	var piece := _piece(rng, rug, at, yaw, room)
	# Grown toward half the room, so a rug does not vanish in a big hall.
	var extent := Vector2(size.x, size.z) if yaw == 0.0 else Vector2(size.z, size.x)
	var fill := bounds.size * 0.5 / extent
	piece["scale"] = clampf(minf(fill.x, fill.y), 1.0, 2.5)
	if bounds.grow(-0.3).encloses(_footprint(piece)):
		pieces.append(piece)


## Tries to place count pieces chosen from options, each clear of the others,
## of the cabinets, of doorways and of monster lines.
static func _place_some(
	level: Level,
	rng: RandomNumberGenerator,
	room: int,
	options: Array,
	count: int,
	pieces: Array[Dictionary]
) -> void:
	if options.is_empty():
		return
	var wanted := pieces.size() + count
	for attempt in count * 10:
		if pieces.size() >= wanted:
			return
		var choice: Dictionary = options[rng.randi() % options.size()]
		var piece := _spot(level, rng, room, choice)
		if not piece.is_empty() and _fits(level, room, piece, choice, pieces):
			pieces.append(piece)


## Where a piece of this kind might go in room: against a wall, in a corner, on
## a wall at its mount height, or anywhere inside (free pieces, and sometimes
## the clutter marked "anywhere"). Empty if it cannot fit.
static func _spot(
	level: Level, rng: RandomNumberGenerator, room: int, choice: Dictionary
) -> Dictionary:
	var size: Vector3 = choice["size"]
	var bounds := level.room_bounds(room).grow(-Level.WALL_THICKNESS / 2.0)
	var middle := bounds.get_center()
	var at := Vector3.ZERO
	var yaw := 0.0
	var narrow := minf(bounds.size.x, bounds.size.y) < NARROW
	if narrow and choice["place"] != "hang" and size.z > NARROW_DEPTH:
		return {}
	var anywhere: bool = choice.get("anywhere", false) and rng.randf() < 0.4
	if (choice["place"] == "free" or anywhere) and not narrow:
		yaw = (rng.randi() % 4) * PI / 2.0
		var half := maxf(size.x, size.z) / 2.0 + 0.4
		if bounds.size.x < half * 2.0 or bounds.size.y < half * 2.0:
			return {}
		at.x = rng.randf_range(bounds.position.x + half, bounds.end.x - half)
		at.z = rng.randf_range(bounds.position.y + half, bounds.end.y - half)
	else:
		var side := rng.randi() % 4  # West, east, north, south wall.
		var span := bounds.size.y if side < 2 else bounds.size.x
		if span < size.x + 0.4:
			return {}
		var room_left := (span - size.x) / 2.0 - 0.02
		var slide := rng.randf_range(-room_left, room_left)
		if choice["place"] == "corner":
			slide = room_left if rng.randf() < 0.5 else -room_left
		var inset := size.z / 2.0 + 0.02
		match side:
			0:
				at = Vector3(bounds.position.x + inset, 0, middle.y + slide)
				yaw = PI / 2.0
			1:
				at = Vector3(bounds.end.x - inset, 0, middle.y + slide)
				yaw = -PI / 2.0
			2:
				at = Vector3(middle.x + slide, 0, bounds.position.y + inset)
			3:
				at = Vector3(middle.x + slide, 0, bounds.end.y - inset)
				yaw = PI
	at.y = level.floor_height(room) + choice.get("mount", 0.0)
	return _piece(rng, choice, at, yaw, room)


static func _piece(
	rng: RandomNumberGenerator, choice: Dictionary, at: Vector3, yaw: float, room: int
) -> Dictionary:
	var tints: Array = choice.get("tints", [])
	var tint := rng.randi() % tints.size() if tints else -1
	return {"name": choice["name"], "position": at, "yaw": yaw, "room": room, "tint": tint}


static func _fits(
	level: Level, room: int, piece: Dictionary, choice: Dictionary, pieces: Array[Dictionary]
) -> bool:
	var rect := _footprint(piece)
	var hanging: bool = choice["place"] == "hang"
	var bottom: float = choice.get("mount", 0.0)
	var top := bottom + (choice["size"] as Vector3).y
	var repeats := 0
	for other in pieces:
		var other_entry := entry(other["name"])
		if other["name"] == piece["name"]:
			repeats += 1
		if other_entry["place"] == "rug":
			continue
		var other_bottom: float = other_entry.get("mount", 0.0)
		var other_top := other_bottom + (other_entry["size"] as Vector3).y
		var overlaps_height := bottom < other_top and other_bottom < top
		if overlaps_height and _footprint(other).grow(GAP).intersects(rect):
			return false
	var most := 4 if piece["name"] in REPEATABLE else (1 if piece["name"] in UNIQUE else 2)
	if repeats >= most:
		return false
	for cabinet in level.furniture_in(room):
		var size: Vector3 = Cabinet.SIZES[cabinet["type"]]
		var cabinet_rect := _rect(cabinet["position"], size, cabinet["yaw"])
		if size.y > bottom and cabinet_rect.grow(GAP).intersects(rect):
			return false
	for door in level.doors(room):
		if rect.grow(DOOR_KEEP).has_point(Vector2(door.x, door.z)):
			return false
	if hanging or not choice.get("solid", false):
		return true
	var clear := rect.grow(ROUTE_CLEARANCE)
	var middle := level.anchor(room)
	for point in level.approaches(room):
		if _crosses(clear, Vector2(middle.x, middle.z), Vector2(point.x, point.z)):
			return false
	return true


static func _footprint(piece: Dictionary) -> Rect2:
	var size: Vector3 = entry(piece["name"])["size"]
	return _rect(piece["position"], size * piece.get("scale", 1.0), piece["yaw"])


## The floor rectangle (x, z) of something size big centred at at, turned by
## yaw (a multiple of a quarter turn).
static func _rect(at: Vector3, size: Vector3, yaw: float) -> Rect2:
	var extent := Vector2(size.x, size.z)
	if absf(sin(yaw)) > 0.5:
		extent = Vector2(size.z, size.x)
	return Rect2(Vector2(at.x, at.z) - extent / 2.0, extent)


## Whether the segment a-b touches rect.
static func _crosses(rect: Rect2, a: Vector2, b: Vector2) -> bool:
	if rect.has_point(a) or rect.has_point(b):
		return true
	var corners: Array[Vector2] = [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y)
	]
	for i in 4:
		if Geometry2D.segment_intersects_segment(a, b, corners[i], corners[(i + 1) % 4]) != null:
			return true
	return false
