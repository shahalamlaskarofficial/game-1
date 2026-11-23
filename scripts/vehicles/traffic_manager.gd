extends Node3D

## Pooled Barmer Traffic AI Manager (Authentic Indian Left-Hand Traffic).
## - Spawns 2 persistent ready-to-drive starter vehicles near the player spawn (Marwar 4x4 + Barmer Auto).
## - Manages a fixed pool of physics-driven VehicleBody3D traffic cars on NH-68 and NH-25.
## - Uses throttled 10 Hz dual-raycast obstacle avoidance (yields to player, NPCs, props, and traffic).
## - Safely verifies loaded chunks before spawning/recycling so vehicles never drop into void.

const BarmerMapDataScript = preload("res://scripts/world/barmer_map_data.gd")
const VehicleControllerScript = preload("res://scripts/vehicles/vehicle_controller.gd")

enum LaneId {
	NH68_NORTHBOUND = 0, # Indian LHT: x = -3.6, heading -Z (North)
	NH68_SOUTHBOUND = 1, # Indian LHT: x = +3.6, heading +Z (South)
	NH25_EASTBOUND = 2,  # Indian LHT: z = -30.8, heading +X (East)
	NH25_WESTBOUND = 3,  # Indian LHT: z = -25.2, heading -X (West)
}

const LANE_COLORS: Array[Color] = [
	Color(0.86, 0.84, 0.80), # Pearl White
	Color(0.68, 0.19, 0.16), # Rajasthani Crimson
	Color(0.24, 0.30, 0.36), # Desert Slate
	Color(0.76, 0.56, 0.26), # Sandstone Gold
	Color(0.16, 0.38, 0.24), # Auto Green
	Color(0.20, 0.32, 0.52), # Highway Blue
]

var map_data: RefCounted = null
var chunk_streamer: Node = null

var all_vehicles: Array[Node3D] = []
var _ai_entries: Array[Dictionary] = []
var _target_traffic_count: int = 6
var _rng := RandomNumberGenerator.new()


func initialize(map_ref: RefCounted, streamer_ref: Node) -> void:
	map_data = map_ref
	chunk_streamer = streamer_ref
	_rng.seed = 407264

	GameManager.register_traffic_manager(self)
	if not GameManager.graphics_profile_changed.is_connected(_on_profile_changed):
		GameManager.graphics_profile_changed.connect(_on_profile_changed)
	_on_profile_changed(GameManager.current_profile)

	_spawn_starter_vehicles()
	_sync_traffic_pool_size()


func get_nearest_enterable_vehicle(world_pos: Vector3, max_dist: float = 4.6) -> Node3D:
	var best: Node3D = null
	var best_d2: float = max_dist * max_dist
	for v: Node3D in all_vehicles:
		if not is_instance_valid(v):
			continue
		if v == GameManager.current_vehicle:
			continue
		var d2: float = v.global_position.distance_squared_to(world_pos)
		if d2 < best_d2 and float(v.get("speed_kmh")) < 22.0:
			best_d2 = d2
			best = v
	return best


func notify_vehicle_taken_by_player(veh: Node3D) -> void:
	for i: int in range(_ai_entries.size() - 1, -1, -1):
		if _ai_entries[i]["veh"] == veh:
			_ai_entries.remove_at(i)
			break
	GameManager.active_traffic_count = _ai_entries.size()


func _physics_process(delta: float) -> void:
	var player := GameManager.player_ref
	if player == null or map_data == null:
		return

	var p_pos: Vector3 = player.global_position
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state

	for entry: Dictionary in _ai_entries:
		var veh := entry["veh"] as VehicleBody3D
		if not is_instance_valid(veh):
			continue
		if veh.get("control_mode") != VehicleControllerScript.ControlMode.AI_TRAFFIC:
			continue

		var dist_to_player: float = veh.global_position.distance_to(p_pos)
		var is_flipped: bool = veh.global_transform.basis.y.y < 0.45
		var lookahead_pos: Vector3 = veh.global_position + veh.global_transform.basis.z * 28.0
		var chunk_ok: bool = _is_position_in_loaded_chunk(lookahead_pos)

		if dist_to_player > 205.0 or is_flipped or not chunk_ok:
			_recycle_ai_vehicle(entry, p_pos)
			continue

		if float(veh.get("speed_kmh")) < 2.2:
			entry["stuck_t"] = float(entry["stuck_t"]) + delta
			if float(entry["stuck_t"]) > 7.5 and dist_to_player > 34.0:
				_recycle_ai_vehicle(entry, p_pos)
				continue
		else:
			entry["stuck_t"] = 0.0

		entry["ray_t"] = float(entry["ray_t"]) - delta
		if float(entry["ray_t"]) <= 0.0:
			entry["ray_t"] = 0.10
			entry["obs_factor"] = _sense_forward_obstacle(veh, space_state)

		_drive_ai_step(entry, veh)


func _spawn_starter_vehicles() -> void:
	var suv := _create_vehicle_instance(
		VehicleControllerScript.Archetype.SUV_4X4,
		Color(0.76, 0.40, 0.18),
		VehicleControllerScript.ControlMode.PARKED
	)
	suv.name = "Starter_Marwar4x4"
	suv.global_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(5.6, 0.55, 5.5))
	add_child(suv)
	all_vehicles.append(suv)

	var auto := _create_vehicle_instance(
		VehicleControllerScript.Archetype.AUTO_RICKSHAW,
		Color(0.14, 0.40, 0.22),
		VehicleControllerScript.ControlMode.PARKED
	)
	auto.name = "Starter_BarmerAuto"
	auto.global_transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(15.2, 0.50, 9.8))
	add_child(auto)
	all_vehicles.append(auto)


func _sync_traffic_pool_size() -> void:
	var p_pos: Vector3 = GameManager.player_ref.global_position if GameManager.player_ref != null else Vector3(0.0, 0.0, 10.0)

	while _ai_entries.size() < _target_traffic_count:
		var arch_roll: float = _rng.randf()
		var arch: int
		var col: Color
		var cruise_kmh: float
		if arch_roll < 0.30:
			arch = VehicleControllerScript.Archetype.CITY_SEDAN
			col = LANE_COLORS[_rng.randi() % LANE_COLORS.size()]
			cruise_kmh = _rng.randf_range(38.0, 52.0)
		elif arch_roll < 0.55:
			arch = VehicleControllerScript.Archetype.AUTO_RICKSHAW
			col = Color(0.14, 0.42, 0.22)
			cruise_kmh = _rng.randf_range(26.0, 36.0)
		elif arch_roll < 0.76:
			arch = VehicleControllerScript.Archetype.UTILITY_PICKUP
			col = LANE_COLORS[_rng.randi() % LANE_COLORS.size()]
			cruise_kmh = _rng.randf_range(36.0, 48.0)
		elif arch_roll < 0.90:
			arch = VehicleControllerScript.Archetype.SUV_4X4
			col = LANE_COLORS[_rng.randi() % LANE_COLORS.size()]
			cruise_kmh = _rng.randf_range(40.0, 54.0)
		else:
			arch = VehicleControllerScript.Archetype.CARGO_TRUCK
			col = Color(0.76, 0.36, 0.14)
			cruise_kmh = _rng.randf_range(30.0, 42.0)

		var veh := _create_vehicle_instance(arch, col, VehicleControllerScript.ControlMode.AI_TRAFFIC)
		veh.name = "Traffic_%d" % _ai_entries.size()
		add_child(veh)
		all_vehicles.append(veh)

		var entry: Dictionary = {
			"veh": veh,
			"lane": _ai_entries.size() % 4,
			"target_kmh": cruise_kmh,
			"stuck_t": 0.0,
			"ray_t": _rng.randf_range(0.02, 0.10),
			"obs_factor": 0.0,
		}
		_ai_entries.append(entry)
		_recycle_ai_vehicle(entry, p_pos)

	while _ai_entries.size() > _target_traffic_count:
		var removed: Dictionary = _ai_entries.pop_back()
		var v: Node3D = removed["veh"]
		all_vehicles.erase(v)
		if is_instance_valid(v):
			v.queue_free()

	GameManager.active_traffic_count = _ai_entries.size()


func _create_vehicle_instance(arch: int, col: Color, mode: int) -> VehicleBody3D:
	var veh := VehicleBody3D.new()
	veh.set_script(VehicleControllerScript)
	veh.setup_vehicle(arch, col, mode)
	return veh


func _drive_ai_step(entry: Dictionary, veh: VehicleBody3D) -> void:
	var lane: int = int(entry["lane"])
	var pos: Vector3 = veh.global_position
	var fwd: Vector3 = veh.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.001:
		return
	fwd = fwd.normalized()

	var target_pt: Vector3 = _compute_lane_lookahead(lane, pos)
	var to_target: Vector3 = target_pt - pos
	to_target.y = 0.0
	if to_target.length_squared() < 0.01:
		return
	to_target = to_target.normalized()

	var cross_y: float = fwd.cross(to_target).y
	var dot_v: float = clampf(fwd.dot(to_target), -1.0, 1.0)
	var angle: float = atan2(cross_y, dot_v)
	var steer_cmd: float = clampf(-angle * 1.45, -1.0, 1.0)

	var obs: float = float(entry["obs_factor"])
	var desired_kmh: float = float(entry["target_kmh"])
	var circle_dist: float = Vector2(pos.x, pos.z).distance_to(BarmerMapDataScript.AHINSA_CIRCLE_POS)
	if circle_dist < 26.0:
		desired_kmh = minf(desired_kmh, 24.0)

	var cur_kmh: float = float(veh.get("speed_kmh"))
	if obs >= 0.85:
		veh.set("ai_throttle", 0.0)
		veh.set("ai_brake", 0.95)
	elif obs > 0.25:
		veh.set("ai_throttle", 0.0)
		veh.set("ai_brake", obs * 0.65)
	elif cur_kmh < desired_kmh - 2.0:
		veh.set("ai_throttle", clampf((desired_kmh - cur_kmh) / 18.0, 0.22, 0.78))
		veh.set("ai_brake", 0.0)
	elif cur_kmh > desired_kmh + 4.0:
		veh.set("ai_throttle", 0.0)
		veh.set("ai_brake", 0.35)
	else:
		veh.set("ai_throttle", 0.14)
		veh.set("ai_brake", 0.0)

	veh.set("ai_steer", steer_cmd)


func _compute_lane_lookahead(lane: int, pos: Vector3) -> Vector3:
	const LOOK_DIST: float = 14.0
	var circle: Vector2 = BarmerMapDataScript.AHINSA_CIRCLE_POS
	var pos_2d := Vector2(pos.x, pos.z)
	var to_circle: Vector2 = pos_2d - circle
	var dist_circle: float = to_circle.length()

	if dist_circle < 20.5:
		var radial: Vector2 = to_circle.normalized() if dist_circle > 0.5 else Vector2(0.0, 1.0)
		var cw_tangent := Vector2(-radial.y, radial.x)
		var ring_pt: Vector2 = circle + radial * 12.2 + cw_tangent * 9.5
		return Vector3(ring_pt.x, pos.y, ring_pt.y)

	match lane:
		LaneId.NH68_NORTHBOUND:
			return Vector3(-3.6, pos.y, pos.z - LOOK_DIST)
		LaneId.NH68_SOUTHBOUND:
			return Vector3(3.6, pos.y, pos.z + LOOK_DIST)
		LaneId.NH25_EASTBOUND:
			return Vector3(pos.x + LOOK_DIST, pos.y, BarmerMapDataScript.STATION_ROAD_Z - 2.8)
		_:
			return Vector3(pos.x - LOOK_DIST, pos.y, BarmerMapDataScript.STATION_ROAD_Z + 2.8)


func _sense_forward_obstacle(veh: VehicleBody3D, space_state: PhysicsDirectSpaceState3D) -> float:
	var fwd: Vector3 = veh.global_transform.basis.z
	var right: Vector3 = veh.global_transform.basis.x
	var origin_base: Vector3 = veh.global_position + Vector3(0.0, 0.85, 0.0) + fwd * 2.4
	var check_len: float = clampf(10.0 + float(veh.get("speed_kmh")) * 0.25, 11.0, 24.0)

	var worst_threat: float = 0.0
	for lat: float in [-0.65, 0.65]:
		var start_p: Vector3 = origin_base + right * lat
		var end_p: Vector3 = start_p + fwd * check_len
		# Check Player (2) + Physics_Props (4) + Vehicles (8) + NPCs (16) = 30
		var q := PhysicsRayQueryParameters3D.create(start_p, end_p, 30)
		q.exclude = [veh.get_rid()]
		var hit: Dictionary = space_state.intersect_ray(q)
		if not hit.is_empty():
			var d: float = start_p.distance_to(hit["position"] as Vector3)
			var threat: float = clampf(1.0 - (d / check_len), 0.0, 1.0)
			if d < 5.5:
				threat = 1.0
			worst_threat = maxf(worst_threat, threat)
	return worst_threat


func _recycle_ai_vehicle(entry: Dictionary, player_pos: Vector3) -> void:
	var veh := entry["veh"] as VehicleBody3D
	var candidates: Array[int] = [0, 1, 2, 3]
	candidates.shuffle()

	for lane: int in candidates:
		var spawn_info: Dictionary = _pick_lane_spawn(lane, player_pos)
		if spawn_info.is_empty():
			continue
		var s_pos: Vector3 = spawn_info["pos"]
		if not _is_position_in_loaded_chunk(s_pos):
			continue
		if not _is_spawn_clear(s_pos, veh):
			continue

		entry["lane"] = lane
		entry["stuck_t"] = 0.0
		entry["obs_factor"] = 0.0
		veh.linear_velocity = Vector3.ZERO
		veh.angular_velocity = Vector3.ZERO
		veh.global_transform = Transform3D(Basis(Vector3.UP, float(spawn_info["yaw"])), s_pos)
		veh.set("ai_throttle", 0.35)
		veh.set("ai_brake", 0.0)
		veh.set("ai_steer", 0.0)
		return


func _pick_lane_spawn(lane: int, player_pos: Vector3) -> Dictionary:
	var dist: float = _rng.randf_range(58.0, 128.0)
	var sign_dir: float = 1.0 if _rng.randf() < 0.55 else -1.0

	match lane:
		LaneId.NH68_NORTHBOUND:
			var z: float = clampf(player_pos.z + dist * sign_dir, -340.0, 240.0)
			if absf(z - BarmerMapDataScript.STATION_ROAD_Z) < 28.0:
				z += 38.0
			return {"pos": Vector3(-3.6, 0.55, z), "yaw": PI}
		LaneId.NH68_SOUTHBOUND:
			var z: float = clampf(player_pos.z + dist * sign_dir, -340.0, 240.0)
			if absf(z - BarmerMapDataScript.STATION_ROAD_Z) < 28.0:
				z -= 38.0
			return {"pos": Vector3(3.6, 0.55, z), "yaw": 0.0}
		LaneId.NH25_EASTBOUND:
			var x: float = clampf(player_pos.x + dist * sign_dir, -340.0, 340.0)
			if absf(x) < 28.0:
				x += 38.0
			return {"pos": Vector3(x, 0.55, BarmerMapDataScript.STATION_ROAD_Z - 2.8), "yaw": PI * 0.5}
		_:
			var x: float = clampf(player_pos.x + dist * sign_dir, -340.0, 340.0)
			if absf(x) < 28.0:
				x -= 38.0
			return {"pos": Vector3(x, 0.55, BarmerMapDataScript.STATION_ROAD_Z + 2.8), "yaw": -PI * 0.5}


func _is_position_in_loaded_chunk(world_pos: Vector3) -> bool:
	if chunk_streamer == null or map_data == null:
		return true
	var c: Vector2i = map_data.world_to_chunk(world_pos)
	return chunk_streamer.loaded_chunks.has(c)


func _is_spawn_clear(pos: Vector3, self_veh: Node3D) -> bool:
	if GameManager.player_ref != null and pos.distance_to(GameManager.player_ref.global_position) < 36.0:
		return false
	for other: Node3D in all_vehicles:
		if other == self_veh or not is_instance_valid(other):
			continue
		if other.global_position.distance_to(pos) < 16.0:
			return false
	return true


func _on_profile_changed(profile: int) -> void:
	match profile:
		GameManager.GraphicsProfile.LOW:
			_target_traffic_count = 4
		GameManager.GraphicsProfile.MEDIUM:
			_target_traffic_count = 6
		GameManager.GraphicsProfile.HIGH:
			_target_traffic_count = 8
		GameManager.GraphicsProfile.ULTRA:
			_target_traffic_count = 10
	if map_data != null:
		_sync_traffic_pool_size()
