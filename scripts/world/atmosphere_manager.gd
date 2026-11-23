extends Node3D

## Phase 3 Dynamic Barmer Atmosphere, 24-Hour Day/Night Cycle,
## ReflectionProbe Reflections, Night Lighting & Thar Desert Weather System.

enum WeatherState {
	CLEAR_DESERT = 0,
	HEAT_HAZE = 1,
	THAR_SANDSTORM = 2,
	TWILIGHT_DUST = 3,
}

const WEATHER_NAMES: Array[String] = [
	"CLEAR",
	"HEAT HAZE",
	"SANDSTORM",
	"DUST WIND",
]

# 1 real second = 0.035 in-game hours (~11.4 minutes per full 24h day)
@export var time_of_day: float = 9.5
@export var time_speed_hours_per_sec: float = 0.035
@export var auto_advance_time: bool = true

var current_weather: WeatherState = WeatherState.CLEAR_DESERT
var sun_light: DirectionalLight3D = null
var world_env: WorldEnvironment = null
var sky_material: ProceduralSkyMaterial = null
var material_lib: RefCounted = null

var _reflection_probe: ReflectionProbe = null
var _dust_particles: GPUParticles3D = null
var _dust_process_mat: ParticleProcessMaterial = null
var _dust_quad_mat: StandardMaterial3D = null
var _night_fill_light: OmniLight3D = null

var _fog_density_cur: float = 0.0016
var _fog_density_target: float = 0.0016
var _probe_refresh_timer: float = 0.0
var _last_probe_hour: float = -10.0


func initialize(sun: DirectionalLight3D, env_node: WorldEnvironment, mat_lib: RefCounted) -> void:
	sun_light = sun
	world_env = env_node
	material_lib = mat_lib
	if world_env and world_env.environment and world_env.environment.sky:
		sky_material = world_env.environment.sky.sky_material as ProceduralSkyMaterial

	_setup_reflection_probe()
	_setup_dust_weather_particles()
	_setup_night_fill_light()

	if not GameManager.graphics_profile_changed.is_connected(_on_profile_changed):
		GameManager.graphics_profile_changed.connect(_on_profile_changed)
	_on_profile_changed(GameManager.current_profile)

	set_weather(WeatherState.CLEAR_DESERT)
	_apply_lighting_for_time(1.0)
	GameManager.register_atmosphere(self)


func _process(delta: float) -> void:
	if auto_advance_time:
		time_of_day = fposmod(time_of_day + time_speed_hours_per_sec * delta, 24.0)

	_apply_lighting_for_time(delta)
	_follow_player_effects(delta)


func cycle_time_preset() -> void:
	# Quick-test cycle: Dawn (06:15) -> Noon (12:30) -> Golden Hour (17:45) -> Night (22:00)
	if time_of_day < 10.0:
		time_of_day = 12.5
	elif time_of_day < 15.5:
		time_of_day = 17.75
	elif time_of_day < 20.0:
		time_of_day = 22.0
	else:
		time_of_day = 6.25
	_apply_lighting_for_time(1.0)
	_refresh_reflection_probe()


func cycle_weather() -> void:
	var next_idx: int = (int(current_weather) + 1) % WEATHER_NAMES.size()
	set_weather(next_idx as WeatherState)


func set_weather(state: WeatherState) -> void:
	current_weather = state
	match state:
		WeatherState.CLEAR_DESERT:
			_fog_density_target = 0.0014
			_configure_dust(false, 4.5, 0.14)
		WeatherState.HEAT_HAZE:
			_fog_density_target = 0.0036
			_configure_dust(true, 6.5, 0.24)
		WeatherState.THAR_SANDSTORM:
			_fog_density_target = 0.0115
			_configure_dust(true, 18.5, 0.52)
		WeatherState.TWILIGHT_DUST:
			_fog_density_target = 0.0055
			_configure_dust(true, 11.0, 0.34)
	_refresh_reflection_probe()


func get_formatted_time() -> String:
	var hrs: int = int(floorf(time_of_day)) % 24
	var mins: int = int(floorf((time_of_day - floorf(time_of_day)) * 60.0)) % 60
	return "%02d:%02d" % [hrs, mins]


func get_weather_name() -> String:
	return WEATHER_NAMES[int(current_weather)]


func _apply_lighting_for_time(delta: float) -> void:
	if sun_light == null or world_env == null or world_env.environment == null:
		return

	# Sun elevation angle: rises at 06:00, zenith at 12:00, sets at 18:00
	var day_angle: float = ((time_of_day - 6.0) / 12.0) * PI
	var sun_sin: float = sin(day_angle) # +1 at noon, 0 at sunrise/sunset, -1 at midnight
	var is_day: bool = sun_sin > -0.06
	var daylight: float = clampf((sun_sin + 0.08) / 0.38, 0.0, 1.0)
	var golden_factor: float = clampf(1.0 - absf(sun_sin - 0.14) * 3.4, 0.0, 1.0)
	var storm_dim: float = 0.62 if current_weather == WeatherState.THAR_SANDSTORM else 1.0

	# Single shadow-casting directional light: switches smoothly between Sun (day) and Moon (night)
	if is_day:
		var pitch_deg: float = clampf(-rad_to_deg(asin(clampf(sun_sin, 0.04, 0.96))), -78.0, -8.0)
		var yaw_deg: float = lerpf(85.0, -85.0, clampf((time_of_day - 6.0) / 12.0, 0.0, 1.0))
		sun_light.rotation_degrees = Vector3(pitch_deg, yaw_deg, 0.0)

		var noon_col := Color(1.0, 0.95, 0.86)
		var golden_col := Color(1.0, 0.64, 0.34)
		sun_light.light_color = noon_col.lerp(golden_col, golden_factor)
		sun_light.light_energy = lerpf(0.55, 1.85, clampf(sun_sin * 1.4, 0.0, 1.0)) * storm_dim
	else:
		# Cool Thar desert moonlight
		var moon_elev: float = clampf(-sun_sin, 0.15, 0.85)
		sun_light.rotation_degrees = Vector3(-rad_to_deg(asin(moon_elev)), 135.0, 0.0)
		sun_light.light_color = Color(0.56, 0.68, 0.92)
		sun_light.light_energy = lerpf(0.22, 0.42, moon_elev) * storm_dim

	# Sky & ambient palette blending
	var env: Environment = world_env.environment
	var day_sky_top := Color(0.20, 0.43, 0.76)
	var gold_sky_top := Color(0.29, 0.31, 0.52)
	var night_sky_top := Color(0.03, 0.05, 0.11)

	var day_horizon := Color(0.89, 0.77, 0.59)
	var gold_horizon := Color(0.95, 0.58, 0.32)
	var night_horizon := Color(0.08, 0.10, 0.16)
	var storm_horizon := Color(0.76, 0.57, 0.36)

	var top_c: Color = night_sky_top.lerp(day_sky_top, daylight).lerp(gold_sky_top, golden_factor * 0.65)
	var hor_c: Color = night_horizon.lerp(day_horizon, daylight).lerp(gold_horizon, golden_factor * 0.85)
	if current_weather == WeatherState.THAR_SANDSTORM:
		var storm_night_hor := Color(0.22, 0.16, 0.11)
		hor_c = hor_c.lerp(storm_night_hor.lerp(storm_horizon, daylight), 0.75)
		top_c = top_c.lerp(hor_c, 0.58)

	if sky_material != null:
		sky_material.sky_top_color = top_c
		sky_material.sky_horizon_color = hor_c
		sky_material.ground_horizon_color = hor_c * 0.92
		sky_material.ground_bottom_color = Color(0.06, 0.05, 0.04).lerp(Color(0.55, 0.41, 0.28), daylight)

	env.ambient_light_energy = lerpf(0.24, 0.72, daylight) * storm_dim
	env.tonemap_exposure = lerpf(1.18, 1.04, daylight)
	_fog_density_cur = lerpf(_fog_density_cur, _fog_density_target, 1.0 - exp(-2.2 * delta))
	env.fog_density = _fog_density_cur
	env.fog_light_color = hor_c

	# Streetlamp night glow & warm local urban night illumination
	var night_factor: float = clampf(1.0 - daylight * 1.35, 0.0, 1.0)
	if material_lib != null and material_lib.has_method("set_night_factor"):
		material_lib.set_night_factor(night_factor)
	if _night_fill_light != null:
		_night_fill_light.visible = night_factor > 0.15
		_night_fill_light.light_energy = night_factor * 1.65

	# Refresh ReflectionProbe periodically when lighting shifts significantly
	_probe_refresh_timer += delta
	if _probe_refresh_timer >= 3.0 and absf(time_of_day - _last_probe_hour) >= 0.45:
		_probe_refresh_timer = 0.0
		_refresh_reflection_probe()


func _follow_player_effects(delta: float) -> void:
	var player := GameManager.player_ref
	if player == null:
		return

	var p: Vector3 = player.global_position
	if _dust_particles != null:
		_dust_particles.global_position = p + Vector3(0.0, 4.5, 0.0)
	if _night_fill_light != null:
		_night_fill_light.global_position = p + Vector3(0.0, 6.5, 0.0)
	if _reflection_probe != null and _reflection_probe.global_position.distance_squared_to(p) > 2500.0:
		_reflection_probe.global_position = p + Vector3(0.0, 12.0, 0.0)
		_refresh_reflection_probe()
	# Keep delta referenced cleanly
	if delta < 0.0:
		return


func _setup_reflection_probe() -> void:
	_reflection_probe = ReflectionProbe.new()
	_reflection_probe.name = "BarmerReflectionProbe"
	_reflection_probe.size = Vector3(160.0, 64.0, 160.0)
	_reflection_probe.max_distance = 160.0
	_reflection_probe.intensity = 0.72
	_reflection_probe.ambient_mode = ReflectionProbe.AMBIENT_ENVIRONMENT
	_reflection_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	_reflection_probe.position = Vector3(0.0, 14.0, -10.0)
	add_child(_reflection_probe)


func _refresh_reflection_probe() -> void:
	if _reflection_probe == null or not _reflection_probe.visible:
		return
	_last_probe_hour = time_of_day
	_reflection_probe.update_mode = ReflectionProbe.UPDATE_ONCE


func _setup_night_fill_light() -> void:
	_night_fill_light = OmniLight3D.new()
	_night_fill_light.name = "UrbanNightGlow"
	_night_fill_light.light_color = Color(1.0, 0.76, 0.42)
	_night_fill_light.light_energy = 0.0
	_night_fill_light.omni_range = 28.0
	_night_fill_light.shadow_enabled = false # Keeps mobile fill-rate fast at night
	_night_fill_light.visible = false
	add_child(_night_fill_light)


func _setup_dust_weather_particles() -> void:
	# Tiny 32x32 soft radial puff texture (4 KB total RAM)
	const SZ: int = 32
	var img: Image = Image.create_empty(SZ, SZ, false, Image.FORMAT_RGBA8)
	var center := Vector2(15.5, 15.5)
	for y: int in range(SZ):
		for x: int in range(SZ):
			var d: float = clampf(Vector2(x, y).distance_to(center) / 15.0, 0.0, 1.0)
			var a: float = pow(1.0 - d, 2.2)
			img.set_pixel(x, y, Color(0.86, 0.70, 0.48, a))
	var puff_tex: ImageTexture = ImageTexture.create_from_image(img)

	_dust_quad_mat = StandardMaterial3D.new()
	_dust_quad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dust_quad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dust_quad_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_dust_quad_mat.albedo_texture = puff_tex
	_dust_quad_mat.albedo_color = Color(0.88, 0.72, 0.50, 0.25)
	_dust_quad_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED

	var quad := QuadMesh.new()
	quad.size = Vector2(0.85, 0.85)
	quad.material = _dust_quad_mat

	_dust_process_mat = ParticleProcessMaterial.new()
	_dust_process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_dust_process_mat.emission_box_extents = Vector3(22.0, 6.0, 22.0)
	_dust_process_mat.direction = Vector3(1.0, -0.08, 0.35)
	_dust_process_mat.spread = 20.0
	_dust_process_mat.initial_velocity_min = 4.5
	_dust_process_mat.initial_velocity_max = 10.5
	_dust_process_mat.gravity = Vector3(0.0, -0.35, 0.0)
	_dust_process_mat.scale_min = 0.55
	_dust_process_mat.scale_max = 1.65

	_dust_particles = GPUParticles3D.new()
	_dust_particles.name = "TharDustParticles"
	_dust_particles.amount = 130
	_dust_particles.lifetime = 2.6
	_dust_particles.visibility_aabb = AABB(Vector3(-32.0, -10.0, -32.0), Vector3(64.0, 24.0, 64.0))
	_dust_particles.process_material = _dust_process_mat
	_dust_particles.draw_pass_1 = quad
	_dust_particles.emitting = false
	add_child(_dust_particles)


func _configure_dust(enabled: bool, wind_speed: float, alpha: float) -> void:
	if _dust_particles == null:
		return
	_dust_particles.emitting = enabled
	_dust_process_mat.initial_velocity_min = wind_speed * 0.65
	_dust_process_mat.initial_velocity_max = wind_speed * 1.25
	_dust_quad_mat.albedo_color = Color(0.88, 0.72, 0.50, alpha)


func _on_profile_changed(_profile: int) -> void:
	if GameManager.perf_optimizer == null:
		return
	if _reflection_probe != null:
		_reflection_probe.visible = GameManager.perf_optimizer.reflection_probes_enabled
	if _dust_particles != null:
		_dust_particles.amount = GameManager.perf_optimizer.weather_particle_budget
