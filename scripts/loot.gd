class_name Loot
extends RigidBody3D
## A valuable to drag to the truck. Hard knocks chip its value and it breaks at
## zero, so carry it gently. Heavy loot needs several players: each holder adds
## at most MAX_FORCE, and lifting has to beat gravity.
##
## The host simulates it; clients freeze their copy and show the replicated
## transform.

const Models := preload("res://scripts/models.gd")

const PULL := 40.0  ## Spring stiffness toward the hold point (1/s²).
const DAMPING := 9.0  ## Keeps the spring from overshooting (1/s).
const MAX_FORCE := 400.0  ## Newtons one player can put into a held item.
const KNOCK_SPEED := 3.5  ## Speed change (m/s) in one physics step that starts costing value.
const DAMAGE := 0.08  ## Share of the base value lost per m/s above KNOCK_SPEED.

# Set before spawning.
var kind := ""  ## Its name in game.gd's KINDS, which picks the model.
var size := Vector3.ONE
var color := Color.WHITE
var base_value := 0
var value := 0  ## Replicated.

var _last_velocity := Vector3.ZERO
var _label: Label3D


func _ready() -> void:
	add_to_group("loot")
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	add_child(collision)
	add_child(Models.loot(kind, size, color))

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 40
	_label.outline_size = 8
	_label.position.y = size.y / 2.0 + 0.25
	add_child(_label)

	if not multiplayer.is_server():
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true


func _physics_process(_delta: float) -> void:
	_label.text = "$%d" % value
	_label.modulate = Color.WHITE.lerp(Color.RED, 1.0 - float(value) / maxf(base_value, 1.0))
	if not multiplayer.is_server():
		return

	var holders := 0
	var target := Vector3.ZERO
	for node in get_tree().get_nodes_in_group("players"):
		var player := node as Player
		if player.held_loot == name:
			holders += 1
			target += player.hold_point
	if holders > 0:
		target /= holders
		var gravity := ProjectSettings.get_setting("physics/3d/default_gravity") as float
		var accel := (target - global_position) * PULL - linear_velocity * DAMPING
		var force := (accel + Vector3.UP * gravity) * mass
		apply_central_force(force.limit_length(MAX_FORCE * holders))
		angular_velocity *= 0.9

	var knock := (linear_velocity - _last_velocity).length()
	_last_velocity = linear_velocity
	if knock > KNOCK_SPEED:
		value = maxi(value - ceili(base_value * DAMAGE * (knock - KNOCK_SPEED)), 0)
		if value == 0:
			queue_free()
