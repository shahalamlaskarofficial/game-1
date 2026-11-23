extends Control

## Phase 3 Multi-Touch Gameplay HUD + Integrated Development Progress Indicator.
## - Preserves independent floating left stick, sprint-lock, right free-look camera drag,
##   and ergonomic right-thumb action buttons.
## - Adds a clean, matte AAA Development Progress Status Bar inside the debug/telemetry HUD
##   showing active phase, honest phase completion %, completed phases, and 8-phase roadmap pips.
## - Adds compact TIME and WX pills in the top-right bar for testing Day/Night and Weather live.

const COLOR_BG := Color(0.07, 0.07, 0.08, 0.62)
const COLOR_BG_DEEP := Color(0.04, 0.04, 0.05, 0.82)
const COLOR_BORDER := Color(0.92, 0.89, 0.84, 0.36)
const COLOR_ACCENT := Color(0.88, 0.62, 0.24, 0.96)
const COLOR_ACCENT_SOFT := Color(0.88, 0.62, 0.24, 0.24)
const COLOR_DONE := Color(0.36, 0.74, 0.48, 0.95)
const COLOR_TEXT := Color(0.95, 0.93, 0.89, 0.95)
const COLOR_TEXT_DIM := Color(0.74, 0.71, 0.66, 0.74)

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

	# Compact right-aligned utility strip: [TIME] [WX] [GFX] [DEV]
	_top_buttons = {
		"time": Rect2(w - 422.0, 16.0, 88.0, 32.0),
		"wx": Rect2(w - 326.0, 16.0, 108.0, 32.0),
		"profile": Rect2(w - 210.0, 16.0, 118.0, 32.0),
		"hud": Rect2(w - 84.0, 16.0, 68.0, 32.0),
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
		for key: String in _top_buttons.keys():
			var rect: Rect2 = _top_buttons[key]
			if rect.has_point(pos):
				_button_fingers[ev.index] = key
				if key == "profile":
					GameManager.cycle_graphics_profile()
				elif key == "hud":
					GameManager.hud_telemetry_visible = not GameManager.hud_telemetry_visible
				elif key == "time":
					GameManager.cycle_time_of_day()
				elif key == "wx":
					GameManager.cycle_weather()
				queue_redraw()
				return

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
			_sprint_lock_active = (dist > STICK_RADIUS * 1.12 and move_vec.y < -0.68)

		InputRouter.set_touch_sprint_stick_lock(_sprint_lock_active)
		queue_redraw()
		return

	if ev.index == _look_finger:
		var mag: float = ev.relative.length()
		var accel_boost: float = clampf(1.0 + (mag * 0.015), 1.0, 1.9)
		InputRouter.add_look_delta(ev.relative * LOOK_SENSITIVITY * accel_boost)


func _draw() -> void:
	_draw_joystick()
	_draw_action_buttons()
	_draw_stamina_bar()
	_draw_top_utility_pills()
	if GameManager.hud_telemetry_visible:
		_draw_dev_progress_and_telemetry()
	_draw_center_reticle()


func _draw_joystick() -> void:
	var active: bool = (_joystick_finger != -1)
	var ring_col: Color = COLOR_ACCENT if _sprint_lock_active else (COLOR_TEXT if active else COLOR_BORDER)

	draw_circle(_stick_origin, STICK_RADIUS, COLOR_BG)
	draw_arc(_stick_origin, STICK_RADIUS, 0.0, TAU, 48, ring_col, 2.0, true)

	var tick_inner: float = STICK_RADIUS - 10.0
	var tick_outer: float = STICK_RADIUS - 3.0
	for angle: float in [0.0, PI * 0.5, PI, PI * 1.5]:
		var dir := Vector2(cos(angle), sin(angle))
		draw_line(_stick_origin + dir * tick_inner, _stick_origin + dir * tick_outer, COLOR_BORDER, 1.5, true)

	if active:
		var lock_pos: Vector2 = _stick_origin + Vector2(0.0, -STICK_RADIUS - 18.0)
		var lock_col: Color = COLOR_ACCENT if _sprint_lock_active else COLOR_TEXT_DIM
		draw_string(_font, lock_pos + Vector2(-22.0, 4.0), "SPRINT", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, lock_col)

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
	_draw_pill(_top_buttons["time"], "T " + GameManager.get_time_display(), COLOR_TEXT, COLOR_BORDER)
	_draw_pill(_top_buttons["wx"], GameManager.get_weather_display(), COLOR_ACCENT, COLOR_BORDER)
	_draw_pill(_top_buttons["profile"], "GFX " + GameManager.get_profile_name(), COLOR_ACCENT, COLOR_BORDER)
	_draw_pill(_top_buttons["hud"], "DEV", COLOR_TEXT, COLOR_ACCENT if GameManager.hud_telemetry_visible else COLOR_BORDER)


func _draw_pill(rect: Rect2, label: String, txt_col: Color, border_col: Color) -> void:
	draw_rect(rect, COLOR_BG, true)
	draw_rect(rect, border_col, false, 1.3)
	var sz: Vector2 = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
	var tx: float = rect.position.x + (rect.size.x - sz.x) * 0.5
	var ty: float = rect.position.y + 20.0
	draw_string(_font, Vector2(tx, ty), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, txt_col)


func _draw_dev_progress_and_telemetry() -> void:
	var tracker: RefCounted = GameManager.dev_tracker
	var panel := Rect2(18.0, 16.0, 368.0, 132.0)
	draw_rect(panel, COLOR_BG_DEEP, true)
	draw_rect(panel, COLOR_BORDER, false, 1.2)
	draw_rect(Rect2(panel.position, Vector2(3.0, panel.size.y)), COLOR_ACCENT, true)

	# --- Section 1: In-Game Development Progress Indicator ---
	if tracker != null:
		var active_p: Dictionary = tracker.get_active_phase()
		var p_id: int = int(active_p["id"])
		var p_pct: int = int(active_p["percent"])
		var p_title: String = String(active_p["title"]).to_upper()
		var done_str: String = tracker.get_completed_labels()

		var header: String = "DEV STATUS  ·  PHASE %d ACTIVE (%d%%)" % [p_id, p_pct]
		draw_string(_font, panel.position + Vector2(14.0, 20.0), header, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR_ACCENT)
		draw_string(_font, panel.position + Vector2(14.0, 36.0), p_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_TEXT)

		# Active phase progress bar
		var bar_rect := Rect2(panel.position.x + 14.0, panel.position.y + 43.0, 338.0, 5.0)
		draw_rect(bar_rect, Color(0.18, 0.18, 0.20, 0.9), true)
		draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * (float(p_pct) / 100.0), bar_rect.size.y)), COLOR_ACCENT, true)

		# 8-Phase segmented milestone strip (P1..P8)
		var pip_y: float = panel.position.y + 54.0
		var pip_w: float = 38.0
		var pip_gap: float = 4.8
		var phases_list: Array = tracker.phases
		for i: int in range(phases_list.size()):
			var ph: Dictionary = phases_list[i]
			var px: float = panel.position.x + 14.0 + float(i) * (pip_w + pip_gap)
			var pip_rect := Rect2(px, pip_y, pip_w, 16.0)
			var st: int = int(ph["status"])
			var fill_c: Color = Color(0.14, 0.26, 0.18, 0.88) if st == 2 else (COLOR_ACCENT_SOFT if st == 1 else Color(0.12, 0.12, 0.14, 0.72))
			var brd_c: Color = COLOR_DONE if st == 2 else (COLOR_ACCENT if st == 1 else Color(0.45, 0.43, 0.40, 0.35))
			var lbl_c: Color = COLOR_DONE if st == 2 else (COLOR_ACCENT if st == 1 else COLOR_TEXT_DIM)

			draw_rect(pip_rect, fill_c, true)
			draw_rect(pip_rect, brd_c, false, 1.1)
			var pip_txt: String = String(ph["short"]) + ("*" if st == 1 else "")
			draw_string(_font, Vector2(px + 9.0, pip_y + 12.0), pip_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, lbl_c)

		var done_line: String = "DONE: %s  |  OVERALL ROADMAP: %d%%" % [done_str, tracker.get_overall_percent()]
		draw_string(_font, panel.position + Vector2(14.0, 84.0), done_line, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_TEXT_DIM)

	# Divider line
	draw_line(
		Vector2(panel.position.x + 12.0, panel.position.y + 92.0),
		Vector2(panel.position.x + panel.size.x - 12.0, panel.position.y + 92.0),
		Color(0.9, 0.87, 0.82, 0.18),
		1.0
	)

	# --- Section 2: Real-Time Performance & Spatial Telemetry ---
	var r_scale: float = GameManager.perf_optimizer.current_render_scale if GameManager.perf_optimizer != null else 1.0
	var c: Vector2i = GameManager.current_chunk
	var perf_line1: String = "%d FPS (%.1f ms)  |  MEM: %.1f MB  |  SCALE: %d%%" % [_cached_fps, _cached_frame_ms, _cached_ram_mb, int(roundf(r_scale * 100.0))]
	var perf_line2: String = "CHUNK (%d, %d) [%d ACT]  |  %s · %s" % [c.x, c.y, GameManager.active_chunk_count, GameManager.get_time_display(), GameManager.get_weather_display()]

	draw_string(_font, panel.position + Vector2(14.0, 108.0), perf_line1, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_TEXT)
	draw_string(_font, panel.position + Vector2(14.0, 123.0), perf_line2, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_TEXT_DIM)


func _draw_center_reticle() -> void:
	var c: Vector2 = size * 0.5
	draw_circle(c, 2.0, Color(0.95, 0.93, 0.89, 0.55))
