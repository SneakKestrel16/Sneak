class_name Monster
extends CharacterBody3D
## Roams the maze along routes from Level.route and chases any player it can
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
const EYE_HEIGHT := 2.28  ## Where its eyes are on the model; also where it looks from.
const STRIDE := 2.2  ## Walk-cycle radians per metre moved.

const STUCK_TIME := 1.5  ## Re-plan after this long without getting closer to the next waypoint.
const PROGRESS := 0.3  ## Metres closer that count as getting somewhere.
## Impulse per physics step into loot in the way (N·s). At 60 steps/s that is 480 N, enough to
## slide even the piano (about 340 N of friction); a shove can chip the loot's value.
const SHOVE := 8.0
const DETOUR := 1.6  ## How far to step aside when stuck (m).
const WANDER_RANGE := Vector2i(2, 6)  ## How many rooms away a roam goes (min, max).

var level: Level  ## Set by the host; clients leave it null and never think.

var _route: Array[Vector3] = []  ## Waypoints still to walk while roaming.
var _stuck_for := 0.0  ## Seconds without getting PROGRESS closer to the waypoint.
var _best_distance := INF  ## Closest it has been to the current waypoint.
var _detour_side := 1.0  ## Flips each time, so a second try goes round the other way.
var _rest_left := 0.0
var _rng := RandomNumberGenerator.new()

# Animation runs on every peer from how far the replicated body moved.
var _last_position := Vector3.ZERO
var _phase := 0.0
var _time := 0.0
var _torso: Node3D
var _head: Node3D
var _arms: Array[Node3D] = []
var _legs: Array[Node3D] = []


func _ready() -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.5
	capsule.height = 2.4
	var collision := CollisionShape3D.new()
	collision.shape = capsule
	collision.position.y = 1.2
	add_child(collision)

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
	_legs[0].rotation.x = swing
	_legs[1].rotation.x = -swing
	# Wandering, the arms dangle and sway; chasing, they reach forward.
	var reach := clampf((speed - WANDER_SPEED) / (CHASE_SPEED - WANDER_SPEED), 0.0, 1.0)
	for i in 2:
		var dangle := (-swing if i == 0 else swing) * 0.6 + sin(_time * 1.3 + i) * 0.06
		_arms[i].rotation.x = lerpf(dangle, 1.25 + sin(_time * 9.0 + i * 2.0) * 0.12, reach)
	_torso.rotation.x = -0.3 - 0.15 * reach + sin(_time * 1.1) * 0.03
	_head.rotation = Vector3(
		0.2 + sin(_time * 0.7) * 0.08, sin(_time * 0.43) * 0.25, sin(_time) * 0.06
	)


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
		# Blocked (usually by loot too heavy to shove): step aside and try round it.
		_route.push_front(_detour(_route[0]))
		_best_distance = INF
		_stuck_for = 0.0
	var goal := target.global_position if target else _route[0]
	var to_goal := goal - global_position
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
	elif not target and to_goal.length() < 0.4:
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


## A gaunt, hunched figure: long arms that hang to its knees, a narrow head
## with glowing eyes and a lit slit of a mouth, and ridges down its back.
## Fits the 2.4 m collision capsule; it faces -Z, the way look_at points it.
func _build_model() -> void:
	var skin := Models.textured(Color(0.13, 0.11, 0.13), Vector2(2, 3), 0.55, 0.55, 0.0, 0.07)
	var bone := Models.textured(Color(0.62, 0.58, 0.5), Vector2.ONE, 0.3, 0.7)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color.RED
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.1, 0.05)
	glow.emission_energy_multiplier = 5.0

	for side: float in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(side * 0.16, 1.1, 0)
		add_child(hip)
		Models.part(hip, _limb(0.1, 0.05, 1.1), skin, Vector3(0, -0.55, 0))
		var foot := BoxMesh.new()
		foot.size = Vector3(0.12, 0.06, 0.3)
		Models.part(hip, foot, skin, Vector3(0, -1.07, -0.08))
		_legs.append(hip)

	_torso = Node3D.new()
	_torso.position.y = 1.1
	add_child(_torso)
	var chest := CapsuleMesh.new()
	chest.radius = 0.24
	chest.height = 1.0
	Models.part(_torso, chest, skin, Vector3(0, 0.45, 0))
	for i in 5:
		var ridge := CylinderMesh.new()
		ridge.top_radius = 0.0
		ridge.bottom_radius = 0.05
		ridge.height = 0.14
		Models.part(_torso, ridge, bone, Vector3(0, 0.15 + i * 0.16, 0.23), Vector3(PI / 2.0, 0, 0))

	for side: float in [-1.0, 1.0]:
		var shoulder := Node3D.new()
		shoulder.position = Vector3(side * 0.25, 0.8, 0)
		_torso.add_child(shoulder)
		var knob := SphereMesh.new()
		knob.radius = 0.09
		knob.height = 0.18
		Models.part(shoulder, knob, skin, Vector3.ZERO)
		Models.part(shoulder, _limb(0.06, 0.04, 1.3), skin, Vector3(0, -0.65, 0))
		for finger in 3:
			var claw := CylinderMesh.new()
			claw.top_radius = 0.0
			claw.bottom_radius = 0.018
			claw.height = 0.2
			var spread := (finger - 1) * 0.035
			Models.part(shoulder, claw, bone, Vector3(spread, -1.38, -0.02), Vector3(0.2, 0, 0))
		_arms.append(shoulder)

	Models.part(_torso, _limb(0.07, 0.09, 0.2), skin, Vector3(0, 1.0, -0.04))
	_head = Node3D.new()
	_head.position = Vector3(0, 1.05, -0.08)
	_torso.add_child(_head)
	var skull := SphereMesh.new()
	skull.radius = 0.19
	skull.height = 0.52
	Models.part(_head, skull, skin, Vector3(0, 0.16, 0))
	for side: float in [-1.0, 1.0]:
		var eye := SphereMesh.new()
		eye.radius = 0.045
		eye.height = 0.07
		Models.part(_head, eye, glow, Vector3(side * 0.08, 0.2, -0.16))
	var mouth := BoxMesh.new()
	mouth.size = Vector3(0.16, 0.015, 0.02)
	Models.part(_head, mouth, glow, Vector3(0, 0.02, -0.17))
	var aura := OmniLight3D.new()
	aura.light_color = Color(1.0, 0.15, 0.1)
	aura.light_energy = 0.6
	aura.omni_range = 2.5
	aura.position = Vector3(0, 0.15, -0.35)
	_head.add_child(aura)


static func _limb(top: float, bottom: float, length: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = length
	return mesh


## The nearest player within notice range that nothing blocks the view of.
func _visible_player() -> Player:
	var best: Player = null
	var best_distance := INF
	var space := get_world_3d().direct_space_state
	var eye := global_position + Vector3.UP * EYE_HEIGHT
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
	var centre := level.room_center(level.room_at(global_position))
	var inner := Level.ROOM / 2.0 - 0.8
	var point := global_position + aside
	point.x = clampf(point.x, centre.x - inner, centre.x + inner)
	point.z = clampf(point.z, centre.z - inner, centre.z + inner)
	point.y = 0.0
	return point


## Picks a room a few doors away and walks there, starting from the middle of
## this room so the first leg is clear (rooms are empty boxes).
func _plan_roam() -> void:
	var here := level.room_at(global_position)
	var options: Array[Vector2i] = []
	var distance := level.distances_from(here)
	for room: Vector2i in distance:
		if distance[room] >= WANDER_RANGE.x and distance[room] <= WANDER_RANGE.y:
			options.append(room)
	if options.is_empty():
		options = level.neighbours(here)
	var target := options[_rng.randi() % options.size()] if options else here
	_route = level.route(here, target)
	_route.push_front(level.room_center(here))
