extends RefCounted

## Builds multi-part procedural 3D vehicle bodies and spinning wheel assemblies for 5 Barmer archetypes.
## Automatically loads external high-poly GLB models if placed at:
##   res://assets/models/vehicles/<archetype_key>.glb

const ARCHETYPE_KEYS: Dictionary = {
	0: "marwar_4x4",
	1: "city_sedan",
	2: "utility_pickup",
	3: "barmer_auto",
	4: "cargo_truck",
}

static var _shared_mats: Dictionary = {}


static func get_spec(archetype: int) -> Dictionary:
	match archetype:
		0: # MARWAR 4X4 SUV (Thar-inspired desert off-roader, AWD)
			return {
				"name": "MARWAR 4X4",
				"mass": 1760.0,
				"com_offset": Vector3(0.0, 0.28, 0.10),
				"collider_size": Vector3(1.88, 1.48, 4.10),
				"collider_y": 0.98,
				"wheel_radius": 0.41,
				"wheel_width": 0.27,
				"wheel_track": 0.86,
				"front_z": 1.32,
				"rear_z": -1.32,
				"wheel_y": 0.46,
				"rest_length": 0.24,
				"travel": 0.30,
				"stiffness": 34.0,
				"damping_comp": 2.8,
				"damping_relax": 3.4,
				"max_force": 18000.0,
				"friction_slip": 2.95,
				"roll_influence": 0.14,
				"engine_force": 5400.0,
				"max_speed_kmh": 135.0,
				"brake_force": 92.0,
				"drive_mode": "AWD",
				"max_steer_deg": 33.0,
			}
		1: # CITY SEDAN (Barmer urban car / taxi, FWD)
			return {
				"name": "CITY SEDAN",
				"mass": 1160.0,
				"com_offset": Vector3(0.0, 0.22, 0.14),
				"collider_size": Vector3(1.76, 1.18, 4.25),
				"collider_y": 0.82,
				"wheel_radius": 0.34,
				"wheel_width": 0.22,
				"wheel_track": 0.80,
				"front_z": 1.36,
				"rear_z": -1.30,
				"wheel_y": 0.38,
				"rest_length": 0.18,
				"travel": 0.20,
				"stiffness": 38.0,
				"damping_comp": 3.0,
				"damping_relax": 3.6,
				"max_force": 13500.0,
				"friction_slip": 3.10,
				"roll_influence": 0.11,
				"engine_force": 3850.0,
				"max_speed_kmh": 148.0,
				"brake_force": 78.0,
				"drive_mode": "FWD",
				"max_steer_deg": 35.0,
			}
		2: # UTILITY PICKUP (Rajasthan highway pickup, RWD)
			return {
				"name": "DESERT PICKUP",
				"mass": 1980.0,
				"com_offset": Vector3(0.0, 0.30, 0.08),
				"collider_size": Vector3(1.92, 1.46, 4.75),
				"collider_y": 0.98,
				"wheel_radius": 0.40,
				"wheel_width": 0.26,
				"wheel_track": 0.88,
				"front_z": 1.56,
				"rear_z": -1.48,
				"wheel_y": 0.44,
				"rest_length": 0.22,
				"travel": 0.26,
				"stiffness": 42.0,
				"damping_comp": 3.2,
				"damping_relax": 3.9,
				"max_force": 21000.0,
				"friction_slip": 2.85,
				"roll_influence": 0.15,
				"engine_force": 5900.0,
				"max_speed_kmh": 124.0,
				"brake_force": 102.0,
				"drive_mode": "RWD",
				"max_steer_deg": 32.0,
			}
		3: # BARMER AUTO-RICKSHAW (Compact Rajasthan city auto)
			return {
				"name": "BARMER AUTO",
				"mass": 540.0,
				"com_offset": Vector3(0.0, 0.22, -0.05),
				"collider_size": Vector3(1.36, 1.44, 2.68),
				"collider_y": 0.92,
				"wheel_radius": 0.27,
				"wheel_width": 0.15,
				"wheel_track": 0.58,
				"front_z": 0.94,
				"rear_z": -0.88,
				"wheel_y": 0.31,
				"rest_length": 0.15,
				"travel": 0.18,
				"stiffness": 34.0,
				"damping_comp": 2.5,
				"damping_relax": 3.1,
				"max_force": 7200.0,
				"friction_slip": 3.25,
				"roll_influence": 0.08,
				"engine_force": 1950.0,
				"max_speed_kmh": 68.0,
				"brake_force": 48.0,
				"drive_mode": "RWD",
				"max_steer_deg": 38.0,
			}
		_: # NH-68 CARGO TRUCK (Heavy Indian highway carrier, RWD)
			return {
				"name": "NH-68 TRUCK",
				"mass": 4650.0,
				"com_offset": Vector3(0.0, 0.45, 0.0),
				"collider_size": Vector3(2.38, 2.58, 6.90),
				"collider_y": 1.62,
				"wheel_radius": 0.52,
				"wheel_width": 0.34,
				"wheel_track": 1.06,
				"front_z": 2.35,
				"rear_z": -2.15,
				"wheel_y": 0.58,
				"rest_length": 0.24,
				"travel": 0.26,
				"stiffness": 66.0,
				"damping_comp": 5.0,
				"damping_relax": 6.2,
				"max_force": 46000.0,
				"friction_slip": 2.75,
				"roll_influence": 0.12,
				"engine_force": 12200.0,
				"max_speed_kmh": 92.0,
				"brake_force": 210.0,
				"drive_mode": "RWD",
				"max_steer_deg": 28.0,
			}


static func build_chassis(body_root: Node3D, archetype: int, paint_color: Color) -> Dictionary:
	_ensure_shared_materials()

	# Optional external high-poly GLB override hook
	var key: String = String(ARCHETYPE_KEYS.get(archetype, "city_sedan"))
	var ext_path: String = "res://assets/models/vehicles/%s.glb" % key
	if ResourceLoader.exists(ext_path):
		var packed := load(ext_path) as PackedScene
		if packed != null:
			body_root.add_child(packed.instantiate())
			return {"headlight_mat": null, "brakelight_mat": null}

	var paint_mat := StandardMaterial3D.new()
	paint_mat.albedo_color = paint_color
	paint_mat.roughness = 0.26
	paint_mat.metallic = 0.48
	paint_mat.clearcoat_enabled = true
	paint_mat.clearcoat = 0.65
	paint_mat.clearcoat_roughness = 0.18

	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.95, 0.94, 0.88)
	head_mat.roughness = 0.12
	head_mat.emission_enabled = true
	head_mat.emission = Color(1.0, 0.94, 0.80)
	head_mat.emission_energy_multiplier = 0.25

	var brake_mat := StandardMaterial3D.new()
	brake_mat.albedo_color = Color(0.55, 0.06, 0.05)
	brake_mat.roughness = 0.18
	brake_mat.emission_enabled = true
	brake_mat.emission = Color(1.0, 0.12, 0.08)
	brake_mat.emission_energy_multiplier = 0.20

	var trim: Material = _shared_mats["trim_dark"]
	var chrome: Material = _shared_mats["chrome"]
	var glass: Material = _shared_mats["glass"]
	var auto_yellow: Material = _shared_mats["auto_yellow"]
	var cargo_wood: Material = _shared_mats["cargo_wood"]

	# Forward direction for VehicleBody3D is +Z
	match archetype:
		0: # MARWAR 4X4 SUV
			_add_box(body_root, Vector3(1.82, 0.56, 3.92), Vector3(0.0, 0.72, 0.0), paint_mat)
			_add_box(body_root, Vector3(1.74, 0.44, 1.38), Vector3(0.0, 1.06, 1.18), paint_mat)
			_add_box(body_root, Vector3(1.74, 0.82, 2.24), Vector3(0.0, 1.36, -0.58), trim)
			_add_box(body_root, Vector3(1.56, 0.56, 0.08), Vector3(0.0, 1.38, 0.56), glass, Vector3(-0.22, 0.0, 0.0))
			_add_box(body_root, Vector3(1.78, 0.48, 1.72), Vector3(0.0, 1.38, -0.62), glass)
			_add_box(body_root, Vector3(1.94, 0.22, 0.30), Vector3(0.0, 0.56, 2.02), trim)
			_add_box(body_root, Vector3(1.94, 0.22, 0.28), Vector3(0.0, 0.56, -2.02), trim)
			_add_box(body_root, Vector3(1.02, 0.34, 0.08), Vector3(0.0, 0.96, 1.98), trim)
			# Rear-mounted spare desert tire
			_add_cyl(body_root, 0.38, 0.22, Vector3(0.0, 1.02, -2.06), Vector3(PI * 0.5, 0.0, 0.0), _shared_mats["tire"])
			# Headlights & tail lights
			_add_box(body_root, Vector3(0.28, 0.22, 0.08), Vector3(0.68, 0.98, 1.96), head_mat)
			_add_box(body_root, Vector3(0.28, 0.22, 0.08), Vector3(-0.68, 0.98, 1.96), head_mat)
			_add_box(body_root, Vector3(0.24, 0.34, 0.08), Vector3(0.76, 0.88, -1.98), brake_mat)
			_add_box(body_root, Vector3(0.24, 0.34, 0.08), Vector3(-0.76, 0.88, -1.98), brake_mat)

		1: # CITY SEDAN
			_add_box(body_root, Vector3(1.74, 0.50, 4.18), Vector3(0.0, 0.60, 0.0), paint_mat)
			_add_box(body_root, Vector3(1.66, 0.24, 1.32), Vector3(0.0, 0.88, 1.32), paint_mat, Vector3(0.08, 0.0, 0.0))
			_add_box(body_root, Vector3(1.52, 0.56, 1.92), Vector3(0.0, 1.12, -0.10), paint_mat)
			_add_box(body_root, Vector3(1.42, 0.44, 0.08), Vector3(0.0, 1.12, 0.88), glass, Vector3(-0.48, 0.0, 0.0))
			_add_box(body_root, Vector3(1.42, 0.44, 0.08), Vector3(0.0, 1.12, -1.08), glass, Vector3(0.45, 0.0, 0.0))
			_add_box(body_root, Vector3(1.56, 0.38, 1.48), Vector3(0.0, 1.12, -0.10), glass)
			_add_box(body_root, Vector3(1.78, 0.22, 0.22), Vector3(0.0, 0.44, 2.10), trim)
			_add_box(body_root, Vector3(1.78, 0.22, 0.22), Vector3(0.0, 0.44, -2.10), trim)
			_add_box(body_root, Vector3(0.92, 0.20, 0.08), Vector3(0.0, 0.66, 2.11), chrome)
			_add_box(body_root, Vector3(0.34, 0.18, 0.08), Vector3(0.64, 0.72, 2.10), head_mat)
			_add_box(body_root, Vector3(0.34, 0.18, 0.08), Vector3(-0.64, 0.72, 2.10), head_mat)
			_add_box(body_root, Vector3(0.38, 0.18, 0.08), Vector3(0.62, 0.72, -2.10), brake_mat)
			_add_box(body_root, Vector3(0.38, 0.18, 0.08), Vector3(-0.62, 0.72, -2.10), brake_mat)

		2: # DESERT UTILITY PICKUP
			_add_box(body_root, Vector3(1.88, 0.58, 4.66), Vector3(0.0, 0.72, 0.0), paint_mat)
			_add_box(body_root, Vector3(1.80, 0.84, 1.72), Vector3(0.0, 1.38, 0.32), paint_mat)
			_add_box(body_root, Vector3(1.66, 0.58, 0.08), Vector3(0.0, 1.42, 1.20), glass, Vector3(-0.24, 0.0, 0.0))
			_add_box(body_root, Vector3(1.84, 0.50, 1.22), Vector3(0.0, 1.40, 0.30), glass)
			# Open rear utility bed rails
			_add_box(body_root, Vector3(0.14, 0.48, 2.05), Vector3(0.86, 1.18, -1.32), paint_mat)
			_add_box(body_root, Vector3(0.14, 0.48, 2.05), Vector3(-0.86, 1.18, -1.32), paint_mat)
			_add_box(body_root, Vector3(1.84, 0.48, 0.14), Vector3(0.0, 1.18, -2.28), paint_mat)
			_add_box(body_root, Vector3(1.64, 0.08, 1.95), Vector3(0.0, 0.96, -1.32), trim)
			_add_box(body_root, Vector3(1.94, 0.24, 0.28), Vector3(0.0, 0.54, 2.36), trim)
			_add_box(body_root, Vector3(1.06, 0.32, 0.08), Vector3(0.0, 0.90, 2.34), chrome)
			_add_box(body_root, Vector3(0.32, 0.22, 0.08), Vector3(0.70, 0.92, 2.34), head_mat)
			_add_box(body_root, Vector3(0.32, 0.22, 0.08), Vector3(-0.70, 0.92, 2.34), head_mat)
			_add_box(body_root, Vector3(0.24, 0.34, 0.08), Vector3(0.78, 0.90, -2.35), brake_mat)
			_add_box(body_root, Vector3(0.24, 0.34, 0.08), Vector3(-0.78, 0.90, -2.35), brake_mat)

		3: # BARMER AUTO-RICKSHAW (Iconic green body + yellow roof canopy)
			_add_box(body_root, Vector3(1.30, 0.62, 2.42), Vector3(0.0, 0.58, -0.05), paint_mat)
			_add_box(body_root, Vector3(0.96, 0.56, 0.68), Vector3(0.0, 0.62, 1.06), paint_mat)
			# Soft yellow canvas canopy + open passenger sides
			_add_box(body_root, Vector3(1.34, 0.28, 2.24), Vector3(0.0, 1.54, -0.10), auto_yellow)
			_add_box(body_root, Vector3(1.24, 0.72, 0.16), Vector3(0.0, 1.18, -1.16), auto_yellow)
			_add_box(body_root, Vector3(0.92, 0.54, 0.08), Vector3(0.0, 1.18, 0.94), glass, Vector3(-0.18, 0.0, 0.0))
			for px: float in [-0.60, 0.60]:
				_add_box(body_root, Vector3(0.08, 0.74, 0.08), Vector3(px, 1.18, 0.76), trim)
				_add_box(body_root, Vector3(0.08, 0.74, 0.08), Vector3(px, 1.18, -0.20), trim)
			_add_box(body_root, Vector3(0.24, 0.20, 0.08), Vector3(0.0, 0.68, 1.42), head_mat)
			_add_box(body_root, Vector3(0.18, 0.16, 0.08), Vector3(0.46, 0.58, -1.27), brake_mat)
			_add_box(body_root, Vector3(0.18, 0.16, 0.08), Vector3(-0.46, 0.58, -1.27), brake_mat)

		_: # NH-68 CARGO TRUCK (Classic Indian painted cab + wooden cargo carrier)
			_add_box(body_root, Vector3(2.26, 0.42, 6.72), Vector3(0.0, 0.72, 0.0), trim)
			# Forward cab
			_add_box(body_root, Vector3(2.24, 1.62, 2.02), Vector3(0.0, 1.68, 2.28), paint_mat)
			_add_box(body_root, Vector3(2.04, 0.68, 0.10), Vector3(0.0, 1.98, 3.31), glass, Vector3(-0.08, 0.0, 0.0))
			_add_box(body_root, Vector3(2.30, 0.34, 0.30), Vector3(0.0, 0.72, 3.38), chrome)
			# Timber & saffron-accent cargo box
			_add_box(body_root, Vector3(2.34, 1.88, 4.42), Vector3(0.0, 1.88, -1.08), cargo_wood)
			_add_box(body_root, Vector3(2.38, 0.24, 4.46), Vector3(0.0, 2.86, -1.08), auto_yellow)
			_add_box(body_root, Vector3(0.36, 0.24, 0.08), Vector3(0.84, 1.08, 3.32), head_mat)
			_add_box(body_root, Vector3(0.36, 0.24, 0.08), Vector3(-0.84, 1.08, 3.32), head_mat)
			_add_box(body_root, Vector3(0.38, 0.22, 0.08), Vector3(0.86, 0.92, -3.38), brake_mat)
			_add_box(body_root, Vector3(0.38, 0.22, 0.08), Vector3(-0.86, 0.92, -3.38), brake_mat)

	return {
		"headlight_mat": head_mat,
		"brakelight_mat": brake_mat,
	}


static func build_wheel_mesh(wheel_node: VehicleWheel3D, radius: float, width: float) -> void:
	_ensure_shared_materials()

	# Outer rubber tire (Cylinder rotated 90 deg around Z aligns axle with local X)
	var tire_mi := MeshInstance3D.new()
	var tire_mesh := CylinderMesh.new()
	tire_mesh.top_radius = radius
	tire_mesh.bottom_radius = radius
	tire_mesh.height = width
	tire_mesh.radial_segments = 16
	tire_mi.mesh = tire_mesh
	tire_mi.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	tire_mi.material_override = _shared_mats["tire"]
	wheel_node.add_child(tire_mi)

	# Inner alloy rim
	var rim_mi := MeshInstance3D.new()
	var rim_mesh := CylinderMesh.new()
	rim_mesh.top_radius = radius * 0.62
	rim_mesh.bottom_radius = radius * 0.62
	rim_mesh.height = width + 0.02
	rim_mesh.radial_segments = 12
	rim_mi.mesh = rim_mesh
	rim_mi.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	rim_mi.material_override = _shared_mats["rim"]
	wheel_node.add_child(rim_mi)

	# Cross-spoke bar so wheel spin is unmistakably visible
	var spoke_mi := MeshInstance3D.new()
	var spoke_mesh := BoxMesh.new()
	spoke_mesh.size = Vector3(width + 0.035, radius * 1.12, 0.06)
	spoke_mi.mesh = spoke_mesh
	spoke_mi.material_override = _shared_mats["trim_dark"]
	wheel_node.add_child(spoke_mi)


static func _ensure_shared_materials() -> void:
	if not _shared_mats.is_empty():
		return

	var tire := StandardMaterial3D.new()
	tire.albedo_color = Color(0.11, 0.11, 0.12)
	tire.roughness = 0.88
	_shared_mats["tire"] = tire

	var rim := StandardMaterial3D.new()
	rim.albedo_color = Color(0.76, 0.78, 0.80)
	rim.metallic = 0.82
	rim.roughness = 0.24
	_shared_mats["rim"] = rim

	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.16, 0.16, 0.17)
	trim.roughness = 0.72
	trim.metallic = 0.15
	_shared_mats["trim_dark"] = trim

	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = Color(0.84, 0.85, 0.86)
	chrome.metallic = 0.90
	chrome.roughness = 0.16
	_shared_mats["chrome"] = chrome

	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.08, 0.11, 0.14)
	glass.metallic = 0.45
	glass.roughness = 0.08
	_shared_mats["glass"] = glass

	var auto_yellow := StandardMaterial3D.new()
	auto_yellow.albedo_color = Color(0.92, 0.72, 0.14)
	auto_yellow.roughness = 0.74
	_shared_mats["auto_yellow"] = auto_yellow

	var cargo_wood := StandardMaterial3D.new()
	cargo_wood.albedo_color = Color(0.54, 0.31, 0.17)
	cargo_wood.roughness = 0.84
	_shared_mats["cargo_wood"] = cargo_wood


static func _add_box(parent: Node3D, sz: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = sz
	mi.mesh = m
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	parent.add_child(mi)


static func _add_cyl(parent: Node3D, radius: float, height: float, pos: Vector3, rot: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 14
	mi.mesh = m
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	parent.add_child(mi)
