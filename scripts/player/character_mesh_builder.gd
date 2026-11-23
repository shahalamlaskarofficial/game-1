extends RefCounted

## Phase 3 Articulated Human Character Rig Builder & Procedural Locomotion Animator.
## - Automatically loads an external rigged GLB character if placed at
##   res://assets/models/player/hero.glb (ready for CC0/Mixamo high-poly upgrades).
## - Otherwise constructs an anatomically proportioned, multi-jointed human character
##   (sculpted head/face/hair, layered Barmer desert jacket, scarf accent, elbow/knee
##   joints, boots) with fluid stride, breathing idle, jump, and crouch posture.

const EXTERNAL_HERO_PATH: String = "res://assets/models/player/hero.glb"

var _using_external_rig: bool = false
var _pelvis: Node3D = null
var _spine: Node3D = null
var _head_pivot: Node3D = null

var _l_shoulder: Node3D = null
var _l_elbow: Node3D = null
var _r_shoulder: Node3D = null
var _r_elbow: Node3D = null

var _l_hip: Node3D = null
var _l_knee: Node3D = null
var _r_hip: Node3D = null
var _r_knee: Node3D = null

var _stride_phase: float = 0.0
var _idle_phase: float = 0.0


func build_into(visual_root: Node3D) -> void:
	if ResourceLoader.exists(EXTERNAL_HERO_PATH):
		var packed := load(EXTERNAL_HERO_PATH) as PackedScene
		if packed != null:
			var hero_inst := packed.instantiate()
			visual_root.add_child(hero_inst)
			_using_external_rig = true
			return

	_build_articulated_human(visual_root)


func update_animation(delta: float, horiz_speed: float, sprint_speed: float, is_on_floor: bool, is_crouching: bool, vel_y: float) -> void:
	if _using_external_rig or _pelvis == null:
		return

	_idle_phase += delta * 2.4
	var breath: float = sin(_idle_phase) * 0.012
	var blend: float = 1.0 - exp(-12.0 * delta)

	var base_hip_y: float = 0.62 if is_crouching else 0.94
	if not is_on_floor:
		# Airborne athletic tuck
		_pelvis.position.y = lerpf(_pelvis.position.y, 0.92, blend)
		_spine.rotation.x = lerpf(_spine.rotation.x, -0.14 if vel_y > 0.0 else 0.08, blend)
		_l_hip.rotation.x = lerpf(_l_hip.rotation.x, -0.45, blend)
		_l_knee.rotation.x = lerpf(_l_knee.rotation.x, 0.78, blend)
		_r_hip.rotation.x = lerpf(_r_hip.rotation.x, 0.22, blend)
		_r_knee.rotation.x = lerpf(_r_knee.rotation.x, 0.35, blend)
		_l_shoulder.rotation.x = lerpf(_l_shoulder.rotation.x, -0.55, blend)
		_l_elbow.rotation.x = lerpf(_l_elbow.rotation.x, -0.55, blend)
		_r_shoulder.rotation.x = lerpf(_r_shoulder.rotation.x, 0.35, blend)
		_r_elbow.rotation.x = lerpf(_r_elbow.rotation.x, -0.45, blend)
		return

	if horiz_speed > 0.22:
		var sf: float = clampf(horiz_speed / maxf(sprint_speed, 0.1), 0.15, 1.0)
		_stride_phase += delta * lerpf(6.5, 13.0, sf)
		var s: float = sin(_stride_phase)
		var c: float = cos(_stride_phase)

		var stride_amp: float = lerpf(0.32, 0.86, sf) * (0.72 if is_crouching else 1.0)
		var bounce: float = absf(c) * lerpf(0.02, 0.065, sf)
		_pelvis.position.y = lerpf(_pelvis.position.y, base_hip_y + bounce, blend)

		# Natural hip + knee bend (rear foot lifts on recovery swing)
		var l_hip_t: float = s * stride_amp - (0.36 if is_crouching else 0.0)
		var r_hip_t: float = -s * stride_amp - (0.36 if is_crouching else 0.0)
		var l_knee_t: float = maxf(0.0, -c) * lerpf(0.35, 1.05, sf) + (0.58 if is_crouching else 0.06)
		var r_knee_t: float = maxf(0.0, c) * lerpf(0.35, 1.05, sf) + (0.58 if is_crouching else 0.06)

		_l_hip.rotation.x = lerpf(_l_hip.rotation.x, l_hip_t, blend)
		_r_hip.rotation.x = lerpf(_r_hip.rotation.x, r_hip_t, blend)
		_l_knee.rotation.x = lerpf(_l_knee.rotation.x, l_knee_t, blend)
		_r_knee.rotation.x = lerpf(_r_knee.rotation.x, r_knee_t, blend)

		# Counter-swinging arms with natural elbow bend
		var arm_amp: float = stride_amp * 0.78
		_l_shoulder.rotation.x = lerpf(_l_shoulder.rotation.x, -s * arm_amp, blend)
		_r_shoulder.rotation.x = lerpf(_r_shoulder.rotation.x, s * arm_amp, blend)
		_l_elbow.rotation.x = lerpf(_l_elbow.rotation.x, -lerpf(0.22, 0.95, sf) - maxf(0.0, -s) * 0.35, blend)
		_r_elbow.rotation.x = lerpf(_r_elbow.rotation.x, -lerpf(0.22, 0.95, sf) - maxf(0.0, s) * 0.35, blend)

		# Forward sprint lean & subtle shoulder counter-twist
		var forward_lean: float = -lerpf(0.05, 0.20, sf) - (0.24 if is_crouching else 0.0)
		_spine.rotation.x = lerpf(_spine.rotation.x, forward_lean, blend)
		_spine.rotation.y = lerpf(_spine.rotation.y, s * 0.09 * sf, blend)
		_head_pivot.rotation.x = lerpf(_head_pivot.rotation.x, -forward_lean * 0.55, blend)
	else:
		# Grounded breathing idle / crouch stance
		_pelvis.position.y = lerpf(_pelvis.position.y, base_hip_y + breath, blend)
		var c_hip: float = -0.45 if is_crouching else 0.0
		var c_knee: float = 0.82 if is_crouching else 0.04
		_l_hip.rotation.x = lerpf(_l_hip.rotation.x, c_hip, blend)
		_r_hip.rotation.x = lerpf(_r_hip.rotation.x, c_hip, blend)
		_l_knee.rotation.x = lerpf(_l_knee.rotation.x, c_knee, blend)
		_r_knee.rotation.x = lerpf(_r_knee.rotation.x, c_knee, blend)
		_l_shoulder.rotation.x = lerpf(_l_shoulder.rotation.x, 0.04 + breath * 2.0, blend)
		_r_shoulder.rotation.x = lerpf(_r_shoulder.rotation.x, 0.04 + breath * 2.0, blend)
		_l_elbow.rotation.x = lerpf(_l_elbow.rotation.x, -0.18, blend)
		_r_elbow.rotation.x = lerpf(_r_elbow.rotation.x, -0.18, blend)
		_spine.rotation.x = lerpf(_spine.rotation.x, -0.26 if is_crouching else 0.0, blend)
		_spine.rotation.y = lerpf(_spine.rotation.y, 0.0, blend)
		_head_pivot.rotation.x = lerpf(_head_pivot.rotation.x, 0.14 if is_crouching else 0.0, blend)


func _build_articulated_human(root: Node3D) -> void:
	var skin := _mat(Color(0.66, 0.48, 0.36), 0.68, 0.0)
	var hair := _mat(Color(0.09, 0.08, 0.08), 0.78, 0.04)
	var eye_col := _mat(Color(0.07, 0.06, 0.06), 0.18, 0.1)
	var jacket := _mat(Color(0.22, 0.25, 0.23), 0.82, 0.04)
	var shirt := _mat(Color(0.84, 0.80, 0.72), 0.86, 0.0)
	var scarf := _mat(Color(0.76, 0.36, 0.16), 0.88, 0.0)
	var trousers := _mat(Color(0.32, 0.28, 0.23), 0.88, 0.0)
	var belt := _mat(Color(0.16, 0.12, 0.09), 0.55, 0.12)
	var boots := _mat(Color(0.21, 0.16, 0.12), 0.65, 0.06)

	_pelvis = Node3D.new()
	_pelvis.position = Vector3(0.0, 0.94, 0.0)
	root.add_child(_pelvis)

	# Pelvis & utility belt
	_pelvis.add_child(_box(Vector3(0.33, 0.16, 0.21), Vector3(0.0, 0.0, 0.0), trousers))
	_pelvis.add_child(_box(Vector3(0.35, 0.055, 0.225), Vector3(0.0, 0.07, 0.0), belt))

	# Upper torso / spine
	_spine = Node3D.new()
	_spine.position = Vector3(0.0, 0.08, 0.0)
	_pelvis.add_child(_spine)

	# Inner shirt & layered open field jacket
	_spine.add_child(_box(Vector3(0.34, 0.46, 0.20), Vector3(0.0, 0.24, 0.0), shirt))
	_spine.add_child(_box(Vector3(0.14, 0.47, 0.23), Vector3(-0.12, 0.24, 0.0), jacket))
	_spine.add_child(_box(Vector3(0.14, 0.47, 0.23), Vector3(0.12, 0.24, 0.0), jacket))
	_spine.add_child(_box(Vector3(0.38, 0.47, 0.12), Vector3(0.0, 0.24, 0.06), jacket))
	# Broad shoulders + collar + Rajasthani terracotta neck scarf
	_spine.add_child(_capsule(0.11, 0.46, Vector3(0.0, 0.44, 0.0), Vector3(0.0, 0.0, PI * 0.5), jacket))
	_spine.add_child(_cylinder(0.105, 0.12, 0.085, Vector3(0.0, 0.49, 0.0), scarf))

	# Neck & sculpted head facing -Z (forward direction of CharacterBody3D visual_root)
	_head_pivot = Node3D.new()
	_head_pivot.position = Vector3(0.0, 0.52, 0.0)
	_spine.add_child(_head_pivot)

	_head_pivot.add_child(_cylinder(0.052, 0.06, 0.10, Vector3(0.0, 0.04, 0.0), skin))
	_head_pivot.add_child(_capsule(0.105, 0.245, Vector3(0.0, 0.17, -0.005), Vector3.ZERO, skin))
	# Hair cap & tapered back hair
	_head_pivot.add_child(_sphere(0.112, Vector3(0.0, 0.225, 0.012), Vector3(1.0, 0.78, 1.04), hair))
	_head_pivot.add_child(_box(Vector3(0.18, 0.09, 0.10), Vector3(0.0, 0.17, 0.068), hair))
	# Facial features (brow ridge, eyes, nose bridge, subtle stubble jawline)
	_head_pivot.add_child(_box(Vector3(0.036, 0.012, 0.014), Vector3(-0.038, 0.195, -0.102), hair))
	_head_pivot.add_child(_box(Vector3(0.036, 0.012, 0.014), Vector3(0.038, 0.195, -0.102), hair))
	_head_pivot.add_child(_box(Vector3(0.022, 0.016, 0.012), Vector3(-0.038, 0.176, -0.101), eye_col))
	_head_pivot.add_child(_box(Vector3(0.022, 0.016, 0.012), Vector3(0.038, 0.176, -0.101), eye_col))
	_head_pivot.add_child(_box(Vector3(0.024, 0.042, 0.032), Vector3(0.0, 0.155, -0.108), skin))

	# Articulated Arms (Upper Arm -> Elbow -> Forearm + Hand)
	var l_arm_nodes: Array[Node3D] = _build_arm(_spine, -0.245, jacket, skin)
	_l_shoulder = l_arm_nodes[0]
	_l_elbow = l_arm_nodes[1]

	var r_arm_nodes: Array[Node3D] = _build_arm(_spine, 0.245, jacket, skin)
	_r_shoulder = r_arm_nodes[0]
	_r_elbow = r_arm_nodes[1]

	# Articulated Legs (Hip -> Thigh -> Knee -> Shin + Boot)
	var l_leg_nodes: Array[Node3D] = _build_leg(_pelvis, -0.105, trousers, boots)
	_l_hip = l_leg_nodes[0]
	_l_knee = l_leg_nodes[1]

	var r_leg_nodes: Array[Node3D] = _build_leg(_pelvis, 0.105, trousers, boots)
	_r_hip = r_leg_nodes[0]
	_r_knee = r_leg_nodes[1]


func _build_arm(parent: Node3D, x_offset: float, sleeve_mat: Material, skin_mat: Material) -> Array[Node3D]:
	var shoulder := Node3D.new()
	shoulder.position = Vector3(x_offset, 0.43, 0.0)
	parent.add_child(shoulder)
	shoulder.add_child(_capsule(0.056, 0.30, Vector3(0.0, -0.13, 0.0), Vector3.ZERO, sleeve_mat))

	var elbow := Node3D.new()
	elbow.position = Vector3(0.0, -0.27, 0.0)
	shoulder.add_child(elbow)
	elbow.add_child(_capsule(0.046, 0.27, Vector3(0.0, -0.12, 0.0), Vector3.ZERO, sleeve_mat))
	elbow.add_child(_box(Vector3(0.062, 0.095, 0.078), Vector3(0.0, -0.27, -0.01), skin_mat))
	return [shoulder, elbow]


func _build_leg(parent: Node3D, x_offset: float, pants_mat: Material, boot_mat: Material) -> Array[Node3D]:
	var hip := Node3D.new()
	hip.position = Vector3(x_offset, -0.04, 0.0)
	parent.add_child(hip)
	hip.add_child(_capsule(0.078, 0.44, Vector3(0.0, -0.20, 0.0), Vector3.ZERO, pants_mat))

	var knee := Node3D.new()
	knee.position = Vector3(0.0, -0.43, 0.0)
	hip.add_child(knee)
	knee.add_child(_capsule(0.062, 0.42, Vector3(0.0, -0.19, 0.0), Vector3.ZERO, pants_mat))
	# Desert tactical boot
	knee.add_child(_box(Vector3(0.11, 0.11, 0.24), Vector3(0.0, -0.42, -0.045), boot_mat))
	return [hip, knee]


func _mat(col: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


func _box(sz: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = sz
	mi.mesh = m
	mi.position = pos
	mi.material_override = mat
	return mi


func _capsule(radius: float, height: float, pos: Vector3, rot: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 10
	m.rings = 4
	mi.mesh = m
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	return mi


func _cylinder(top_r: float, bot_r: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = top_r
	m.bottom_radius = bot_r
	m.height = h
	m.radial_segments = 10
	mi.mesh = m
	mi.position = pos
	mi.material_override = mat
	return mi


func _sphere(radius: float, pos: Vector3, scl: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 10
	m.rings = 6
	mi.mesh = m
	mi.position = pos
	mi.scale = scl
	mi.material_override = mat
	return mi
