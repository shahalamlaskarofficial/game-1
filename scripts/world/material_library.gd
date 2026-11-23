extends RefCounted

## Phase 3 RAM-Optimized PBR Material Library.
## - Uses compact RGB8 normal/albedo maps with shared noise normals (~60% lower RAM than Phase 2).
## - Supports automatic drop-in external PBR textures at res://assets/textures/<key>_albedo.png
##   and <key>_normal.png when you add high-res CC0 textures later.
## - Dynamically shifts streetlamps & lit windows at night via set_night_factor().

var materials: Dictionary = {}
var _shared_plaster_normal: ImageTexture = null
var _shared_concrete_normal: ImageTexture = null
var _shared_metal_normal: ImageTexture = null


func build_all() -> void:
	if not materials.is_empty():
		return

	_shared_plaster_normal = _build_noise_normal(3303, 0.085, 1.45, 128)
	_shared_concrete_normal = _build_noise_normal(6117, 0.115, 2.35, 128)
	_shared_metal_normal = _build_corrugated_normal(128)

	materials["terrain"] = _make_terrain_material()
	materials["asphalt"] = _make_asphalt_material()
	materials["sidewalk"] = _make_shared_normal_mat("sidewalk", Color(0.71, 0.66, 0.58), _shared_concrete_normal, 0.89, 0.0, 0.52)
	materials["concrete"] = _make_shared_normal_mat("concrete", Color(0.58, 0.56, 0.52), _shared_concrete_normal, 0.91, 0.0, 0.58)
	materials["sandstone"] = _make_sandstone_masonry("sandstone", Color(0.81, 0.62, 0.44), Color(0.62, 0.46, 0.32), 1101)
	materials["sandstone_dark"] = _make_sandstone_masonry("sandstone_dark", Color(0.63, 0.45, 0.32), Color(0.46, 0.32, 0.22), 2202)
	materials["fort_stone"] = _make_sandstone_masonry("fort_stone", Color(0.68, 0.52, 0.38), Color(0.42, 0.31, 0.22), 8812)
	materials["plaster_cream"] = _make_shared_normal_mat("plaster_cream", Color(0.88, 0.82, 0.72), _shared_plaster_normal, 0.85, 0.0, 0.42)
	materials["plaster_ochre"] = _make_shared_normal_mat("plaster_ochre", Color(0.86, 0.67, 0.42), _shared_plaster_normal, 0.86, 0.0, 0.42)
	materials["plaster_terracotta"] = _make_shared_normal_mat("plaster_terracotta", Color(0.76, 0.44, 0.31), _shared_plaster_normal, 0.86, 0.0, 0.42)
	materials["metal_roof"] = _make_shared_normal_mat("metal_roof", Color(0.47, 0.50, 0.54), _shared_metal_normal, 0.48, 0.60, 0.80)
	materials["metal_blue"] = _make_shared_normal_mat("metal_blue", Color(0.18, 0.39, 0.58), _shared_metal_normal, 0.42, 0.42, 0.65)
	materials["rail_steel"] = _make_flat_pbr(Color(0.34, 0.32, 0.30), 0.36, 0.78)
	materials["window_dark"] = _make_window_material(false)
	materials["window_lit"] = _make_window_material(true)
	materials["awning_crimson"] = _make_flat_pbr(Color(0.71, 0.21, 0.17), 0.91, 0.0)
	materials["awning_indigo"] = _make_flat_pbr(Color(0.17, 0.31, 0.53), 0.91, 0.0)
	materials["awning_saffron"] = _make_flat_pbr(Color(0.87, 0.55, 0.15), 0.90, 0.0)
	materials["paint_white"] = _make_flat_pbr(Color(0.90, 0.88, 0.82), 0.76, 0.0)
	materials["paint_amber"] = _make_flat_pbr(Color(0.93, 0.69, 0.16), 0.72, 0.0)
	materials["lamp_glow"] = _make_emissive_material(Color(1.0, 0.84, 0.50), 0.6)
	materials["tree_bark"] = _make_shared_normal_mat("tree_bark", Color(0.36, 0.27, 0.19), _shared_concrete_normal, 0.94, 0.0, 0.72)
	materials["tree_foliage"] = _make_flat_pbr(Color(0.30, 0.41, 0.22), 0.89, 0.0)
	materials["desert_scrub"] = _make_flat_pbr(Color(0.46, 0.43, 0.25), 0.92, 0.0)
	materials["desert_rock"] = _make_shared_normal_mat("desert_rock", Color(0.62, 0.47, 0.35), _shared_concrete_normal, 0.92, 0.0, 0.82)


func get_mat(key: String) -> StandardMaterial3D:
	if materials.has(key):
		return materials[key] as StandardMaterial3D
	return materials["sandstone"] as StandardMaterial3D


func set_night_factor(night_t: float) -> void:
	if materials.has("lamp_glow"):
		var lm: StandardMaterial3D = materials["lamp_glow"]
		lm.emission_energy_multiplier = lerpf(0.35, 3.8, night_t)
	if materials.has("window_lit"):
		var wm: StandardMaterial3D = materials["window_lit"]
		wm.emission_enabled = night_t > 0.12
		wm.emission_energy_multiplier = lerpf(0.0, 1.35, night_t)


func _try_apply_external_textures(key: String, mat: StandardMaterial3D) -> bool:
	var alb_path: String = "res://assets/textures/%s_albedo.png" % key
	if not ResourceLoader.exists(alb_path):
		return false
	mat.albedo_texture = load(alb_path) as Texture2D
	var norm_path: String = "res://assets/textures/%s_normal.png" % key
	if ResourceLoader.exists(norm_path):
		mat.normal_enabled = true
		mat.normal_texture = load(norm_path) as Texture2D
	return true


func _make_terrain_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.94
	mat.metallic = 0.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if not _try_apply_external_textures("terrain", mat):
		mat.normal_enabled = true
		mat.normal_texture = _build_noise_normal(7711, 0.06, 2.1, 128)
		mat.normal_scale = 0.78
	return mat


func _make_asphalt_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.22, 0.23)
	mat.roughness = 0.84
	mat.metallic = 0.04
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if not _try_apply_external_textures("asphalt", mat):
		var n := FastNoiseLite.new()
		n.seed = 5050
		n.noise_type = FastNoiseLite.TYPE_CELLULAR
		n.frequency = 0.18
		n.fractal_octaves = 2
		var img: Image = n.get_seamless_image(128, 128, false, false, 0.12, true)
		img.convert(Image.FORMAT_RGB8)
		var norm_img: Image = img.duplicate() as Image
		norm_img.bump_map_to_normal_map(1.85)
		norm_img.generate_mipmaps()
		img.generate_mipmaps()
		mat.albedo_texture = ImageTexture.create_from_image(img)
		mat.normal_enabled = true
		mat.normal_texture = ImageTexture.create_from_image(norm_img)
		mat.normal_scale = 0.65
	return mat


func _make_sandstone_masonry(key: String, stone_col: Color, mortar_col: Color, seed_val: int) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.88
	mat.metallic = 0.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if _try_apply_external_textures(key, mat):
		return mat

	const SZ: int = 128
	var albedo_img: Image = Image.create_empty(SZ, SZ, false, Image.FORMAT_RGB8)
	var height_img: Image = Image.create_empty(SZ, SZ, false, Image.FORMAT_RGB8)
	albedo_img.fill(mortar_col)
	height_img.fill(Color(0.20, 0.20, 0.20))

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var rows: int = 8
	var row_h: int = SZ / rows
	var cols: int = 4
	var col_w: int = SZ / cols

	for r: int in range(rows):
		var x_offset: int = (col_w / 2) if (r % 2 == 1) else 0
		for c: int in range(-1, cols + 1):
			var bx: int = c * col_w + x_offset + 1
			var by: int = r * row_h + 1
			var x0: int = clampi(bx, 0, SZ)
			var y0: int = clampi(by, 0, SZ)
			var x1: int = clampi(bx + col_w - 2, 0, SZ)
			var y1: int = clampi(by + row_h - 2, 0, SZ)
			if x1 <= x0 or y1 <= y0:
				continue

			var v: float = rng.randf_range(-0.065, 0.065)
			var brick_c := Color(
				clampf(stone_col.r + v, 0.0, 1.0),
				clampf(stone_col.g + v * 0.9, 0.0, 1.0),
				clampf(stone_col.b + v * 0.8, 0.0, 1.0)
			)
			var h_val: float = rng.randf_range(0.68, 0.94)
			var rect := Rect2i(x0, y0, x1 - x0, y1 - y0)
			albedo_img.fill_rect(rect, brick_c)
			height_img.fill_rect(rect, Color(h_val, h_val, h_val))

	albedo_img.generate_mipmaps()
	height_img.bump_map_to_normal_map(2.7)
	height_img.generate_mipmaps()

	mat.albedo_texture = ImageTexture.create_from_image(albedo_img)
	mat.normal_enabled = true
	mat.normal_texture = ImageTexture.create_from_image(height_img)
	mat.normal_scale = 0.85
	return mat


func _make_shared_normal_mat(key: String, col: Color, shared_norm: ImageTexture, rough: float, metal: float, norm_scale: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = rough
	mat.metallic = metal
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if not _try_apply_external_textures(key, mat):
		mat.normal_enabled = true
		mat.normal_texture = shared_norm
		mat.normal_scale = norm_scale
	return mat


func _make_window_material(warm_night_glow: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.09, 0.13, 0.17)
	mat.roughness = 0.10 # Crisp ReflectionProbe desert sky reflection on glass
	mat.metallic = 0.45
	if warm_night_glow:
		mat.emission = Color(1.0, 0.78, 0.46)
		mat.emission_enabled = false
		mat.emission_energy_multiplier = 0.0
	return mat


func _make_flat_pbr(base_col: Color, rough: float, metal: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = base_col
	mat.roughness = rough
	mat.metallic = metal
	return mat


func _make_emissive_material(col: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = energy
	mat.roughness = 0.22
	return mat


func _build_noise_normal(seed_val: int, freq: float, bump: float, sz: int) -> ImageTexture:
	var n := FastNoiseLite.new()
	n.seed = seed_val
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = 3
	var img: Image = n.get_seamless_image(sz, sz, false, false, 0.15, true)
	img.convert(Image.FORMAT_RGB8)
	img.bump_map_to_normal_map(bump)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _build_corrugated_normal(sz: int) -> ImageTexture:
	var img: Image = Image.create_empty(sz, sz, false, Image.FORMAT_RGB8)
	for x: int in range(0, sz, 8):
		img.fill_rect(Rect2i(x, 0, 4, sz), Color(0.86, 0.86, 0.86))
		img.fill_rect(Rect2i(x + 4, 0, 4, sz), Color(0.26, 0.26, 0.26))
	img.bump_map_to_normal_map(2.8)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
