extends CharacterBody3D

## Physics-driven third-person character controller with momentum, stamina,
## crouch clearance detection, articulated human locomotion, RigidBody3D push impulses,
## Vehicle Enter/Exit handoff, and contextual Barmer NPC greeting interaction.

const CharacterMeshBuilderScript = preload("res://scripts/player/character_mesh_builder.gd")
const VehicleControllerScript = preload("res://scripts/vehicles/vehicle_controller.gd")

@export_group("Locomotion")
@export var walk_speed: float = 2.4
@export var run_speed: float = 5.2
@export var sprint_speed: float = 7.6
@export var crouch_speed: float = 2.3
@export var ground_acceleration: float = 11.5
@export var ground_deceleration: float = 14.0
@export var air_acceleration: float = 3.2
@export var turn_speed: float = 11.0

@export_group("Jumping & Gravity")
@export var jump_velocity: float = 5.15
@export var coyote_time: float = 0.14
@export var gravity_multiplier: float = 1.15

@export_group("Stamina")
@export var max_stamina: float = 100.0
@export var stamina_drain_rate: float = 22.0
@export var stamina_regen_rate: float = 17.5
@export var stamina_regen_delay: float = 0.9

@export_group("Physics Interaction")
@export var push_force_multiplier: float = 1.65
@export var max_push_impulse: float = 14.0

const STAND_HEIGHT: float = 1.80
const CROUCH_HEIGHT: float = 1.15
const STAND_CAM_Y: float = 1.50
const CROUCH_CAM_Y: float = 0.96
const VEHICLE_CAM_Y: float = 1.85

@onready var standing_collider: CollisionShape3D = $StandingCollider
@onready var visual_root: Node3D = $VisualRoot
@onready var ceiling_check: RayCast3D = $CeilingCheck
@onready var camera_pivot: Node3D = $CameraPivot

var stamina: float = 100.0
var is_crouching: bool = false
var is_sprinting_active: bool = false

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") as float
var _coyote_timer: float = 0.0
var _stamina_delay_timer: float = 0.0
var _stamina_exhausted: bool = false
var _capsule_shape: CapsuleShape3D = null
var _character_rig: RefCounted = null
var _nearby_scan_timer: float = 0.0


func _ready() -> void:
	GameManager.register_player(self)
	# Collide physically with World_Static (1) + Physics_Props (4) + Vehicles (8) + NPCs (16) = 29
	collision_mask = 29

	if standing_collider.shape is CapsuleShape3D:
		_capsule_shape = standing_collider.shape.duplicate() as CapsuleShape3D
		standing_collider.shape = _capsule_shape

	_character_rig = CharacterMeshBuilderScript.new()
	_character_rig.build_into(visual_root)


func _physics_process(delta: float) -> void:
	if GameManager.current_context == GameManager.ControlContext.VEHICLE:
		_update_vehicle_passenger_state(delta)
		return

	if GameManager.current_context != GameManager.ControlContext.ON_FOOT:
		return

	_scan_nearby_interactables(delta)
	if InputRouter.consume_interact_if_buffered():
		if GameManager.nearby_vehicle != null:
			_enter_vehicle(GameManager.nearby_vehicle)
			return
		elif GameManager.nearby_npc != null and is_instance_valid(GameManager.nearby_npc):
			GameManager.nearby_npc.call("on_player_greeted", global_position)

	_update_crouch_state(delta)
	_update_locomotion(delta)
	_apply_rigidbody_push_impulses()

	var horiz_speed: float = Vector2(velocity.x, velocity.z).length()
	if _character_rig != null:
		_character_rig.update_animation(
			delta,
			horiz_speed,
			sprint_speed,
			is_on_floor(),
			is_crouching,
			velocity.y
		)

	camera_pivot.update_dynamic_effects(
		delta,
		horiz_speed,
		sprint_speed,
		is_on_floor(),
		is_crouching,
		is_sprinting_active
	)


func _scan_nearby_interactables(delta: float) -> void:
	_nearby_scan_timer -= delta
	if _nearby_scan_timer > 0.0:
		return
	_nearby_scan_timer = 0.14

	if GameManager.traffic_manager_ref != null and GameManager.traffic_manager_ref.has_method("get_nearest_enterable_vehicle"):
		GameManager.nearby_vehicle = GameManager.traffic_manager_ref.get_nearest_enterable_vehicle(global_position, 4.6)
	else:
		GameManager.nearby_vehicle = null

	if GameManager.nearby_vehicle == null and GameManager.npc_manager_ref != null and GameManager.npc_manager_ref.has_method("get_nearest_interactable_npc"):
		GameManager.nearby_npc = GameManager.npc_manager_ref.get_nearest_interactable_npc(global_position, 3.2)
	else:
		GameManager.nearby_npc = null


func _enter_vehicle(veh: Node3D) -> void:
	if not is_instance_valid(veh):
		return
	if GameManager.traffic_manager_ref != null and GameManager.traffic_manager_ref.has_method("notify_vehicle_taken_by_player"):
		GameManager.traffic_manager_ref.notify_vehicle_taken_by_player(veh)

	GameManager.current_vehicle = veh
	GameManager.nearby_vehicle = null
	GameManager.nearby_npc = null
	veh.call("set_control_mode", VehicleControllerScript.ControlMode.PLAYER)

	standing_collider.disabled = true
	visual_root.visible = false
	velocity = Vector3.ZERO
	InputRouter.set_crouch(false)
	is_crouching = false
	InputRouter.reset_touch_controls()

	if veh is CollisionObject3D:
		camera_pivot.attach_vehicle(veh as CollisionObject3D)
	camera_pivot.position.y = VEHICLE_CAM_Y

	GameManager.set_control_context(GameManager.ControlContext.VEHICLE)


func _update_vehicle_passenger_state(delta: float) -> void:
	var veh: Node3D = GameManager.current_vehicle
	if veh == null or not is_instance_valid(veh):
		_exit_vehicle()
		return

	global_position = veh.global_position
	camera_pivot.position.y = lerpf(camera_pivot.position.y, VEHICLE_CAM_Y, 1.0 - exp(-10.0 * delta))

	var kmh: float = float(veh.get("speed_kmh"))
	var fwd_mps: float = float(veh.get("forward_speed_mps"))
	camera_pivot.update_vehicle_chase(delta, veh, kmh, fwd_mps)

	if InputRouter.consume_interact_if_buffered():
		_exit_vehicle()


func _exit_vehicle() -> void:
	var veh: Node3D = GameManager.current_vehicle
	GameManager.current_vehicle = null
	camera_pivot.detach_vehicle()

	if veh != null and is_instance_valid(veh):
		veh.call("set_control_mode", VehicleControllerScript.ControlMode.PARKED)
		var exit_pos: Vector3 = veh.call("get_exit_spawn_position", get_world_3d().direct_space_state)
		global_position = exit_pos
		if veh is RigidBody3D:
			velocity = (veh as RigidBody3D).linear_velocity * 0.35
			velocity.y = 0.0

	standing_collider.disabled = false
	visual_root.visible = true
	camera_pivot.position.y = STAND_CAM_Y
	InputRouter.reset_touch_controls()
	GameManager.set_control_context(GameManager.ControlContext.ON_FOOT)


func _update_crouch_state(delta: float) -> void:
	var wants_crouch: bool = InputRouter.crouch_toggled
	if not wants_crouch and is_crouching:
		ceiling_check.force_raycast_update()
		if ceiling_check.is_colliding():
			wants_crouch = true

	is_crouching = wants_crouch

	var target_h: float = CROUCH_HEIGHT if is_crouching else STAND_HEIGHT
	var target_cam_y: float = CROUCH_CAM_Y if is_crouching else STAND_CAM_Y

	if _capsule_shape:
		_capsule_shape.height = lerpf(_capsule_shape.height, target_h, 1.0 - exp(-14.0 * delta))
		standing_collider.position.y = _capsule_shape.height * 0.5

	camera_pivot.position.y = lerpf(camera_pivot.position.y, target_cam_y, 1.0 - exp(-12.0 * delta))


func _update_locomotion(delta: float) -> void:
	var on_floor: bool = is_on_floor()
	if on_floor:
		_coyote_timer = coyote_time
	else:
		_coyote_timer = maxf(0.0, _coyote_timer - delta)
		velocity.y -= _gravity * gravity_multiplier * delta

	var input_vec: Vector2 = InputRouter.get_move_vector()
	var input_mag: float = clampf(input_vec.length(), 0.0, 1.0)

	var cam_yaw: float = camera_pivot.get_camera_yaw_rad()
	var forward_dir := Vector3(-sin(cam_yaw), 0.0, -cos(cam_yaw))
	var right_dir := Vector3(cos(cam_yaw), 0.0, -sin(cam_yaw))
	var move_dir: Vector3 = (right_dir * input_vec.x) + (forward_dir * -input_vec.y)
	if move_dir.length_squared() > 0.0001:
		move_dir = move_dir.normalized()

	var wants_sprint: bool = InputRouter.is_sprinting() and input_mag > 0.65 and not is_crouching
	if _stamina_exhausted and stamina > 25.0:
		_stamina_exhausted = false

	is_sprinting_active = wants_sprint and not _stamina_exhausted and stamina > 0.5

	if is_sprinting_active and on_floor:
		stamina = maxf(0.0, stamina - stamina_drain_rate * delta)
		_stamina_delay_timer = stamina_regen_delay
		if stamina <= 0.5:
			_stamina_exhausted = true
			is_sprinting_active = false
	else:
		if _stamina_delay_timer > 0.0:
			_stamina_delay_timer -= delta
		else:
			stamina = minf(max_stamina, stamina + stamina_regen_rate * delta)

	var target_speed: float = 0.0
	if input_mag > 0.02:
		if is_crouching:
			target_speed = crouch_speed * input_mag
		elif is_sprinting_active:
			target_speed = sprint_speed
		elif input_mag < 0.55:
			target_speed = lerpf(walk_speed * 0.5, walk_speed, input_mag / 0.55)
		else:
			target_speed = lerpf(walk_speed, run_speed, (input_mag - 0.55) / 0.45)

	var desired_horiz: Vector3 = move_dir * target_speed
	var current_horiz := Vector3(velocity.x, 0.0, velocity.z)

	var accel: float
	if on_floor:
		accel = ground_acceleration if input_mag > 0.02 else ground_deceleration
	else:
		accel = air_acceleration

	var new_horiz: Vector3 = current_horiz.move_toward(desired_horiz, accel * delta * 3.2)
	velocity.x = new_horiz.x
	velocity.z = new_horiz.z

	if _coyote_timer > 0.0 and InputRouter.consume_jump_if_buffered():
		if is_crouching:
			ceiling_check.force_raycast_update()
			if not ceiling_check.is_colliding():
				InputRouter.set_crouch(false)
				is_crouching = false
		if not is_crouching:
			velocity.y = jump_velocity
			_coyote_timer = 0.0

	move_and_slide()

	if new_horiz.length_squared() > 0.08:
		var desired_angle: float = atan2(-new_horiz.x, -new_horiz.z)
		visual_root.rotation.y = lerp_angle(visual_root.rotation.y, desired_angle, 1.0 - exp(-turn_speed * delta))


func _apply_rigidbody_push_impulses() -> void:
	for i: int in range(get_slide_collision_count()):
		var col: KinematicCollision3D = get_slide_collision(i)
		var body: Object = col.get_collider()
		if body is RigidBody3D and not (body is VehicleBody3D):
			var rb := body as RigidBody3D
			var push_dir: Vector3 = -col.get_normal()
			push_dir.y = 0.0
			if push_dir.length_squared() < 0.001:
				continue
			push_dir = push_dir.normalized()
			var player_speed: float = Vector2(velocity.x, velocity.z).length()
			var impulse_mag: float = clampf(player_speed * push_force_multiplier, 0.5, max_push_impulse)
			var offset: Vector3 = col.get_position() - rb.global_position
			rb.apply_impulse(push_dir * impulse_mag, offset * 0.45)
