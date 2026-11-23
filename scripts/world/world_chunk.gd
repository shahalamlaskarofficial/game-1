extends Node3D

## Self-contained 256m x 256m streaming sector of Barmer, Rajasthan.
## Generates seamless normal-matched PBR terrain, highway/city road networks,
## batched Rajasthani buildings, and GPU-instanced MultiMesh desert/street details.

const BarmerMapDataScript = preload("res://scripts/world/barmer_map_data.gd")
const BuildingFactoryScript = preload("res://scripts/world/building_factory.gd")

const TERRAIN_SUBDIVS: int = 32

var chunk_coord: Vector2i = Vector2i.ZERO
var _building_meshes: Array[MeshInstance3D] = []
var _prop_multimeshes: Array[MultiMeshInstance3D] = []
var _road_meshes: Array[MeshInstance3D] = []


func build_chunk(coord: Vector2i, map_data: RefCounted, mat_lib: RefCounted, lod_scale: float) -> void:
	chunk_coord = coord
	name = "Chunk_%d_%d" % [coord.x, coord.y]
	position = map_data.chunk_to_world_origin(coord)

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(coord.x * 73856093, coord.y * 19349663))

	_build_terrain_mesh(map_data, mat_lib)
	_build_roads_and_structures(map_data, mat_lib, rng, lod_scale)
	_build_instanced_environment_props(map_data, mat_lib, rng, lod_scale)


func apply_lod_scale(lod_scale: float) -> void:
	var b_dist: float = 340.0 * lod_scale
	var p_dist: float = 175.0 * lod_scale
	var r_dist: float = 420.0 * lod_scale

	for mi: MeshInstance3D in _building_meshes:
		if is_instance_valid(mi):
			mi.visibility_range_end = b_dist
	for mmi: MultiMeshInstance3D in _prop_multimeshes:
		if is_instance_valid(mmi):
			mmi.visibility_range_end = p_dist
	for rmi: MeshInstance3D in _road_meshes:
		if is_instance_valid(rmi):
			rmi.visibility_range_end = r_dist


func _build_terrain_mesh(map_data: RefCounted, mat_lib: RefCounted) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var chunk_sz: float = BarmerMapDataScript.CHUNK_SIZE
	var half: float = BarmerMapDataScript.HALF_CHUNK
	var step: float = chunk_sz / float(TERRAIN_SUBDIVS)
	var ox: float = position.x
	var oz: float = position.z
	const UV_SCALE: float = 0.085

	for gz: int in range(TERRAIN_SUBDIVS):
		for gx: int in range(TERRAIN_SUBDIVS):
			var lx0: float = -half + float(gx) * step
			var lz0: float = -half + float(gz) * step
			var lx1: float = lx0 + step
			var lz1: float = lz0 + step

			var wx0: float = ox + lx0
			var wz0: float = oz + lz0
			var wx1: float = ox + lx1
			var wz1: float = oz + lz1

			var p00 := Vector3(lx0, map_data.get_terrain_height(wx0, wz0), lz0)
			var p10 := Vector3(lx1, map_data.get_terrain_height(wx1, wz0), lz0)
			var p01 := Vector3(lx0, map_data.get_terrain_height(wx0, wz1), lz1)
			var p11 := Vector3(lx1, map_data.get_terrain_height(wx1, wz1), lz1)

			var n00: Vector3 = map_data.get_terrain_normal(wx0, wz0)
			var n10: Vector3 = map_data.get_terrain_normal(wx1, wz0)
			var n01: Vector3 = map_data.get_terrain_normal(wx0, wz1)
			var n11: Vector3 = map_data.get_terrain_normal(wx1, wz1)

			var c00: Color = map_data.get_terrain_vertex_color(wx0, p00.y, wz0)
			var c10: Color = map_data.get_terrain_vertex_color(wx1, p10.y, wz0)
			var c01: Color = map_data.get_terrain_vertex_color(wx0, p01.y, wz1)
			var c11: Color = map_data.get_terrain_vertex_color(wx1, p11.y, wz1)

			var uv00 := Vector2(wx0 * UV_SCALE, wz0 * UV_SCALE)
			var uv10 := Vector2(wx1 * UV_SCALE, wz0 * UV_SCALE)
			var uv01 := Vector2(wx0 * UV_SCALE, wz1 * UV_SCALE)
			var uv11 := Vector2(wx1 * UV_SCALE, wz1 * UV_SCALE)

			# Triangle 1 (CW)
			st.set_normal(n00); st.set_color(c00); st.set_uv(uv00); st.add_vertex(p00)
			st.set_normal(n10); st.set_color(c10); st.set_uv(uv10); st.add_vertex(p10)
			st.set_normal(n01); st.set_color(c01); st.set_uv(uv01); st.add_vertex(p01)

			# Triangle 2 (CW)
			st.set_normal(n10); st.set_color(c10); st.set_uv(uv10); st.add_vertex(p10)
			st.set_normal(n11); st.set_color(c11); st.set_uv(uv11); st.add_vertex(p11)
			st.set_normal(n01); st.set_color(c01); st.set_uv(uv01); st.add_vertex(p01)

	st.generate_tangents()
	var terrain_mesh: ArrayMesh = st.commit()

	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	body.collision_mask = 0

	var mi := MeshInstance3D.new()
	mi.name = "TerrainMesh"
	mi.mesh = terrain_mesh
	mi.material_override = mat_lib.get_mat("terrain")
	body.add_child(mi)

	var col := CollisionShape3D.new()
	col.shape = terrain_mesh.create_trimesh_shape()
	body.add_child(col)

	add_child(body)


func _build_roads_and_structures(map_data: RefCounted, mat_lib: RefCounted, rng: RandomNumberGenerator, lod_scale: float) -> void:
	var road_factory = BuildingFactoryScript.new()
	var bldg_factory = BuildingFactoryScript.new()
	var district: int = map_data.get_district(chunk_coord)
	var is_urban: bool = map_data.is_urban_chunk(chunk_coord)

	# 1. NH-68 4-Lane Divided Highway runs continuously along chunk x == 0
	if chunk_coord.x == 0:
		_add_nh68_highway(road_factory, district)

	# 2. Station Road East-West Arterial runs across cz == 0 for cx in [-2, 2]
	if chunk_coord.y == 0 and abs(chunk_coord.x) <= 2:
		_add_station_road_arterial(road_factory, is_urban)

	# 3. Secondary city grid avenues & footpaths inside urban Barmer chunks
	if is_urban:
		_add_urban_secondary_streets(road_factory)

	# 4. District-specific landmarks, buildings, and architecture
	match district:
		BarmerMapDataScript.DistrictType.AHINSA_GATEWAY:
			_populate_ahinsa_gateway(road_factory, bldg_factory, rng)
		BarmerMapDataScript.DistrictType.STATION_BAZAAR:
			_populate_station_bazaar(bldg_factory, map_data, rng)
		BarmerMapDataScript.DistrictType.MAHAVEER_RESIDENTIAL:
			_populate_mahaveer_residential(bldg_factory, map_data, rng)
		BarmerMapDataScript.DistrictType.TRANSPORT_INDUSTRIAL:
			_populate_transport_industrial(bldg_factory, map_data, rng)
		BarmerMapDataScript.DistrictType.THAR_DESERT:
			_populate_thar_desert_structures(bldg_factory, map_data, rng)

	_road_meshes = road_factory.commit_to_chunk(self, mat_lib, 420.0 * lod_scale)
	_building_meshes = bldg_factory.commit_to_chunk(self, mat_lib, 340.0 * lod_scale)


func _add_nh68_highway(f: RefCounted, district: int) -> void:
	# Main 14.8m wide asphalt deck (top at y = 0.04)
	f.add_box("asphalt", Vector3(0.0, 0.0, 0.0), Vector3(14.8, 0.08, 256.0), 0.0, true, 0.14)

	# Raised concrete kerbs / footpaths along urban sections (top at y = 0.11 -> smooth 7cm step)
	var kerb_len: float = 256.0 if district != BarmerMapDataScript.DistrictType.THAR_DESERT else 0.0
	if kerb_len > 0.0:
		f.add_box("sidewalk", Vector3(-8.8, 0.055, 0.0), Vector3(2.8, 0.11, kerb_len), 0.0, true, 0.22)
		f.add_box("sidewalk", Vector3(8.8, 0.055, 0.0), Vector3(2.8, 0.11, kerb_len), 0.0, true, 0.22)

	# White outer edge lines (top at y = 0.052 -> zero z-fighting)
	f.add_box("paint_white", Vector3(-6.7, 0.048, 0.0), Vector3(0.18, 0.008, 254.0), 0.0, false, 1.0)
	f.add_box("paint_white", Vector3(6.7, 0.048, 0.0), Vector3(0.18, 0.008, 254.0), 0.0, false, 1.0)

	# Central raised divider median (with gap around Ahinsa Circle and cross-streets)
	for seg_z: int in range(-120, 121, 16):
		var wz: float = position.z + float(seg_z)
		if absf(wz - BarmerMapDataScript.STATION_ROAD_Z) < 24.0:
			continue
		if absf(float(seg_z) - 64.0) < 12.0 or absf(float(seg_z) + 64.0) < 12.0:
			continue
		f.add_box("concrete", Vector3(0.0, 0.11, float(seg_z)), Vector3(0.68, 0.14, 11.5), 0.0, true, 0.35)
		f.add_box("paint_amber", Vector3(0.0, 0.185, float(seg_z)), Vector3(0.70, 0.015, 5.2), 0.0, false, 1.0)

	# Dashed lane dividers on both carriageways
	for z_mark: int in range(-124, 125, 8):
		var wz: float = position.z + float(z_mark)
		if absf(wz - BarmerMapDataScript.STATION_ROAD_Z) < 18.0:
			continue
		f.add_box("paint_white", Vector3(-3.45, 0.048, float(z_mark)), Vector3(0.14, 0.008, 3.4), 0.0, false, 1.0)
		f.add_box("paint_white", Vector3(3.45, 0.048, float(z_mark)), Vector3(0.14, 0.008, 3.4), 0.0, false, 1.0)

	# Authentic Indian Highway Kilometer Milestone (Yellow top = National Highway NH-68)
	f.add_box("paint_white", Vector3(9.4, 0.42, 42.0), Vector3(0.46, 0.84, 0.26), 0.0, true, 0.5)
	f.add_box("paint_amber", Vector3(9.4, 0.98, 42.0), Vector3(0.46, 0.28, 0.26), 0.0, false, 0.5)


func _add_station_road_arterial(f: RefCounted, is_urban: bool) -> void:
	var lz: float = BarmerMapDataScript.STATION_ROAD_Z
	f.add_box("asphalt", Vector3(0.0, 0.002, lz), Vector3(256.0, 0.08, 11.2), 0.0, true, 0.14)
	if is_urban:
		f.add_box("sidewalk", Vector3(0.0, 0.055, lz - 6.9), Vector3(256.0, 0.11, 2.6), 0.0, true, 0.22)
		f.add_box("sidewalk", Vector3(0.0, 0.055, lz + 6.9), Vector3(256.0, 0.11, 2.6), 0.0, true, 0.22)

	for x_mark: int in range(-122, 123, 8):
		var wx: float = position.x + float(x_mark)
		if absf(wx) < 19.0:
			continue
		f.add_box("paint_amber", Vector3(float(x_mark), 0.050, lz), Vector3(3.6, 0.008, 0.16), 0.0, false, 1.0)


func _add_urban_secondary_streets(f: RefCounted) -> void:
	for off: float in BarmerMapDataScript.LOCAL_AVENUE_OFFSETS:
		# North-South local avenue
		f.add_box("asphalt", Vector3(off, -0.002, 0.0), Vector3(8.4, 0.08, 256.0), 0.0, true, 0.16)
		f.add_box("sidewalk", Vector3(off - 5.2, 0.052, 0.0), Vector3(2.0, 0.104, 256.0), 0.0, true, 0.24)
		f.add_box("sidewalk", Vector3(off + 5.2, 0.052, 0.0), Vector3(2.0, 0.104, 256.0), 0.0, true, 0.24)

		# East-West local street
		f.add_box("asphalt", Vector3(0.0, -0.002, off), Vector3(256.0, 0.08, 8.4), 0.0, true, 0.16)
		f.add_box("sidewalk", Vector3(0.0, 0.052, off - 5.2), Vector3(256.0, 0.104, 2.0), 0.0, true, 0.24)
		f.add_box("sidewalk", Vector3(0.0, 0.052, off + 5.2), Vector3(256.0, 0.104, 2.0), 0.0, true, 0.24)


func _populate_ahinsa_gateway(road_f: RefCounted, bldg_f: RefCounted, rng: RandomNumberGenerator) -> void:
	# Ahinsa Circle Plaza & Ghanta Ghar Clock Tower directly ahead of player spawn
	var circle_pos := Vector3(0.0, 0.0, BarmerMapDataScript.STATION_ROAD_Z)
	road_f.add_box("asphalt", circle_pos + Vector3(0.0, 0.004, 0.0), Vector3(34.0, 0.08, 34.0), 0.0, true, 0.14)
	road_f.add_box("sidewalk", circle_pos + Vector3(0.0, 0.07, 0.0), Vector3(13.0, 0.14, 13.0), 0.0, true, 0.22)
	bldg_f.build_clock_tower(circle_pos + Vector3(0.0, 0.14, 0.0))

	# Zebra pedestrian crossings around Ahinsa Circle
	for stripe: int in range(-4, 5):
		var s_off: float = float(stripe) * 1.4
		road_f.add_box("paint_white", circle_pos + Vector3(s_off, 0.052, 18.2), Vector3(0.65, 0.008, 2.8), 0.0, false, 1.0)
		road_f.add_box("paint_white", circle_pos + Vector3(s_off, 0.052, -18.2), Vector3(0.65, 0.008, 2.8), 0.0, false, 1.0)
		road_f.add_box("paint_white", circle_pos + Vector3(18.2, 0.052, s_off), Vector3(2.8, 0.008, 0.65), 0.0, false, 1.0)
		road_f.add_box("paint_white", circle_pos + Vector3(-18.2, 0.052, s_off), Vector3(2.8, 0.008, 0.65), 0.0, false, 1.0)

	# Roadside Barmer Sandstone Dhaba (east of spawn) + Elevated Municipal Water Tank (west)
	bldg_f.build_bazaar_shop(Vector3(24.0, 0.0, 4.0), 11.5, 8.2, 1, -PI * 0.5, rng)
	bldg_f.build_water_tower(Vector3(-28.0, 0.0, -78.0))

	# Preserve Phase 1 low sandstone archway (1.42m clearance) & ramp for crouch/slope testing
	bldg_f.add_box("sandstone_dark", Vector3(-12.0, 1.2, -2.0), Vector3(0.9, 2.4, 2.6), 0.0, true, 0.35)
	bldg_f.add_box("sandstone_dark", Vector3(-16.0, 1.2, -2.0), Vector3(0.9, 2.4, 2.6), 0.0, true, 0.35)
	bldg_f.add_box("sandstone", Vector3(-14.0, 1.92, -2.0), Vector3(4.9, 1.0, 2.6), 0.0, true, 0.35)

	# Commercial shops framing Ahinsa Circle & northern approach along NH-68
	var shop_slots: Array[Dictionary] = [
		{"pos": Vector3(24.0, 0.0, -50.0), "w": 11.0, "d": 8.8, "f": 2, "rot": -PI * 0.5},
		{"pos": Vector3(24.0, 0.0, -86.0), "w": 12.0, "d": 9.2, "f": 3, "rot": -PI * 0.5},
		{"pos": Vector3(24.0, 0.0, -106.0), "w": 10.5, "d": 8.6, "f": 2, "rot": -PI * 0.5},
		{"pos": Vector3(-24.0, 0.0, -50.0), "w": 11.0, "d": 8.8, "f": 2, "rot": PI * 0.5},
		{"pos": Vector3(-24.0, 0.0, -104.0), "w": 12.0, "d": 9.0, "f": 2, "rot": PI * 0.5},
		{"pos": Vector3(44.0, 0.0, -12.0), "w": 11.5, "d": 8.5, "f": 2, "rot": PI},
		{"pos": Vector3(88.0, 0.0, -12.0), "w": 12.0, "d": 8.8, "f": 2, "rot": PI},
		{"pos": Vector3(44.0, 0.0, -44.0), "w": 11.5, "d": 8.5, "f": 3, "rot": 0.0},
		{"pos": Vector3(88.0, 0.0, -44.0), "w": 11.0, "d": 8.5, "f": 2, "rot": 0.0},
		{"pos": Vector3(-44.0, 0.0, -12.0), "w": 11.0, "d": 8.5, "f": 2, "rot": PI},
		{"pos": Vector3(-88.0, 0.0, -12.0), "w": 12.0, "d": 8.8, "f": 2, "rot": PI},
		{"pos": Vector3(-44.0, 0.0, -44.0), "w": 11.0, "d": 8.5, "f": 2, "rot": 0.0},
		{"pos": Vector3(-88.0, 0.0, -44.0), "w": 11.5, "d": 8.5, "f": 2, "rot": 0.0},
	]
	for slot: Dictionary in shop_slots:
		bldg_f.build_bazaar_shop(slot["pos"], float(slot["w"]), float(slot["d"]), int(slot["f"]), float(slot["rot"]), rng)

	# Residential havelis filling northeast and northwest inner quadrants
	for qx: float in [-102.0, -86.0, 86.0, 102.0]:
		for qz: float in [-96.0, -80.0, 22.0, 38.0]:
			var face_rot: float = PI if qz > 0.0 else 0.0
			bldg_f.build_sandstone_haveli(Vector3(qx, 0.0, qz), rng.randf_range(9.5, 11.5), rng.randf_range(8.5, 10.2), rng.randi_range(1, 2), face_rot, rng)


func _populate_station_bazaar(bldg_f: RefCounted, map_data: RefCounted, rng: RandomNumberGenerator) -> void:
	# Dense commercial bazaar flanking NH-68 and side streets
	for gz: int in range(-108, 109, 20):
		for gx: int in [-104, -84, -44, -24, 24, 44, 84, 104]:
			var wx: float = position.x + float(gx)
			var wz: float = position.z + float(gz)
			if map_data.is_on_major_road_or_reserved(wx, wz, 8.5):
				continue

			var rot: float = -PI * 0.5 if gx > 0 else PI * 0.5
			var w: float = rng.randf_range(10.5, 13.5)
			var d: float = rng.randf_range(8.2, 10.2)
			var floors: int = rng.randi_range(2, 3)
			bldg_f.build_bazaar_shop(Vector3(float(gx), 0.0, float(gz)), w, d, floors, rot, rng)


func _populate_mahaveer_residential(bldg_f: RefCounted, map_data: RefCounted, rng: RandomNumberGenerator) -> void:
	# Residential colonies of Barmer: sandstone havelis, courtyards, neighborhood water tower
	if chunk_coord == Vector2i(1, 0):
		bldg_f.build_water_tower(Vector3(34.0, 0.0, 26.0))

	for gz: int in range(-106, 107, 24):
		for gx: int in range(-106, 107, 24):
			var wx: float = position.x + float(gx)
			var wz: float = position.z + float(gz)
			if chunk_coord.y == 0 and wz > 46.0:
				continue
			if chunk_coord == Vector2i(1, 0) and Vector2(float(gx) - 34.0, float(gz) - 26.0).length() < 16.0:
				continue
			if map_data.is_on_major_road_or_reserved(wx, wz, 9.5):
				continue

			var rot: float = float(rng.randi() % 4) * (PI * 0.5)
			var w: float = rng.randf_range(9.5, 12.2)
			var d: float = rng.randf_range(8.4, 10.6)
			var floors: int = rng.randi_range(1, 2)
			bldg_f.build_sandstone_haveli(Vector3(float(gx), 0.0, float(gz)), w, d, floors, rot, rng)


func _populate_transport_industrial(bldg_f: RefCounted, map_data: RefCounted, rng: RandomNumberGenerator) -> void:
	# Highway petrol pump landmark on Station Road approach
	if chunk_coord == Vector2i(-1, 0):
		bldg_f.build_fuel_station(Vector3(28.0, 0.0, -6.0), 0.0)

	for gz: int in range(-100, 101, 34):
		for gx: int in range(-96, 97, 36):
			var wx: float = position.x + float(gx)
			var wz: float = position.z + float(gz)
			if chunk_coord.y == 0 and wz > 46.0:
				continue
			if chunk_coord == Vector2i(-1, 0) and Vector2(float(gx) - 28.0, float(gz) + 6.0).length() < 24.0:
				continue
			if map_data.is_on_major_road_or_reserved(wx, wz, 13.5):
				continue

			var rot: float = 0.0 if (rng.randi() % 2 == 0) else PI * 0.5
			var w: float = rng.randf_range(14.0, 18.5)
			var d: float = rng.randf_range(10.5, 13.5)
			var h: float = rng.randf_range(5.4, 7.6)
			bldg_f.build_warehouse(Vector3(float(gx), 0.0, float(gz)), w, d, h, rot)


func _populate_thar_desert_structures(bldg_f: RefCounted, map_data: RefCounted, rng: RandomNumberGenerator) -> void:
	# Occasional rural Rajasthani dhanis (desert huts) near highway or flat valleys
	var hut_attempts: int = 3
	for _i: int in range(hut_attempts):
		var lx: float = rng.randf_range(-95.0, 95.0)
		var lz: float = rng.randf_range(-95.0, 95.0)
		var wx: float = position.x + lx
		var wz: float = position.z + lz
		if map_data.is_on_major_road_or_reserved(wx, wz, 14.0):
			continue
		var h: float = map_data.get_terrain_height(wx, wz)
		var n: Vector3 = map_data.get_terrain_normal(wx, wz)
		if n.y < 0.94:
			continue
		bldg_f.build_desert_dhani(Vector3(lx, h - 0.15, lz), rng.randf_range(0.0, TAU))


func _build_instanced_environment_props(map_data: RefCounted, mat_lib: RefCounted, rng: RandomNumberGenerator, lod_scale: float) -> void:
	var is_urban: bool = map_data.is_urban_chunk(chunk_coord)
	var prop_dist: float = 175.0 * lod_scale

	# 1. Concrete Streetlamps along NH-68 and Station Road
	var lamp_transforms: Array[Transform3D] = []
	var lamp_head_transforms: Array[Transform3D] = []
	if chunk_coord.x == 0:
		for lz: int in range(-112, 113, 32):
			if chunk_coord.y == 0 and absf(float(lz) - BarmerMapDataScript.STATION_ROAD_Z) < 22.0:
				continue
			for side: float in [-8.4, 8.4]:
				var h: float = map_data.get_terrain_height(position.x + side, position.z + float(lz))
				lamp_transforms.append(Transform3D(Basis.IDENTITY, Vector3(side, h + 3.6, float(lz))))
				lamp_head_transforms.append(Transform3D(Basis.IDENTITY, Vector3(side + (-1.0 if side > 0.0 else 1.0), h + 7.1, float(lz))))

	if chunk_coord.y == 0 and abs(chunk_coord.x) <= 1:
		for lx: int in range(-110, 111, 32):
			if chunk_coord.x == 0 and absf(float(lx)) < 24.0:
				continue
			var lz: float = BarmerMapDataScript.STATION_ROAD_Z + 6.8
			lamp_transforms.append(Transform3D(Basis.IDENTITY, Vector3(float(lx), 3.6, lz)))
			lamp_head_transforms.append(Transform3D(Basis.IDENTITY, Vector3(float(lx), 7.1, lz - 1.0)))

	if not lamp_transforms.is_empty():
		var pole_mesh := CylinderMesh.new()
		pole_mesh.top_radius = 0.08
		pole_mesh.bottom_radius = 0.14
		pole_mesh.height = 7.2
		pole_mesh.radial_segments = 8
		_spawn_multimesh("StreetLampPoles", pole_mesh, mat_lib.get_mat("concrete"), lamp_transforms, prop_dist)

		var head_mesh := BoxMesh.new()
		head_mesh.size = Vector3(1.15, 0.16, 0.36)
		_spawn_multimesh("StreetLampHeads", head_mesh, mat_lib.get_mat("lamp_glow"), lamp_head_transforms, prop_dist)

	# 2. Native Rajasthan Khejri Trees, Desert Scrub Bushes, and Sandstone Boulders
	var tree_trunks: Array[Transform3D] = []
	var tree_canopies: Array[Transform3D] = []
	var scrub_xforms: Array[Transform3D] = []
	var rock_xforms: Array[Transform3D] = []

	var tree_budget: int = 12 if is_urban else 28
	var scrub_budget: int = 18 if is_urban else 64
	var rock_budget: int = 8 if is_urban else 34

	for _i: int in range(tree_budget):
		var lx: float = rng.randf_range(-120.0, 120.0)
		var lz: float = rng.randf_range(-120.0, 120.0)
		var wx: float = position.x + lx
		var wz: float = position.z + lz
		if is_urban and not (chunk_coord.y == 0 and wz > 52.0):
			# Keep urban trees to road edges / desert fringe so they don't clip buildings
			continue
		if map_data.is_on_major_road_or_reserved(wx, wz, 5.5):
			continue
		var h: float = map_data.get_terrain_height(wx, wz)
		var scale_f: float = rng.randf_range(0.85, 1.45)
		var rot_b := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * scale_f)
		tree_trunks.append(Transform3D(rot_b, Vector3(lx, h + 1.6 * scale_f, lz)))
		tree_canopies.append(Transform3D(rot_b, Vector3(lx, h + 3.7 * scale_f, lz)))

	for _i: int in range(scrub_budget):
		var lx: float = rng.randf_range(-122.0, 122.0)
		var lz: float = rng.randf_range(-122.0, 122.0)
		var wx: float = position.x + lx
		var wz: float = position.z + lz
		if is_urban and not (chunk_coord.y == 0 and wz > 48.0):
			continue
		if map_data.is_on_major_road_or_reserved(wx, wz, 3.0):
			continue
		var h: float = map_data.get_terrain_height(wx, wz)
		var s: float = rng.randf_range(0.55, 1.35)
		var b := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(s * 1.25, s * 0.65, s * 1.1))
		scrub_xforms.append(Transform3D(b, Vector3(lx, h + 0.35 * s, lz)))

	for _i: int in range(rock_budget):
		var lx: float = rng.randf_range(-122.0, 122.0)
		var lz: float = rng.randf_range(-122.0, 122.0)
		var wx: float = position.x + lx
		var wz: float = position.z + lz
		if is_urban and not (chunk_coord.y == 0 and wz > 50.0):
			continue
		if map_data.is_on_major_road_or_reserved(wx, wz, 4.0):
			continue
		var h: float = map_data.get_terrain_height(wx, wz)
		var b := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(
			rng.randf_range(0.9, 2.4),
			rng.randf_range(0.5, 1.3),
			rng.randf_range(0.9, 2.1)
		))
		rock_xforms.append(Transform3D(b, Vector3(lx, h + 0.2, lz)))

	if not tree_trunks.is_empty():
		var trunk_mesh := CylinderMesh.new()
		trunk_mesh.top_radius = 0.14
		trunk_mesh.bottom_radius = 0.24
		trunk_mesh.height = 3.4
		trunk_mesh.radial_segments = 7
		_spawn_multimesh("KhejriTrunks", trunk_mesh, mat_lib.get_mat("tree_bark"), tree_trunks, prop_dist)

		var canopy_mesh := SphereMesh.new()
		canopy_mesh.radius = 2.15
		canopy_mesh.height = 2.4
		canopy_mesh.radial_segments = 10
		canopy_mesh.rings = 5
		_spawn_multimesh("KhejriCanopies", canopy_mesh, mat_lib.get_mat("tree_foliage"), tree_canopies, prop_dist)

	if not scrub_xforms.is_empty():
		var scrub_mesh := SphereMesh.new()
		scrub_mesh.radius = 0.85
		scrub_mesh.height = 1.2
		scrub_mesh.radial_segments = 7
		scrub_mesh.rings = 4
		_spawn_multimesh("DesertScrub", scrub_mesh, mat_lib.get_mat("desert_scrub"), scrub_xforms, prop_dist * 0.72)

	if not rock_xforms.is_empty():
		var rock_mesh := BoxMesh.new()
		rock_mesh.size = Vector3(1.1, 0.85, 1.0)
		_spawn_multimesh("SandstoneRocks", rock_mesh, mat_lib.get_mat("desert_rock"), rock_xforms, prop_dist)


func _spawn_multimesh(node_name: String, mesh_res: Mesh, mat: Material, transforms: Array[Transform3D], vis_dist: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh_res
	mm.instance_count = transforms.size()
	for i: int in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])

	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.visibility_range_end = vis_dist
	add_child(mmi)
	_prop_multimeshes.append(mmi)
