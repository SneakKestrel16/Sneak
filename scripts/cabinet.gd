class_name Cabinet
extends StaticBody3D
## Furniture that opens: a cupboard with two doors over shelves, or a dresser
## with three drawers. Look at a closed door or drawer and press E to open it;
## the host then puts small valuables inside (game.gd _fill_cabinet). Parts
## stay open once opened, so nothing ever closes on loot.
##
## Built in code like everything else, origin at the floor in the middle of its
## footprint, front facing +Z. Doors and drawers are AnimatableBody3D, so their
## collision moves with them and pushes whatever is in the way. Each part
## carries meta "cabinet" (its index in game.gd) and "part" for the player's
## look-at ray.

enum Type { CUPBOARD, DRESSER }

const Models := preload("res://scripts/models.gd")

## Footprint and height of each type (m), used by level.gd to fit them in rooms.
const SIZES: Array[Vector3] = [Vector3(1.0, 2.0, 0.55), Vector3(1.2, 1.0, 0.5)]
const PANEL := 0.03
const PLINTH := 0.08
const OPEN_TIME := 0.5
const DOOR_SWING := deg_to_rad(105.0)
const DRAWER_PULL := 0.6  ## Share of the depth a drawer slides out.
const SHELVES: Array[float] = [0.75, 1.4]  ## Cupboard shelf heights (m).

var type := Type.CUPBOARD
var index := 0
var opened := 0  ## Bit per part.

var _parts: Array[Node3D] = []  ## Door pivots or drawers, in part order.


func _ready() -> void:
	var size := SIZES[type]
	var wood := Models.textured(
		Color(0.42, 0.28, 0.17) if type == Type.CUPBOARD else Color(0.3, 0.19, 0.12),
		Vector2(1, 5),
		0.35,
		0.55,
		0.0,
		0.05
	)
	var brass := Models.textured(Models.BRASS, Vector2.ONE, 0.2, 0.3, Models.METAL)
	var w := size.x
	var h := size.y
	var d := size.z
	# The carcass: back, sides, top, bottom.
	_panel(self, Vector3(w, h, PANEL), Vector3(0, h / 2.0, -d / 2.0 + PANEL / 2.0), wood)
	for x: float in [-1.0, 1.0]:
		_panel(self, Vector3(PANEL, h, d), Vector3(x * (w - PANEL) / 2.0, h / 2.0, 0), wood)
	_panel(self, Vector3(w, PANEL, d), Vector3(0, h - PANEL / 2.0, 0), wood)
	_panel(self, Vector3(w, PLINTH, d), Vector3(0, PLINTH / 2.0, 0), wood)
	if type == Type.CUPBOARD:
		for shelf in SHELVES:
			_panel(self, Vector3(w - PANEL * 2.0, PANEL, d - PANEL), Vector3(0, shelf, 0), wood)
		_build_doors(size, wood, brass)
	else:
		_build_drawers(size, wood, brass)


func part_count() -> int:
	return _parts.size()


## True if the body is one of this cabinet's doors or drawers that is still shut.
func is_closed_part(body: Object) -> bool:
	return body.has_meta("part") and (opened & (1 << int(body.get_meta("part")))) == 0


## Opens every part whose bit is set in mask; with animate false they snap open
## (a late joiner catching up).
func set_opened(mask: int, animate: bool) -> void:
	for part in _parts.size():
		var bit := 1 << part
		if (mask & bit) != 0 and (opened & bit) == 0:
			_open(part, animate)
	opened |= mask


## Where valuables go when part opens, in world space at the surface they sit on.
func content_spots(part: int) -> Array[Vector3]:
	var size := SIZES[type]
	var spots: Array[Vector3] = []
	if type == Type.CUPBOARD:
		var x := (-1.0 if part == 0 else 1.0) * size.x / 4.0
		for y: float in [PLINTH, SHELVES[0] + PANEL / 2.0, SHELVES[1] + PANEL / 2.0]:
			spots.append(to_global(Vector3(x, y, 0.02)))
	else:
		var drawer := _parts[part]
		for x: float in [-0.3, 0.0, 0.3]:
			spots.append(drawer.to_global(Vector3(x, 0.03, 0)))
	return spots


func _build_doors(size: Vector3, wood: Material, brass: Material) -> void:
	var door := Vector3(size.x / 2.0 - 0.01, size.y - PLINTH - 0.02, 0.025)
	for part in 2:
		var side := -1.0 if part == 0 else 1.0  # Hinge on the outer edge.
		var pivot := Node3D.new()
		pivot.position = Vector3(side * size.x / 2.0, 0, size.z / 2.0)
		add_child(pivot)
		var body := _part_body(pivot, part)
		var middle := Vector3(-side * door.x / 2.0, PLINTH + door.y / 2.0, door.z / 2.0)
		_panel(body, door, middle, wood)
		var knob := SphereMesh.new()
		knob.radius = 0.025
		knob.height = 0.05
		Models.part(
			body, knob, brass, Vector3(-side * (door.x - 0.06), size.y * 0.55, door.z + 0.02)
		)
		_parts.append(pivot)


func _build_drawers(size: Vector3, wood: Material, brass: Material) -> void:
	var height := (size.y - PLINTH - PANEL) / 3.0
	var inner := Vector3(size.x - PANEL * 2.0 - 0.02, height - 0.03, size.z - PANEL - 0.02)
	for part in 3:
		var drawer := _part_body(self, part)
		drawer.position = Vector3(0, PLINTH + part * height, PANEL / 2.0)
		# An open-top box: bottom, two sides, back, and the front with a handle.
		_panel(drawer, Vector3(inner.x, 0.015, inner.z), Vector3(0, 0.0075, 0), wood)
		for x: float in [-1.0, 1.0]:
			var side_at := Vector3(x * (inner.x - 0.015) / 2.0, inner.y / 2.0, 0)
			_panel(drawer, Vector3(0.015, inner.y, inner.z), side_at, wood)
		_panel(
			drawer,
			Vector3(inner.x, inner.y, 0.015),
			Vector3(0, inner.y / 2.0, -inner.z / 2.0),
			wood
		)
		var front := Vector3(size.x - 0.01, height - 0.01, 0.025)
		_panel(drawer, front, Vector3(0, front.y / 2.0, inner.z / 2.0 + front.z / 2.0), wood)
		var handle := BoxMesh.new()
		handle.size = Vector3(0.2, 0.025, 0.025)
		Models.part(drawer, handle, brass, Vector3(0, front.y / 2.0, inner.z / 2.0 + 0.05))
		_parts.append(drawer)


## A door or drawer body that moves with its animation and answers the look-at ray.
func _part_body(parent: Node3D, part: int) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	# Off: with it on, the body keeps its physics-side transform and ignores the
	# position set here and the hinge it hangs from, so doors and drawers never
	# appeared to move. The tweens already run in the physics step.
	body.sync_to_physics = false
	body.set_meta("cabinet", index)
	body.set_meta("part", part)
	parent.add_child(body)
	return body


func _open(part: int, animate: bool) -> void:
	var node := _parts[part]
	var property := "rotation:y" if type == Type.CUPBOARD else "position:z"
	var target: float
	if type == Type.CUPBOARD:
		target = (1.0 if part == 0 else -1.0) * -DOOR_SWING
	else:
		target = node.position.z + SIZES[type].z * DRAWER_PULL
	if not animate:
		node.set_indexed(property, target)
		return
	var tween := create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, property, target, OPEN_TIME)


## A box with collision on body and a mesh to see.
static func _panel(body: Node3D, size: Vector3, at: Vector3, material: Material) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = at
	body.add_child(collision)
	var mesh := BoxMesh.new()
	mesh.size = size
	Models.part(body, mesh, material, at)
