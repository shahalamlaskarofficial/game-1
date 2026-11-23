extends Node3D

## Generates the Phase 1 Barmer, Rajasthan vertical slice procedurally so the APK
## runs with full desert terrain, highway, sandstone outpost, crouch-clearance arch,
## natural lighting/sky, and interactive physics objects with zero external assets.

const TERRAIN_SIZE: float = 360.0
const TERRAIN_SUBDIVISIONS: int = 72

@onready var generated_world: Node3D = $GeneratedWorld
@onready var dynamic_props: Node3D = $DynamicProps

var _noise := FastNoiseLite.new()


func _ready() -> void:
	_setup_noise()
	_build_environment_and_sun()
	_build_thar_desert_terrain()
	_build_barmer_highway()
	_build_sandstone_outpost()
	_spawn_physics_test_props()


func _setup_noise() -> void:
	_noise.seed = 40726
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.0085
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 4
	_noise.fractal_gain = 0.45


func _sample_height(x: float, z: float) -> float:
	# Keep central NH-68 style highway corridor & outpost pad level around y = 0
	var corridor_dist: float = absf(x)
	var outpost_dist: float = Vector2(x - 16.0, z + 18.0).length()

	var road_blend: float = smoothstep(10.0, 32.0, corridor_dist)
	var pad_blend: float = smoothstep(16.0, 34.0, outpost_dist)
	var flat_factor: float = minf(road_blend, pad_blend)

	var dune_raw: float = _noise.get_noise_2d(x, z) * 14.5
	var ridge: float = absf(_noise.get_noise_2d(x * 0.45 + 120.0, z * 0.45)) * 7.0
	return (dune_raw + ridge - 1.5) * flat_factor


func _build_environment_and_sun() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "BarmerSun"
	sun.light_color = Color(1.0, 0.90, 0.74)
	sun.light_energy = 1.65
	sun.rotation_degrees = Vector3(-34.0, 42.0, 0.0)
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	generated_world.add_child(sun)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.24, 0.45, 0.74)
	sky_mat.sky_horizon_color = Color(0.87, 0.74, 0.56)
	sky_mat.ground_bottom_color = Color(0.55, 0.41, 0.28)
	sky_mat.ground_horizon_color = Color(0.82, 0.68, 0.49)
	sky_mat.sun_angle_max = 28.0
	sky_mat.sun_curve = 0.08

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.86, 0.73, 0.56)
	env.fog_density = 0.0022
	env.fog_sky_affect = 0.35

	var world_env := WorldEnvironment.new()
	world_env.name = "BarmerEnvironment"
	world_env.environment = env
	generated_world.add_child(world_env)

	GameManager.register_environment(world_env, sun)


func _build_thar_desert_terrain() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half: float = TERRAIN_SIZE * 0.5
	var step: float = TERRAIN_SIZE / float(TERRAIN_SUBDIVISIONS)

	var sand_low := Color(0.76, 0.61, 0.42)
	var sand_high := Color(0.85, 0.70, 0.49)
	var gravel_col := Color(0.60, 0.49, 0.38)

	for gz: int in range(TERRAIN_SUBDIVISIONS):
		for gx: int in range(TERRAIN_SUBDIVISIONS):
			var x0: float = -half + gx * step
			var z0: float = -half + gz * step
			var x1: float = x0 + step
			var z1: float = z0 + step

			var p00 := Vector3(x0, _sample_height(x0, z0), z0)
			var p10 := Vector3(x1, _sample_height(x1, z0), z0)
			var p01 := Vector3(x0, _sample_height(x0, z1), z1)
			var p11 := Vector3(x1, _sample_height(x1, z1), z1)

			var c00: Color = _terrain_color(p00, sand_low, sand_high, gravel_col)
			var c10: Color = _terrain_color(p10, sand_low, sand_high, gravel_col)
			var c01: Color = _terrain_color(p01, sand_low, sand_high, gravel_col)
			var c11: Color = _terrain_color(p11, sand_low, sand_high, gravel_col)

			# Triangle 1
			st.set_color(c00)
			st.add_vertex(p00)
			st.set_color(c10)
			st.add_vertex(p10)
			st.set_color(c01)
			st.add_vertex(p01)

			# Triangle 2
			st.set_color(c10)
			st.add_vertex(p10)
			st.set_color(c11)
			st.add_vertex(p11)
			st.set_color(c01)
			st.add_vertex(p01)

	st.generate_normals()
	var terrain_mesh: ArrayMesh = st.commit()

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.94
	mat.metallic = 0.0

	var body := StaticBody3D.new()
	body.name = "TharDesertTerrain"
	body.collision_layer = 1
	body.collision_mask = 0

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = terrain_mesh
	mesh_inst.material_override = mat
	body.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	col.shape = terrain_mesh.create_trimesh_shape()
	body.add_child(col)

	generated_world.add_child(body)


func _terrain_color(p: Vector3, sand_low: Color, sand_high: Color, gravel_col: Color) -> Color:
	var h_t: float = clampf((p.y + 4.0) / 14.0, 0.0, 1.0)
	var col: Color = sand_low.lerp(sand_high, h_t)
	var road_shoulder: float = 1.0 - smoothstep(6.0, 14.0, absf(p.x))
	return col.lerp(gravel_col, road_shoulder * 0.55)


func _build_barmer_highway() -> void:
	var asphalt_mat := StandardMaterial3D.new()
	asphalt_mat.albedo_color = Color(0.19, 0.19, 0.20)
	asphalt_mat.roughness = 0.88

	var line_white := StandardMaterial3D.new()
	line_white.albedo_color = Color(0.86, 0.84, 0.78)
	line_white.roughness = 0.78

	var line_amber := StandardMaterial3D.new()
	line_amber.albedo_color = Color(0.88, 0.65, 0.20)
	line_amber.roughness = 0.75

	# Main 2-lane desert highway deck
	_create_static_box("HighwayDeck", Vector3(0.0, -0.04, 0.0), Vector3(9.6, 0.14, 240.0), asphalt_mat)

	# Shoulder edge markings
	_create_static_box("ShoulderLeft", Vector3(-4.35, 0.035, 0.0), Vector3(0.16, 0.01, 236.0), line_white, false)
	_create_static_box("ShoulderRight", Vector3(4.35, 0.035, 0.0), Vector3(0.16, 0.01, 236.0), line_white, false)

	# Dashed yellow centerline
	for z_idx: int in range(-14, 15):
		_create_static_box(
			"CenterDash_%d" % z_idx,
			Vector3(0.0, 0.036, float(z_idx) * 8.0),
			Vector3(0.16, 0.01, 3.6),
			line_amber,
			false
		)

	# Rajasthan Highway Kilometer Milestone (NH-68 Barmer)
	var stone_mat := StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.90, 0.88, 0.83)
	stone_mat.roughness = 0.85
	var top_yellow := StandardMaterial3D.new()
	top_yellow.albedo_color = Color(0.92, 0.72, 0.14)
	top_yellow.roughness = 0.70

	_create_static_box("MilestoneBase", Vector3(6.2, 0.42, -4.0), Vector3(0.45, 0.85, 0.26), stone_mat)
	_create_static_box("MilestoneCap", Vector3(6.2, 0.96, -4.0), Vector3(0.45, 0.28, 0.26), top_yellow)


func _build_sandstone_outpost() -> void:
	var sandstone := StandardMaterial3D.new()
	sandstone.albedo_color = Color(0.76, 0.57, 0.40)
	sandstone.roughness = 0.89

	var sandstone_dark := StandardMaterial3D.new()
	sandstone_dark.albedo_color = Color(0.58, 0.41, 0.29)
	sandstone_dark.roughness = 0.91

	var shade_cloth := StandardMaterial3D.new()
	shade_cloth.albedo_color = Color(0.68, 0.24, 0.18)
	shade_cloth.roughness = 0.85

	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.56, 0.54, 0.50)
	concrete.roughness = 0.92

	# Roadside Dhaba / Shop Building (Barmer Sandstone Architecture)
	_create_static_box("ShopMain", Vector3(15.5, 2.2, -16.0), Vector3(9.5, 4.4, 7.2), sandstone)
	_create_static_box("ShopParapet", Vector3(15.5, 4.65, -16.0), Vector3(9.9, 0.5, 7.6), sandstone_dark)
	_create_static_box("ShopAwning", Vector3(9.6, 2.95, -16.0), Vector3(2.8, 0.14, 6.6), shade_cloth)
	_create_static_box("AwningPost1", Vector3(8.4, 1.48, -19.0), Vector3(0.18, 2.95, 0.18), sandstone_dark)
	_create_static_box("AwningPost2", Vector3(8.4, 1.48, -13.0), Vector3(0.18, 2.95, 0.18), sandstone_dark)

	# Compound perimeter walls
	_create_static_box("CompoundWallNorth", Vector3(16.0, 0.9, -27.0), Vector3(18.0, 1.8, 0.55), sandstone)
	_create_static_box("CompoundWallEast", Vector3(24.8, 0.9, -18.0), Vector3(0.55, 1.8, 18.0), sandstone)

	# Elevated Water Tank Landmark (classic Rajasthan town skyline feature)
	var tank_center := Vector3(-16.0, 0.0, -24.0)
	for ox: float in [-2.2, 2.2]:
		for oz: float in [-2.2, 2.2]:
			_create_static_box("TankLeg", tank_center + Vector3(ox, 5.5, oz), Vector3(0.55, 11.0, 0.55), concrete)
	_create_static_box("TankBasin", tank_center + Vector3(0.0, 12.2, 0.0), Vector3(6.2, 3.2, 6.2), sandstone)
	_create_static_box("TankRim", tank_center + Vector3(0.0, 14.0, 0.0), Vector3(6.6, 0.45, 6.6), sandstone_dark)

	# Low Sandstone Archway (specifically sized at 1.42m clearance to test crouch physics & ceiling check)
	_create_static_box("CrouchArchLeft", Vector3(-8.5, 1.2, -4.0), Vector3(0.9, 2.4, 2.6), sandstone_dark)
	_create_static_box("CrouchArchRight", Vector3(-12.5, 1.2, -4.0), Vector3(0.9, 2.4, 2.6), sandstone_dark)
	_create_static_box("CrouchArchLint", Vector3(-10.5, 1.92, -4.0), Vector3(4.9, 1.0, 2.6), sandstone)

	# Slope / Ramp test platform (tests CharacterBody3D slope traction & jumping)
	var ramp_body := _create_static_box("SlopeRamp", Vector3(-9.5, 0.85, 5.0), Vector3(4.0, 0.35, 7.5), concrete)
	ramp_body.rotation_degrees.x = 18.0


func _spawn_physics_test_props() -> void:
	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.56, 0.39, 0.22)
	wood_mat.roughness = 0.84

	var drum_mat := StandardMaterial3D.new()
	drum_mat.albedo_color = Color(0.18, 0.34, 0.46)
	drum_mat.roughness = 0.48
	drum_mat.metallic = 0.45

	# Stackable wooden supply crates beside the shop
	var crate_positions: Array[Vector3] = [
		Vector3(6.8, 0.55, -8.0),
		Vector3(7.9, 0.55, -8.2),
		Vector3(7.35, 1.45, -8.1),
		Vector3(6.5, 0.55, -9.2),
	]
	for i: int in range(crate_positions.size()):
		_spawn_rigid_crate("SupplyCrate_%d" % i, crate_positions[i], Vector3(0.85, 0.85, 0.85), 24.0, wood_mat)

	# Heavy metal fuel drums near highway shoulder
	var drum_positions: Array[Vector3] = [
		Vector3(-6.4, 0.65, 1.5),
		Vector3(-7.3, 0.65, 2.2),
		Vector3(-6.2, 0.65, 2.7),
	]
	for i: int in range(drum_positions.size()):
		_spawn_rigid_drum("FuelDrum_%d" % i, drum_positions[i], 0.34, 1.05, 38.0, drum_mat)


func _create_static_box(node_name: String, pos: Vector3, box_size: Vector3, mat: Material, with_collision: bool = true) -> Node3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box_size
	mi.mesh = bm
	mi.material_override = mat

	if not with_collision:
		mi.name = node_name
		mi.position = pos
		generated_world.add_child(mi)
		return mi

	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_child(mi)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	col.shape = shape
	body.add_child(col)

	generated_world.add_child(body)
	return body


func _spawn_rigid_crate(node_name: String, pos: Vector3, box_size: Vector3, mass_kg: float, mat: Material) -> void:
	var rb := RigidBody3D.new()
	rb.name = node_name
	rb.position = pos
	rb.mass = mass_kg
	rb.collision_layer = 4 # Layer 3: Physics_Props
	rb.collision_mask = 7  # Collides with World_Static (1) + Player (2) + Physics_Props (4)

	var phys := PhysicsMaterial.new()
	phys.friction = 0.72
	phys.bounce = 0.08
	rb.physics_material_override = phys

	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box_size
	mi.mesh = bm
	mi.material_override = mat
	rb.add_child(mi)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	col.shape = shape
	rb.add_child(col)

	dynamic_props.add_child(rb)


func _spawn_rigid_drum(node_name: String, pos: Vector3, radius: float, height: float, mass_kg: float, mat: Material) -> void:
	var rb := RigidBody3D.new()
	rb.name = node_name
	rb.position = pos
	rb.mass = mass_kg
	rb.collision_layer = 4
	rb.collision_mask = 7

	var phys := PhysicsMaterial.new()
	phys.friction = 0.62
	phys.bounce = 0.14
	rb.physics_material_override = phys

	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 16
	mi.mesh = cm
	mi.material_override = mat
	rb.add_child(mi)

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	col.shape = shape
	rb.add_child(col)

	dynamic_props.add_child(rb)
