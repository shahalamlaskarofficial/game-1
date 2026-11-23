extends RefCounted

## Batched modular architectural & urban detail builder for Barmer, Rajasthan.
## Appends geometry into per-material SurfaceTool buckets so an entire 256m x 256m
## city chunk renders in ~12 draw calls on Android Vulkan while preserving full
## architectural character (sandstone havelis, bazaar shops, jharokhas, clock tower).

var _buckets: Dictionary = {} # mat_key (String) -> SurfaceTool
var _colliders: Array[Dictionary] = [] # { "pos": Vector3, "size": Vector3, "rot_y": float }


func reset() -> void:
	_buckets.clear()
	_colliders.clear()


func add_box(
	mat_key: String,
	center: Vector3,
	size: Vector3,
	rot_y: float = 0.0,
	with_collision: bool = true,
	uv_scale: float = 0.25,
	skip_bottom: bool = true
) -> void:
	var st: SurfaceTool = _get_bucket(mat_key)
	_append_uv_box(st, center, size, rot_y, uv_scale, skip_bottom)
	if with_collision:
		_colliders.append({
			"pos": center,
			"size": size,
			"rot_y": rot_y,
		})


func build_clock_tower(origin: Vector3) -> void:
	# Iconic Barmer Ghanta Ghar centerpiece at Ahinsa Circle
	# Octagonal-style stepped sandstone base
	add_box("sandstone_dark", origin + Vector3(0.0, 0.45, 0.0), Vector3(8.2, 0.9, 8.2), 0.0, true, 0.22)
	add_box("sandstone", origin + Vector3(0.0, 1.35, 0.0), Vector3(6.4, 0.9, 6.4), 0.0, true, 0.22)

	# Lower archway shaft
	add_box("sandstone", origin + Vector3(0.0, 5.2, 0.0), Vector3(4.6, 6.8, 4.6), 0.0, true, 0.25)
	add_box("sandstone_dark", origin + Vector3(0.0, 8.8, 0.0), Vector3(5.2, 0.48, 5.2), 0.0, false, 0.25)

	# Upper clock chamber
	add_box("plaster_cream", origin + Vector3(0.0, 11.4, 0.0), Vector3(3.8, 4.8, 3.8), 0.0, true, 0.25)
	# Four clock dials
	add_box("window_dark", origin + Vector3(0.0, 11.7, 1.94), Vector3(1.9, 1.9, 0.12), 0.0, false, 0.5)
	add_box("window_dark", origin + Vector3(0.0, 11.7, -1.94), Vector3(1.9, 1.9, 0.12), 0.0, false, 0.5)
	add_box("window_dark", origin + Vector3(1.94, 11.7, 0.0), Vector3(0.12, 1.9, 1.9), 0.0, false, 0.5)
	add_box("window_dark", origin + Vector3(-1.94, 11.7, 0.0), Vector3(0.12, 1.9, 1.9), 0.0, false, 0.5)
	add_box("paint_amber", origin + Vector3(0.0, 11.7, 2.02), Vector3(0.14, 0.72, 0.04), 0.0, false, 1.0)
	add_box("paint_amber", origin + Vector3(0.0, 11.7, -2.02), Vector3(0.14, 0.72, 0.04), 0.0, false, 1.0)

	# Rajasthani Chhatri roof pavilion
	add_box("sandstone_dark", origin + Vector3(0.0, 14.0, 0.0), Vector3(4.5, 0.45, 4.5), 0.0, false, 0.25)
	for px: float in [-1.5, 1.5]:
		for pz: float in [-1.5, 1.5]:
			add_box("sandstone", origin + Vector3(px, 15.5, pz), Vector3(0.38, 2.6, 0.38), 0.0, false, 0.4)
	add_box("sandstone_dark", origin + Vector3(0.0, 17.0, 0.0), Vector3(4.2, 0.45, 4.2), 0.0, false, 0.25)
	add_box("sandstone", origin + Vector3(0.0, 18.0, 0.0), Vector3(2.8, 1.6, 2.8), 0.0, false, 0.3)
	add_box("paint_amber", origin + Vector3(0.0, 19.3, 0.0), Vector3(0.32, 1.2, 0.32), 0.0, false, 0.5)


func build_bazaar_shop(origin: Vector3, width: float, depth: float, floors: int, rot_y: float, rng: RandomNumberGenerator) -> void:
	var wall_mats: Array[String] = ["sandstone", "plaster_cream", "plaster_ochre", "plaster_terracotta"]
	var awning_mats: Array[String] = ["awning_crimson", "awning_indigo", "awning_saffron"]
	var wall_mat: String = wall_mats[rng.randi() % wall_mats.size()]
	var awning_mat: String = awning_mats[rng.randi() % awning_mats.size()]

	var floor_h: float = 3.5
	var total_h: float = float(floors) * floor_h

	# Main structure mass
	add_box(wall_mat, origin + Vector3(0.0, total_h * 0.5, 0.0), Vector3(width, total_h, depth), rot_y, true, 0.22)

	# Rooftop Rajasthani parapet cornice
	var para_pos: Vector3 = origin + Vector3(0.0, total_h + 0.42, 0.0)
	add_box("sandstone_dark", para_pos, Vector3(width + 0.35, 0.84, depth + 0.35), rot_y, false, 0.25)

	# Front shop shutter / recessed doorway (+Z local front)
	var front_z: float = depth * 0.5 + 0.06
	add_box("window_dark", _xform(origin, Vector3(0.0, 1.4, front_z), rot_y), Vector3(width * 0.62, 2.5, 0.14), rot_y, false, 0.5)

	# Commercial signboard fascia above ground floor
	add_box(awning_mat, _xform(origin, Vector3(0.0, 3.25, front_z + 0.08), rot_y), Vector3(width * 0.88, 0.72, 0.18), rot_y, false, 0.4)

	# Projecting sun awning over footpath
	add_box(awning_mat, _xform(origin, Vector3(0.0, 2.75, depth * 0.5 + 1.15), rot_y), Vector3(width * 0.92, 0.12, 2.2), rot_y, false, 0.4)

	# Upper floor recessed windows & jharokha balcony ledge
	for f: int in range(1, floors):
		var wy: float = float(f) * floor_h + 1.85
		add_box("sandstone_dark", _xform(origin, Vector3(0.0, float(f) * floor_h + 0.12, front_z + 0.35), rot_y), Vector3(width * 0.82, 0.22, 0.78), rot_y, false, 0.3)
		var win_count: int = maxi(2, int(width / 3.4))
		for w_i: int in range(win_count):
			var frac: float = (float(w_i) + 0.5) / float(win_count) - 0.5
			var wx: float = frac * (width - 1.4)
			add_box("window_dark", _xform(origin, Vector3(wx, wy, front_z), rot_y), Vector3(1.15, 1.45, 0.14), rot_y, false, 0.5)

	# Rooftop overhead water tank (authentic Indian urban skyline)
	if rng.randf() < 0.65:
		var tx: float = rng.randf_range(-width * 0.25, width * 0.25)
		var tz: float = rng.randf_range(-depth * 0.22, depth * 0.22)
		add_box("concrete", _xform(origin, Vector3(tx, total_h + 1.0, tz), rot_y), Vector3(1.2, 0.6, 1.2), rot_y, false, 0.4)
		add_box("metal_blue", _xform(origin, Vector3(tx, total_h + 1.85, tz), rot_y), Vector3(1.05, 1.15, 1.05), rot_y, false, 0.4)


func build_sandstone_haveli(origin: Vector3, width: float, depth: float, floors: int, rot_y: float, rng: RandomNumberGenerator) -> void:
	var wall_mats: Array[String] = ["sandstone", "plaster_cream", "plaster_ochre"]
	var wall_mat: String = wall_mats[rng.randi() % wall_mats.size()]
	var floor_h: float = 3.35
	var total_h: float = float(floors) * floor_h

	# Main sandstone house volume
	add_box(wall_mat, origin + Vector3(0.0, total_h * 0.5, 0.0), Vector3(width, total_h, depth), rot_y, true, 0.22)

	# Stepped Rajasthani cornice & rooftop parapet
	add_box("sandstone_dark", origin + Vector3(0.0, total_h + 0.45, 0.0), Vector3(width + 0.4, 0.9, depth + 0.4), rot_y, false, 0.25)

	# Jharokha projecting bay window on front facade
	var front_z: float = depth * 0.5
	add_box("sandstone_dark", _xform(origin, Vector3(0.0, 2.35, front_z + 0.42), rot_y), Vector3(2.4, 0.22, 0.88), rot_y, false, 0.35)
	add_box("window_dark", _xform(origin, Vector3(0.0, 1.15, front_z + 0.06), rot_y), Vector3(1.35, 2.25, 0.14), rot_y, false, 0.5)

	if floors >= 2:
		var j_y: float = floor_h + 1.65
		add_box("sandstone", _xform(origin, Vector3(0.0, j_y, front_z + 0.42), rot_y), Vector3(2.8, 2.2, 0.85), rot_y, false, 0.3)
		add_box("sandstone_dark", _xform(origin, Vector3(0.0, j_y + 1.25, front_z + 0.52), rot_y), Vector3(3.15, 0.28, 1.05), rot_y, false, 0.3)
		add_box("window_dark", _xform(origin, Vector3(0.0, j_y, front_z + 0.88), rot_y), Vector3(1.6, 1.2, 0.12), rot_y, false, 0.5)

	# Courtyard compound front boundary wall (with entry gate gap)
	var wall_z: float = depth * 0.5 + 2.8
	var side_w: float = (width + 2.2) * 0.34
	add_box("sandstone", _xform(origin, Vector3(-(width * 0.5 + 1.1 - side_w * 0.5), 0.85, wall_z), rot_y), Vector3(side_w, 1.7, 0.38), rot_y, true, 0.28)
	add_box("sandstone", _xform(origin, Vector3((width * 0.5 + 1.1 - side_w * 0.5), 0.85, wall_z), rot_y), Vector3(side_w, 1.7, 0.38), rot_y, true, 0.28)

	# Rooftop stair mumty + tank
	add_box("plaster_cream", _xform(origin, Vector3(-width * 0.22, total_h + 1.55, -depth * 0.22), rot_y), Vector3(2.8, 2.2, 2.8), rot_y, false, 0.28)
	add_box("metal_blue", _xform(origin, Vector3(width * 0.22, total_h + 1.35, -depth * 0.15), rot_y), Vector3(1.1, 1.1, 1.1), rot_y, false, 0.4)


func build_warehouse(origin: Vector3, width: float, depth: float, height: float, rot_y: float) -> void:
	# Industrial Transport Nagar warehouse with corrugated metal roof & loading bay
	add_box("concrete", origin + Vector3(0.0, height * 0.5, 0.0), Vector3(width, height, depth), rot_y, true, 0.18)
	add_box("metal_roof", origin + Vector3(0.0, height + 0.32, 0.0), Vector3(width + 0.8, 0.65, depth + 0.8), rot_y, false, 0.22)
	add_box("metal_blue", _xform(origin, Vector3(0.0, height - 0.55, depth * 0.5 + 0.08), rot_y), Vector3(width * 0.95, 0.7, 0.14), rot_y, false, 0.35)
	# Twin roll-up truck bay doors
	add_box("window_dark", _xform(origin, Vector3(-width * 0.24, 2.0, depth * 0.5 + 0.07), rot_y), Vector3(3.6, 3.8, 0.16), rot_y, false, 0.4)
	add_box("window_dark", _xform(origin, Vector3(width * 0.24, 2.0, depth * 0.5 + 0.07), rot_y), Vector3(3.6, 3.8, 0.16), rot_y, false, 0.4)


func build_fuel_station(origin: Vector3, rot_y: float) -> void:
	# Highway Petrol Pump Canopy + Office (Transport Nagar landmark)
	add_box("concrete", origin + Vector3(0.0, 0.12, 0.0), Vector3(18.0, 0.24, 13.0), rot_y, true, 0.2)
	# Canopy roof
	add_box("awning_saffron", origin + Vector3(0.0, 5.2, 0.0), Vector3(15.5, 0.95, 10.5), rot_y, false, 0.25)
	add_box("metal_blue", origin + Vector3(0.0, 4.65, 0.0), Vector3(15.7, 0.22, 10.7), rot_y, false, 0.3)
	# 4 structural columns + fuel dispenser islands
	for px: float in [-5.2, 5.2]:
		for pz: float in [-3.0, 3.0]:
			add_box("concrete", _xform(origin, Vector3(px, 2.4, pz), rot_y), Vector3(0.55, 4.6, 0.55), rot_y, true, 0.35)
	for px: float in [-2.6, 2.6]:
		add_box("concrete", _xform(origin, Vector3(px, 0.38, 0.0), rot_y), Vector3(1.1, 0.5, 3.8), rot_y, true, 0.35)
		add_box("awning_crimson", _xform(origin, Vector3(px, 1.35, 0.0), rot_y), Vector3(0.75, 1.5, 0.9), rot_y, true, 0.4)
	# Back station office
	add_box("plaster_cream", _xform(origin, Vector3(0.0, 1.9, -9.2), rot_y), Vector3(11.0, 3.8, 4.5), rot_y, true, 0.24)
	add_box("window_dark", _xform(origin, Vector3(0.0, 1.7, -6.9), rot_y), Vector3(5.2, 1.8, 0.14), rot_y, false, 0.5)


func build_water_tower(origin: Vector3) -> void:
	# Elevated Rajasthan Municipal Water Tank landmark
	for ox: float in [-2.6, 2.6]:
		for oz: float in [-2.6, 2.6]:
			add_box("concrete", origin + Vector3(ox, 6.0, oz), Vector3(0.6, 12.0, 0.6), 0.0, true, 0.3)
	add_box("concrete", origin + Vector3(0.0, 5.5, 0.0), Vector3(5.6, 0.45, 5.6), 0.0, false, 0.3)
	add_box("sandstone", origin + Vector3(0.0, 13.8, 0.0), Vector3(7.4, 3.8, 7.4), 0.0, true, 0.22)
	add_box("sandstone_dark", origin + Vector3(0.0, 16.0, 0.0), Vector3(7.8, 0.55, 7.8), 0.0, false, 0.24)


func build_desert_dhani(origin: Vector3, rot_y: float) -> void:
	# Rural Thar Desert sandstone & mud-plaster hut compound
	add_box("plaster_ochre", origin + Vector3(0.0, 1.5, 0.0), Vector3(5.6, 3.0, 4.8), rot_y, true, 0.28)
	add_box("sandstone_dark", origin + Vector3(0.0, 3.25, 0.0), Vector3(6.2, 0.45, 5.4), rot_y, false, 0.28)
	add_box("window_dark", _xform(origin, Vector3(0.0, 1.05, 2.44), rot_y), Vector3(1.1, 2.0, 0.12), rot_y, false, 0.5)


func commit_to_chunk(parent: Node3D, mat_lib: RefCounted, mesh_visibility_range: float) -> Array[MeshInstance3D]:
	var created_meshes: Array[MeshInstance3D] = []

	for mat_key: String in _buckets.keys():
		var st: SurfaceTool = _buckets[mat_key]
		st.generate_tangents()
		var arr_mesh: ArrayMesh = st.commit()
		if arr_mesh.get_surface_count() == 0:
			continue

		var mi := MeshInstance3D.new()
		mi.name = "Batch_" + mat_key
		mi.mesh = arr_mesh
		mi.material_override = mat_lib.get_mat(mat_key)
		mi.visibility_range_end = mesh_visibility_range
		parent.add_child(mi)
		created_meshes.append(mi)

	if not _colliders.is_empty():
		var body := StaticBody3D.new()
		body.name = "ChunkStaticColliders"
		body.collision_layer = 1
		body.collision_mask = 0

		for c_info: Dictionary in _colliders:
			var col := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = c_info["size"]
			col.shape = shape
			var xform := Transform3D(Basis(Vector3.UP, float(c_info["rot_y"])), c_info["pos"])
			col.transform = xform
			body.add_child(col)

		parent.add_child(body)

	return created_meshes


func _get_bucket(mat_key: String) -> SurfaceTool:
	if not _buckets.has(mat_key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_buckets[mat_key] = st
	return _buckets[mat_key] as SurfaceTool


func _xform(origin: Vector3, local_offset: Vector3, rot_y: float) -> Vector3:
	return origin + local_offset.rotated(Vector3.UP, rot_y)


func _append_uv_box(st: SurfaceTool, center: Vector3, size: Vector3, rot_y: float, uv_scale: float, skip_bottom: bool) -> void:
	var hx: float = size.x * 0.5
	var hy: float = size.y * 0.5
	var hz: float = size.z * 0.5

	var u_x: float = size.x * uv_scale
	var u_y: float = size.y * uv_scale
	var u_z: float = size.z * uv_scale

	# Front (+Z)
	_append_quad(
		st, center, rot_y, Vector3(0.0, 0.0, 1.0),
		Vector3(-hx, hy, hz), Vector3(hx, hy, hz), Vector3(hx, -hy, hz), Vector3(-hx, -hy, hz),
		u_x, u_y
	)
	# Back (-Z)
	_append_quad(
		st, center, rot_y, Vector3(0.0, 0.0, -1.0),
		Vector3(hx, hy, -hz), Vector3(-hx, hy, -hz), Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz),
		u_x, u_y
	)
	# Right (+X)
	_append_quad(
		st, center, rot_y, Vector3(1.0, 0.0, 0.0),
		Vector3(hx, hy, hz), Vector3(hx, hy, -hz), Vector3(hx, -hy, -hz), Vector3(hx, -hy, hz),
		u_z, u_y
	)
	# Left (-X)
	_append_quad(
		st, center, rot_y, Vector3(-1.0, 0.0, 0.0),
		Vector3(-hx, hy, -hz), Vector3(-hx, hy, hz), Vector3(-hx, -hy, hz), Vector3(-hx, -hy, -hz),
		u_z, u_y
	)
	# Top (+Y)
	_append_quad(
		st, center, rot_y, Vector3(0.0, 1.0, 0.0),
		Vector3(-hx, hy, -hz), Vector3(hx, hy, -hz), Vector3(hx, hy, hz), Vector3(-hx, hy, hz),
		u_x, u_z
	)
	if not skip_bottom:
		_append_quad(
			st, center, rot_y, Vector3(0.0, -1.0, 0.0),
			Vector3(-hx, -hy, hz), Vector3(hx, -hy, hz), Vector3(hx, -hy, -hz), Vector3(-hx, -hy, -hz),
			u_x, u_z
		)


func _append_quad(
	st: SurfaceTool,
	center: Vector3,
	rot_y: float,
	local_normal: Vector3,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	d: Vector3,
	u_max: float,
	v_max: float
) -> void:
	var n: Vector3 = local_normal.rotated(Vector3.UP, rot_y) if rot_y != 0.0 else local_normal
	var va: Vector3 = center + (a.rotated(Vector3.UP, rot_y) if rot_y != 0.0 else a)
	var vb: Vector3 = center + (b.rotated(Vector3.UP, rot_y) if rot_y != 0.0 else b)
	var vc: Vector3 = center + (c.rotated(Vector3.UP, rot_y) if rot_y != 0.0 else c)
	var vd: Vector3 = center + (d.rotated(Vector3.UP, rot_y) if rot_y != 0.0 else d)

	# Triangle 1 (CW front-facing)
	st.set_normal(n)
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(va)
	st.set_normal(n)
	st.set_uv(Vector2(u_max, 0.0))
	st.add_vertex(vb)
	st.set_normal(n)
	st.set_uv(Vector2(u_max, v_max))
	st.add_vertex(vc)

	# Triangle 2 (CW front-facing)
	st.set_normal(n)
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(va)
	st.set_normal(n)
	st.set_uv(Vector2(u_max, v_max))
	st.add_vertex(vc)
	st.set_normal(n)
	st.set_uv(Vector2(0.0, v_max))
	st.add_vertex(vd)
