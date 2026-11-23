extends Node3D

## Collision-aware, smoothly damped 3rd-person camera rig.

@export var min_pitch_deg: float = -48.0
@export var max_pitch_deg: float = 68.0
@export var rotation_smoothing: float = 18.0
@export var base_fov: float = 70.0
@export var sprint_fov: float = 79.0
@export var crouch_spring_length: float = 3.5
@export var stand_spring_length: float = 4.3
@export var bob_amplitude: float = 0.032
@export var bob_frequency: float = 8.5

@onready var spring_arm: SpringArm3D = $SpringArm
@onready var camera: Camera3D = $SpringArm/Camera3D

var target_yaw: float = 0.0
var target_pitch: float = -12.0
var current_yaw: float = 0.0
var current_pitch: float = -12.0

var _bob_phase: float = 0.0
var _base_spring_offset: Vector3 = Vector3(0.42, 0.08, 0.0)


func _ready() -> void:
	var shape := SphereShape3D.new()
	shape.radius = 0.22
	spring_arm.shape = shape
	spring_arm.spring_length = stand_spring_length
	spring_arm.position = _base_spring_offset

	var owner_body := get_parent()
	if owner_body is CollisionObject3D:
		spring_arm.add_excluded_object(owner_body.get_rid())

	current_yaw = target_yaw
	current_pitch = target_pitch
	_apply_rig_rotation()


func _process(delta: float) -> void:
	var look_delta: Vector2 = InputRouter.consume_look_delta()
	if look_delta.length_squared() > 0.00001:
		target_yaw -= look_delta.x
		target_pitch = clampf(target_pitch - look_delta.y, min_pitch_deg, max_pitch_deg)

	var blend: float = 1.0 - exp(-rotation_smoothing * delta)
	current_yaw = lerpf(current_yaw, target_yaw, blend)
	current_pitch = lerpf(current_pitch, target_pitch, blend)
	_apply_rig_rotation()


func update_dynamic_effects(delta: float, horizontal_speed: float, max_sprint_speed: float, is_on_floor: bool, is_crouching: bool, is_sprinting: bool) -> void:
	var desired_fov: float = sprint_fov if (is_sprinting and horizontal_speed > 3.5) else base_fov
	camera.fov = lerpf(camera.fov, desired_fov, 1.0 - exp(-7.5 * delta))

	var desired_len: float = crouch_spring_length if is_crouching else stand_spring_length
	spring_arm.spring_length = lerpf(spring_arm.spring_length, desired_len, 1.0 - exp(-8.0 * delta))

	if is_on_floor and horizontal_speed > 0.35:
		var speed_ratio: float = clampf(horizontal_speed / maxf(max_sprint_speed, 0.1), 0.0, 1.0)
		_bob_phase += delta * bob_frequency * (0.7 + 0.65 * speed_ratio)
		var bob_y: float = sin(_bob_phase * 2.0) * bob_amplitude * speed_ratio
		var bob_x: float = cos(_bob_phase) * bob_amplitude * 0.5 * speed_ratio
		spring_arm.position = spring_arm.position.lerp(_base_spring_offset + Vector3(bob_x, bob_y, 0.0), 1.0 - exp(-12.0 * delta))
	else:
		spring_arm.position = spring_arm.position.lerp(_base_spring_offset, 1.0 - exp(-8.0 * delta))


func get_camera_yaw_rad() -> float:
	return deg_to_rad(current_yaw)


func _apply_rig_rotation() -> void:
	rotation_degrees = Vector3(current_pitch, current_yaw, 0.0)
