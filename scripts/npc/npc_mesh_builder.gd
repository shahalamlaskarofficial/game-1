extends RefCounted

## Shared-Resource Articulated Rajasthani NPC Rig Builder.
## - Caches every Mesh and StandardMaterial3D statically so 28 active NPCs share
##   a single tiny VRAM/RAM footprint (< 0.3 MB total).
## - Supports automatic drop-in rigged GLB overrides at:
##     res://assets/models/npcs/<role_key>.glb

const ROLE_KEYS: Dictionary = {
	0: "resident",
	1: "shopkeeper",
	2: "commuter",
	3: "worker",
	4: "elder",
}

static var _mesh_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}


static func build_rig(root: Node3D, role: int, rng: RandomNumberGenerator) -> Dictionary:
	_ensure_shared_cache()

	# Optional high-poly GLB drop-in override
	var r_key: String = String(ROLE_KEYS.get(role, "resident"))
	var ext_path: String = "res://assets/models/npcs/%s.glb" % r_key
	if ResourceLoader.exists(ext_path):
		var packed := load(ext_path) as PackedScene
		if packed != null:
			root.add_child(packed.instantiate())
			return {"external": true}

	# Select role-appropriate Rajasthani palette from cached materials
	var skin_keys: Array[String] = ["skin_a", "skin_b", "skin_c"]
	var skin_mat: Material = _mat_cache[skin_keys[rng.randi() % skin_keys.size()]]
	var hair_mat: Material = _mat_cache["hair_grey"] if role == 4 else _mat_cache["hair_dark"]
	var eye_mat: Material = _mat_cache["eye"]
	var shoe_mat: Material = _mat_cache["footwear"]

	var top_mat: Material
	var bottom_mat: Material
	var has_turban: bool = false
	var turban_mat: Material = _mat_cache["turban_saffron"]
	var has_scarf: bool = false
	var scarf_mat: Material = _mat_cache["turban_crimson"]

	match role:
		1: # Bazaar Shopkeeper
			var shop_tops: Array[String] = ["kurta_cream", "kurta_ochre", "kurta_sky"]
			top_mat = _mat_cache[shop_tops[rng.randi() % shop_tops.size()]]
			bottom_mat = _mat_cache["pants_cream"]
			has_turban = rng.randf() < 0.45
			turban_mat = _mat_cache["turban_saffron"] if rng.randf() < 0.5 else _mat_cache["turban_crimson"]
			has_scarf = not has_turban
		2: # Station / Bus Commuter
			var com_tops: Array[String] = ["shirt_indigo", "shirt_teal", "kurta_cream", "shirt_maroon"]
			top_mat = _mat_cache[com_tops[rng.randi() % com_tops.size()]]
			bottom_mat = _mat_cache["pants_slate"] if rng.randf() < 0.65 else _mat_cache["pants_khaki"]
		3: # Transport / Railway Worker
			top_mat = _mat_cache["shirt_work_blue"] if rng.randf() < 0.55 else _mat_cache["shirt_work_rust"]
			bottom_mat = _mat_cache["pants_khaki"]
			has_scarf = true
			scarf_mat = _mat_cache["turban_saffron"]
		4: # Desert Elder (Traditional White Kurta + Marwari Pagdi)
			top_mat = _mat_cache["kurta_white"]
			bottom_mat = _mat_cache["pants_cream"]
			has_turban = true
			turban_mat = _mat_cache["turban_crimson"] if rng.randf() < 0.55 else _mat_cache["turban_saffron"]
		_: # Barmer Resident
			var res_tops: Array[String] = ["kurta_cream", "kurta_ochre", "shirt_indigo", "shirt_maroon", "shirt_teal"]
			top_mat = _mat_cache[res_tops[rng.randi() % res_tops.size()]]
			bottom_mat = _mat_cache["pants_slate"] if rng.randf() < 0.5 else _mat_cache["pants_khaki"]
			has_turban = rng.randf() < 0.22
			turban_mat = _mat_cache["turban_saffron"]

	var height_scale: float = rng.randf_range(0.93, 1.05)
	root.scale = Vector3(height_scale, height_scale, height_scale)

	var pelvis := Node3D.new()
	pelvis.position = Vector3(0.0, 0.90, 0.0)
	root.add_child(pelvis)
	pelvis.add_child(_inst("pelvis_box", Vector3.ZERO, bottom_mat))

	var spine := Node3D.new()
	spine.position = Vector3(0.0, 0.08, 0.0)
	pelvis.add_child(spine)
	spine.add_child(_inst("torso_box", Vector3(0.0, 0.24, 0.0), top_mat))
	spine.add_child(_inst("kurta_skirt", Vector3(0.0, -0.02, 0.0), top_mat))
	if has_scarf:
		spine.add_child(_inst("scarf_ring", Vector3(0.0, 0.45, 0.0), scarf_mat))

	var head := Node3D.new()
	head.position = Vector3(0.0, 0.50, 0.0)
	spine.add_child(head)
	head.add_child(_inst("neck_cyl", Vector3(0.0, 0.04, 0.0), skin_mat))
	head.add_child(_inst("head_cap", Vector3(0.0, 0.165, 0.0), skin_mat))
	head.add_child(_inst("eye_box", Vector3(-0.036, 0.175, -0.098), eye_mat))
	head.add_child(_inst("eye_box", Vector3(0.036, 0.175, -0.098), eye_mat))

	if has_turban:
		# Traditional Marwari Pagdi turban wrap
		head.add_child(_inst("turban_wrap", Vector3(0.0, 0.255, 0.005), turban_mat))
		head.add_child(_inst("turban_tail", Vector3(0.05, 0.17, 0.085), turban_mat))
	else:
		head.add_child(_inst("hair_cap", Vector3(0.0, 0.22, 0.01), hair_mat))

	# Arms
	var l_arm := Node3D.new()
	l_arm.position = Vector3(-0.225, 0.42, 0.0)
	spine.add_child(l_arm)
	l_arm.add_child(_inst("arm_cap", Vector3(0.0, -0.22, 0.0), top_mat))
	l_arm.add_child(_inst("hand_box", Vector3(0.0, -0.47, 0.0), skin_mat))

	var r_arm := Node3D.new()
	r_arm.position = Vector3(0.225, 0.42, 0.0)
	spine.add_child(r_arm)
	r_arm.add_child(_inst("arm_cap", Vector3(0.0, -0.22, 0.0), top_mat))
	r_arm.add_child(_inst("hand_box", Vector3(0.0, -0.47, 0.0), skin_mat))

	# Legs
	var l_leg := Node3D.new()
	l_leg.position = Vector3(-0.098, -0.04, 0.0)
	pelvis.add_child(l_leg)
	l_leg.add_child(_inst("leg_cap", Vector3(0.0, -0.39, 0.0), bottom_mat))
	l_leg.add_child(_inst("foot_box", Vector3(0.0, -0.81, -0.04), shoe_mat))

	var r_leg := Node3D.new()
	r_leg.position = Vector3(0.098, -0.04, 0.0)
	pelvis.add_child(r_leg)
	r_leg.add_child(_inst("leg_cap", Vector3(0.0, -0.39, 0.0), bottom_mat))
	r_leg.add_child(_inst("foot_box", Vector3(0.0, -0.81, -0.04), shoe_mat))

	return {
		"external": false,
		"pelvis": pelvis,
		"spine": spine,
		"head": head,
		"l_arm": l_arm,
		"r_arm": r_arm,
		"l_leg": l_leg,
		"r_leg": r_leg,
	}


static func _inst(mesh_key: String, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh_cache[mesh_key] as Mesh
	mi.position = pos
	mi.material_override = mat
	mi.visibility_range_end = 135.0
	return mi


static func _ensure_shared_cache() -> void:
	if not _mesh_cache.is_empty():
		return

	_mesh_cache["pelvis_box"] = _make_box(Vector3(0.31, 0.15, 0.20))
	_mesh_cache["torso_box"] = _make_box(Vector3(0.35, 0.46, 0.21))
	_mesh_cache["kurta_skirt"] = _make_box(Vector3(0.33, 0.18, 0.21))
	_mesh_cache["scarf_ring"] = _make_cyl(0.11, 0.125, 0.08)
	_mesh_cache["neck_cyl"] = _make_cyl(0.048, 0.054, 0.09)
	_mesh_cache["head_cap"] = _make_cap(0.10, 0.235)
	_mesh_cache["eye_box"] = _make_box(Vector3(0.02, 0.015, 0.012))
	_mesh_cache["hair_cap"] = _make_sph(0.106, 0.16)
	_mesh_cache["turban_wrap"] = _make_cyl(0.128, 0.115, 0.11)
	_mesh_cache["turban_tail"] = _make_box(Vector3(0.055, 0.14, 0.04))
	_mesh_cache["arm_cap"] = _make_cap(0.052, 0.48)
	_mesh_cache["hand_box"] = _make_box(Vector3(0.06, 0.085, 0.07))
	_mesh_cache["leg_cap"] = _make_cap(0.068, 0.78)
	_mesh_cache["foot_box"] = _make_box(Vector3(0.10, 0.08, 0.22))

	_mat_cache["skin_a"] = _make_mat(Color(0.66, 0.48, 0.36), 0.72)
	_mat_cache["skin_b"] = _make_mat(Color(0.56, 0.39, 0.29), 0.72)
	_mat_cache["skin_c"] = _make_mat(Color(0.72, 0.54, 0.41), 0.70)
	_mat_cache["hair_dark"] = _make_mat(Color(0.09, 0.08, 0.08), 0.80)
	_mat_cache["hair_grey"] = _make_mat(Color(0.68, 0.67, 0.65), 0.82)
	_mat_cache["eye"] = _make_mat(Color(0.06, 0.06, 0.06), 0.20)
	_mat_cache["footwear"] = _make_mat(Color(0.24, 0.18, 0.13), 0.76)

	_mat_cache["kurta_white"] = _make_mat(Color(0.91, 0.89, 0.84), 0.88)
	_mat_cache["kurta_cream"] = _make_mat(Color(0.86, 0.79, 0.66), 0.88)
	_mat_cache["kurta_ochre"] = _make_mat(Color(0.83, 0.61, 0.30), 0.86)
	_mat_cache["kurta_sky"] = _make_mat(Color(0.46, 0.62, 0.76), 0.85)
	_mat_cache["shirt_indigo"] = _make_mat(Color(0.19, 0.29, 0.47), 0.84)
	_mat_cache["shirt_teal"] = _make_mat(Color(0.20, 0.44, 0.44), 0.84)
	_mat_cache["shirt_maroon"] = _make_mat(Color(0.55, 0.20, 0.21), 0.85)
	_mat_cache["shirt_work_blue"] = _make_mat(Color(0.22, 0.36, 0.56), 0.82)
	_mat_cache["shirt_work_rust"] = _make_mat(Color(0.69, 0.33, 0.21), 0.84)

	_mat_cache["pants_cream"] = _make_mat(Color(0.84, 0.81, 0.74), 0.90)
	_mat_cache["pants_khaki"] = _make_mat(Color(0.49, 0.43, 0.34), 0.88)
	_mat_cache["pants_slate"] = _make_mat(Color(0.24, 0.26, 0.30), 0.86)

	_mat_cache["turban_saffron"] = _make_mat(Color(0.90, 0.52, 0.14), 0.88)
	_mat_cache["turban_crimson"] = _make_mat(Color(0.76, 0.17, 0.16), 0.88)


static func _make_box(sz: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = sz
	return m


static func _make_cap(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 8
	m.rings = 3
	return m


static func _make_cyl(top_r: float, bot_r: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top_r
	m.bottom_radius = bot_r
	m.height = h
	m.radial_segments = 8
	return m


static func _make_sph(r: float, h: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 8
	m.rings = 4
	return m


static func _make_mat(col: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	return m
