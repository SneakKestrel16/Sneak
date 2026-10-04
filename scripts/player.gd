class_name Player
extends CharacterBody3D
## First-person looter. WASD to move, Shift to sprint, Ctrl to crouch (slow,
## but monsters only notice you up close), Space to jump. Hold the left mouse
## button on loot to drag it; the mouse wheel pulls it nearer or pushes it out.
## E opens the cupboard door or drawer under the crosshair.
##
## Each player is driven by its own peer and replicated to the others. The host
## owns loot physics, so grabbing only publishes which loot this player holds
## and where it should go (held_loot, hold_point); loot.gd does the pulling.

const WALK_SPEED := 4.5
const SPRINT_SPEED := 7.0
const CROUCH_SPEED := 2.0
const JUMP_VELOCITY := 5.0
const GRAVITY := 14.0
const MOUSE_SENSITIVITY := 0.0025
const EYE_HEIGHT := 1.6
const CROUCH_EYE_HEIGHT := 1.0
const GRAB_RANGE := 3.5
const HOLD_MIN := 1.0
const HOLD_MAX := 3.0

# Replicated from the owning peer.
var pitch := 0.0
var crouching := false
var held_loot := ""  ## Name of the loot being dragged, or "".
var hold_point := Vector3.ZERO  ## Where the dragged loot should go, in world space.

var _hold_distance := 2.0
var _shown_prompt := ""
var _head: Node3D
var _camera: Camera3D


func _ready() -> void:
	add_to_group("players")
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	var collision := CollisionShape3D.new()
	collision.shape = capsule
	collision.position.y = 0.9
	add_child(collision)

	var body := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.35
	mesh.height = 1.8
	var material := StandardMaterial3D.new()
	# Golden-ratio hues give each peer a distinct colour.
	material.albedo_color = Color.from_hsv(fmod(get_multiplayer_authority() * 0.618, 1.0), 0.6, 0.9)
	mesh.material = material
	body.mesh = mesh
	body.position.y = 0.9
	add_child(body)

	_head = Node3D.new()
	_head.position.y = EYE_HEIGHT
	add_child(_head)
	var flashlight := SpotLight3D.new()
	flashlight.spot_range = 16.0
	flashlight.spot_angle = 28.0
	flashlight.light_energy = 2.5
	flashlight.shadow_enabled = true
	flashlight.position = Vector3(0.2, -0.2, 0)
	_head.add_child(flashlight)

	if is_multiplayer_authority():
		body.visible = false
		_camera = Camera3D.new()
		_head.add_child(_camera)
		_camera.make_current()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var motion := event as InputEventMouseMotion
	if motion and captured:
		rotate_y(-motion.relative.x * MOUSE_SENSITIVITY)
		pitch = clampf(pitch - motion.relative.y * MOUSE_SENSITIVITY, -1.45, 1.45)
	var button := event as InputEventMouseButton
	if button and button.pressed:
		if not captured:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_hold_distance = minf(_hold_distance + 0.25, HOLD_MAX)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_hold_distance = maxf(_hold_distance - 0.25, HOLD_MIN)


func _physics_process(delta: float) -> void:
	_head.rotation.x = pitch
	var eye := CROUCH_EYE_HEIGHT if crouching else EYE_HEIGHT
	_head.position.y = move_toward(_head.position.y, eye, delta * 4.0)
	if not is_multiplayer_authority():
		return

	# ponytail: crouching only lowers the eyes; the collision capsule stays full height.
	crouching = Input.is_action_pressed("crouch")
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif Input.is_action_just_pressed("jump") and not crouching:
		velocity.y = JUMP_VELOCITY
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := transform.basis * Vector3(input.x, 0.0, input.y)
	var speed := WALK_SPEED
	if crouching:
		speed = CROUCH_SPEED
	elif Input.is_action_pressed("sprint"):
		speed = SPRINT_SPEED
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	move_and_slide()
	_update_grab()
	_update_interact()


func _update_grab() -> void:
	var holding := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if not holding or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		held_loot = ""
		return
	var from := _camera.global_position
	if held_loot == "":
		var to := from - _camera.global_basis.z * GRAB_RANGE
		var query := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, [get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		var loot := hit.get("collider") as Loot
		if loot:
			held_loot = loot.name
			_hold_distance = clampf(from.distance_to(hit["position"]), HOLD_MIN, HOLD_MAX)
	hold_point = from - _camera.global_basis.z * _hold_distance


## Sent by the host when a monster catches this player: back to the truck,
## dropping whatever was held.
@rpc("any_peer", "call_local", "reliable")
func caught(spawn: Vector3) -> void:
	position = spawn
	velocity = Vector3.ZERO
	held_loot = ""
	if is_multiplayer_authority():
		get_tree().call_group("hud", "flash", "You were caught!")


## Looks for a shut cupboard door or drawer under the crosshair: shows a prompt
## for it, and E asks the host to open it.
func _update_interact() -> void:
	var from := _camera.global_position
	var to := from - _camera.global_basis.z * GRAB_RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, [get_rid()])
	var body := get_world_3d().direct_space_state.intersect_ray(query).get("collider") as Node
	var cabinet: Cabinet = null
	var node := body
	while node and not node is Cabinet:
		node = node.get_parent()
	cabinet = node as Cabinet
	var closed := cabinet != null and cabinet.is_closed_part(body)
	var text := "[E] Open" if closed else ""
	if text != _shown_prompt:
		_shown_prompt = text
		get_tree().call_group("hud", "prompt", text)
	if closed and Input.is_action_just_pressed("interact"):
		get_tree().call_group("hud", "request_open", cabinet.index, int(body.get_meta("part")))
