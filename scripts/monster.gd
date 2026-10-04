class_name Monster
extends CharacterBody3D
## Roams the house along routes from Level.route and chases any player it can
## see. Crouching players are only noticed up close, which is the point of
## sneaking. Loot and walls block its view. The host runs it; clients see the
## replicated transform and only animate it.

const Level := preload("res://scripts/level.gd")
const Models := preload("res://scripts/models.gd")

const WANDER_SPEED := 1.8
const CHASE_SPEED := 4.0  ## Below sprint speed, so sprinting can lose it.
const NOTICE_RANGE := 14.0
const CROUCH_NOTICE_RANGE := 4.0
const CATCH_RANGE := 1.2
const GRAVITY := 14.0
const REST_TIME := 4.0  ## Pause after a catch so it doesn't camp the truck.
const EYE_HEIGHT := 2.28  ## Where it looks from if its model marks no eyes.
## The four bodies (assets/models/monsters), and the colour each one's eyes cast.
## They share one collision capsule and behaviour for now.
const VARIANTS: Array[String] = ["stalker", "crawler", "wraith", "brute"]
const AURAS: Array[Color] = [
	Color(1.0, 0.15, 0.1), Color(1.0, 0.8, 0.2), Color(0.3, 1.0, 0.85), Color(1.0, 0.45, 0.1)
]
const STRIDE := 2.2  ## Walk-cycle radians per metre moved.

const STUCK_TIME := 1.5  ## Re-plan after this long without getting closer to the next waypoint.
const PROGRESS := 0.3  ## Metres closer that count as getting somewhere.
## Impulse per physics step into loot in the way (N·s). At 60 steps/s that is 480 N, enough to
## slide even the piano (about 340 N of friction); a shove can chip the loot's value.
const SHOVE := 8.0
const DETOUR := 1.6  ## How far to step aside when stuck (m).
const GIVE_UP := 3  ## Detours tried in one room before roaming somewhere else.
const WANDER_RANGE := Vector2i(3, 16)  ## How many rooms away a roam goes (min, max).

var level: Level  ## Set by the host; clients leave it null and never think.
var variant := 0  ## Index into VARIANTS; which body it has.
var eye_height := EYE_HEIGHT  ## Where it looks from, read off the model.

var _route: Array[Vector3] = []  ## Waypoints still to walk while roaming.
var _stuck_for := 0.0  ## Seconds without getting PROGRESS closer to the waypoint.
var _best_distance := INF  ## Closest it has been to the current waypoint.
var _detour_side := 1.0  ## Flips each time, so a second try goes round the other way.
var _detours := 0  ## Detours tried in _detour_room since arriving there.
var _detour_room := -1
var _rest_left := 0.0
var _rng := RandomNumberGenerator.new()

# Animation runs on every peer from how far the replicated body moved.
var _last_position := Vector3.ZERO
var _phase := 0.0
var _time := 0.0
var _joints: Array[Node3D] = []  ## Animated by name: torso, head, arm_N, leg_N, float.
var _rest: Array[Transform3D] = []  ## Each joint's pose as modelled.


func _ready() -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.5
	capsule.height = 2.4
	var collision := CollisionShape3D.new()
	collision.shape = capsule
	collision.position.y = 1.2
	add_child(collision)

	# Monsters sit on their own layer and only collide with layer 1 (the house,
	# loot, players), so two never jam each other on the narrow stairs.
	collision_layer = 2
	collision_mask = 1
	_build_model()
	_last_position = position


func _process(delta: float) -> void:
	_time += delta
	var moved := global_position - _last_position
	moved.y = 0.0
	_last_position = global_position
	var speed := moved.length() / maxf(delta, 0.001)
	_phase += moved.length() * STRIDE
	var walk := clampf(speed / CHASE_SPEED, 0.0, 1.0)
	var swing := sin(_phase) * 0.7 * walk
	# Roaming, the arms dangle and sway; chasing, they reach forward (-X turns a
	# hanging arm toward the model's front, +Z).
	var reach := clampf((speed - WANDER_SPEED) / (CHASE_SPEED - WANDER_SPEED), 0.0, 1.0)
	for i in _joints.size():
		var joint := _joints[i]
		var rest := _rest[i]
		var number := joint.name.get_slice("_", 1).to_int()
		var side := 1.0 if number % 2 == 0 else -1.0
		var turn := Vector3.ZERO
		match joint.name.get_slice("_", 0):
			"leg":
				turn.x = swing * side
			"arm":
				var dangle := swing * side * 0.6 + sin(_time * 1.3 + number) * 0.06
				turn.x = lerpf(dangle, -1.25 + sin(_time * 9.0 + number * 2.0) * 0.12, reach)
			"torso":
				turn.x = 0.15 * reach + sin(_time * 1.1) * 0.03
			"head":
				turn = Vector3(sin(_time * 0.7) * 0.08, sin(_time * 0.43) * 0.25, sin(_time) * 0.06)
			"float":
				joint.position = rest.origin + Vector3.UP * (0.12 + sin(_time * 1.6) * 0.08)
		joint.basis = rest.basis * Basis.from_euler(turn)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	_rest_left -= delta
	var target: Player = _visible_player() if _rest_left <= 0.0 else null
	if target:
		_route.clear()  # Re-plan from wherever the chase ends.
	elif _route.is_empty():
		_plan_roam()
		_best_distance = INF
	elif _stuck_for > STUCK_TIME:
		var room := level.room_at(global_position)
		_detours = _detours + 1 if room == _detour_room else 1
		_detour_room = room
		if _detours > GIVE_UP:
			# Still blocked (loot wedged against furniture): go somewhere else.
			_plan_roam()
			_detours = 0
		else:
			# Blocked (usually by loot too heavy to shove): step aside and try round it.
			_route.push_front(_detour(_route[0]))
		_best_distance = INF
		_stuck_for = 0.0
	var goal := target.global_position if target else _route[0]
	var to_goal := goal - global_position
	var climb := absf(to_goal.y)  # A waypoint upstairs is not reached from below it.
	to_goal.y = 0.0
	# Stuck means not getting closer to the waypoint (sliding along loot still moves).
	var distance := to_goal.length()
	if target or distance < _best_distance - PROGRESS:
		_best_distance = distance
		_stuck_for = 0.0
	else:
		_stuck_for += delta

	if target and to_goal.length() < CATCH_RANGE:
		target.caught.rpc_id(target.get_multiplayer_authority(), level.spawn)
		_rest_left = REST_TIME
	elif not target and to_goal.length() < 0.4 and climb < 1.5:
		_route.pop_front()
		_best_distance = INF

	var direction := to_goal.normalized()
	var speed := CHASE_SPEED if target else WANDER_SPEED
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if direction.length_squared() > 0.0:
		look_at(global_position + direction)
	move_and_slide()
	# Shove loot that blocks the way, like a monster barging through a room would.
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var loot := hit.get_collider() as Loot
		if loot:
			loot.apply_central_impulse(-hit.get_normal() * SHOVE)


## Loads this variant's model (tools/blender/monsters.py) and finds the
## joints to animate by name. The model faces +Z, so it is turned to face -Z,
## the way look_at points the body. A red-ish glow lights the face, and the
## wraith's lantern lights its way.
func _build_model() -> void:
	var model := Models.model("monsters/" + VARIANTS[variant], 0.6)
	model.rotation.y = PI
	add_child(model)
	for node in model.find_children("*", "Node3D", true, false):
		var joint := node as Node3D
		var key := joint.name.get_slice("_", 0)
		if key in ["torso", "head", "arm", "leg", "float"] and not joint is MeshInstance3D:
			_joints.append(joint)
			_rest.append(joint.transform)
	var eyes := model.find_child("eyes") as Node3D
	eye_height = (model.transform * eyes.position).y if eyes else EYE_HEIGHT
	for marker: String in ["eyes", "light"]:
		var at := model.find_child(marker) as Node3D
		if at:
			var light := OmniLight3D.new()
			light.light_color = AURAS[variant]
			light.light_energy = 0.6 if marker == "eyes" else 1.2
			light.omni_range = 2.5 if marker == "eyes" else 5.0
			light.position = Vector3(0, 0, 0.3) if marker == "eyes" else Vector3.ZERO
			at.add_child(light)


## The nearest player within notice range that nothing blocks the view of.
func _visible_player() -> Player:
	var best: Player = null
	var best_distance := INF
	var space := get_world_3d().direct_space_state
	var eye := global_position + Vector3.UP * eye_height
	for node in get_tree().get_nodes_in_group("players"):
		var player := node as Player
		var reach := CROUCH_NOTICE_RANGE if player.crouching else NOTICE_RANGE
		var distance := global_position.distance_to(player.global_position)
		if distance > reach or distance >= best_distance:
			continue
		var chest := player.global_position + Vector3.UP
		var query := PhysicsRayQueryParameters3D.create(eye, chest, 0xFFFFFFFF, [get_rid()])
		if space.intersect_ray(query).get("collider") == player:
			best = player
			best_distance = distance
	return best


## A point beside the blocked line to the waypoint, kept inside this room.
func _detour(waypoint: Vector3) -> Vector3:
	_detour_side = -_detour_side
	var ahead := waypoint - global_position
	ahead.y = 0.0
	var aside := ahead.normalized().rotated(Vector3.UP, PI / 2.0) * _detour_side * DETOUR
	var bounds := level.room_bounds(level.room_at(global_position)).grow(-0.8)
	var point := global_position + aside
	point.x = clampf(point.x, bounds.position.x, bounds.end.x)
	point.z = clampf(point.z, bounds.position.y, bounds.end.y)
	return point


## Picks a room a few doors away and walks there, starting from where it stands
## in this room (furniture keeps clear of the line to its middle).
func _plan_roam() -> void:
	var here := level.room_at(global_position)
	var options: Array = []
	var distance := level.distances_from(here)
	for room: int in distance:
		if distance[room] >= WANDER_RANGE.x and distance[room] <= WANDER_RANGE.y:
			options.append(room)
	if options.is_empty():
		options = level.neighbours(here)
	var target: int = options[_rng.randi() % options.size()] if options else here
	_route = level.route(here, target)
	_route.push_front(level.anchor(here))
