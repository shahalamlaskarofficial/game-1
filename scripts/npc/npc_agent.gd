extends CharacterBody3D

## Performance-Efficient Barmer NPC AI Agent.
## - Follows 24-hour daily schedules (morning commute, work shift, evening bazaar, night rest).
## - Navigates Barmer's sidewalk waypoint graph with local obstacle avoidance.
## - Interacts with other NPCs (paired conversations), reacts to sandstorms (seeks awning/wall
##   shelter), dodges approaching vehicles, and responds to player greetings with Barmer dialogue.
## - Uses near/far simulation LOD so 28 active NPCs stay ultra-light on Android CPUs.

const NpcMeshBuilder = preload("res://scripts/npc/npc_mesh_builder.gd")

enum Role {
	RESIDENT = 0,
	SHOPKEEPER = 1,
	COMMUTER = 2,
	WORKER = 3,
	ELDER = 4,
}

enum State {
	WALK_SIDEWALK = 0,
	WORK_SHIFT = 1,
	SOCIALIZE = 2,
	SHELTER_STORM = 3,
	FLEE_VEHICLE = 4,
	CONVERSE_PLAYER = 5,
	REST_NIGHT = 6,
}

const ROLE_LABELS: Array[String] = [
	"RESIDENT",
	"BAZAAR TRADER",
	"COMMUTER",
	"TRANSPORT WORKER",
	"DESERT ELDER",
]

const STATE_LABELS: Array[String] = [
	"WALKING",
	"WORKING",
	"CHATTING",
	"TAKING SHELTER",
	"DODGING TRAFFIC",
	"GREETING",
	"NIGHT REST",
]

var npc_name: String = "Ramesh"
var role: Role = Role.RESIDENT
var state: State = State.WALK_SIDEWALK
var workplace_pos: Vector3 = Vector3.ZERO
var workplace_facing_yaw: float = 0.0
var workplace_label: String = "Station Road"

var _manager: Node3D = null
var _map_data: RefCounted = null
var _rng := RandomNumberGenerator.new()

var _visual_root: Node3D = null
var _rig: Dictionary = {}
var _collider: CollisionShape3D = null

var _current_target: Vector3 = Vector3.ZERO
var _current_node_id: int = -1
var _partner_npc: Node3D = null
var _state_timer: float = 0.0
var _brain_timer: float = 0.0
var _flee_dir: Vector3 = Vector3.ZERO
var _walk_speed: float = 1.45
var _stride_phase: float = 0.0
var _gesture_phase: float = 0.0
var _gravity: float = 9.81
var _dist_to_player_sq: float = 0.0


func setup_npc(
	manager: Node3D,
	map_ref: RefCounted,
	display_name: String,
	npc_role: Role,
	work_poi: Dictionary,
	seed_val: int
) -> void:
	_manager = manager
	_map_data = map_ref
	npc_name = display_name
	role = npc_role
	workplace_pos = work_poi["pos"] as Vector3
	workplace_facing_yaw = float(work_poi["yaw"])
	workplace_label = String(work_poi["label"])

	_rng.seed = seed_val
	_walk_speed = _rng.randf_range(1.25, 1.65)
	if role == Role.ELDER:
		_walk_speed = _rng.randf_range(0.95, 1.18)

	collision_layer = 16 # Layer 5: NPCs
	collision_mask = 3   # Collides cleanly with World_Static (1) + Player (2)
	floor_max_angle = 0.78
	floor_snap_length = 0.2

	_collider = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.30
	cap.height = 1.72
	_collider.shape = cap
	_collider.position = Vector3(0.0, 0.86, 0.0)
	add_child(_collider)

	_visual_root = Node3D.new()
	add_child(_visual_root)
	_rig = NpcMeshBuilder.build_rig(_visual_root, int(role), _rng)
	_brain_timer = _rng.randf_range(0.05, 0.25)


func reset_to_waypoint(node_id: int, world_pos: Vector3) -> void:
	_current_node_id = node_id
	_partner_npc = null
	global_position = world_pos
	velocity = Vector3.ZERO
	_pick_initial_schedule_state()


func get_role_label() -> String:
	return ROLE_LABELS[int(role)]


func get_status_label() -> String:
	return STATE_LABELS[int(state)]


func trigger_vehicle_flee(threat_dir_away: Vector3) -> void:
	if state == State.FLEE_VEHICLE:
		return
	_partner_npc = null
	state = State.FLEE_VEHICLE
	_flee_dir = threat_dir_away.normalized()
	_state_timer = 2.4


func begin_socializing_with(other: Node3D, duration: float) -> void:
	if state == State.FLEE_VEHICLE or state == State.SHELTER_STORM or state == State.CONVERSE_PLAYER:
		return
	_partner_npc = other
	state = State.SOCIALIZE
	_state_timer = duration


func on_player_greeted(player_pos: Vector3) -> void:
	_partner_npc = null
	state = State.CONVERSE_PLAYER
	_state_timer = 3.4
	_gesture_phase = 0.0

	var to_p: Vector3 = player_pos - global_position
	to_p.y = 0.0
	if to_p.length_squared() > 0.01:
		_visual_root.rotation.y = atan2(-to_p.x, -to_p.z)

	var line: String = _pick_contextual_dialogue()
	GameManager.show_npc_dialogue("%s · %s" % [npc_name.to_upper(), get_role_label()], line)


func _physics_process(delta: float) -> void:
	var player := GameManager.player_ref
	if player == null:
		return

	_dist_to_player_sq = global_position.distance_squared_to(player.global_position)
	if _dist_to_player_sq > 24000.0: # > ~155m -> let manager recycle
		return

	_brain_timer -= delta
	if _brain_timer <= 0.0:
		_brain_timer = 0.18 if _dist_to_player_sq < 2500.0 else 0.45
		_evaluate_schedule_and_reactions()

	_state_timer = maxf(0.0, _state_timer - delta)
	var desired_vel: Vector3 = _compute_state_velocity(delta)

	# Near-LOD (< 65m): full physics CharacterBody3D. Far-LOD (>= 65m): ultra-cheap grounded kinematic step.
	if _dist_to_player_sq < 4225.0:
		if _collider.disabled:
			_collider.disabled = false
		if not is_on_floor():
			velocity.y -= _gravity * delta
		else:
			velocity.y = 0.0
		velocity.x = lerpf(velocity.x, desired_vel.x, 1.0 - exp(-8.5 * delta))
		velocity.z = lerpf(velocity.z, desired_vel.z, 1.0 - exp(-8.5 * delta))
		move_and_slide()
	else:
		if not _collider.disabled:
			_collider.disabled = true
		global_position.x += desired_vel.x * delta
		global_position.z += desired_vel.z * delta
		if _map_data != null:
			var g_h: float = _map_data.get_terrain_height(global_position.x, global_position.z)
			global_position.y = maxf(0.11, g_h + 0.05)
		velocity = desired_vel

	# Rotate smoothly toward travel or interaction target
	var horiz_v := Vector2(velocity.x, velocity.z)
	if horiz_v.length_squared() > 0.06:
		var yaw: float = atan2(-velocity.x, -velocity.z)
		_visual_root.rotation.y = lerp_angle(_visual_root.rotation.y, yaw, 1.0 - exp(-9.0 * delta))
	elif state == State.WORK_SHIFT:
		_visual_root.rotation.y = lerp_angle(_visual_root.rotation.y, workplace_facing_yaw, 1.0 - exp(-6.0 * delta))
	elif state == State.SOCIALIZE and is_instance_valid(_partner_npc):
		var to_partner: Vector3 = _partner_npc.global_position - global_position
		if Vector2(to_partner.x, to_partner.z).length_squared() > 0.02:
			_visual_root.rotation.y = lerp_angle(_visual_root.rotation.y, atan2(-to_partner.x, -to_partner.z), 1.0 - exp(-7.0 * delta))
	elif state == State.CONVERSE_PLAYER:
		var to_p: Vector3 = player.global_position - global_position
		if Vector2(to_p.x, to_p.z).length_squared() > 0.02:
			_visual_root.rotation.y = lerp_angle(_visual_root.rotation.y, atan2(-to_p.x, -to_p.z), 1.0 - exp(-8.0 * delta))

	# Animation LOD: full limb articulation within 52m, idle pose beyond to save Android CPU
	if _dist_to_player_sq < 2704.0:
		_update_procedural_animation(delta, horiz_v.length(), player.global_position)


func _evaluate_schedule_and_reactions() -> void:
	# 1. Highest priority: active dodge or player conversation
	if state == State.FLEE_VEHICLE:
		if _state_timer <= 0.0:
			_pick_next_waypoint_and_walk()
		return

	if state == State.CONVERSE_PLAYER:
		if _state_timer <= 0.0:
			_pick_initial_schedule_state()
		return

	# 2. Weather reaction: Thar Sandstorm pushes outdoor NPCs to shelter beside walls/workplaces
	var is_storm: bool = false
	var hour: float = 9.5
	if GameManager.atmosphere_ref != null:
		is_storm = int(GameManager.atmosphere_ref.get("current_weather")) == 2
		hour = float(GameManager.atmosphere_ref.get("time_of_day"))

	if is_storm:
		if state != State.SHELTER_STORM:
			_partner_npc = null
			state = State.SHELTER_STORM
			_current_target = workplace_pos
		return
	elif state == State.SHELTER_STORM:
		_pick_initial_schedule_state()
		return

	# 3. 24-Hour Barmer Daily Schedule
	var is_night: bool = (hour >= 22.0 or hour < 5.5)
	var is_work_hours: bool = (hour >= 8.0 and hour < 18.0)

	if is_night:
		if state != State.REST_NIGHT and _rng.randf() < 0.35:
			_partner_npc = null
			state = State.REST_NIGHT
			_current_target = workplace_pos
			_state_timer = _rng.randf_range(12.0, 24.0)
		return
	elif state == State.REST_NIGHT:
		_pick_initial_schedule_state()
		return

	if state == State.SOCIALIZE:
		if _state_timer <= 0.0 or not is_instance_valid(_partner_npc):
			_partner_npc = null
			_pick_next_waypoint_and_walk()
		return

	if state == State.WORK_SHIFT:
		if not is_work_hours or _state_timer <= 0.0:
			_pick_next_waypoint_and_walk()
		return

	# Shopkeepers & Workers gravitate to their assigned Barmer workplace during shift hours
	if is_work_hours and (role == Role.SHOPKEEPER or role == Role.WORKER) and _state_timer <= 0.0:
		if global_position.distance_to(workplace_pos) < 52.0 and _rng.randf() < 0.28:
			state = State.WORK_SHIFT
			_current_target = workplace_pos
			_state_timer = _rng.randf_range(18.0, 36.0)


func _compute_state_velocity(_delta: float) -> Vector3:
	match state:
		State.FLEE_VEHICLE:
			return _flee_dir * 3.85

		State.CONVERSE_PLAYER, State.SOCIALIZE:
			return Vector3.ZERO

		State.SHELTER_STORM:
			var to_sh: Vector3 = _current_target - global_position
			to_sh.y = 0.0
			if to_sh.length() > 1.8:
				return to_sh.normalized() * 2.55
			return Vector3.ZERO

		State.WORK_SHIFT, State.REST_NIGHT:
			var to_wk: Vector3 = _current_target - global_position
			to_wk.y = 0.0
			if to_wk.length() > 1.4:
				return to_wk.normalized() * _walk_speed
			return Vector3.ZERO

		_: # WALK_SIDEWALK
			var to_wp: Vector3 = _current_target - global_position
			to_wp.y = 0.0
			if to_wp.length() < 2.2:
				_pick_next_waypoint_and_walk()
				to_wp = _current_target - global_position
				to_wp.y = 0.0
			if to_wp.length_squared() < 0.01:
				return Vector3.ZERO

			var move_dir: Vector3 = to_wp.normalized()
			# Gentle personal-space separation if player is directly in front
			var player := GameManager.player_ref
			if player != null and GameManager.current_context == GameManager.ControlContext.ON_FOOT:
				var away: Vector3 = global_position - player.global_position
				away.y = 0.0
				var d: float = away.length()
				if d > 0.05 and d < 1.35:
					move_dir = (move_dir + away.normalized() * 1.1).normalized()

			return move_dir * _walk_speed


func _pick_initial_schedule_state() -> void:
	var hour: float = float(GameManager.atmosphere_ref.get("time_of_day")) if GameManager.atmosphere_ref != null else 9.5
	if (role == Role.SHOPKEEPER or role == Role.WORKER) and hour >= 8.0 and hour < 18.0 and global_position.distance_to(workplace_pos) < 35.0:
		state = State.WORK_SHIFT
		_current_target = workplace_pos
		_state_timer = _rng.randf_range(16.0, 34.0)
	else:
		_pick_next_waypoint_and_walk()


func _pick_next_waypoint_and_walk() -> void:
	state = State.WALK_SIDEWALK
	if _manager != null and _manager.has_method("get_next_waypoint"):
		var wp: Dictionary = _manager.call("get_next_waypoint", _current_node_id, _rng)
		_current_node_id = int(wp["id"])
		var base_pos: Vector3 = wp["pos"] as Vector3
		# Small lateral sidewalk offset so pedestrians pass naturally in two directions
		_current_target = base_pos + Vector3(_rng.randf_range(-0.65, 0.65), 0.0, _rng.randf_range(-0.65, 0.65))
	else:
		_current_target = global_position + Vector3(_rng.randf_range(-12.0, 12.0), 0.0, _rng.randf_range(-12.0, 12.0))


func _update_procedural_animation(delta: float, speed: float, player_pos: Vector3) -> void:
	if bool(_rig.get("external", true)):
		return

	var l_arm: Node3D = _rig["l_arm"]
	var r_arm: Node3D = _rig["r_arm"]
	var l_leg: Node3D = _rig["l_leg"]
	var r_leg: Node3D = _rig["r_leg"]
	var spine: Node3D = _rig["spine"]
	var head: Node3D = _rig["head"]
	var blend: float = 1.0 - exp(-11.0 * delta)

	if speed > 0.20:
		var sf: float = clampf(speed / 3.8, 0.25, 1.0)
		_stride_phase += delta * lerpf(5.8, 12.2, sf)
		var sw: float = sin(_stride_phase) * lerpf(0.32, 0.80, sf)
		l_leg.rotation.x = lerpf(l_leg.rotation.x, sw, blend)
		r_leg.rotation.x = lerpf(r_leg.rotation.x, -sw, blend)
		l_arm.rotation.x = lerpf(l_arm.rotation.x, -sw * 0.72, blend)
		r_arm.rotation.x = lerpf(r_arm.rotation.x, sw * 0.72, blend)
		r_arm.rotation.z = lerpf(r_arm.rotation.z, 0.0, blend)
		spine.rotation.x = lerpf(spine.rotation.x, -0.18 if state == State.SHELTER_STORM else -0.06 * sf, blend)
	else:
		l_leg.rotation.x = lerpf(l_leg.rotation.x, 0.0, blend)
		r_leg.rotation.x = lerpf(r_leg.rotation.x, 0.0, blend)
		_gesture_phase += delta * 3.4

		if state == State.CONVERSE_PLAYER:
			# Friendly Rajasthani wave / greeting gesture
			r_arm.rotation.x = lerpf(r_arm.rotation.x, -1.95, blend)
			r_arm.rotation.z = lerpf(r_arm.rotation.z, 0.28 + sin(_gesture_phase * 2.2) * 0.22, blend)
			l_arm.rotation.x = lerpf(l_arm.rotation.x, -0.18, blend)
			spine.rotation.x = lerpf(spine.rotation.x, 0.0, blend)
		elif state == State.SOCIALIZE or state == State.WORK_SHIFT:
			# Conversational / shop-tending hand gestures
			r_arm.rotation.x = lerpf(r_arm.rotation.x, -0.45 + sin(_gesture_phase) * 0.24, blend)
			r_arm.rotation.z = lerpf(r_arm.rotation.z, 0.0, blend)
			l_arm.rotation.x = lerpf(l_arm.rotation.x, -0.32 + cos(_gesture_phase * 0.8) * 0.18, blend)
			spine.rotation.x = lerpf(spine.rotation.x, 0.0, blend)
		elif state == State.SHELTER_STORM:
			# Shielding face from Thar sandstorm wind
			r_arm.rotation.x = lerpf(r_arm.rotation.x, -1.65, blend)
			r_arm.rotation.z = lerpf(r_arm.rotation.z, -0.32, blend)
			l_arm.rotation.x = lerpf(l_arm.rotation.x, -0.4, blend)
			spine.rotation.x = lerpf(spine.rotation.x, -0.22, blend)
		else:
			l_arm.rotation.x = lerpf(l_arm.rotation.x, 0.0, blend)
			r_arm.rotation.x = lerpf(r_arm.rotation.x, 0.0, blend)
			r_arm.rotation.z = lerpf(r_arm.rotation.z, 0.0, blend)
			spine.rotation.x = lerpf(spine.rotation.x, 0.0, blend)

	# Subtle head-look toward player when nearby (< 5.5m)
	var target_head_yaw: float = 0.0
	if _dist_to_player_sq < 30.25:
		var to_p: Vector3 = player_pos - global_position
		var world_yaw: float = atan2(-to_p.x, -to_p.z)
		target_head_yaw = clampf(wrapf(world_yaw - _visual_root.rotation.y, -PI, PI), -0.85, 0.85)
	head.rotation.y = lerpf(head.rotation.y, target_head_yaw, blend)


func _pick_contextual_dialogue() -> String:
	var weather: int = int(GameManager.atmosphere_ref.get("current_weather")) if GameManager.atmosphere_ref != null else 0
	var hour: float = float(GameManager.atmosphere_ref.get("time_of_day")) if GameManager.atmosphere_ref != null else 9.5

	if weather == 2:
		return "Aandhi is blowing hard off the Thar! Best stay near the sandstone walls until it passes."
	if hour >= 21.5 or hour < 5.0:
		return "Quiet night in Barmer. Heading home before NH-68 gets too dark."

	match role:
		Role.SHOPKEEPER:
			return "Khamma Ghani! Fresh tea and spices ready right here at %s." % workplace_label
		Role.COMMUTER:
			return "Catching the afternoon connection near %s. Traffic around Ahinsa Circle is lively today." % workplace_label
		Role.WORKER:
			return "Heavy cargo rolling in from Jodhpur on NH-25. Long shift over at %s." % workplace_label
		Role.ELDER:
			return "Ram Ram! Have you climbed up to Garh Mandir on Barmer Fort hill? Best view of the dunes."
		_:
			return "Namaste! Good day to walk down Station Road toward the bazaar."
