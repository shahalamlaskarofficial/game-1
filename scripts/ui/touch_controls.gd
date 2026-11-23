extends Control

## Sharp, vector-drawn multi-touch gameplay HUD for Android.
## Supports simultaneous left floating stick, right free-look camera drag,
## sprint-lock threshold, ergonomic action buttons, and live performance telemetry.

const COLOR_BG := Color(0.07, 0.07, 0.08, 0.56)
const COLOR_BORDER := Color(0.92, 0.89, 0.84, 0.42)
const COLOR_ACCENT := Color(0.88, 0.62, 0.24, 0.95)
const COLOR_ACCENT_SOFT := Color(0.88, 0.62, 0.24, 0.24)
const COLOR_TEXT := Color(0.95, 0.93, 0.89, 0.94)
const COLOR_TEXT_DIM := Color(0.76, 0.73, 0.68, 0.72)

const STICK_RADIUS: float = 82.0
const KNOB_RADIUS: float = 28.0
const STICK_DEADZONE: float = 0.12
const LOOK_SENSITIVITY: float = 0.22

var _joystick_finger: int = -1
var _look_finger: int = -1
var _button_fingers: Dictionary = {}

var _stick_rest_center: Vector2 = Vector2(155.0, 560.0)
var _stick_origin: Vector2 = Vector2(155.0, 560.0)
var _stick_knob_offset: Vector2 = Vector2.ZERO
var _sprint_lock_active: bool = false

var _buttons: Dictionary = {}
var _top_buttons: Dictionary = {}
var _fps_sample_timer: float = 0.0
var _cached_fps: int = 60
var _cached_frame_ms: float = 16.6
var _cached_ram_mb: float = 0.0
var _font: Font = null


func _ready() -> void:
	_font = ThemeDB.fallback_font
	resized.connect(_recompute_layout)
	_recompute_layout()


func _process(delta: float) -> void:
	_fps_sample_timer += delta
	if _fps_sample_timer >= 0.25:
		_fps_sample_timer = 0.0
		_cached_fps = Engine.get_frames_per_second()
		_cached_frame_ms = delta * 1000.0
		_cached_ram_mb = float(OS.get_static_memory_usage()) / 1048576.0
		queue_redraw()
	elif GameManager.player_ref != null:
		queue_redraw()


func _recompute_layout() -> void:
	var w: float = maxf(size.x, 640.0)
	var h: float = maxf(size.y, 360.0)

	_stick_rest_center = Vector2(maxf(130.0, w * 0.125), h - maxf(135.0, h * 0.21))
	if _joystick_finger == -1:
		_stick_origin = _stick_rest_center

	# Ergonomic right-thumb arc
	var base_x: float = w - maxf(122.0, w * 0.095)
	var base_y: float = h - maxf(118.0, h * 0.185)

	_buttons = {
		"jump": {
			"center": Vector2(base_x, base_y),
			"radius": 48.0,
			"label": "JUMP",
		},
		"crouch": {
			"center": Vector2(base_x - 116.0, base_y + 22.0),
			"radius": 38.0,
			"label": "CROUCH",
		},
		"sprint": {
			"center": Vector2(base_x - 102.0, base_y - 84.0),
			"radius": 38.0,
			"label": "SPRINT",
		},
	}

	# Compact top-right utility pills (Graphics Profile & Telemetry Toggle)
	_top_buttons = {
		"profile": Rect2(w - 236.0, 18.0, 124.0, 34.0),
		"hud": Rect2(w - 102.0, 18.0, 82.0, 34.0),
	}
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_screen_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event as InputEventScreenDrag)


func _handle_screen_touch(ev: InputEventScreenTouch) -> void:
	var pos: Vector2 = ev.position

	if ev.pressed:
		# 1. Check top utility pills
		for key: String in _top_buttons.keys():
			var rect: Rect2 = _top_buttons[key]
			if rect.has_point(pos):
				_button_fingers[ev.index] = key
				if key == "profile":
					GameManager.cycle_graphics_profile()
				elif key == "hud":
					GameManager.hud_telemetry_visible = not GameManager.hud_telemetry_visible
				queue_redraw()
				return

		# 2. Check circular action triggers
		for key: String in _buttons.keys():
			var btn: Dictionary = _buttons[key]
			if pos.distance_to(btn["center"]) <= float(btn["radius"]) + 10.0:
				_button_fingers[ev.index] = key
				if key == "jump":
					InputRouter.trigger_jump()
				elif key == "crouch":
					InputRouter.toggle_crouch()
				elif key == "sprint":
					InputRouter.set_touch_sprint_button(true)
				queue_redraw()
				return

		# 3. Left zone -> floating virtual joystick
		if pos.x < size.x * 0.45 and _joystick_finger == -1:
			_joystick_finger = ev.index
			_stick_origin = Vector2(
				clampf(pos.x, STICK_RADIUS + 20.0, size.x * 0.40),
				clampf(pos.y, STICK_RADIUS + 80.0, size.y - STICK_RADIUS - 20.0)
			)
			_stick_knob_offset = Vector2.ZERO
			_sprint_lock_active = false
			InputRouter.set_touch_move(Vector2.ZERO)
			queue_redraw()
			return

		# 4. Remaining screen -> free-look camera pad
		if _look_finger == -1:
			_look_finger = ev.index
			return
	else:
		if _button_fingers.has(ev.index):
			var released_key: String = _button_fingers[ev.index]
			_button_fingers.erase(ev.index)
			if released_key == "sprint":
				InputRouter.set_touch_sprint_button(false)
			queue_redraw()
			return

		if ev.index == _joystick_finger:
			_joystick_finger = -1
			_stick_origin = _stick_rest_center
			_stick_knob_offset = Vector2.ZERO
			_sprint_lock_active = false
			InputRouter.set_touch_move(Vector2.ZERO)
			InputRouter.set_touch_sprint_stick_lock(false)
			queue_redraw()
			return

		if ev.index == _look_finger:
			_look_finger = -1
			return


func _handle_screen_drag(ev: InputEventScreenDrag) -> void:
	if ev.index == _joystick_finger:
		var raw_offset: Vector2 = ev.position - _stick_origin
		var dist: float = raw_offset.length()
		var clamped_offset: Vector2 = raw_offset.limit_length(STICK_RADIUS)
		_stick_knob_offset = clamped_offset

		var norm_len: float = clampf(dist / STICK_RADIUS, 0.0, 1.0)
		if norm_len < STICK_DEADZONE:
			InputRouter.set_touch_move(Vector2.ZERO)
			_sprint_lock_active = false
		else:
			var remapped: float = (norm_len - STICK_DEADZONE) / (1.0 - STICK_DEADZONE)
			var move_vec: Vector2 = raw_offset.normalized() * remapped
			InputRouter.set_touch_move(move_vec)
			# Push firmly upward past outer ring to engage automatic sprint
			_sprint_lock_active = (dist > STICK_RADIUS * 1.12 and move_vec.y < -0.68)

		InputRouter.set_touch_sprint_stick_lock(_sprint_lock_active)
		queue_redraw()
		return

	if ev.index == _look_finger:
		# Subtle non-linear curve for fine aim + fast 180-degree turns
		var mag: float = ev.relative.length()
		var accel_boost: float = clampf(1.0 + (mag * 0.015), 1.0, 1.9)
		InputRouter.add_look_delta(ev.relative * LOOK_SENSITIVITY * accel_boost)


func _draw() -> void:
	_draw_joystick()
	_draw_action_buttons()
	_draw_stamina_bar()
	_draw_top_utility_pills()
	if GameManager.hud_telemetry_visible:
		_draw_telemetry_panel()
	_draw_center_reticle()


func _draw_joystick() -> void:
	var active: bool = (_joystick_finger != -1)
	var ring_col: Color = COLOR_ACCENT if _sprint_lock_active else (COLOR_TEXT if active else COLOR_BORDER)

	# Outer matte track
	draw_circle(_stick_origin, STICK_RADIUS, COLOR_BG)
	draw_arc(_stick_origin, STICK_RADIUS, 0.0, TAU, 48, ring_col, 2.0, true)

	# Directional crosshair ticks
	var tick_inner: float = STICK_RADIUS - 10.0
	var tick_outer: float = STICK_RADIUS - 3.0
	for angle: float in [0.0, PI * 0.5, PI, PI * 1.5]:
		var dir := Vector2(cos(angle), sin(angle))
		draw_line(_stick_origin + dir * tick_inner, _stick_origin + dir * tick_outer, COLOR_BORDER, 1.5, true)

	# Sprint-lock upper indicator
	if active:
		var lock_pos: Vector2 = _stick_origin + Vector2(0.0, -STICK_RADIUS - 18.0)
		var lock_col: Color = COLOR_ACCENT if _sprint_lock_active else COLOR_TEXT_DIM
		draw_string(_font, lock_pos + Vector2(-22.0, 4.0), "SPRINT", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, lock_col)

	# Inner thumb knob
	var knob_pos: Vector2 = _stick_origin + _stick_knob_offset
	draw_circle(knob_pos, KNOB_RADIUS, COLOR_ACCENT_SOFT if active else Color(0.15, 0.15, 0.16, 0.7))
	draw_arc(knob_pos, KNOB_RADIUS, 0.0, TAU, 32, COLOR_ACCENT if active else COLOR_BORDER, 2.2, true)
	draw_circle(knob_pos, 4.0, COLOR_ACCENT if active else COLOR_TEXT_DIM)


func _draw_action_buttons() -> void:
	var active_values: Array = _button_fingers.values()
	for key: String in _buttons.keys():
		var btn: Dictionary = _buttons[key]
		var center: Vector2 = btn["center"]
		var radius: float = btn["radius"]
		var label: String = btn["label"]

		var is_pressed: bool = active_values.has(key)
		var is_toggled_on: bool = (key == "crouch" and InputRouter.crouch_toggled) or (key == "sprint" and InputRouter.is_sprinting())

		var fill: Color = COLOR_ACCENT_SOFT if (is_pressed or is_toggled_on) else COLOR_BG
		var stroke: Color = COLOR_ACCENT if (is_pressed or is_toggled_on) else COLOR_BORDER

		draw_circle(center, radius, fill)
		draw_arc(center, radius, 0.0, TAU, 40, stroke, 2.2 if (is_pressed or is_toggled_on) else 1.8, true)

		var font_size: int = 12 if key == "jump" else 11
		var text_size: Vector2 = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(
			_font,
			center + Vector2(-text_size.x * 0.5, text_size.y * 0.28),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			COLOR_ACCENT if is_toggled_on else COLOR_TEXT
		)


func _draw_stamina_bar() -> void:
	var player := GameManager.player_ref
	if player == null:
		return

	var ratio: float = clampf(float(player.get("stamina")) / float(player.get("max_stamina")), 0.0, 1.0)
	var bar_w: float = 190.0
	var bar_h: float = 4.0
	var pos := Vector2(22.0, size.y - 26.0)

	draw_rect(Rect2(pos, Vector2(bar_w, bar_h)), Color(0.1, 0.1, 0.11, 0.75), true)
	draw_rect(Rect2(pos, Vector2(bar_w * ratio, bar_h)), COLOR_ACCENT, true)
	draw_string(_font, pos + Vector2(0.0, -7.0), "STAMINA", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_TEXT_DIM)


func _draw_top_utility_pills() -> void:
	var profile_rect: Rect2 = _top_buttons["profile"]
	draw_rect(profile_rect, COLOR_BG, true)
	draw_rect(profile_rect, COLOR_BORDER, false, 1.4)
	var prof_text: String = "GFX: " + GameManager.get_profile_name()
	draw_string(_font, profile_rect.position + Vector2(12.0, 22.0), prof_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_ACCENT)

	var hud_rect: Rect2 = _top_buttons["hud"]
	draw_rect(hud_rect, COLOR_BG, true)
	draw_rect(hud_rect, COLOR_ACCENT if GameManager.hud_telemetry_visible else COLOR_BORDER, false, 1.4)
	draw_string(_font, hud_rect.position + Vector2(14.0, 22.0), "TELEM", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_TEXT)


func _draw_telemetry_panel() -> void:
	var panel := Rect2(20.0, 18.0, 326.0, 74.0)
	draw_rect(panel, COLOR_BG, true)
	draw_rect(panel, COLOR_BORDER, false, 1.2)
	# Sharp left amber accent stripe
	draw_rect(Rect2(panel.position, Vector2(3.0, panel.size.y)), COLOR_ACCENT, true)

	var line1: String = "BARMER SECTOR [PHASE 1]   |   %d FPS (%.1f ms)" % [_cached_fps, _cached_frame_ms]
	var pos_str: String = "POS: --"
	if GameManager.player_ref != null:
		var p: Vector3 = GameManager.player_ref.global_position
		pos_str = "POS: %.1f, %.1f, %.1f" % [p.x, p.y, p.z]

	var c: Vector2i = GameManager.current_chunk
	var line2: String = "CHUNK (%d, %d)   |   %s" % [c.x, c.y, pos_str]
	var line3: String = "STATIC MEM: %.1f MB   |   PROFILE: %s" % [_cached_ram_mb, GameManager.get_profile_name()]

	draw_string(_font, panel.position + Vector2(14.0, 22.0), line1, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_TEXT)
	draw_string(_font, panel.position + Vector2(14.0, 42.0), line2, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR_TEXT_DIM)
	draw_string(_font, panel.position + Vector2(14.0, 62.0), line3, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR_ACCENT)


func _draw_center_reticle() -> void:
	var c: Vector2 = size * 0.5
	draw_circle(c, 2.0, Color(0.95, 0.93, 0.89, 0.55))
