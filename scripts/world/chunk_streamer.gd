extends Node

## Modular world streaming foundation (256m x 256m spatial grid).
## Phase 1 tracks active/neighboring cells and fires streaming hooks;
## Phase 2 binds async ResourceLoader chunk scenes and HLOD swaps directly to these signals.

signal chunk_load_requested(chunk_coord: Vector2i)
signal chunk_unload_requested(chunk_coord: Vector2i)

@export var chunk_size_meters: float = 256.0
@export var active_radius_chunks: int = 1

var active_chunks: Dictionary = {} # Vector2i -> bool
var _last_center_chunk: Vector2i = Vector2i(999999, 999999)


func _physics_process(_delta: float) -> void:
	var player := GameManager.player_ref
	if player == null:
		return

	var pos: Vector3 = player.global_position
	var cx: int = floori(pos.x / chunk_size_meters)
	var cz: int = floori(pos.z / chunk_size_meters)
	var current := Vector2i(cx, cz)

	if current != _last_center_chunk:
		_last_center_chunk = current
		GameManager.set_current_chunk(current)
		_refresh_chunk_window(current)


func _refresh_chunk_window(center: Vector2i) -> void:
	var desired: Dictionary = {}
	for dx: int in range(-active_radius_chunks, active_radius_chunks + 1):
		for dz: int in range(-active_radius_chunks, active_radius_chunks + 1):
			var coord := Vector2i(center.x + dx, center.y + dz)
			desired[coord] = true
			if not active_chunks.has(coord):
				active_chunks[coord] = true
				chunk_load_requested.emit(coord)

	var to_remove: Array[Vector2i] = []
	for existing: Vector2i in active_chunks.keys():
		if not desired.has(existing):
			to_remove.append(existing)

	for coord: Vector2i in to_remove:
		active_chunks.erase(coord)
		chunk_unload_requested.emit(coord)
