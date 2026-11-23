extends Node3D

## Phase 3 Barmer World Bootstrap.
## Initializes RAM-optimized PBR textures, AtmosphereManager (24h cycle + weather + reflections),
## real Barmer 256m chunk streaming, Phase 1 interactive physics props, and district banners.

const BarmerMapDataScript = preload("res://scripts/world/barmer_map_data.gd")
const MaterialLibraryScript = preload("res://scripts/world/material_library.gd")
const AtmosphereManagerScript = preload("res://scripts/world/atmosphere_manager.gd")

@onready var chunk_streamer: Node = $ChunkStreamer
@onready var generated_world: Node3D = $GeneratedWorld
@onready var dynamic_props: Node3D = $DynamicProps

var map_data: RefCounted = null
var material_lib: RefCounted = null
var atmosphere: Node3D = null

var _banner_control: Control = null
var _banner_text: String = ""
var _banner_timer: float = 0.0
var _banner_alpha: float = 0.0


func _ready() -> void:
	map_data = BarmerMapDataScript.new()
	material_lib = MaterialLibraryScript.new()
	material_lib.build_all()

	_build_environment_and_atmosphere()
	_setup_district_banner()

	chunk_streamer.district_entered.connect(_on_district_entered)
	chunk_streamer.chunk_load_requested.connect(_on_chunk_count_changed)
	chunk_streamer.chunk_unload_requested.connect(_on_chunk_count_changed)
	chunk_streamer.initialize(generated_world, map_data, material_lib, Vector2i(0, 0))
	GameManager.active_chunk_count = chunk_streamer.loaded_chunks.size()

	_spawn_phase1_physics_props()


func _process(delta: float) -> void:
	if _banner_control == null:
		return

	if _banner_timer > 0.0:
		_banner_timer = maxf(0.0, _banner_timer - delta)
		_banner_alpha = lerpf(_banner_alpha, 1.0, 1.0 - exp(-8.0 * delta))
		_banner_control.modulate.a = _banner_alpha
		_banner_control.queue_redraw()
	elif _banner_alpha > 0.01:
		_banner_alpha = lerpf(_banner_alpha, 0.0, 1.0 - exp(-4.5 * delta))
		_banner_control.modulate.a = _banner_alpha
		if _banner_alpha <= 0.01:
			_banner_control.visible = false


func _on_district_entered(district_name: String) -> void:
	_banner_text = district_name
	_banner_timer = 3.2
	if _banner_control != null:
		_banner_control.visible = true
		_banner_control.queue_redraw()


func _on_chunk_count_changed(_coord: Vector2i) -> void:
	GameManager.active_chunk_count = chunk_streamer.loaded_chunks.size()


func _build_environment_and_atmosphere() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "BarmerSun"
	sun.light_color = Color(1.0, 0.91, 0.76)
	sun.light_energy = 1.72
	sun.rotation_degrees = Vector3(-36.0, 44.0, 0.0)
	sun.shadow_enabled = true
	sun.shadow_bias = 0.035
	sun.shadow_normal_bias = 1.15
	generated_world.add_child(sun)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.22, 0.44, 0.74)
	sky_mat.sky_horizon_color = Color(0.88, 0.75, 0.58)
	sky_mat.ground_bottom_color = Color(0.56, 0.42, 0.29)
	sky_mat.ground_horizon_color = Color(0.83, 0.69, 0.50)
	sky_mat.sun_angle_max = 26.0
	sky_mat.sun_curve = 0.075

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.68
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.87, 0.75, 0.58)
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.34

	var world_env := WorldEnvironment.new()
	world_env.name = "BarmerEnvironment"
	world_env.environment = env
	generated_world.add_child(world_env)

	GameManager.register_environment(world_env, sun)

	atmosphere = Node3D.new()
	atmosphere.name = "AtmosphereManager"
	atmosphere.set_script(AtmosphereManagerScript)
	add_child(atmosphere)
	atmosphere.initialize(sun, world_env, material_lib)


func _spawn_phase1_physics_props() -> void:
	var wood_mat: StandardMaterial3D = material_lib.get_mat("sandstone_dark")
	var drum_mat: StandardMaterial3D = material_lib.get_mat("metal_blue")

	var crate_positions: Array[Vector3] = [
		Vector3(10.8, 0.60, 2.0),
		Vector3(11.9, 0.60, 1.8),
		Vector3(11.35, 1.50, 1.9),
		Vector3(10.5, 0.60, 0.8),
	]
	for i: int in range(crate_positions.size()):
		_spawn_rigid_crate("SupplyCrate_%d" % i, crate_positions[i], Vector3(0.85, 0.85, 0.85), 24.0, wood_mat)

	var drum_positions: Array[Vector3] = [
		Vector3(-10.4, 0.68, 4.5),
		Vector3(-11.3, 0.68, 5.2),
		Vector3(-10.2, 0.68, 5.7),
	]
	for i: int in range(drum_positions.size()):
		_spawn_rigid_drum("FuelDrum_%d" % i, drum_positions[i], 0.34, 1.05, 38.0, drum_mat)


func _spawn_rigid_crate(node_name: String, pos: Vector3, box_size: Vector3, mass_kg: float, mat: Material) -> void:
	var rb := RigidBody3D.new()
	rb.name = node_name
	rb.position = pos
	rb.mass = mass_kg
	rb.collision_layer = 4
	rb.collision_mask = 7

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


func _setup_district_banner() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DistrictBannerLayer"
	layer.layer = 11
	add_child(layer)

	_banner_control = Control.new()
	_banner_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_banner_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_control.visible = false
	_banner_control.draw.connect(_draw_district_banner)
	layer.add_child(_banner_control)


func _draw_district_banner() -> void:
	if _banner_text.is_empty():
		return
	var font: Font = ThemeDB.fallback_font
	var text_sz: Vector2 = font.get_string_size(_banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	var pad_x: float = 20.0
	var box_w: float = text_sz.x + pad_x * 2.0
	var box_h: float = 34.0
	var bx: float = (_banner_control.size.x - box_w) * 0.5
	var by: float = 64.0
	var rect := Rect2(bx, by, box_w, box_h)

	_banner_control.draw_rect(rect, Color(0.07, 0.07, 0.08, 0.72), true)
	_banner_control.draw_rect(Rect2(bx, by + box_h - 2.0, box_w, 2.0), Color(0.88, 0.62, 0.24, 0.95), true)
	_banner_control.draw_string(
		font,
		Vector2(bx + pad_x, by + 22.0),
		_banner_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		13,
		Color(0.95, 0.93, 0.89, 0.96)
	)
