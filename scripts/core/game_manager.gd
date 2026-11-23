extends Node

## Central game state, graphics profile orchestrator, and streaming telemetry hub.
## Loaded as Autoload: GameManager

enum GraphicsProfile {
	LOW = 0,
	MEDIUM = 1,
	HIGH = 2,
	ULTRA = 3,
}

enum ControlContext {
	ON_FOOT,
	VEHICLE,
	UI_MENU,
}

signal graphics_profile_changed(profile: GraphicsProfile)
signal chunk_changed(new_chunk: Vector2i)
signal control_context_changed(new_context: ControlContext)

const PROFILE_NAMES: Array[String] = ["LOW", "MEDIUM", "HIGH", "ULTRA"]

var current_profile: GraphicsProfile = GraphicsProfile.MEDIUM
var current_context: ControlContext = ControlContext.ON_FOOT
var current_chunk: Vector2i = Vector2i.ZERO
var player_ref: CharacterBody3D = null
var world_environment_ref: WorldEnvironment = null
var sun_light_ref: DirectionalLight3D = null
var hud_telemetry_visible: bool = true


func _ready() -> void:
	if OS.has_feature("android"):
		apply_graphics_profile(GraphicsProfile.MEDIUM)
	else:
		apply_graphics_profile(GraphicsProfile.HIGH)


func register_player(player: CharacterBody3D) -> void:
	player_ref = player


func register_environment(world_env: WorldEnvironment, sun: DirectionalLight3D) -> void:
	world_environment_ref = world_env
	sun_light_ref = sun
	apply_graphics_profile(current_profile)


func set_current_chunk(chunk_coords: Vector2i) -> void:
	if chunk_coords != current_chunk:
		current_chunk = chunk_coords
		chunk_changed.emit(current_chunk)


func set_control_context(context: ControlContext) -> void:
	if context != current_context:
		current_context = context
		control_context_changed.emit(current_context)


func cycle_graphics_profile() -> void:
	var next_idx: int = (int(current_profile) + 1) % PROFILE_NAMES.size()
	apply_graphics_profile(next_idx as GraphicsProfile)


func get_profile_name() -> String:
	return PROFILE_NAMES[int(current_profile)]


func apply_graphics_profile(profile: GraphicsProfile) -> void:
	current_profile = profile
	var viewport: Viewport = get_viewport()

	match profile:
		GraphicsProfile.LOW:
			viewport.scaling_3d_scale = 0.72
			viewport.msaa_3d = Viewport.MSAA_DISABLED
			if sun_light_ref:
				sun_light_ref.shadow_enabled = true
				sun_light_ref.directional_shadow_max_distance = 55.0
				sun_light_ref.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			if world_environment_ref and world_environment_ref.environment:
				world_environment_ref.environment.fog_enabled = true
				world_environment_ref.environment.glow_enabled = false

		GraphicsProfile.MEDIUM:
			viewport.scaling_3d_scale = 0.85
			viewport.msaa_3d = Viewport.MSAA_2X
			if sun_light_ref:
				sun_light_ref.shadow_enabled = true
				sun_light_ref.directional_shadow_max_distance = 110.0
				sun_light_ref.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			if world_environment_ref and world_environment_ref.environment:
				world_environment_ref.environment.fog_enabled = true
				world_environment_ref.environment.glow_enabled = false

		GraphicsProfile.HIGH:
			viewport.scaling_3d_scale = 1.0
			viewport.msaa_3d = Viewport.MSAA_2X
			if sun_light_ref:
				sun_light_ref.shadow_enabled = true
				sun_light_ref.directional_shadow_max_distance = 180.0
				sun_light_ref.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			if world_environment_ref and world_environment_ref.environment:
				world_environment_ref.environment.fog_enabled = true
				world_environment_ref.environment.glow_enabled = true

		GraphicsProfile.ULTRA:
			viewport.scaling_3d_scale = 1.0
			viewport.msaa_3d = Viewport.MSAA_4X
			if sun_light_ref:
				sun_light_ref.shadow_enabled = true
				sun_light_ref.directional_shadow_max_distance = 260.0
				sun_light_ref.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			if world_environment_ref and world_environment_ref.environment:
				world_environment_ref.environment.fog_enabled = true
				world_environment_ref.environment.glow_enabled = true

	graphics_profile_changed.emit(current_profile)
