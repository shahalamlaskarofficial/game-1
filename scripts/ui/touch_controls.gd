extends Control

## Phase 4 Multi-Touch Gameplay HUD + Contextual Driving Controls + Dev Progress Bar.
## - ON_FOOT: Floating left stick, sprint-lock, JUMP/CROUCH/SPRINT, contextual ENTER vehicle trigger.
## - VEHICLE: Left steering pads (supports both tapping & sliding), GAS, BRAKE/REV, HANDBRAKE,
##   EXIT, live digital KM/H + GEAR + RPM tachometer cluster, plus full free-look camera orbit.

const COLOR_BG := Color(0.07, 0.07, 0.08, 0.62)
const COLOR_BG_DEEP := Color(0.04, 0.04, 0.05, 0.84)
const COLOR_BORDER := Color(0.92, 0.89, 0.84, 0.36)
const COLOR_ACCENT := Color(0.88, 0.62, 0.24, 0.96)
const COLOR_ACCENT_SOFT := Color(0.88, 0.62, 0.24, 0.26)
const COLOR_BRAKE := Color(0.86, 0.24, 0.20, 0.94)
const COLOR_BRAKE_SOFT := Color(0.86, 0.24, 0.20, 0.26)
const COLOR_DONE := Color(0.36, 0.74, 0.48, 0.95)
const COLOR_TEXT := Color(0.95, 0.93, 0.89, 0.95)
const COLOR_TEXT_DIM := Color(0.74, 0.71, 0.66, 0.74)

const STICK_RADIUS: float = 82.0
const KNOB_RADIUS: float = 28.0
const STICK_DEADZONE: float = 0.12
const LOOK_SENSITIVITY: float = 0.22

var _joystick_finger: int = -1
var _steer_finger: int = -1
var _look_finger: int = -1
var _button_fingers: Dictionary = {}

var _stick_rest_center: Vector2 = Vector2(155.0, 560.0)
var _stick_origin: Vector2 = Vector2(155.0, 560.0)
var _stick_knob_offset: Vector2 = Vector2.ZERO
var _sprint_lock_active: bool = false

var _buttons: Dictionary = {}
var _enter_button_rect: Rect2 = Rect2()
var _drive_rects: Dictionary = {}
var _top_buttons: Dictionary = {}

var _fps_sample_timer: float = 0.0
var _cached_fps: int = 60
var _cached_frame_ms: float = 16.6
var _cached_ram_mb: float = 0.0
var _font: Font = null


func _ready() -> void:
	_font = ThemeDB.fallback_font
	resized.connect(_recompute_layout)
	GameManager.control_context_changed.connect(_on_context_changed)
	_recompute_layout()


func _on_context_changed(_new_ctx: int) -> void:
	_joystick_finger = -1
	_steer_finger = -1
	_look_finger = -1
	_button_fingers.clear()
	_stick_origin = _stick_rest_center
	_stick_knob_offset = Vector2.ZERO
	_sprint_lock_active = false
	queue_redraw()


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

	# Contextual ENTER vehicle trigger (shown only when near a vehicle on foot)
	_enter_button_rect = Rect2(w - 226.0, base_y - 166.0, 198.0, 44.0)

	# Vehicle Driving Layout (left steering deck, right pedals + handbrake + exit)
	var steer_y: float = h - 146.0
	_drive_rects = {
		"steer_left": Rect2(26.0, steer_y, 118.0, 102.0),
		"steer_right": Rect2(158.0, steer_y, 118.0, 102.0),
		"steer_zone": Rect2(20.0, steer_y - 16.0, 266.0, 132.0),
		"gas": Rect2(w - 114.0, h - 186.0, 88.0, 146.0),
		"brake": Rect2(w - 216.0, h - 150.0, 88.0, 110.0),
		"handbrake": Rect2(w - 306.0, h - 116.0, 76.0, 76.0),
		"exit": Rect2(w - 114.0, h - 246.0, 88.0, 42.0),
	}

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
		# Top utility strip always active in both modes
		for key: String in _top_buttons.keys():
			if (_top_buttons[key] as Rect2).has_point(pos):
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

		if GameManager.current_context == GameManager.ControlContext.VEHICLE:
			_handle_vehicle_touch_down(ev.index, pos)
		else:
			_handle_on_foot_touch_down(ev.index, pos)
	else:
		_handle_touch_up(ev.index)


func _handle_on_foot_touch_down(idx: int, pos: Vector2) -> void:
	if GameManager.nearby_vehicle != null and _enter_button_rect.has_point(pos):
		_button_fingers[idx] = "enter"
		InputRouter.trigger_interact()
		queue_redraw()
		return

	for key: String in _buttons.keys():
		var btn: Dictionary = _buttons[key]
		if pos.distance_to(btn["center"]) <= float(btn["radius"]) + 10.0:
			_button_fingers[idx] = key
			if key == "jump":
				InputRouter.trigger_jump()
			elif key == "crouch":
				InputRouter.toggle_crouch()
			elif key == "sprint":
				InputRouter.set_touch_sprint_button(true)
			queue_redraw()
			return

	if pos.x < size.x * 0.45 and _joystick_finger == -1:
		_joystick_finger = idx
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
		_look_finger = idx


func _handle_vehicle_touch_down(idx: int, pos: Vector2) -> void:
	if (_drive_rects["exit"] as Rect2).has_point(pos):
		_button_fingers[idx] = "exit"
		InputRouter.trigger_interact()
		queue_redraw()
		return

	if (_drive_rects["gas"] as Rect2).has_point(pos):
		_button_fingers[idx] = "gas"
		InputRouter.set_touch_vehicle_throttle(1.0)
		queue_redraw()
		return

	if (_drive_rects["brake"] as Rect2).has_point(pos):
		_button_fingers[idx] = "brake"
		InputRouter.set_touch_vehicle_brake_reverse(1.0)
		queue_redraw()
		return

	if (_drive_rects["handbrake"] as Rect2).has_point(pos):
		_button_fingers[idx] = "handbrake"
		InputRouter.set_touch_vehicle_handbrake(true)
		queue_redraw()
		return

	if (_drive_rects["steer_zone"] as Rect2).has_point(pos) and _steer_finger == -1:
		_steer_finger = idx
		_update_steer_from_x(pos.x)
		queue_redraw()
		return

	if _look_finger == -1:
		_look_finger = idx


func _handle_touch_up(idx: int) -> void:
	if _button_fingers.has(idx):
		var released_key: String = _button_fingers[idx]
		_button_fingers.erase(idx)
		if released_key == "sprint":
			InputRouter.set_touch_sprint_button(false)
		elif released_key == "gas":
			InputRouter.set_touch_vehicle_throttle(0.0)
		elif released_key == "brake":
			InputRouter.set_touch_vehicle_brake_reverse(0.0)
		elif released_key == "handbrake":
			InputRouter.set_touch_vehicle_handbrake(false)
		queue_redraw()
		return

	if idx == _joystick_finger:
		_joystick_finger = -1
		_stick_origin = _stick_rest_center
		_stick_knob_offset = Vector2.ZERO
		_sprint_lock_active = false
		InputRouter.set_touch_move(Vector2.ZERO)
		InputRouter.set_touch_sprint_stick_lock(false)
		queue_redraw()
		return

	if idx == _steer_finger:
		_steer_finger = -1
		InputRouter.set_touch_vehicle_steer(0.0)
		queue_redraw()
		return

	if idx == _look_finger:
		_look_finger = -1


func _handle_screen_drag(ev: InputEventScreenDrag) -> void:
	if ev.index == _joystick_finger:
		var raw_offset: Vector2 = ev.position - _stick_origin
		var dist: float = raw_offset.length()
		_stick_knob_offset = raw_offset.limit_length(STICK_RADIUS)

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

	if ev.index == _steer_finger:
		_update_steer_from_x(ev.position.x)
		queue_redraw()
		return

	if ev.index == _look_finger:
		var mag: float = ev.relative.length()
		var accel_boost: float = clampf(1.0 + (mag * 0.015), 1.0, 1.9)
		InputRouter.add_look_delta(ev.relative * LOOK_SENSITIVITY * accel_boost)


func _update_steer_from_x(x_pos: float) -> void:
	var left_r: Rect2 = _drive_rects["steer_left"]
	var right_r: Rect2 = _drive_rects["steer_right"]
	var mid_x: float = (left_r.end.x + right_r.position.x) * 0.5
	var half_span: float = (right_r.end.x - left_r.position.x) * 0.44
	var raw: float = clampf((x_pos - mid_x) / maxf(half_span, 1.0), -1.0, 1.0)
	if absf(raw) < 0.08:
		raw = 0.0
	InputRouter.set_touch_vehicle_steer(raw)


func _draw() -> void:
	if GameManager.current_context == GameManager.ControlContext.VEHICLE:
		_draw_driving_controls()
		_draw_speedometer_cluster()
	else:
		_draw_joystick()
		_draw_action_buttons()
		_draw_stamina_bar()
		if GameManager.nearby_vehicle != null:
			_draw_enter_vehicle_prompt()
		_draw_center_reticle()

	_draw_top_utility_pills()
	if GameManager.hud_telemetry_visible:
		_draw_dev_progress_and_telemetry()


func _draw_driving_controls() -> void:
	var steer_val: float = InputRouter.get_vehicle_steer()
	var gas_on: bool = InputRouter.get_vehicle_throttle() > 0.05
	var brk_on: bool = InputRouter.get_vehicle_brake_reverse() > 0.05
	var hb_on: bool = InputRouter.is_vehicle_handbrake()

	var l_rect: Rect2 = _drive_rects["steer_left"]
	var r_rect: Rect2 = _drive_rects["steer_right"]
	_draw_drive_pad(l_rect, "<", steer_val < -0.08, COLOR_ACCENT, COLOR_ACCENT_SOFT)
	_draw_drive_pad(r_rect, ">", steer_val > 0.08, COLOR_ACCENT, COLOR_ACCENT_SOFT)

	# Steering angle indicator rail beneath L/R pads
	var rail := Rect2(l_rect.position.x, l_rect.end.y + 8.0, r_rect.end.x - l_rect.position.x, 4.0)
	draw_rect(rail, Color(0.12, 0.12, 0.14, 0.8), true)
	var mid_x: float = rail.position.x + rail.size.x * 0.5
	var bar_x: float = minf(mid_x, mid_x + steer_val * rail.size.x * 0.5)
	var bar_w: float = absf(steer_val) * rail.size.x * 0.5
	draw_rect(Rect2(bar_x, rail.position.y, maxf(bar_w, 4.0), rail.size.y), COLOR_ACCENT, true)

	_draw_drive_pad(_drive_rects["gas"], "GAS", gas_on, COLOR_ACCENT, COLOR_ACCENT_SOFT)
	_draw_drive_pad(_drive_rects["brake"], "BRAKE", brk_on, COLOR_BRAKE, COLOR_BRAKE_SOFT)
	_draw_drive_pad(_drive_rects["handbrake"], "HB", hb_on, COLOR_BRAKE, COLOR_BRAKE_SOFT)
	_draw_drive_pad(_drive_rects["exit"], "EXIT", false, COLOR_BORDER, COLOR_BG)


func _draw_drive_pad(rect: Rect2, label: String, active: bool, active_col: Color, active_fill: Color) -> void:
	draw_rect(rect, active_fill if active else COLOR_BG, true)
	draw_rect(rect, active_col if active else COLOR_BORDER, false, 2.0 if active else 1.5)
	var f_sz: int = 20 if (label == "<" or label == ">") else 12
	var sz: Vector2 = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, f_sz)
	var tx: float = rect.position.x + (rect.size.x - sz.x) * 0.5
	var ty: float = rect.position.y + (rect.size.y + sz.y * 0.6) * 0.5
	draw_string(_font, Vector2(tx, ty), label, HORIZONTAL_ALIGNMENT_LEFT, -1, f_sz, active_col if active else COLOR_TEXT)


func _draw_speedometer_cluster() -> void:
	var veh: Node3D = GameManager.current_vehicle
	if veh == null or not is_instance_valid(veh):
		return

	var kmh: int = int(roundf(float(veh.get("speed_kmh"))))
	var gear: String = String(veh.get("current_gear_label"))
	var rpm: float = clampf(float(veh.get("rpm_normalized")), 0.0, 1.0)
	var v_name: String = String(veh.get("vehicle_display_name"))

	var box_w: float = 216.0
	var box_h: float = 70.0
	var bx: float = (size.x - box_w) * 0.5
	var by: float = size.y - box_h - 22.0
	var rect := Rect2(bx, by, box_w, box_h)

	draw_rect(rect, COLOR_BG_DEEP, true)
	draw_rect(rect, COLOR_BORDER, false, 1.2)
	draw_rect(Rect2(bx, by, box_w, 2.5), COLOR_ACCENT, true)

	draw_string(_font, Vector2(bx + 14.0, by + 18.0), v_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_TEXT_DIM)
	draw_string(_font, Vector2(bx + 14.0, by + 48.0), "%03d" % kmh, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, COLOR_TEXT)
	draw_string(_font, Vector2(bx + 76.0, by + 47.0), "KM/H", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR_TEXT_DIM)

	# Gear indicator pill
	var g_rect := Rect2(bx + box_w - 50.0, by + 18.0, 36.0, 32.0)
	draw_rect(g_rect, COLOR_ACCENT_SOFT, true)
	draw_rect(g_rect, COLOR_ACCENT, false, 1.3)
	draw_string(_font, Vector2(g_rect.position.x + 13.0, g_rect.position.y + 22.0), gear, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COLOR_ACCENT)

	# Segmented RPM bar
	var rpm_bar := Rect2(bx + 14.0, by + box_h - 11.0, box_w - 28.0, 4.0)
	draw_rect(rpm_bar, Color(0.16, 0.16, 0.18, 0.9), true)
	var rpm_col: Color = COLOR_BRAKE if rpm > 0.84 else COLOR_ACCENT
	draw_rect(Rect2(rpm_bar.position, Vector2(rpm_bar.size.x * rpm, rpm_bar.size.y)), rpm_col, true)


func _draw_enter_vehicle_prompt() -> void:
	var veh: Node3D = GameManager.nearby_vehicle
	if veh == null or not is_instance_valid(veh):
		return
	var v_name: String = String(veh.get("vehicle_display_name"))
	var label: String = "DRIVE  ·  " + v_name
	draw_rect(_enter_button_rect, COLOR_BG_DEEP, true)
	draw_rect(_enter_button_rect, COLOR_ACCENT, false, 1.8)
	draw_rect(Rect2(_enter_button_rect.position, Vector2(4.0, _enter_button_rect.size.y)), COLOR_ACCENT, true)
	var sz: Vector2 = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	var tx: float = _enter_button_rect.position.x + (_enter_button_rect.size.x - sz.x) * 0.5
	var ty: float = _enter_button_rect.position.y + 27.0
	draw_string(_font, Vector2(tx, ty), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_ACCENT)


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

	if tracker != null:
		var active_p: Dictionary = tracker.get_active_phase()
		var p_id: int = int(active_p["id"])
		var p_pct: int = int(active_p["percent"])
		var p_title: String = String(active_p["title"]).to_upper()
		var done_str: String = tracker.get_completed_labels()

		var header: String = "DEV STATUS  ·  PHASE %d ACTIVE (%d%%)" % [p_id, p_pct]
		draw_string(_font, panel.position + Vector2(14.0, 20.0), header, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR_ACCENT)
		draw_string(_font, panel.position + Vector2(14.0, 36.0), p_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_TEXT)

		var bar_rect := Rect2(panel.position.x + 14.0, panel.position.y + 43.0, 338.0, 5.0)
		draw_rect(bar_rect, Color(0.18, 0.18, 0.20, 0.9), true)
		draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * (float(p_pct) / 100.0), bar_rect.size.y)), COLOR_ACCENT, true)

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

	draw_line(
		Vector2(panel.position.x + 12.0, panel.position.y + 92.0),
		Vector2(panel.position.x + panel.size.x - 12.0, panel.position.y + 92.0),
		Color(0.9, 0.87, 0.82, 0.18),
		1.0
	)

	var r_scale: float = GameManager.perf_optimizer.current_render_scale if GameManager.perf_optimizer != null else 1.0
	var c: Vector2i = GameManager.current_chunk
	var perf_line1: String = "%d FPS (%.1f ms)  |  MEM: %.1f MB  |  SCALE: %d%%" % [_cached_fps, _cached_frame_ms, _cached_ram_mb, int(roundf(r_scale * 100.0))]
	var perf_line2: String = "CHUNK (%d,%d) [%d CH | %d AI]  |  %s · %s" % [c.x, c.y, GameManager.active_chunk_count, GameManager.active_traffic_count, GameManager.get_time_display(), GameManager.get_weather_display()]

	draw_string(_font, panel.position + Vector2(14.0, 108.0), perf_line1, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_TEXT)
	draw_string(_font, panel.position + Vector2(14.0, 123.0), perf_line2, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_TEXT_DIM)


func _draw_center_reticle() -> void:
	var c: Vector2 = size * 0.5
	draw_circle(c, 2.0, Color(0.95, 0.93, 0.89, 0.55))
