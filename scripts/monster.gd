class_name Monster
extends CharacterBody3D
## Wanders room to room and chases any player it can see. Crouching players
## are only noticed up close, which is the point of sneaking. Loot and walls
## block its view. The host runs it; clients see the replicated transform.

const Level := preload("res://scripts/level.gd")

const WANDER_SPEED := 1.8
const CHASE_SPEED := 4.0  ## Below sprint speed, so sprinting can lose it.
const NOTICE_RANGE := 14.0
const CROUCH_NOTICE_RANGE := 4.0
const CATCH_RANGE := 1.2
const GRAVITY := 14.0
const REST_TIME := 4.0  ## Pause after a catch so it doesn't camp the truck.
const EYE_HEIGHT := 2.0

var _wander_target := Vector3.ZERO
var _rest_left := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.5
	capsule.height = 2.4
	var collision := CollisionShape3D.new()
	collision.shape = capsule
	collision.position.y = 1.2
	add_child(collision)

	var body := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.5
	mesh.height = 2.4
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.08, 0.07, 0.09)
	mesh.material = skin
	body.mesh = mesh
	body.position.y = 1.2
	add_child(body)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color.RED
	glow.emission_enabled = true
	glow.emission = Color.RED
	glow.emission_energy_multiplier = 4.0
	for side: float in [-0.18, 0.18]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.07
		eye_mesh.height = 0.14
		eye_mesh.material = glow
		eye.mesh = eye_mesh
		eye.position = Vector3(side, EYE_HEIGHT, -0.45)
		add_child(eye)
	_wander_target = Level.room_center(Level.room_at(position))


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	_rest_left -= delta
	var target: Player = _visible_player() if _rest_left <= 0.0 else null
	var goal := target.global_position if target else _wander_target
	var to_goal := goal - global_position
	to_goal.y = 0.0

	if target and to_goal.length() < CATCH_RANGE:
		target.caught.rpc_id(target.get_multiplayer_authority(), Level.SPAWN)
		_rest_left = REST_TIME
		_wander_target = Level.room_center(Level.room_at(global_position))
	elif not target and to_goal.length() < 0.5:
		_wander_target = _neighbour_room_center()
	elif not target and is_on_wall():
		# Off the centre-to-centre line after a chase: re-centre in this room first.
		_wander_target = Level.room_center(Level.room_at(global_position))

	var direction := to_goal.normalized()
	var speed := CHASE_SPEED if target else WANDER_SPEED
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if direction.length_squared() > 0.0:
		look_at(global_position + direction)
	move_and_slide()


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


func _neighbour_room_center() -> Vector3:
	var room := Level.room_at(global_position)
	var options: Array[Vector2i] = []
	for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var next := room + step
		if next.x >= 0 and next.y >= 0 and next.x < Level.ROOMS and next.y < Level.ROOMS:
			options.append(next)
	return Level.room_center(options[_rng.randi() % options.size()])
