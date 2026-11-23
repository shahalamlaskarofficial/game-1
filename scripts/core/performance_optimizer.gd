extends Node

## Centralized Mobile Performance, Memory & Thermal Optimization Controller.
## - Enables hardware/software occlusion culling on the main Viewport.
## - Shares pooled procedural Mesh resources across all chunks (prevents duplicate VRAM allocations).
## - Governs Low / Medium / High / Ultra graphics profiles cleanly.
## - Dynamically eases 3D render scale if sustained FPS drops to prevent overheating on mobile.

var mesh_pool: Dictionary = {}
var base_render_scale: float = 0.85
var current_render_scale: float = 0.85
var target_fps: float = 45.0
var weather_particle_budget: int = 140
var reflection_probes_enabled: bool = true

var _sample_accum: float = 0.0
var _frame_count: int = 0
var _avg_fps: float = 60.0


func _ready() -> void:
	_build_shared_mesh_pool()
	var vp: Viewport = get_viewport()
	if vp != null:
		vp.use_occlusion_culling = true


func _process(delta: float) -> void:
	_sample_accum += delta
	_frame_count += 1

	# Evaluate thermal/FPS headroom every 2.0 seconds
	if _sample_accum >= 2.0:
		_avg_fps = float(_frame_count) / maxf(_sample_accum, 0.001)
		_sample_accum = 0.0
		_frame_count = 0
		_adjust_dynamic_resolution()


func apply_profile(profile: int, viewport: Viewport, sun: DirectionalLight3D, world_env: WorldEnvironment) -> void:
	if viewport != null:
		viewport.use_occlusion_culling = true

	match profile:
		0: # LOW — maximum thermal efficiency & lowest RAM/VRAM footprint
			base_render_scale = 0.68
			target_fps = 30.0
			weather_particle_budget = 55
			reflection_probes_enabled = false
			RenderingServer.directional_shadow_atlas_set_size(1024, true)
			if viewport:
				viewport.msaa_3d = Viewport.MSAA_DISABLED
			if sun:
				sun.shadow_enabled = true
				sun.directional_shadow_max_distance = 60.0
				sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			if world_env and world_env.environment:
				world_env.environment.fog_enabled = true
				world_env.environment.glow_enabled = false

		1: # MEDIUM — balanced default for Android devices
			base_render_scale = 0.84
			target_fps = 40.0
			weather_particle_budget = 130
			reflection_probes_enabled = true
			RenderingServer.directional_shadow_atlas_set_size(2048, true)
			if viewport:
				viewport.msaa_3d = Viewport.MSAA_2X
			if sun:
				sun.shadow_enabled = true
				sun.directional_shadow_max_distance = 120.0
				sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			if world_env and world_env.environment:
				world_env.environment.fog_enabled = true
				world_env.environment.glow_enabled = false

		2: # HIGH — sharp native resolution & 4-split shadows
			base_render_scale = 0.96
			target_fps = 45.0
			weather_particle_budget = 240
			reflection_probes_enabled = true
			RenderingServer.directional_shadow_atlas_set_size(2048, true)
			if viewport:
				viewport.msaa_3d = Viewport.MSAA_2X
			if sun:
				sun.shadow_enabled = true
				sun.directional_shadow_max_distance = 195.0
				sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			if world_env and world_env.environment:
				world_env.environment.fog_enabled = true
				world_env.environment.glow_enabled = true
				world_env.environment.glow_intensity = 0.45
				world_env.environment.glow_bloom = 0.08

		3: # ULTRA — full resolution, 4x MSAA, 3072px shadow atlas & rich atmosphere
			base_render_scale = 1.0
			target_fps = 50.0
			weather_particle_budget = 360
			reflection_probes_enabled = true
			RenderingServer.directional_shadow_atlas_set_size(3072, true)
			if viewport:
				viewport.msaa_3d = Viewport.MSAA_4X
			if sun:
				sun.shadow_enabled = true
				sun.directional_shadow_max_distance = 270.0
				sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			if world_env and world_env.environment:
				world_env.environment.fog_enabled = true
				world_env.environment.glow_enabled = true
				world_env.environment.glow_intensity = 0.55
				world_env.environment.glow_bloom = 0.12

	current_render_scale = base_render_scale
	if viewport != null:
		viewport.scaling_3d_scale = current_render_scale


func get_pooled_mesh(key: String) -> Mesh:
	if mesh_pool.has(key):
		return mesh_pool[key] as Mesh
	return null


func _adjust_dynamic_resolution() -> void:
	var vp: Viewport = get_viewport()
	if vp == null:
		return

	var min_scale: float = maxf(0.55, base_render_scale - 0.18)
	if _avg_fps < target_fps - 5.0 and current_render_scale > min_scale:
		current_render_scale = maxf(min_scale, current_render_scale - 0.04)
		vp.scaling_3d_scale = current_render_scale
	elif _avg_fps > target_fps + 8.0 and current_render_scale < base_render_scale:
		current_render_scale = minf(base_render_scale, current_render_scale + 0.03)
		vp.scaling_3d_scale = current_render_scale


func _build_shared_mesh_pool() -> void:
	var pole := CylinderMesh.new()
	pole.top_radius = 0.075
	pole.bottom_radius = 0.135
	pole.height = 7.2
	pole.radial_segments = 8
	mesh_pool["lamp_pole"] = pole

	var lamp_arm := BoxMesh.new()
	lamp_arm.size = Vector3(1.25, 0.14, 0.32)
	mesh_pool["lamp_head"] = lamp_arm

	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.13
	trunk.bottom_radius = 0.25
	trunk.height = 3.6
	trunk.radial_segments = 7
	mesh_pool["khejri_trunk"] = trunk

	var canopy := SphereMesh.new()
	canopy.radius = 2.25
	canopy.height = 2.2
	canopy.radial_segments = 9
	canopy.rings = 5
	mesh_pool["khejri_canopy"] = canopy

	var scrub := SphereMesh.new()
	scrub.radius = 0.85
	scrub.height = 1.15
	scrub.radial_segments = 7
	scrub.rings = 4
	mesh_pool["desert_scrub"] = scrub

	var rock := BoxMesh.new()
	rock.size = Vector3(1.15, 0.85, 1.05)
	mesh_pool["sandstone_rock"] = rock
