extends Node

## Central game state, graphics profile orchestrator, streaming telemetry hub,
## vehicle/traffic/NPC registry, performance optimizer host, and dev-status tracker.
## Loaded as Autoload: GameManager

const DevProgressTrackerScript = preload("res://scripts/core/dev_progress_tracker.gd")
const PerformanceOptimizerScript = preload("res://scripts/core/performance_optimizer.gd")

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
var active_chunk_count: int = 1
var active_traffic_count: int = 0
var active_npc_count: int = 0

var player_ref: CharacterBody3D = null
var current_vehicle: Node3D = null
var nearby_vehicle: Node3D = null
var nearby_npc: Node3D = null
var traffic_manager_ref: Node3D = null
var npc_manager_ref: Node3D = null
var world_environment_ref: WorldEnvironment = null
var sun_light_ref: DirectionalLight3D = null
var atmosphere_ref: Node3D = null
var hud_telemetry_visible: bool = true

var npc_dialogue_speaker: String = ""
var npc_dialogue_text: String = ""
var npc_dialogue_timer: float = 0.0

var dev_tracker: RefCounted = null
var perf_optimizer: Node = null


func _ready() -> void:
	dev_tracker = DevProgressTrackerScript.new()
	perf_optimizer = Node.new()
	perf_optimizer.name = "PerformanceOptimizer"
	perf_optimizer.set_script(PerformanceOptimizerScript)
	add_child(perf_optimizer)

	if OS.has_feature("android"):
		apply_graphics_profile(GraphicsProfile.MEDIUM)
	else:
		apply_graphics_profile(GraphicsProfile.HIGH)


func _process(delta: float) -> void:
	if npc_dialogue_timer > 0.0:
		npc_dialogue_timer = maxf(0.0, npc_dialogue_timer - delta)


func register_player(player: CharacterBody3D) -> void:
	player_ref = player


func register_environment(world_env: WorldEnvironment, sun: DirectionalLight3D) -> void:
	world_environment_ref = world_env
	sun_light_ref = sun
	apply_graphics_profile(current_profile)


func register_atmosphere(atmo: Node3D) -> void:
	atmosphere_ref = atmo


func register_traffic_manager(tm: Node3D) -> void:
	traffic_manager_ref = tm


func register_npc_manager(nm: Node3D) -> void:
	npc_manager_ref = nm


func show_npc_dialogue(speaker: String, line: String, duration: float = 3.8) -> void:
	npc_dialogue_speaker = speaker
	npc_dialogue_text = line
	npc_dialogue_timer = duration


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


func cycle_time_of_day() -> void:
	if atmosphere_ref != null and atmosphere_ref.has_method("cycle_time_preset"):
		atmosphere_ref.cycle_time_preset()


func cycle_weather() -> void:
	if atmosphere_ref != null and atmosphere_ref.has_method("cycle_weather"):
		atmosphere_ref.cycle_weather()


func get_profile_name() -> String:
	return PROFILE_NAMES[int(current_profile)]


func get_time_display() -> String:
	if atmosphere_ref != null and atmosphere_ref.has_method("get_formatted_time"):
		return atmosphere_ref.get_formatted_time()
	return "09:30"


func get_weather_display() -> String:
	if atmosphere_ref != null and atmosphere_ref.has_method("get_weather_name"):
		return atmosphere_ref.get_weather_name()
	return "CLEAR"


func apply_graphics_profile(profile: GraphicsProfile) -> void:
	current_profile = profile
	if perf_optimizer != null and perf_optimizer.has_method("apply_profile"):
		perf_optimizer.apply_profile(int(profile), get_viewport(), sun_light_ref, world_environment_ref)
	graphics_profile_changed.emit(current_profile)
