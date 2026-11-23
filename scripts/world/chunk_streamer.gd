extends Node

## Frame-budgeted Modular World Streamer (256m x 256m Barmer grid).
## - Streams chunks incrementally (1 chunk per frame) to avoid mobile stutters.
## - Automatically frees out-of-range chunks to keep Android RAM flat.
## - Checks for custom/DLC PackedScene overrides before procedural generation,
##   enabling seamless map expansion via downloadable .pck packs.

const BarmerMapDataScript = preload("res://scripts/world/barmer_map_data.gd")
const WorldChunkScript = preload("res://scripts/world/world_chunk.gd")

signal chunk_load_requested(chunk_coord: Vector2i)
signal chunk_unload_requested(chunk_coord: Vector2i)
signal district_entered(district_name: String)

@export var active_radius_chunks: int = 1

var map_data: RefCounted = null
var material_lib: RefCounted = null
var chunks_container: Node3D = null

var loaded_chunks: Dictionary = {} # Vector2i -> Node3D
var _load_queue: Array[Vector2i] = []
var _async_dlc_loads: Dictionary = {} # Vector2i -> String (resource path)
var _last_center_chunk: Vector2i = Vector2i(999999, 999999)
var _last_district_name: String = ""
var _current_lod_scale: float = 0.85


func initialize(container: Node3D, map_ref: RefCounted, mat_ref: RefCounted, start_chunk: Vector2i) -> void:
	chunks_container = container
	map_data = map_ref
	material_lib = mat_ref

	if not GameManager.graphics_profile_changed.is_connected(_on_graphics_profile_changed):
		GameManager.graphics_profile_changed.connect(_on_graphics_profile_changed)
	_on_graphics_profile_changed(GameManager.current_profile)

	# Build spawn chunk synchronously so the player immediately lands on solid ground
	_spawn_chunk_now(start_chunk)
	_last_center_chunk = start_chunk
	GameManager.set_current_chunk(start_chunk)
	_emit_district_if_changed(start_chunk)
	_refresh_chunk_window(start_chunk)


func _physics_process(_delta: float) -> void:
	if chunks_container == null or map_data == null:
		return

	var player := GameManager.player_ref
	if player != null:
		var current: Vector2i = map_data.world_to_chunk(player.global_position)
		if current != _last_center_chunk:
			_last_center_chunk = current
			GameManager.set_current_chunk(current)
			_emit_district_if_changed(current)
			_refresh_chunk_window(current)

	_poll_async_dlc_loads()
	_process_load_queue_step()


func _refresh_chunk_window(center: Vector2i) -> void:
	var desired: Dictionary = {}
	var candidates: Array[Vector2i] = []

	for dx: int in range(-active_radius_chunks, active_radius_chunks + 1):
		for dz: int in range(-active_radius_chunks, active_radius_chunks + 1):
			var coord := Vector2i(center.x + dx, center.y + dz)
			desired[coord] = true
			if not loaded_chunks.has(coord) and not _load_queue.has(coord) and not _async_dlc_loads.has(coord):
				candidates.append(coord)

	# Load closest chunks first
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.distance_squared_to(center) < b.distance_squared_to(center)
	)
	for coord: Vector2i in candidates:
		_load_queue.append(coord)
		chunk_load_requested.emit(coord)

	# Prune stale queued entries
	var pruned_queue: Array[Vector2i] = []
	for q_coord: Vector2i in _load_queue:
		if desired.has(q_coord):
			pruned_queue.append(q_coord)
	_load_queue = pruned_queue

	# Unload out-of-range chunks immediately to free VRAM & physics memory
	var to_unload: Array[Vector2i] = []
	for existing: Vector2i in loaded_chunks.keys():
		if not desired.has(existing):
			to_unload.append(existing)

	for coord: Vector2i in to_unload:
		var chunk_node: Node3D = loaded_chunks[coord]
		loaded_chunks.erase(coord)
		if is_instance_valid(chunk_node):
			chunk_node.queue_free()
		chunk_unload_requested.emit(coord)


func _process_load_queue_step() -> void:
	if _load_queue.is_empty():
		return

	var coord: Vector2i = _load_queue.pop_front()
	if loaded_chunks.has(coord):
		return

	# Expansion / DLC hook: load authored PackedScene chunk asynchronously if present
	var dlc_path: String = "res://scenes/world/chunks/chunk_%d_%d.tscn" % [coord.x, coord.y]
	if ResourceLoader.exists(dlc_path):
		var err: Error = ResourceLoader.load_threaded_request(dlc_path)
		if err == OK:
			_async_dlc_loads[coord] = dlc_path
			return

	_spawn_chunk_now(coord)


func _poll_async_dlc_loads() -> void:
	if _async_dlc_loads.is_empty():
		return

	var finished: Array[Vector2i] = []
	for coord: Vector2i in _async_dlc_loads.keys():
		var path: String = _async_dlc_loads[coord]
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var packed := ResourceLoader.load_threaded_get(path) as PackedScene
			if packed != null:
				var inst := packed.instantiate() as Node3D
				if inst != null:
					inst.position = map_data.chunk_to_world_origin(coord)
					chunks_container.add_child(inst)
					loaded_chunks[coord] = inst
			finished.append(coord)
		elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_spawn_chunk_now(coord)
			finished.append(coord)

	for coord: Vector2i in finished:
		_async_dlc_loads.erase(coord)


func _spawn_chunk_now(coord: Vector2i) -> void:
	if loaded_chunks.has(coord):
		return
	var chunk := Node3D.new()
	chunk.set_script(WorldChunkScript)
	chunks_container.add_child(chunk)
	chunk.build_chunk(coord, map_data, material_lib, _current_lod_scale)
	loaded_chunks[coord] = chunk


func _emit_district_if_changed(coord: Vector2i) -> void:
	var d_name: String = map_data.get_district_display_name(coord)
	if d_name != _last_district_name:
		_last_district_name = d_name
		district_entered.emit(d_name)


func _on_graphics_profile_changed(profile: int) -> void:
	match profile:
		GameManager.GraphicsProfile.LOW:
			active_radius_chunks = 1
			_current_lod_scale = 0.62
		GameManager.GraphicsProfile.MEDIUM:
			active_radius_chunks = 1
			_current_lod_scale = 0.88
		GameManager.GraphicsProfile.HIGH:
			active_radius_chunks = 1
			_current_lod_scale = 1.20
		GameManager.GraphicsProfile.ULTRA:
			active_radius_chunks = 2
			_current_lod_scale = 1.50

	for chunk_node: Node3D in loaded_chunks.values():
		if is_instance_valid(chunk_node) and chunk_node.has_method("apply_lod_scale"):
			chunk_node.apply_lod_scale(_current_lod_scale)

	if _last_center_chunk != Vector2i(999999, 999999):
		_refresh_chunk_window(_last_center_chunk)
