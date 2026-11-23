extends RefCounted

## Generates and caches PBR StandardMaterial3D assets with procedural
## albedo, tangent-space normal maps, and roughness maps optimized for
## Godot 4.3 Forward Mobile (Vulkan). Zero external binary textures required.

var materials: Dictionary = {}


func build_all() -> void:
	if not materials.is_empty():
		return

	materials["terrain"] = _make_terrain_material()
	materials["asphalt"] = _make_asphalt_material()
	materials["sidewalk"] = _make_concrete_material(Color(0.70, 0.65, 0.57), 0.90, 2.2)
	materials["concrete"] = _make_concrete_material(Color(0.58, 0.56, 0.52), 0.92, 2.5)
	materials["sandstone"] = _make_sandstone_masonry_material(Color(0.80, 0.61, 0.43), Color(0.64, 0.47, 0.32), 1101)
	materials["sandstone_dark"] = _make_sandstone_masonry_material(Color(0.62, 0.44, 0.31), Color(0.47, 0.33, 0.23), 2202)
	materials["plaster_cream"] = _make_plaster_material(Color(0.87, 0.81, 0.70), 3303)
	materials["plaster_ochre"] = _make_plaster_material(Color(0.85, 0.67, 0.42), 4404)
	materials["plaster_terracotta"] = _make_plaster_material(Color(0.75, 0.43, 0.31), 5505)
	materials["metal_roof"] = _make_corrugated_metal_material(Color(0.46, 0.49, 0.52), 0.55, 0.52)
	materials["metal_blue"] = _make_corrugated_metal_material(Color(0.18, 0.38, 0.56), 0.35, 0.44)
	materials["window_dark"] = _make_window_material()
	materials["awning_crimson"] = _make_fabric_material(Color(0.70, 0.22, 0.17))
	materials["awning_indigo"] = _make_fabric_material(Color(0.17, 0.31, 0.52))
	materials["awning_saffron"] = _make_fabric_material(Color(0.86, 0.56, 0.16))
	materials["paint_white"] = _make_flat_pbr(Color(0.90, 0.88, 0.82), 0.78, 0.0)
	materials["paint_amber"] = _make_flat_pbr(Color(0.92, 0.68, 0.16), 0.74, 0.0)
	materials["lamp_glow"] = _make_emissive_material(Color(1.0, 0.84, 0.52), 1.65)
	materials["tree_bark"] = _make_concrete_material(Color(0.36, 0.27, 0.19), 0.94, 3.2)
	materials["tree_foliage"] = _make_flat_pbr(Color(0.32, 0.41, 0.23), 0.90, 0.0)
	materials["desert_scrub"] = _make_flat_pbr(Color(0.45, 0.43, 0.25), 0.92, 0.0)
	materials["desert_rock"] = _make_concrete_material(Color(0.64, 0.49, 0.36), 0.93, 3.8)


func get_mat(key: String) -> StandardMaterial3D:
	if materials.has(key):
		return materials[key] as StandardMaterial3D
	return materials["sandstone"] as StandardMaterial3D


func _make_terrain_material() -> StandardMaterial3D:
	var n := FastNoiseLite.new()
	n.seed = 7711
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.055
	n.fractal_octaves = 4

	var height_img: Image = n.get_seamless_image(256, 256, false, false, 0.15, true)
	var normal_tex: ImageTexture = _height_to_normal_texture(height_img, 2.2)

	var rough_img: Image = height_img.duplicate() as Image
	rough_img.generate_mipmaps()
	var rough_tex: ImageTexture = ImageTexture.create_from_image(rough_img)

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.normal_enabled = true
	mat.normal_texture = normal_tex
	mat.normal_scale = 0.75
	mat.roughness = 0.95
	mat.roughness_texture = rough_tex
	mat.metallic = 0.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat


func _make_asphalt_material() -> StandardMaterial3D:
	var n := FastNoiseLite.new()
	n.seed = 5050
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.frequency = 0.18
	n.fractal_octaves = 2

	var grain_img: Image = n.get_seamless_image(256, 256, false, false, 0.12, true)
	var normal_tex: ImageTexture = _height_to_normal_texture(grain_img, 1.9)

	var albedo_img: Image = grain_img.duplicate() as Image
	albedo_img.convert(Image.FORMAT_RGBA8)
	albedo_img.generate_mipmaps()
	var albedo_tex: ImageTexture = ImageTexture.create_from_image(albedo_img)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.24, 0.24, 0.25)
	mat.albedo_texture = albedo_tex
	mat.normal_enabled = true
	mat.normal_texture = normal_tex
	mat.normal_scale = 0.65
	mat.roughness = 0.87
	mat.metallic = 0.02
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat


func _make_sandstone_masonry_material(stone_col: Color, mortar_col: Color, seed_val: int) -> StandardMaterial3D:
	const SZ: int = 128
	var albedo_img: Image = Image.create_empty(SZ, SZ, false, Image.FORMAT_RGBA8)
	var height_img: Image = Image.create_empty(SZ, SZ, false, Image.FORMAT_RGBA8)

	albedo_img.fill(mortar_col)
	height_img.fill(Color(0.22, 0.22, 0.22, 1.0))

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
			var bw: int = col_w - 2
			var bh: int = row_h - 2

			var x0: int = clampi(bx, 0, SZ)
			var y0: int = clampi(by, 0, SZ)
			var x1: int = clampi(bx + bw, 0, SZ)
			var y1: int = clampi(by + bh, 0, SZ)
			if x1 <= x0 or y1 <= y0:
				continue

			var v: float = rng.randf_range(-0.06, 0.06)
			var brick_c := Color(
				clampf(stone_col.r + v, 0.0, 1.0),
				clampf(stone_col.g + v * 0.9, 0.0, 1.0),
				clampf(stone_col.b + v * 0.8, 0.0, 1.0),
				1.0
			)
			var h_val: float = rng.randf_range(0.68, 0.92)
			var rect := Rect2i(x0, y0, x1 - x0, y1 - y0)
			albedo_img.fill_rect(rect, brick_c)
			height_img.fill_rect(rect, Color(h_val, h_val, h_val, 1.0))

	albedo_img.generate_mipmaps()
	var albedo_tex: ImageTexture = ImageTexture.create_from_image(albedo_img)
	var normal_tex: ImageTexture = _height_to_normal_texture(height_img, 2.8)

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = albedo_tex
	mat.normal_enabled = true
	mat.normal_texture = normal_tex
	mat.normal_scale = 0.85
	mat.roughness = 0.89
	mat.metallic = 0.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat


func _make_plaster_material(base_col: Color, seed_val: int) -> StandardMaterial3D:
	var n := FastNoiseLite.new()
	n.seed = seed_val
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.08
	n.fractal_octaves = 3

	var h_img: Image = n.get_seamless_image(128, 128, false, false, 0.15, true)
	var normal_tex: ImageTexture = _height_to_normal_texture(h_img, 1.4)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = base_col
	mat.normal_enabled = true
	mat.normal_texture = normal_tex
	mat.normal_scale = 0.45
	mat.roughness = 0.86
	mat.metallic = 0.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat


func _make_concrete_material(base_col: Color, rough: float, bump_strength: float) -> StandardMaterial3D:
	var n := FastNoiseLite.new()
	n.seed = int(base_col.r * 9999.0) + 17
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.11
	n.fractal_octaves = 3

	var h_img: Image = n.get_seamless_image(128, 128, false, false, 0.15, true)
	var normal_tex: ImageTexture = _height_to_normal_texture(h_img, bump_strength)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = base_col
	mat.normal_enabled = true
	mat.normal_texture = normal_tex
	mat.normal_scale = 0.55
	mat.roughness = rough
	mat.metallic = 0.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat


func _make_corrugated_metal_material(base_col: Color, metal: float, rough: float) -> StandardMaterial3D:
	const SZ: int = 128
	var h_img: Image = Image.create_empty(SZ, SZ, false, Image.FORMAT_RGBA8)
	for x: int in range(0, SZ, 8):
		h_img.fill_rect(Rect2i(x, 0, 4, SZ), Color(0.85, 0.85, 0.85, 1.0))
		h_img.fill_rect(Rect2i(x + 4, 0, 4, SZ), Color(0.28, 0.28, 0.28, 1.0))

	var normal_tex: ImageTexture = _height_to_normal_texture(h_img, 3.0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = base_col
	mat.normal_enabled = true
	mat.normal_texture = normal_tex
	mat.normal_scale = 0.85
	mat.metallic = metal
	mat.roughness = rough
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat


func _make_window_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.11, 0.15, 0.19)
	mat.roughness = 0.14
	mat.metallic = 0.35
	return mat


func _make_fabric_material(base_col: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = base_col
	mat.roughness = 0.92
	mat.metallic = 0.0
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
	mat.roughness = 0.2
	return mat


func _height_to_normal_texture(height_img: Image, bump_scale: float) -> ImageTexture:
	var n_img: Image = height_img.duplicate() as Image
	n_img.convert(Image.FORMAT_RGBA8)
	n_img.bump_map_to_normal_map(bump_scale)
	n_img.generate_mipmaps()
	return ImageTexture.create_from_image(n_img)
