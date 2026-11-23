extends Node

## Unified input router bridging multi-touch Android controls, keyboards, and gamepads
## across ON_FOOT and VEHICLE control contexts.
## Loaded as Autoload: InputRouter

const JUMP_BUFFER_DURATION: float = 0.16
const INTERACT_BUFFER_DURATION: float = 0.20

# On-foot touch state
var touch_move_vector: Vector2 = Vector2.ZERO
var touch_sprint_button: bool = false
var touch_sprint_stick_lock: bool = false
var crouch_toggled: bool = false

# Vehicle touch state
var touch_vehicle_throttle: float = 0.0
var touch_vehicle_brake_reverse: float = 0.0
var touch_vehicle_steer: float = 0.0
var touch_vehicle_handbrake: bool = false

var _pending_look_delta: Vector2 = Vector2.ZERO
var _jump_buffer_timer: float = 0.0
var _interact_buffer_timer: float = 0.0

var _keyboard_move_vector: Vector2 = Vector2.ZERO
var _keyboard_sprint: bool = false
var _kb_throttle: float = 0.0
var _kb_brake_rev: float = 0.0
var _kb_steer: float = 0.0
var _kb_handbrake: bool = false


func _physics_process(delta: float) -> void:
	if _jump_buffer_timer > 0.0:
		_jump_buffer_timer = maxf(0.0, _jump_buffer_timer - delta)
	if _interact_buffer_timer > 0.0:
		_interact_buffer_timer = maxf(0.0, _interact_buffer_timer - delta)

	_poll_keyboard_fallback()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_SPACE:
			if GameManager.current_context == GameManager.ControlContext.ON_FOOT:
				trigger_jump()
		elif event.physical_keycode == KEY_C or event.physical_keycode == KEY_CTRL:
			if GameManager.current_context == GameManager.ControlContext.ON_FOOT:
				toggle_crouch()
		elif event.physical_keycode == KEY_E or event.physical_keycode == KEY_F:
			trigger_interact()
		elif event.physical_keycode == KEY_F3:
			GameManager.hud_telemetry_visible = not GameManager.hud_telemetry_visible
		elif event.physical_keycode == KEY_F4:
			GameManager.cycle_graphics_profile()
	elif event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		add_look_delta(event.relative * 0.18)


func _poll_keyboard_fallback() -> void:
	var kb := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		kb.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		kb.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		kb.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		kb.y += 1.0
	if kb.length_squared() > 1.0:
		kb = kb.normalized()

	_keyboard_move_vector = kb
	_keyboard_sprint = Input.is_physical_key_pressed(KEY_SHIFT)

	_kb_throttle = 1.0 if (Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)) else 0.0
	_kb_brake_rev = 1.0 if (Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) else 0.0
	_kb_steer = kb.x
	_kb_handbrake = Input.is_physical_key_pressed(KEY_SPACE)


func reset_touch_controls() -> void:
	touch_move_vector = Vector2.ZERO
	touch_sprint_button = false
	touch_sprint_stick_lock = false
	touch_vehicle_throttle = 0.0
	touch_vehicle_brake_reverse = 0.0
	touch_vehicle_steer = 0.0
	touch_vehicle_handbrake = false


func set_touch_move(vec: Vector2) -> void:
	touch_move_vector = vec


func set_touch_sprint_button(active: bool) -> void:
	touch_sprint_button = active


func set_touch_sprint_stick_lock(active: bool) -> void:
	touch_sprint_stick_lock = active


func set_touch_vehicle_throttle(val: float) -> void:
	touch_vehicle_throttle = clampf(val, 0.0, 1.0)


func set_touch_vehicle_brake_reverse(val: float) -> void:
	touch_vehicle_brake_reverse = clampf(val, 0.0, 1.0)


func set_touch_vehicle_steer(val: float) -> void:
	touch_vehicle_steer = clampf(val, -1.0, 1.0)


func set_touch_vehicle_handbrake(active: bool) -> void:
	touch_vehicle_handbrake = active


func add_look_delta(delta_deg: Vector2) -> void:
	_pending_look_delta += delta_deg


func consume_look_delta() -> Vector2:
	var out: Vector2 = _pending_look_delta
	_pending_look_delta = Vector2.ZERO
	return out


func trigger_jump() -> void:
	_jump_buffer_timer = JUMP_BUFFER_DURATION


func consume_jump_if_buffered() -> bool:
	if _jump_buffer_timer > 0.0:
		_jump_buffer_timer = 0.0
		return true
	return false


func trigger_interact() -> void:
	_interact_buffer_timer = INTERACT_BUFFER_DURATION


func consume_interact_if_buffered() -> bool:
	if _interact_buffer_timer > 0.0:
		_interact_buffer_timer = 0.0
		return true
	return false


func toggle_crouch() -> void:
	crouch_toggled = not crouch_toggled


func set_crouch(state: bool) -> void:
	crouch_toggled = state


func get_move_vector() -> Vector2:
	if touch_move_vector.length_squared() > 0.001:
		return touch_move_vector
	return _keyboard_move_vector


func is_sprinting() -> bool:
	return touch_sprint_button or touch_sprint_stick_lock or _keyboard_sprint


func get_vehicle_throttle() -> float:
	return maxf(touch_vehicle_throttle, _kb_throttle)


func get_vehicle_brake_reverse() -> float:
	return maxf(touch_vehicle_brake_reverse, _kb_brake_rev)


func get_vehicle_steer() -> float:
	if absf(touch_vehicle_steer) > 0.01:
		return touch_vehicle_steer
	return _kb_steer


func is_vehicle_handbrake() -> bool:
	return touch_vehicle_handbrake or _kb_handbrake
