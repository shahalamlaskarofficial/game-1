extends Node3D

## Pooled Barmer Crowd, Sidewalk Waypoint Graph & Event Reaction Director.
## - Maintains a real Barmer sidewalk navigation network (NH-68, NH-25, Ahinsa Circle,
##   Station Road Bazaar, Barmer Railway Station, Sindhari Bus Stand, Chohtan Circle).
## - Pairs nearby wandering NPCs to stop and chat naturally.
## - Broadcasts oncoming-vehicle danger checks at 5 Hz so NPCs dodge traffic dynamically.
## - Scales pool size cleanly across LOW (10) / MEDIUM (16) / HIGH (22) / ULTRA (28) profiles.

const NpcAgentScript = preload("res://scripts/npc/npc_agent.gd")

const BARMER_NAMES: Array[String] = [
	"Ramesh", "Mahendra", "Kavita", "Suresh", "Bhawani",
	"Vikram", "Rekha", "Deepak", "Harish", "Sunita",
	"Kailash", "Pooja", "Narayan", "Gajendra", "Meena",
	"Rajendra", "Dinesh", "Anita", "Prakash", "Suman",
	"Devendra", "Lakshmi", "Ashok", "Kiran", "Ratan",
	"Babu", "Chandra", "Manoj",
]

var map_data: RefCounted = null
var chunk_streamer: Node = null
var traffic_manager: Node3D = null

var npcs: Array[Node3D] = []
var _waypoints: Array[Dictionary] = [] # { "id": int, "pos": Vector3, "neighbors": Array[int] }
var _workplaces: Array[Dictionary] = [] # { "pos": Vector3, "yaw": float, "label": String, "role": int }

var _target_npc_count: int = 16
var _director_timer: float = 0.0
var _rng := RandomNumberGenerator.new()


func initialize(map_ref: RefCounted, streamer_ref: Node, traffic_ref: Node3D) -> void:
	map_data = map_ref
	chunk_streamer = streamer_ref
	traffic_manager = traffic_ref
	_rng.seed = 407265

	_build_barmer_sidewalk_graph()
	_build_barmer_workplaces()

	GameManager.register_npc_manager(self)
	if not GameManager.graphics_profile_changed.is_connected(_on_profile_changed):
		GameManager.graphics_profile_changed.connect(_on_profile_changed)
	_on_profile_changed(GameManager.current_profile)

	_sync_npc_pool_size()


func get_nearest_interactable_npc(world_pos: Vector3, max_dist: float = 3.2) -> Node3D:
	var best: Node3D = null
	var best_d2: float = max_dist * max_dist
	for npc: Node3D in npcs:
		if not is_instance_valid(npc):
			continue
		var d2: float = npc.global_position.distance_squared_to(world_pos)
		if d2 < best_d2:
			best_d2 = d2
			best = npc
	return best


func get_next_waypoint(current_id: int, rng: RandomNumberGenerator) -> Dictionary:
	if current_id >= 0 and current_id < _waypoints.size():
		var neighbors: Array = _waypoints[current_id]["neighbors"]
		if not neighbors.is_empty():
			# Prefer neighbors inside currently loaded chunks
			var valid_n: Array[int] = []
			for nid: int in neighbors:
				if _is_in_loaded_chunk(_waypoints[nid]["pos"] as Vector3):
					valid_n.append(nid)
			if not valid_n.is_empty():
				var picked: int = valid_n[rng.randi() % valid_n.size()]
				return _waypoints[picked]
	return _waypoints[0]


func _physics_process(delta: float) -> void:
	_director_timer -= delta
	if _director_timer > 0.0:
		return
	_director_timer = 0.22 # ~4.5 Hz director tick (ultra-light on mobile)

	var player := GameManager.player_ref
	if player == null:
		return
	var p_pos: Vector3 = player.global_position

	_check_vehicle_threats()
	_pair_socializing_npcs()
	_recycle_distant_npcs(p_pos)


func _check_vehicle_threats() -> void:
	if traffic_manager == null:
		return
	var vehicles: Array = traffic_manager.get("all_vehicles") as Array
	if vehicles == null or vehicles.is_empty():
		return

	for v_obj: Variant in vehicles:
		var veh := v_obj as Node3D
		if not is_instance_valid(veh):
			continue
		var kmh: float = float(veh.get("speed_kmh"))
		if kmh < 9.0:
			continue

		var v_pos: Vector3 = veh.global_position
		var v_fwd: Vector3 = veh.global_transform.basis.z
		v_fwd.y = 0.0
		if v_fwd.length_squared() < 0.001:
			continue
		v_fwd = v_fwd.normalized()

		for npc: Node3D in npcs:
			if not is_instance_valid(npc):
				continue
			var to_npc: Vector3 = npc.global_position - v_pos
			to_npc.y = 0.0
			var d2: float = to_npc.length_squared()
			if d2 > 132.0 or d2 < 0.25: # within ~11.5m
				continue
			var dir_to_npc: Vector3 = to_npc.normalized()
			if v_fwd.dot(dir_to_npc) > 0.42:
				# Push laterally away from vehicle's travel line
				var side := Vector3(-v_fwd.z, 0.0, v_fwd.x)
				var side_sign: float = 1.0 if side.dot(dir_to_npc) >= 0.0 else -1.0
				var dodge_vec: Vector3 = (side * side_sign * 1.4 + dir_to_npc * 0.45).normalized()
				npc.call("trigger_vehicle_flee", dodge_vec)


func _pair_socializing_npcs() -> void:
	if GameManager.atmosphere_ref != null:
		var wx: int = int(GameManager.atmosphere_ref.get("current_weather"))
		var hr: float = float(GameManager.atmosphere_ref.get("time_of_day"))
		if wx == 2 or hr >= 22.0 or hr < 5.5:
			return

	var count: int = npcs.size()
	if count < 2:
		return

	# Sample one random candidate pair per tick to keep O(1) CPU cost
	var idx_a: int = _rng.randi() % count
	var a: Node3D = npcs[idx_a]
	if not is_instance_valid(a) or int(a.get("state")) != NpcAgentScript.State.WALK_SIDEWALK:
		return

	for i: int in range(count):
		if i == idx_a:
			continue
		var b: Node3D = npcs[i]
		if not is_instance_valid(b) or int(b.get("state")) != NpcAgentScript.State.WALK_SIDEWALK:
			continue
		var d: float = a.global_position.distance_to(b.global_position)
		if d > 1.2 and d < 2.8:
			var dur: float = _rng.randf_range(5.5, 10.5)
			a.call("begin_socializing_with", b, dur)
			b.call("begin_socializing_with", a, dur)
			return


func _recycle_distant_npcs(player_pos: Vector3) -> void:
	for npc: Node3D in npcs:
		if not is_instance_valid(npc):
			continue
		var d: float = npc.global_position.distance_to(player_pos)
		if d > 148.0 or not _is_in_loaded_chunk(npc.global_position):
			_place_npc_near_player(npc, player_pos, true)


func _sync_npc_pool_size() -> void:
	var p_pos: Vector3 = GameManager.player_ref.global_position if GameManager.player_ref != null else Vector3(0.0, 0.0, 10.0)

	while npcs.size() < _target_npc_count:
		var idx: int = npcs.size()
		var npc_name: String = BARMER_NAMES[idx % BARMER_NAMES.size()]
		var wp_poi: Dictionary = _workplaces[idx % _workplaces.size()]
		var npc_role: int = int(wp_poi["role"])

		var npc := CharacterBody3D.new()
		npc.name = "NPC_%s_%d" % [npc_name, idx]
		npc.set_script(NpcAgentScript)
		npc.setup_npc(self, map_data, npc_name, npc_role, wp_poi, 5000 + idx * 97)
		add_child(npc)
		npcs.append(npc)

		# Spawn initial batch visibly around Ahinsa Circle & NH-68 sidewalks
		_place_npc_near_player(npc, p_pos, false)

	while npcs.size() > _target_npc_count:
		var removed: Node3D = npcs.pop_back()
		if GameManager.nearby_npc == removed:
			GameManager.nearby_npc = null
		if is_instance_valid(removed):
			removed.queue_free()

	GameManager.active_npc_count = npcs.size()


func _place_npc_near_player(npc: Node3D, player_pos: Vector3, far_only: bool) -> void:
	var best_ids: Array[int] = []
	var min_d: float = 42.0 if far_only else 12.0
	var max_d: float = 128.0 if far_only else 96.0

	for wp: Dictionary in _waypoints:
		var wpos: Vector3 = wp["pos"] as Vector3
		if not _is_in_loaded_chunk(wpos):
			continue
		var d: float = wpos.distance_to(player_pos)
		if d >= min_d and d <= max_d:
			best_ids.append(int(wp["id"]))

	if best_ids.is_empty():
		for wp: Dictionary in _waypoints:
			var wpos: Vector3 = wp["pos"] as Vector3
			if _is_in_loaded_chunk(wpos) and wpos.distance_to(player_pos) < 140.0:
				best_ids.append(int(wp["id"]))

	if best_ids.is_empty():
		return

	var chosen_id: int = best_ids[_rng.randi() % best_ids.size()]
	var base: Vector3 = _waypoints[chosen_id]["pos"] as Vector3
	var jitter := Vector3(_rng.randf_range(-0.6, 0.6), 0.15, _rng.randf_range(-0.6, 0.6))
	npc.call("reset_to_waypoint", chosen_id, base + jitter)


func _build_barmer_sidewalk_graph() -> void:
	_waypoints.clear()

	# NH-68 West Sidewalk (x = -8.8) & East Sidewalk (x = +8.8) skirting Ahinsa Circle cleanly
	var nh_z: Array[float] = [44.0, 18.0, -6.0, -50.0, -96.0, -148.0, -206.0, -262.0, -318.0]
	var west_ids: Array[int] = []
	var east_ids: Array[int] = []
	for z: float in nh_z:
		west_ids.append(_add_wp(Vector3(-8.8, 0.12, z)))
		east_ids.append(_add_wp(Vector3(8.8, 0.12, z)))

	for i: int in range(nh_z.size() - 1):
		if i == 2:
			# Gap across Ahinsa Circle (-6 -> -50) routed via perimeter corners below
			continue
		_link(west_ids[i], west_ids[i + 1])
		_link(east_ids[i], east_ids[i + 1])

	# Ahinsa Circle 4 pedestrian perimeter corners (outside roundabout asphalt, clear of shops)
	var sw: int = _add_wp(Vector3(-17.8, 0.12, -10.5))
	var se: int = _add_wp(Vector3(17.8, 0.12, -10.5))
	var nw: int = _add_wp(Vector3(-17.8, 0.12, -45.5))
	var ne: int = _add_wp(Vector3(17.8, 0.12, -45.5))

	_link(west_ids[2], sw)
	_link(east_ids[2], se)
	_link(sw, nw)
	_link(se, ne)
	_link(sw, se) # Zebra crossing south of Ahinsa Circle
	_link(nw, ne) # Zebra crossing north of Ahinsa Circle
	_link(nw, west_ids[3])
	_link(ne, east_ids[3])

	# NH-25 / Station Road Eastbound (Sindhari Circle & RSRTC Bus Stand)
	var east_n_prev: int = ne
	var east_s_prev: int = se
	for x: float in [44.0, 88.0, 148.0, 210.0, 268.0]:
		var n_id: int = _add_wp(Vector3(x, 0.12, -34.9))
		var s_id: int = _add_wp(Vector3(x, 0.12, -21.1))
		_link(east_n_prev, n_id)
		_link(east_s_prev, s_id)
		if int(x) == 88 or int(x) == 210:
			_link(n_id, s_id)
		east_n_prev = n_id
		east_s_prev = s_id

	# NH-25 / Station Road Westbound (Chohtan Circle & Transport Nagar)
	var west_n_prev: int = nw
	var west_s_prev: int = sw
	for x: float in [-44.0, -88.0, -148.0, -210.0, -268.0]:
		var n_id: int = _add_wp(Vector3(x, 0.12, -34.9))
		var s_id: int = _add_wp(Vector3(x, 0.12, -21.1))
		_link(west_n_prev, n_id)
		_link(west_s_prev, s_id)
		if int(x) == -88 or int(x) == -210:
			_link(n_id, s_id)
		west_n_prev = n_id
		west_s_prev = s_id

	# Branch to Barmer Railway Station (BME) entrance plaza inside chunk (0, -1)
	var bme_entry: int = _add_wp(Vector3(31.5, 0.12, -262.0))
	_link(east_ids[7], bme_entry)


func _build_barmer_workplaces() -> void:
	_workplaces = [
		{"pos": Vector3(17.6, 0.12, 4.0), "yaw": PI * 0.5, "label": "NH-68 Dhaba", "role": NpcAgentScript.Role.SHOPKEEPER},
		{"pos": Vector3(17.8, 0.12, -50.0), "yaw": PI * 0.5, "label": "Ahinsa Bazaar", "role": NpcAgentScript.Role.SHOPKEEPER},
		{"pos": Vector3(-17.8, 0.12, -50.0), "yaw": -PI * 0.5, "label": "Station Road Market", "role": NpcAgentScript.Role.SHOPKEEPER},
		{"pos": Vector3(31.5, 0.12, -262.0), "yaw": -PI * 0.5, "label": "Barmer Railway Station", "role": NpcAgentScript.Role.COMMUTER},
		{"pos": Vector3(8.8, 0.12, -206.0), "yaw": 0.0, "label": "Station Road Bazaar", "role": NpcAgentScript.Role.COMMUTER},
		{"pos": Vector3(232.0, 0.12, -62.0), "yaw": 0.0, "label": "RSRTC Bus Stand", "role": NpcAgentScript.Role.COMMUTER},
		{"pos": Vector3(-216.0, 0.12, -16.0), "yaw": 0.0, "label": "Transport Nagar Yard", "role": NpcAgentScript.Role.WORKER},
		{"pos": Vector3(-8.8, 0.12, 18.0), "yaw": -PI * 0.5, "label": "Ahinsa Circle", "role": NpcAgentScript.Role.ELDER},
		{"pos": Vector3(44.0, 0.12, -21.1), "yaw": PI, "label": "Mahaveer Nagar Road", "role": NpcAgentScript.Role.RESIDENT},
		{"pos": Vector3(-44.0, 0.12, -34.9), "yaw": 0.0, "label": "Chohtan Road", "role": NpcAgentScript.Role.RESIDENT},
	]


func _add_wp(pos: Vector3) -> int:
	var id: int = _waypoints.size()
	_waypoints.append({
		"id": id,
		"pos": pos,
		"neighbors": [],
	})
	return id


func _link(a: int, b: int) -> void:
	var na: Array = _waypoints[a]["neighbors"]
	var nb: Array = _waypoints[b]["neighbors"]
	if not na.has(b):
		na.append(b)
	if not nb.has(a):
		nb.append(a)


func _is_in_loaded_chunk(world_pos: Vector3) -> bool:
	if chunk_streamer == null or map_data == null:
		return true
	var c: Vector2i = map_data.world_to_chunk(world_pos)
	return chunk_streamer.loaded_chunks.has(c)


func _on_profile_changed(profile: int) -> void:
	match profile:
		GameManager.GraphicsProfile.LOW:
			_target_npc_count = 10
		GameManager.GraphicsProfile.MEDIUM:
			_target_npc_count = 16
		GameManager.GraphicsProfile.HIGH:
			_target_npc_count = 22
		GameManager.GraphicsProfile.ULTRA:
			_target_npc_count = 28
	if map_data != null:
		_sync_npc_pool_size()
