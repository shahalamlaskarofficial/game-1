extends VehicleBody3D

## Native Physics-Driven Vehicle Controller (Godot 4.3 VehicleBody3D + 4x VehicleWheel3D).
## - Real raycast suspension travel, spring stiffness, damping, roll influence, and weight transfer.
## - Automatic 5-speed gear ratio curve, speed-sensitive steering, ABS braking, and handbrake drift.
## - Dual control mode: Player-driven (full manual physics) or AI Traffic autopilot.

const VehicleMeshBuilder = preload("res://scripts/vehicles/vehicle_mesh_builder.gd")

enum Archetype {
	SUV_4X4 = 0,
	CITY_SEDAN = 1,
	UTILITY_PICKUP = 2,
	AUTO_RICKSHAW = 3,
	CARGO_TRUCK = 4,
}

enum ControlMode {
	PARKED = 0,
	PLAYER = 1,
	AI_TRAFFIC = 2,
}

const GEAR_SPEED_THRESHOLDS_KMH: Array[float] = [0.0, 24.0, 48.0, 78.0, 112.0]
const GEAR_TORQUE_MULTS: Array[float] = [1.38, 1.08, 0.86, 0.68, 0.54]

var archetype: Archetype = Archetype.SUV_4X4
var control_mode: ControlMode = ControlMode.PARKED
var vehicle_display_name: String = "MARWAR 4X4"

# Live telemetry read by Driving HUD
var speed_kmh: float = 0.0
var forward_speed_mps: float = 0.0
var current_gear_label: String = "N"
var rpm_normalized: float = 0.14

# AI control inputs (written by TrafficManager)
var ai_throttle: float = 0.0
var ai_brake: float = 0.0
var ai_steer: float = 0.0

var _spec: Dictionary = {}
var _wheels: Array[VehicleWheel3D] = []
var _rear_wheels: Array[VehicleWheel3D] = []
var _headlight_mat: StandardMaterial3D = null
var _brakelight_mat: StandardMaterial3D = null
var _headlight_spot: SpotLight3D = null

var _current_steer_rad: float = 0.0
var _base_friction_slip: float = 2.95
var _is_reversing: bool = false
var _night_lights_on: bool = false


func setup_vehicle(arch: Archetype, paint_color: Color, initial_mode: ControlMode) -> void:
	archetype = arch
	control_mode = initial_mode
	_spec = VehicleMeshBuilder.get_spec(int(arch))
	vehicle_display_name = String(_spec["name"])

	collision_layer = 8 # Layer 4: Vehicles
	collision_mask = 15 # World_Static (1) + Player (2) + Physics_Props (4) + Vehicles (8)

	mass = float(_spec["mass"])
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = _spec["com_offset"] as Vector3
	linear_damp = 0.06
	angular_damp = 0.35

	var phys := PhysicsMaterial.new()
	phys.friction = 0.42
	phys.bounce = 0.06
	physics_material_override = phys

	# Main rigid-body chassis collider
	var col := CollisionShape3D.new()
	col.name = "ChassisCollider"
	var box := BoxShape3D.new()
	box.size = _spec["collider_size"] as Vector3
	col.shape = box
	col.position = Vector3(0.0, float(_spec["collider_y"]), 0.0)
	add_child(col)

	# Visual chassis hierarchy
	var visual := Node3D.new()
	visual.name = "ChassisVisual"
	add_child(visual)
	var mat_refs: Dictionary = VehicleMeshBuilder.build_chassis(visual, int(arch), paint_color)
	_headlight_mat = mat_refs.get("headlight_mat") as StandardMaterial3D
	_brakelight_mat = mat_refs.get("brakelight_mat") as StandardMaterial3D

	# 4 independent raycast physics wheels
	_build_physics_wheels()

	# Forward SpotLight3D (only active when player-driven at dusk/night for mobile fill-rate safety)
	_headlight_spot = SpotLight3D.new()
	_headlight_spot.name = "PlayerHeadlightBeam"
	_headlight_spot.light_color = Color(1.0, 0.94, 0.80)
	_headlight_spot.light_energy = 3.2
	_headlight_spot.spot_range = 42.0
	_headlight_spot.spot_angle = 36.0
	_headlight_spot.shadow_enabled = false
	_headlight_spot.position = Vector3(0.0, 1.05, float(_spec["front_z"]) + 0.55)
	_headlight_spot.rotation_degrees = Vector3(-8.0, 180.0, 0.0)
	_headlight_spot.visible = false
	add_child(_headlight_spot)


func set_control_mode(new_mode: ControlMode) -> void:
	control_mode = new_mode
	if new_mode == ControlMode.PARKED:
		engine_force = 0.0
		brake = float(_spec["brake_force"]) * 0.45
		steering = 0.0
		ai_throttle = 0.0
		ai_brake = 0.0
		ai_steer = 0.0
		_set_rear_slip(_base_friction_slip)
	elif new_mode == ControlMode.PLAYER:
		sleeping = false
		brake = 0.0
	elif new_mode == ControlMode.AI_TRAFFIC:
		sleeping = false
		_set_rear_slip(_base_friction_slip)


func get_exit_spawn_position(space_state: PhysicsDirectSpaceState3D) -> Vector3:
	# Check left door (+X in VehicleBody3D local frame), then right door (-X), then roof fallback
	var half_w: float = (_spec["collider_size"] as Vector3).x * 0.5
	var side_dist: float = half_w + 1.15
	var candidates: Array[Vector3] = [
		global_transform.origin + global_transform.basis.x * side_dist + Vector3(0.0, 0.45, 0.0),
		global_transform.origin - global_transform.basis.x * side_dist + Vector3(0.0, 0.45, 0.0),
		global_transform.origin + Vector3(0.0, (_spec["collider_size"] as Vector3).y + 1.1, 0.0),
	]

	var from_pt: Vector3 = global_transform.origin + Vector3(0.0, 1.0, 0.0)
	for target: Vector3 in candidates:
		var q := PhysicsRayQueryParameters3D.create(from_pt, target, 1)
		q.exclude = [get_rid()]
		var hit: Dictionary = space_state.intersect_ray(q)
		if hit.is_empty():
			return target
	return candidates[2]


func _physics_process(delta: float) -> void:
	var fwd: Vector3 = global_transform.basis.z
	forward_speed_mps = linear_velocity.dot(fwd)
	speed_kmh = linear_velocity.length() * 3.6

	var throttle_in: float = 0.0
	var brake_rev_in: float = 0.0
	var steer_in: float = 0.0
	var handbrake_in: bool = false

	match control_mode:
		ControlMode.PLAYER:
			throttle_in = InputRouter.get_vehicle_throttle()
			brake_rev_in = InputRouter.get_vehicle_brake_reverse()
			steer_in = InputRouter.get_vehicle_steer()
			handbrake_in = InputRouter.is_vehicle_handbrake()
			_apply_rollover_assist(steer_in)
		ControlMode.AI_TRAFFIC:
			throttle_in = ai_throttle
			brake_rev_in = ai_brake
			steer_in = ai_steer
			handbrake_in = false
		ControlMode.PARKED:
			engine_force = 0.0
			brake = float(_spec["brake_force"]) * 0.55 if speed_kmh < 4.0 else float(_spec["brake_force"]) * 0.2
			steering = lerpf(steering, 0.0, 1.0 - exp(-6.0 * delta))
			_update_lights_and_telemetry(false)
			return

	# Speed-sensitive steering (full lock at low speeds, steady precision on NH-68 highway)
	var max_steer_rad: float = deg_to_rad(float(_spec["max_steer_deg"]))
	var speed_factor: float = clampf(speed_kmh / 110.0, 0.0, 1.0)
	var active_max_steer: float = lerpf(max_steer_rad, max_steer_rad * 0.34, speed_factor)
	# Input steer_in: -1 = left (+Y rad), +1 = right (-Y rad)
	var desired_steer: float = -steer_in * active_max_steer
	var steer_rate: float = 8.5 if absf(steer_in) > 0.05 else 11.5
	_current_steer_rad = lerpf(_current_steer_rad, desired_steer, 1.0 - exp(-steer_rate * delta))
	steering = _current_steer_rad

	# Gear selection & torque curve
	var max_kmh: float = float(_spec["max_speed_kmh"])
	var base_engine: float = float(_spec["engine_force"])
	var base_brake: float = float(_spec["brake_force"])
	var braking_lights: bool = false

	if handbrake_in:
		engine_force = 0.0
		brake = base_brake * 0.15
		_set_rear_slip(_base_friction_slip * 0.36)
		for rw: VehicleWheel3D in _rear_wheels:
			rw.brake = base_brake * 1.15
		braking_lights = true
	else:
		_set_rear_slip(_base_friction_slip)
		for rw: VehicleWheel3D in _rear_wheels:
			rw.brake = 0.0

		if throttle_in > 0.02:
			if forward_speed_mps < -1.2:
				# Braking while reversing
				engine_force = 0.0
				brake = base_brake * throttle_in
				braking_lights = true
			else:
				_is_reversing = false
				brake = 0.0
				var gear_idx: int = _compute_gear_index(speed_kmh)
				var torque_mult: float = GEAR_TORQUE_MULTS[gear_idx]
				var speed_cutoff: float = clampf(1.0 - pow(speed_kmh / max_kmh, 3.0), 0.0, 1.0)
				engine_force = base_engine * torque_mult * throttle_in * speed_cutoff
		elif brake_rev_in > 0.02:
			braking_lights = true
			if forward_speed_mps > 1.2:
				# Progressive service braking
				engine_force = 0.0
				brake = base_brake * brake_rev_in
			else:
				# Smooth reverse gear engagement
				_is_reversing = true
				brake = 0.0
				var rev_cap: float = clampf(1.0 - (absf(forward_speed_mps) * 3.6) / 30.0, 0.0, 1.0)
				engine_force = -base_engine * 0.72 * brake_rev_in * rev_cap
		else:
			# Natural engine braking + gentle rolling drag
			engine_force = 0.0
			brake = base_brake * 0.06 if speed_kmh > 1.5 else base_brake * 0.25

	# Aerodynamic drag at high highway speeds
	if speed_kmh > 20.0:
		var drag_force: float = linear_velocity.length_squared() * 0.42
		apply_central_force(-linear_velocity.normalized() * drag_force)

	_update_lights_and_telemetry(braking_lights)


func _build_physics_wheels() -> void:
	var track: float = float(_spec["wheel_track"])
	var fz: float = float(_spec["front_z"])
	var rz: float = float(_spec["rear_z"])
	var wy: float = float(_spec["wheel_y"])
	var drive_mode: String = String(_spec["drive_mode"])
	_base_friction_slip = float(_spec["friction_slip"])

	var configs: Array[Dictionary] = [
		{"name": "Wheel_FL", "pos": Vector3(track, wy, fz), "steer": true, "rear": false},
		{"name": "Wheel_FR", "pos": Vector3(-track, wy, fz), "steer": true, "rear": false},
		{"name": "Wheel_RL", "pos": Vector3(track, wy, rz), "steer": false, "rear": true},
		{"name": "Wheel_RR", "pos": Vector3(-track, wy, rz), "steer": false, "rear": true},
	]

	for cfg: Dictionary in configs:
		var w := VehicleWheel3D.new()
		w.name = String(cfg["name"])
		w.position = cfg["pos"] as Vector3
		w.use_as_steering = bool(cfg["steer"])
		var is_rear: bool = bool(cfg["rear"])
		w.use_as_traction = (drive_mode == "AWD") or (drive_mode == "RWD" and is_rear) or (drive_mode == "FWD" and not is_rear)

		w.wheel_radius = float(_spec["wheel_radius"])
		w.wheel_rest_length = float(_spec["rest_length"])
		w.wheel_friction_slip = _base_friction_slip
		w.wheel_roll_influence = float(_spec["roll_influence"])

		w.suspension_travel = float(_spec["travel"])
		w.suspension_stiffness = float(_spec["stiffness"])
		w.suspension_max_force = float(_spec["max_force"])
		w.damping_compression = float(_spec["damping_comp"])
		w.damping_relaxation = float(_spec["damping_relax"])

		VehicleMeshBuilder.build_wheel_mesh(w, float(_spec["wheel_radius"]), float(_spec["wheel_width"]))
		add_child(w)
		_wheels.append(w)
		if is_rear:
			_rear_wheels.append(w)


func _set_rear_slip(slip_val: float) -> void:
	for rw: VehicleWheel3D in _rear_wheels:
		rw.wheel_friction_slip = slip_val


func _compute_gear_index(kmh: float) -> int:
	var g: int = 0
	for i: int in range(GEAR_SPEED_THRESHOLDS_KMH.size()):
		if kmh >= GEAR_SPEED_THRESHOLDS_KMH[i]:
			g = i
	return g


func _apply_rollover_assist(steer_in: float) -> void:
	# Allows player to rock an overturned vehicle back onto its wheels on steep desert dunes
	if global_transform.basis.y.y < 0.25 and speed_kmh < 8.0 and absf(steer_in) > 0.2:
		apply_torque(global_transform.basis.z * steer_in * mass * 6.5)


func _update_lights_and_telemetry(braking: bool) -> void:
	if _is_reversing and forward_speed_mps < -0.35:
		current_gear_label = "R"
		rpm_normalized = clampf(0.22 + absf(forward_speed_mps) * 0.08, 0.2, 0.92)
	elif speed_kmh < 1.2 and control_mode != ControlMode.PLAYER:
		current_gear_label = "P"
		rpm_normalized = 0.14
	else:
		var g_idx: int = _compute_gear_index(speed_kmh)
		current_gear_label = str(g_idx + 1)
		var g_min: float = GEAR_SPEED_THRESHOLDS_KMH[g_idx]
		var g_max: float = GEAR_SPEED_THRESHOLDS_KMH[g_idx + 1] if g_idx + 1 < GEAR_SPEED_THRESHOLDS_KMH.size() else float(_spec["max_speed_kmh"])
		var frac: float = clampf((speed_kmh - g_min) / maxf(g_max - g_min, 10.0), 0.0, 1.0)
		rpm_normalized = lerpf(0.24, 0.94, frac)

	# Night headlights respond automatically to Phase 3 AtmosphereManager time of day
	var is_night: bool = false
	if GameManager.atmosphere_ref != null:
		var tod: float = float(GameManager.atmosphere_ref.get("time_of_day"))
		is_night = (tod < 6.4 or tod > 18.2)
	_night_lights_on = is_night

	if _headlight_mat != null:
		_headlight_mat.emission_energy_multiplier = 3.2 if (is_night and control_mode != ControlMode.PARKED) else 0.25
	if _brakelight_mat != null:
		_brakelight_mat.emission_energy_multiplier = 3.4 if braking else (0.85 if is_night else 0.18)
	if _headlight_spot != null:
		_headlight_spot.visible = is_night and (control_mode == ControlMode.PLAYER)
