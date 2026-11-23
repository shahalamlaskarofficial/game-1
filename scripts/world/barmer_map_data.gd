extends RefCounted

## Single source of truth for Barmer, Rajasthan geography, districts,
## seamless multi-chunk terrain height/normals, and road corridors.
## Shared by terrain streaming, building placement, and future Phases 4-6 traffic/AI.

enum DistrictType {
	AHINSA_GATEWAY,
	STATION_BAZAAR,
	MAHAVEER_RESIDENTIAL,
	TRANSPORT_INDUSTRIAL,
	THAR_DESERT,
}

const CHUNK_SIZE: float = 256.0
const HALF_CHUNK: float = 128.0

# Core highway axes (world coordinates)
const NH68_X: float = 0.0
const NH68_HALF_WIDTH: float = 7.4
const STATION_ROAD_Z: float = -28.0
const STATION_ROAD_HALF_WIDTH: float = 5.6
const AHINSA_CIRCLE_POS := Vector2(0.0, -28.0)
const AHINSA_OUTER_RADIUS: float = 17.5
const AHINSA_ISLAND_RADIUS: float = 7.2

# Secondary city street offsets inside each 256m urban chunk (local coordinates)
const LOCAL_AVENUE_OFFSETS: Array[float] = [-64.0, 64.0]
const SECONDARY_ROAD_HALF_WIDTH: float = 4.2

var _dune_noise := FastNoiseLite.new()
var _ridge_noise := FastNoiseLite.new()
var _detail_noise := FastNoiseLite.new()


func _init() -> void:
	_dune_noise.seed = 40726
	_dune_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_dune_noise.frequency = 0.0042
	_dune_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_dune_noise.fractal_octaves = 4
	_dune_noise.fractal_gain = 0.46

	_ridge_noise.seed = 91823
	_ridge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridge_noise.frequency = 0.0024
	_ridge_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge_noise.fractal_octaves = 3

	_detail_noise.seed = 13579
	_detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail_noise.frequency = 0.028


func world_to_chunk(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		floori((world_pos.x + HALF_CHUNK) / CHUNK_SIZE),
		floori((world_pos.z + HALF_CHUNK) / CHUNK_SIZE)
	)


func chunk_to_world_origin(chunk_coord: Vector2i) -> Vector3:
	return Vector3(float(chunk_coord.x) * CHUNK_SIZE, 0.0, float(chunk_coord.y) * CHUNK_SIZE)


func get_district(chunk_coord: Vector2i) -> DistrictType:
	if chunk_coord == Vector2i(0, 0):
		return DistrictType.AHINSA_GATEWAY
	if chunk_coord == Vector2i(0, -1):
		return DistrictType.STATION_BAZAAR
	if chunk_coord.x == 1 and (chunk_coord.y == 0 or chunk_coord.y == -1):
		return DistrictType.MAHAVEER_RESIDENTIAL
	if chunk_coord.x == -1 and (chunk_coord.y == 0 or chunk_coord.y == -1):
		return DistrictType.TRANSPORT_INDUSTRIAL
	return DistrictType.THAR_DESERT


func get_district_display_name(chunk_coord: Vector2i) -> String:
	match get_district(chunk_coord):
		DistrictType.AHINSA_GATEWAY:
			return "AHINSA CIRCLE · NH-68 GATEWAY"
		DistrictType.STATION_BAZAAR:
			return "STATION ROAD BAZAAR · BARMER"
		DistrictType.MAHAVEER_RESIDENTIAL:
			return "MAHAVEER NAGAR · RESIDENTIAL"
		DistrictType.TRANSPORT_INDUSTRIAL:
			return "TRANSPORT NAGAR · INDUSTRIAL"
		_:
			return "THAR DESERT · KIRADU OUTSKIRTS"


func is_urban_chunk(chunk_coord: Vector2i) -> bool:
	return get_district(chunk_coord) != DistrictType.THAR_DESERT


func get_urban_flatness(x: float, z: float) -> float:
	# Returns 0.0 inside Barmer urban footprint (flat buildable grade),
	# transitioning smoothly to 1.0 in the surrounding Thar Desert dunes.
	var dx: float = maxf(0.0, absf(x) - 348.0)
	var dz_north: float = maxf(0.0, -348.0 - z)
	var dz_south: float = maxf(0.0, z - 56.0)
	var dz: float = maxf(dz_north, dz_south)
	var outside_dist: float = Vector2(dx, dz).length()
	var urban_factor: float = smoothstep(0.0, 82.0, outside_dist)

	# Keep NH-68 highway corridor graded smoothly across the entire desert
	var nh68_factor: float = smoothstep(13.0, 38.0, absf(x - NH68_X))

	# Keep Station Road East-West corridor graded through outskirts
	var ew_factor: float = 1.0
	if absf(x) < 640.0:
		ew_factor = smoothstep(11.0, 32.0, absf(z - STATION_ROAD_Z))

	return urban_factor * nh68_factor * ew_factor


func get_terrain_height(x: float, z: float) -> float:
	var dune_mask: float = get_urban_flatness(x, z)
	if dune_mask <= 0.0005:
		return 0.0

	var broad_dunes: float = _dune_noise.get_noise_2d(x, z) * 11.5
	var wind_ridges: float = (_ridge_noise.get_noise_2d(x * 0.8 + 200.0, z * 1.15) + 0.35) * 9.5
	var micro_ripple: float = _detail_noise.get_noise_2d(x, z) * 0.65
	var raw_h: float = broad_dunes + wind_ridges + micro_ripple - 1.2
	return raw_h * dune_mask


func get_terrain_normal(x: float, z: float) -> Vector3:
	# Analytical central-difference normal ensures 100% seamless lighting across chunk borders
	const EPS: float = 1.5
	var h_l: float = get_terrain_height(x - EPS, z)
	var h_r: float = get_terrain_height(x + EPS, z)
	var h_d: float = get_terrain_height(x, z - EPS)
	var h_u: float = get_terrain_height(x, z + EPS)
	return Vector3(h_l - h_r, 2.0 * EPS, h_d - h_u).normalized()


func get_terrain_vertex_color(x: float, y: float, z: float) -> Color:
	var sand_low := Color(0.77, 0.62, 0.43)
	var sand_crest := Color(0.88, 0.74, 0.52)
	var dusty_earth := Color(0.67, 0.55, 0.42)
	var gravel_shoulder := Color(0.55, 0.48, 0.40)

	var h_t: float = clampf((y + 2.0) / 14.0, 0.0, 1.0)
	var col: Color = sand_low.lerp(sand_crest, h_t)

	var dune_mask: float = get_urban_flatness(x, z)
	col = dusty_earth.lerp(col, clampf(dune_mask * 1.25, 0.0, 1.0))

	# Darken gravel along NH-68 and Station Road shoulders
	var nh_shoulder: float = 1.0 - smoothstep(7.0, 15.0, absf(x - NH68_X))
	var ew_shoulder: float = 0.0
	if absf(x) < 620.0:
		ew_shoulder = 1.0 - smoothstep(5.5, 13.0, absf(z - STATION_ROAD_Z))

	var shoulder: float = maxf(nh_shoulder, ew_shoulder)
	return col.lerp(gravel_shoulder, shoulder * 0.62)


func is_on_major_road_or_reserved(world_x: float, world_z: float, clearance: float = 4.0) -> bool:
	# 1. NH-68 North-South Highway
	if absf(world_x - NH68_X) < (NH68_HALF_WIDTH + clearance):
		return true

	# 2. Station Road East-West Arterial (within Barmer + outskirts)
	if absf(world_x) < 640.0 and absf(world_z - STATION_ROAD_Z) < (STATION_ROAD_HALF_WIDTH + clearance):
		return true

	# 3. Ahinsa Circle Roundabout Plaza
	if Vector2(world_x, world_z).distance_to(AHINSA_CIRCLE_POS) < (AHINSA_OUTER_RADIUS + clearance + 3.0):
		return true

	# 4. Player Spawn & Phase 1 Interactive Test Zone
	if world_x > -18.0 and world_x < 18.0 and world_z > -12.0 and world_z < 22.0:
		return true

	# 5. Secondary urban avenues inside urban chunks
	var chunk_c: Vector2i = world_to_chunk(Vector3(world_x, 0.0, world_z))
	if is_urban_chunk(chunk_c):
		var origin: Vector3 = chunk_to_world_origin(chunk_c)
		var lx: float = world_x - origin.x
		var lz: float = world_z - origin.z
		for offset: float in LOCAL_AVENUE_OFFSETS:
			if absf(lx - offset) < (SECONDARY_ROAD_HALF_WIDTH + clearance):
				return true
			if absf(lz - offset) < (SECONDARY_ROAD_HALF_WIDTH + clearance):
				return true

	return false
