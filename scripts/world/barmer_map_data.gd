extends RefCounted

## Phase 3 Geographically Grounded Barmer, Rajasthan Map Data.
## Models real Barmer corridors & landmarks:
## - NH-68 (North-South: Jaisalmer <-> Ahinsa Circle <-> Mahabar Sand Dunes)
## - NH-25 (East-West: Munabao <-> Chohtan Circle <-> Ahinsa Circle <-> Sindhari Circle <-> Jodhpur)
## - Barmer Railway Station (BME) on Station Road (chunk 0, -1)
## - Barmer Fort & Garh Mandir Rocky Hill overlooking town from NW (chunk -1, -1)
## - Sindhari Circle & RSRTC Bus Stand (chunk 1, 0)
## - Mahaveer Nagar residential sector (chunk 1, -1)
## - Chohtan Circle & Transport Nagar (chunk -1, 0)

enum DistrictType {
	AHINSA_GATEWAY,
	STATION_BAZAAR,
	BARMER_FORT_HILL,
	SINDHARI_BUS_STAND,
	MAHAVEER_RESIDENTIAL,
	CHOHTAN_TRANSPORT,
	MAHABAR_DUNES,
	THAR_DESERT,
}

const CHUNK_SIZE: float = 256.0
const HALF_CHUNK: float = 128.0

const NH68_X: float = 0.0
const NH68_HALF_WIDTH: float = 7.4
const STATION_ROAD_Z: float = -28.0 # NH-25 / Station Road East-West axis
const STATION_ROAD_HALF_WIDTH: float = 5.6
const AHINSA_CIRCLE_POS := Vector2(0.0, -28.0)
const AHINSA_OUTER_RADIUS: float = 17.5
const AHINSA_ISLAND_RADIUS: float = 7.2

# Real Barmer Fort Hill center inside chunk (-1, -1)
const FORT_HILL_CENTER := Vector2(-256.0, -256.0)
const FORT_SUMMIT_HEIGHT: float = 24.0
const FORT_SUMMIT_RADIUS: float = 34.0
const FORT_BASE_RADIUS: float = 104.0

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
	if chunk_coord == Vector2i(-1, -1):
		return DistrictType.BARMER_FORT_HILL
	if chunk_coord == Vector2i(1, 0):
		return DistrictType.SINDHARI_BUS_STAND
	if chunk_coord == Vector2i(1, -1):
		return DistrictType.MAHAVEER_RESIDENTIAL
	if chunk_coord == Vector2i(-1, 0):
		return DistrictType.CHOHTAN_TRANSPORT
	if chunk_coord == Vector2i(0, 1):
		return DistrictType.MAHABAR_DUNES
	return DistrictType.THAR_DESERT


func get_district_display_name(chunk_coord: Vector2i) -> String:
	match get_district(chunk_coord):
		DistrictType.AHINSA_GATEWAY:
			return "AHINSA CIRCLE · NH-68 / NH-25 JUNCTION"
		DistrictType.STATION_BAZAAR:
			return "STATION ROAD · BARMER RAILWAY STATION (BME)"
		DistrictType.BARMER_FORT_HILL:
			return "BARMER FORT · GARH MANDIR HILL"
		DistrictType.SINDHARI_BUS_STAND:
			return "SINDHARI CIRCLE · RSRTC BUS STAND (NH-25)"
		DistrictType.MAHAVEER_RESIDENTIAL:
			return "MAHAVEER NAGAR · NEHRU NAGAR COLONY"
		DistrictType.CHOHTAN_TRANSPORT:
			return "CHOHTAN CIRCLE · TRANSPORT NAGAR (NH-25)"
		DistrictType.MAHABAR_DUNES:
			return "MAHABAR SAND DUNES · NH-68 SOUTH"
		_:
			return "THAR DESERT · UTTARLAI OUTSKIRTS"


func is_urban_chunk(chunk_coord: Vector2i) -> bool:
	var d: DistrictType = get_district(chunk_coord)
	return (
		d == DistrictType.AHINSA_GATEWAY
		or d == DistrictType.STATION_BAZAAR
		or d == DistrictType.SINDHARI_BUS_STAND
		or d == DistrictType.MAHAVEER_RESIDENTIAL
		or d == DistrictType.CHOHTAN_TRANSPORT
	)


func get_urban_flatness(x: float, z: float) -> float:
	var dx: float = maxf(0.0, absf(x) - 348.0)
	var dz_north: float = maxf(0.0, -348.0 - z)
	var dz_south: float = maxf(0.0, z - 56.0)
	var dz: float = maxf(dz_north, dz_south)
	var outside_dist: float = Vector2(dx, dz).length()
	var urban_factor: float = smoothstep(0.0, 82.0, outside_dist)

	var nh68_factor: float = smoothstep(13.0, 38.0, absf(x - NH68_X))
	var nh25_factor: float = 1.0
	if absf(x) < 760.0:
		nh25_factor = smoothstep(11.0, 32.0, absf(z - STATION_ROAD_Z))

	return urban_factor * nh68_factor * nh25_factor


func get_fort_hill_height(x: float, z: float) -> float:
	var dist: float = Vector2(x, z).distance_to(FORT_HILL_CENTER)
	if dist >= FORT_BASE_RADIUS:
		return 0.0
	if dist <= FORT_SUMMIT_RADIUS:
		return FORT_SUMMIT_HEIGHT

	# Walkable graded slope from city level (0m) up to Barmer Fort summit (24m)
	var t: float = 1.0 - smoothstep(FORT_SUMMIT_RADIUS, FORT_BASE_RADIUS, dist)
	var rock_crag: float = _detail_noise.get_noise_2d(x * 1.4, z * 1.4) * 1.35 * sin(t * PI)
	return FORT_SUMMIT_HEIGHT * t + rock_crag


func get_terrain_height(x: float, z: float) -> float:
	var hill_h: float = get_fort_hill_height(x, z)
	var dune_mask: float = get_urban_flatness(x, z)
	if dune_mask <= 0.0005:
		return hill_h

	var broad_dunes: float = _dune_noise.get_noise_2d(x, z) * 11.5
	var wind_ridges: float = (_ridge_noise.get_noise_2d(x * 0.8 + 200.0, z * 1.15) + 0.35) * 9.5
	var micro_ripple: float = _detail_noise.get_noise_2d(x, z) * 0.65
	var dune_h: float = (broad_dunes + wind_ridges + micro_ripple - 1.2) * dune_mask
	return maxf(hill_h, dune_h)


func get_terrain_normal(x: float, z: float) -> Vector3:
	const EPS: float = 1.6
	var h_l: float = get_terrain_height(x - EPS, z)
	var h_r: float = get_terrain_height(x + EPS, z)
	var h_d: float = get_terrain_height(x, z - EPS)
	var h_u: float = get_terrain_height(x, z + EPS)
	return Vector3(h_l - h_r, 2.0 * EPS, h_d - h_u).normalized()


func get_terrain_vertex_color(x: float, y: float, z: float) -> Color:
	var sand_low := Color(0.77, 0.62, 0.43)
	var sand_crest := Color(0.89, 0.74, 0.52)
	var dusty_earth := Color(0.67, 0.55, 0.42)
	var gravel_shoulder := Color(0.55, 0.48, 0.40)
	var rocky_hill := Color(0.52, 0.42, 0.34)

	var h_t: float = clampf((y + 2.0) / 14.0, 0.0, 1.0)
	var col: Color = sand_low.lerp(sand_crest, h_t)

	var dune_mask: float = get_urban_flatness(x, z)
	col = dusty_earth.lerp(col, clampf(dune_mask * 1.25, 0.0, 1.0))

	# Blend rocky granite/sandstone tint onto Barmer Fort Hill slopes
	var hill_h: float = get_fort_hill_height(x, z)
	if hill_h > 0.5:
		col = col.lerp(rocky_hill, clampf(hill_h / 12.0, 0.0, 0.88))

	var nh_shoulder: float = 1.0 - smoothstep(7.0, 15.0, absf(x - NH68_X))
	var ew_shoulder: float = 0.0
	if absf(x) < 720.0:
		ew_shoulder = 1.0 - smoothstep(5.5, 13.0, absf(z - STATION_ROAD_Z))

	var shoulder: float = maxf(nh_shoulder, ew_shoulder)
	return col.lerp(gravel_shoulder, shoulder * 0.62)


func is_on_major_road_or_reserved(world_x: float, world_z: float, clearance: float = 4.0) -> bool:
	if absf(world_x - NH68_X) < (NH68_HALF_WIDTH + clearance):
		return true

	if absf(world_x) < 740.0 and absf(world_z - STATION_ROAD_Z) < (STATION_ROAD_HALF_WIDTH + clearance):
		return true

	if Vector2(world_x, world_z).distance_to(AHINSA_CIRCLE_POS) < (AHINSA_OUTER_RADIUS + clearance + 3.0):
		return true

	# Player spawn & Phase 1 test zone
	if world_x > -18.0 and world_x < 18.0 and world_z > -12.0 and world_z < 22.0:
		return true

	# Barmer Railway Station yard corridor inside chunk (0, -1)
	if world_x > 26.0 and world_x < 126.0 and world_z > -328.0 and world_z < -196.0:
		return true

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
