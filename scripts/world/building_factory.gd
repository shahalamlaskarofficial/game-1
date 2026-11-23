extends RefCounted

## Phase 3 High-Detail Modular Rajasthani Architecture Builder + Occlusion Culling Generator.
## - Adds carved chhajja stone eaves, window sills & frames, jharokha corbels,
##   rooftop AC/solar/water tanks, warm night-lit windows, and bespoke Barmer landmarks:
##   Ghanta Ghar Clock Tower, Barmer Railway Station (BME), Barmer Fort & Garh Mandir,
##   and RSRTC Bus Stand.
## - Automatically generates BoxOccluder3D occlusion volumes for major buildings.
## - Checks res://assets/models/landmarks/<name>.glb for optional external high-poly overrides.

var _buckets: Dictionary = {}
var _colliders: Array[Dictionary] = []
var _occluders: Array[Dictionary] = []


func reset() -> void:
	_buckets.clear()
	_colliders.clear()
	_occluders.clear()


func add_box(
	mat_key: String,
	center: Vector3,
	size: Vector3,
	rot_y: float = 0.0,
	with_collision: bool = true,
	uv_scale: float = 0.25,
	skip_bottom: bool = true,
	add_occluder: bool = false
) -> void:
	var st: SurfaceTool = _get_bucket(mat_key)
	_append_uv_box(st, center, size, rot_y, uv_scale, skip_bottom)
	if with_collision:
		_colliders.append({
			"pos": center,
			"size": size,
			"rot_y": rot_y,
		})
	if add_occluder and size.x >= 6.5 and size.y >= 4.5 and size.z >= 5.5:
		_occluders.append({
			"pos": center,
			"size": size * 0.94,
			"rot_y": rot_y,
		})


func build_clock_tower(origin: Vector3) -> void:
	# Iconic Barmer Ghanta Ghar at Ahinsa Circle with stepped plinth, arches & chhatri dome
	add_box("sandstone_dark", origin + Vector3(0.0, 0.45, 0.0), Vector3(8.6, 0.9, 8.6), 0.0, true, 0.22)
	add_box("sandstone", origin + Vector3(0.0, 1.35, 0.0), Vector3(6.8, 0.9, 6.8), 0.0, true, 0.22)
	add_box("sandstone", origin + Vector3(0.0, 5.2, 0.0), Vector3(4.8, 6.8, 4.8), 0.0, true, 0.25, true, true)

	# Decorative arched stone pilasters & chhajja overhang
	for px: float in [-2.45, 2.45]:
		add_box("sandstone_dark", origin + Vector3(px, 5.2, 0.0), Vector3(0.35, 6.6, 1.6), 0.0, false, 0.35)
		add_box("sandstone_dark", origin + Vector3(0.0, 5.2, px), Vector3(1.6, 6.6, 0.35), 0.0, false, 0.35)
	add_box("sandstone_dark", origin + Vector3(0.0, 8.8, 0.0), Vector3(5.8, 0.45, 5.8), 0.0, false, 0.25)

	# Upper clock chamber & 4 illuminated dials
	add_box("plaster_cream", origin + Vector3(0.0, 11.4, 0.0), Vector3(3.9, 4.8, 3.9), 0.0, true, 0.25)
	for side_v: Vector3 in [Vector3(0, 0, 1.98), Vector3(0, 0, -1.98), Vector3(1.98, 0, 0), Vector3(-1.98, 0, 0)]:
		var is_z: bool = absf(side_v.z) > 0.5
		var dial_sz := Vector3(2.0, 2.0, 0.14) if is_z else Vector3(0.14, 2.0, 2.0)
		var rim_sz := Vector3(2.3, 2.3, 0.08) if is_z else Vector3(0.08, 2.3, 2.3)
		add_box("sandstone_dark", origin + Vector3(0.0, 11.7, 0.0) + side_v * 0.98, rim_sz, 0.0, false, 0.4)
		add_box("window_lit", origin + Vector3(0.0, 11.7, 0.0) + side_v, dial_sz, 0.0, false, 0.5)

	# Chhatri pavilion cupola
	add_box("sandstone_dark", origin + Vector3(0.0, 14.05, 0.0), Vector3(4.9, 0.42, 4.9), 0.0, false, 0.25)
	for px: float in [-1.55, 1.55]:
		for pz: float in [-1.55, 1.55]:
			add_box("sandstone", origin + Vector3(px, 15.5, pz), Vector3(0.38, 2.6, 0.38), 0.0, false, 0.4)
	add_box("sandstone_dark", origin + Vector3(0.0, 17.05, 0.0), Vector3(4.5, 0.45, 4.5), 0.0, false, 0.25)
	add_box("sandstone", origin + Vector3(0.0, 18.0, 0.0), Vector3(3.0, 1.5, 3.0), 0.0, false, 0.3)
	add_box("sandstone_dark", origin + Vector3(0.0, 19.0, 0.0), Vector3(1.6, 0.75, 1.6), 0.0, false, 0.35)
	add_box("paint_amber", origin + Vector3(0.0, 19.9, 0.0), Vector3(0.28, 1.2, 0.28), 0.0, false, 0.5)


func build_barmer_railway_station(origin: Vector3) -> void:
	# Authentic Barmer Junction (BME) Rajasthani Heritage Terminal + Covered Platform
	# Main terminal facade facing west toward Station Road
	add_box("sandstone", origin + Vector3(0.0, 4.2, 0.0), Vector3(12.0, 8.4, 38.0), 0.0, true, 0.20, true, true)
	add_box("sandstone_dark", origin + Vector3(0.0, 8.75, 0.0), Vector3(12.8, 0.75, 38.8), 0.0, false, 0.22)

	# Central Rajputana gateway arch porch & chhatri turret
	add_box("plaster_cream", origin + Vector3(-7.0, 4.8, 0.0), Vector3(4.2, 9.6, 12.0), 0.0, true, 0.22)
	add_box("sandstone_dark", origin + Vector3(-7.0, 10.0, 0.0), Vector3(4.8, 0.85, 12.8), 0.0, false, 0.24)
	add_box("sandstone", origin + Vector3(-7.0, 11.4, 0.0), Vector3(3.4, 2.0, 5.2), 0.0, false, 0.26)
	add_box("awning_saffron", origin + Vector3(-9.2, 6.2, 0.0), Vector3(0.22, 1.15, 10.6), 0.0, false, 0.4)
	add_box("window_lit", origin + Vector3(-9.15, 2.2, 0.0), Vector3(0.2, 4.2, 6.4), 0.0, false, 0.5)

	# Facade recessed arched windows along terminal wings
	for wz: float in [-14.0, -9.5, 9.5, 14.0]:
		add_box("window_lit", origin + Vector3(-6.08, 2.4, wz), Vector3(0.18, 2.6, 2.2), 0.0, false, 0.5)
		add_box("sandstone_dark", origin + Vector3(-6.28, 3.85, wz), Vector3(0.65, 0.22, 2.7), 0.0, false, 0.35)
		add_box("window_dark", origin + Vector3(-6.08, 6.1, wz), Vector3(0.18, 2.0, 2.0), 0.0, false, 0.5)

	# Concrete Passenger Platform #1 (east of terminal) + corrugated steel canopy
	add_box("concrete", origin + Vector3(11.0, 0.55, 0.0), Vector3(10.0, 1.1, 68.0), 0.0, true, 0.18)
	add_box("paint_amber", origin + Vector3(15.7, 1.12, 0.0), Vector3(0.35, 0.02, 67.5), 0.0, false, 1.0)
	add_box("metal_roof", origin + Vector3(11.0, 5.4, 0.0), Vector3(8.6, 0.28, 56.0), 0.0, false, 0.22)
	for pz: float in [-24.0, -12.0, 0.0, 12.0, 24.0]:
		add_box("metal_blue", origin + Vector3(11.0, 3.2, pz), Vector3(0.32, 4.4, 0.32), 0.0, true, 0.4)
		add_box("lamp_glow", origin + Vector3(11.0, 5.15, pz), Vector3(1.2, 0.12, 0.25), 0.0, false, 0.5)

	# Dual Broad-Gauge Railway Tracks (ballast bed + sleepers + steel rails)
	add_box("desert_rock", origin + Vector3(19.2, 0.10, 0.0), Vector3(5.4, 0.20, 124.0), 0.0, false, 0.25)
	add_box("rail_steel", origin + Vector3(17.9, 0.24, 0.0), Vector3(0.14, 0.14, 124.0), 0.0, false, 0.5)
	add_box("rail_steel", origin + Vector3(19.58, 0.24, 0.0), Vector3(0.14, 0.14, 124.0), 0.0, false, 0.5)
	add_box("rail_steel", origin + Vector3(21.4, 0.24, 0.0), Vector3(0.14, 0.14, 124.0), 0.0, false, 0.5)
	add_box("rail_steel", origin + Vector3(23.08, 0.24, 0.0), Vector3(0.14, 0.14, 124.0), 0.0, false, 0.5)


func build_barmer_fort_complex(origin: Vector3) -> void:
	# Historic 16th-century Barmer Fort ramparts + Jogmaya Devi (Garh Mandir) hilltop temple
	# Massive perimeter bastion walls with northern/eastern entry gateway
	add_box("fort_stone", origin + Vector3(0.0, 3.4, -22.0), Vector3(44.0, 7.2, 2.8), 0.0, true, 0.18, true, true)
	add_box("fort_stone", origin + Vector3(-22.0, 3.4, 0.0), Vector3(2.8, 7.2, 44.0), 0.0, true, 0.18, true, true)
	add_box("fort_stone", origin + Vector3(0.0, 3.4, 22.0), Vector3(44.0, 7.2, 2.8), 0.0, true, 0.18, true, true)
	# East entrance wall with grand archway gap
	add_box("fort_stone", origin + Vector3(22.0, 3.4, -14.5), Vector3(2.8, 7.2, 15.0), 0.0, true, 0.18)
	add_box("fort_stone", origin + Vector3(22.0, 3.4, 14.5), Vector3(2.8, 7.2, 15.0), 0.0, true, 0.18)
	add_box("sandstone_dark", origin + Vector3(22.0, 6.4, 0.0), Vector3(3.4, 2.2, 14.2), 0.0, true, 0.20)

	# 4 Corner Watchtower Bastions with battlements
	for bx: float in [-22.5, 22.5]:
		for bz: float in [-22.5, 22.5]:
			add_box("fort_stone", origin + Vector3(bx, 4.8, bz), Vector3(6.8, 10.0, 6.8), 0.0, true, 0.20)
			add_box("sandstone_dark", origin + Vector3(bx, 10.1, bz), Vector3(7.4, 0.75, 7.4), 0.0, false, 0.24)

	# Crenellated merlons along north & south ramparts
	for mx: int in range(-18, 19, 6):
		add_box("sandstone_dark", origin + Vector3(float(mx), 7.5, -22.0), Vector3(2.4, 1.2, 1.2), 0.0, false, 0.3)
		add_box("sandstone_dark", origin + Vector3(float(mx), 7.5, 22.0), Vector3(2.4, 1.2, 1.2), 0.0, false, 0.3)

	# Inner Royal Palace Courtyard (Durbar Hall)
	add_box("sandstone", origin + Vector3(-9.5, 4.2, -9.5), Vector3(15.0, 8.4, 12.0), 0.0, true, 0.22, true, true)
	add_box("sandstone_dark", origin + Vector3(-9.5, 8.8, -9.5), Vector3(15.8, 0.85, 12.8), 0.0, false, 0.24)
	add_box("window_lit", origin + Vector3(-1.9, 2.5, -9.5), Vector3(0.2, 2.8, 4.2), 0.0, false, 0.45)

	# Garh Mandir (Jogmaya Devi Shrine) with stepped Rajasthani Nagara Shikhara Spire
	var shrine := origin + Vector3(-6.0, 0.0, 9.0)
	add_box("sandstone", shrine + Vector3(0.0, 0.8, 0.0), Vector3(11.0, 1.6, 11.0), 0.0, true, 0.22)
	add_box("plaster_cream", shrine + Vector3(0.0, 3.8, 0.0), Vector3(7.6, 4.8, 7.6), 0.0, true, 0.24)
	add_box("sandstone_dark", shrine + Vector3(0.0, 7.4, 0.0), Vector3(6.2, 2.4, 6.2), 0.0, false, 0.26)
	add_box("sandstone", shrine + Vector3(0.0, 9.6, 0.0), Vector3(4.5, 2.2, 4.5), 0.0, false, 0.28)
	add_box("sandstone_dark", shrine + Vector3(0.0, 11.5, 0.0), Vector3(2.8, 1.8, 2.8), 0.0, false, 0.30)
	add_box("paint_amber", shrine + Vector3(0.0, 13.0, 0.0), Vector3(0.9, 1.4, 0.9), 0.0, false, 0.4)
	add_box("awning_saffron", shrine + Vector3(0.0, 14.5, 0.0), Vector3(0.18, 2.4, 1.1), 0.0, false, 0.5)


func build_rsrtc_bus_stand(origin: Vector3) -> void:
	# Barmer RSRTC Roadways Bus Depot at Sindhari Circle (NH-25)
	add_box("concrete", origin + Vector3(0.0, 0.14, 0.0), Vector3(42.0, 0.28, 28.0), 0.0, true, 0.18)
	# Main terminal waiting hall
	add_box("plaster_cream", origin + Vector3(0.0, 2.6, -8.5), Vector3(32.0, 5.2, 8.2), 0.0, true, 0.20, true, true)
	add_box("awning_crimson", origin + Vector3(0.0, 5.4, -4.3), Vector3(32.2, 0.95, 0.24), 0.0, false, 0.35)
	# Cantilevered bus boarding bay roof
	add_box("metal_roof", origin + Vector3(0.0, 5.1, 1.8), Vector3(34.0, 0.32, 12.0), 0.0, false, 0.22)
	for bx: float in [-14.0, -7.0, 0.0, 7.0, 14.0]:
		add_box("concrete", origin + Vector3(bx, 2.5, 5.5), Vector3(0.55, 4.8, 0.55), 0.0, true, 0.35)
		add_box("window_lit", origin + Vector3(bx, 2.1, -4.35), Vector3(3.4, 2.3, 0.16), 0.0, false, 0.5)


func build_bazaar_shop(origin: Vector3, width: float, depth: float, floors: int, rot_y: float, rng: RandomNumberGenerator) -> void:
	var wall_mats: Array[String] = ["sandstone", "plaster_cream", "plaster_ochre", "plaster_terracotta"]
	var awning_mats: Array[String] = ["awning_crimson", "awning_indigo", "awning_saffron"]
	var wall_mat: String = wall_mats[rng.randi() % wall_mats.size()]
	var awning_mat: String = awning_mats[rng.randi() % awning_mats.size()]

	var floor_h: float = 3.55
	var total_h: float = float(floors) * floor_h

	# Main structure + occlusion volume
	add_box(wall_mat, origin + Vector3(0.0, total_h * 0.5, 0.0), Vector3(width, total_h, depth), rot_y, true, 0.22, true, true)
	# Stone plinth base
	add_box("sandstone_dark", origin + Vector3(0.0, 0.26, 0.0), Vector3(width + 0.18, 0.52, depth + 0.18), rot_y, false, 0.28)
	# Carved rooftop parapet cornice + corner finials
	add_box("sandstone_dark", origin + Vector3(0.0, total_h + 0.44, 0.0), Vector3(width + 0.38, 0.88, depth + 0.38), rot_y, false, 0.25)

	var front_z: float = depth * 0.5 + 0.06
	# Recessed ground-floor shopfront + side display pilasters
	add_box("window_lit", _xform(origin, Vector3(0.0, 1.48, front_z), rot_y), Vector3(width * 0.64, 2.55, 0.14), rot_y, false, 0.5)
	add_box("sandstone_dark", _xform(origin, Vector3(-width * 0.42, 1.5, front_z + 0.05), rot_y), Vector3(0.45, 3.0, 0.26), rot_y, false, 0.35)
	add_box("sandstone_dark", _xform(origin, Vector3(width * 0.42, 1.5, front_z + 0.05), rot_y), Vector3(0.45, 3.0, 0.26), rot_y, false, 0.35)

	# Commercial signboard fascia + projecting sun awning
	add_box(awning_mat, _xform(origin, Vector3(0.0, 3.28, front_z + 0.10), rot_y), Vector3(width * 0.90, 0.74, 0.22), rot_y, false, 0.4)
	add_box(awning_mat, _xform(origin, Vector3(0.0, 2.75, depth * 0.5 + 1.15), rot_y), Vector3(width * 0.92, 0.12, 2.2), rot_y, false, 0.4)

	# Upper floors: chhajja eaves, carved window sills, frames & lit/dark glass variety
	for f: int in range(1, floors):
		var floor_base: float = float(f) * floor_h
		var wy: float = floor_base + 1.85
		add_box("sandstone_dark", _xform(origin, Vector3(0.0, floor_base + 0.10, front_z + 0.38), rot_y), Vector3(width * 0.88, 0.20, 0.84), rot_y, false, 0.3)
		var win_count: int = maxi(2, int(width / 3.3))
		for w_i: int in range(win_count):
			var frac: float = (float(w_i) + 0.5) / float(win_count) - 0.5
			var wx: float = frac * (width - 1.5)
			var w_mat: String = "window_lit" if rng.randf() < 0.48 else "window_dark"
			add_box(w_mat, _xform(origin, Vector3(wx, wy, front_z), rot_y), Vector3(1.18, 1.48, 0.14), rot_y, false, 0.5)
			# Stone window lintel chhajja + bottom sill
			add_box("sandstone_dark", _xform(origin, Vector3(wx, wy + 0.84, front_z + 0.16), rot_y), Vector3(1.48, 0.16, 0.44), rot_y, false, 0.4)
			add_box("sandstone_dark", _xform(origin, Vector3(wx, wy - 0.80, front_z + 0.10), rot_y), Vector3(1.36, 0.12, 0.28), rot_y, false, 0.4)

	# Rooftop utility details (water tank + AC outdoor unit / solar panel)
	if rng.randf() < 0.72:
		var tx: float = rng.randf_range(-width * 0.24, width * 0.24)
		var tz: float = rng.randf_range(-depth * 0.20, depth * 0.20)
		add_box("concrete", _xform(origin, Vector3(tx, total_h + 1.0, tz), rot_y), Vector3(1.25, 0.55, 1.25), rot_y, false, 0.4)
		add_box("metal_blue", _xform(origin, Vector3(tx, total_h + 1.85, tz), rot_y), Vector3(1.08, 1.15, 1.08), rot_y, false, 0.4)
	if rng.randf() < 0.55:
		add_box("metal_roof", _xform(origin, Vector3(-width * 0.25, total_h + 1.05, depth * 0.15), rot_y), Vector3(1.6, 0.14, 1.1), rot_y, false, 0.4)


func build_sandstone_haveli(origin: Vector3, width: float, depth: float, floors: int, rot_y: float, rng: RandomNumberGenerator) -> void:
	var wall_mats: Array[String] = ["sandstone", "plaster_cream", "plaster_ochre"]
	var wall_mat: String = wall_mats[rng.randi() % wall_mats.size()]
	var floor_h: float = 3.40
	var total_h: float = float(floors) * floor_h

	add_box(wall_mat, origin + Vector3(0.0, total_h * 0.5, 0.0), Vector3(width, total_h, depth), rot_y, true, 0.22, true, true)
	add_box("sandstone_dark", origin + Vector3(0.0, total_h + 0.48, 0.0), Vector3(width + 0.44, 0.94, depth + 0.44), rot_y, false, 0.25)

	var front_z: float = depth * 0.5
	# Ornate entrance doorway & flanking stone brackets
	add_box("sandstone_dark", _xform(origin, Vector3(0.0, 2.42, front_z + 0.42), rot_y), Vector3(2.6, 0.24, 0.92), rot_y, false, 0.35)
	add_box("window_lit", _xform(origin, Vector3(0.0, 1.18, front_z + 0.06), rot_y), Vector3(1.42, 2.30, 0.14), rot_y, false, 0.5)

	if floors >= 2:
		var j_y: float = floor_h + 1.65
		# Carved Rajasthani Jharokha bay + supporting corbels
		add_box("sandstone", _xform(origin, Vector3(0.0, j_y, front_z + 0.44), rot_y), Vector3(3.0, 2.25, 0.90), rot_y, false, 0.3)
		add_box("sandstone_dark", _xform(origin, Vector3(-1.1, j_y - 1.25, front_z + 0.38), rot_y), Vector3(0.32, 0.42, 0.72), rot_y, false, 0.4)
		add_box("sandstone_dark", _xform(origin, Vector3(1.1, j_y - 1.25, front_z + 0.38), rot_y), Vector3(0.32, 0.42, 0.72), rot_y, false, 0.4)
		add_box("sandstone_dark", _xform(origin, Vector3(0.0, j_y + 1.28, front_z + 0.54), rot_y), Vector3(3.4, 0.28, 1.12), rot_y, false, 0.3)
		add_box("window_lit", _xform(origin, Vector3(0.0, j_y, front_z + 0.92), rot_y), Vector3(1.65, 1.25, 0.12), rot_y, false, 0.5)

	# Courtyard compound wall with gate pillars
	var wall_z: float = depth * 0.5 + 2.8
	var side_w: float = (width + 2.2) * 0.34
	add_box("sandstone", _xform(origin, Vector3(-(width * 0.5 + 1.1 - side_w * 0.5), 0.85, wall_z), rot_y), Vector3(side_w, 1.7, 0.38), rot_y, true, 0.28)
	add_box("sandstone", _xform(origin, Vector3((width * 0.5 + 1.1 - side_w * 0.5), 0.85, wall_z), rot_y), Vector3(side_w, 1.7, 0.38), rot_y, true, 0.28)
	add_box("sandstone_dark", _xform(origin, Vector3(-1.75, 1.1, wall_z), rot_y), Vector3(0.55, 2.2, 0.55), rot_y, true, 0.35)
	add_box("sandstone_dark", _xform(origin, Vector3(1.75, 1.1, wall_z), rot_y), Vector3(0.55, 2.2, 0.55), rot_y, true, 0.35)

	add_box("plaster_cream", _xform(origin, Vector3(-width * 0.22, total_h + 1.55, -depth * 0.22), rot_y), Vector3(2.8, 2.2, 2.8), rot_y, false, 0.28)
	add_box("metal_blue", _xform(origin, Vector3(width * 0.22, total_h + 1.35, -depth * 0.15), rot_y), Vector3(1.1, 1.1, 1.1), rot_y, false, 0.4)


func build_warehouse(origin: Vector3, width: float, depth: float, height: float, rot_y: float) -> void:
	add_box("concrete", origin + Vector3(0.0, height * 0.5, 0.0), Vector3(width, height, depth), rot_y, true, 0.18, true, true)
	add_box("metal_roof", origin + Vector3(0.0, height + 0.32, 0.0), Vector3(width + 0.8, 0.65, depth + 0.8), rot_y, false, 0.22)
	add_box("metal_blue", _xform(origin, Vector3(0.0, height - 0.55, depth * 0.5 + 0.08), rot_y), Vector3(width * 0.95, 0.7, 0.14), rot_y, false, 0.35)
	add_box("window_dark", _xform(origin, Vector3(-width * 0.24, 2.0, depth * 0.5 + 0.07), rot_y), Vector3(3.6, 3.8, 0.16), rot_y, false, 0.4)
	add_box("window_dark", _xform(origin, Vector3(width * 0.24, 2.0, depth * 0.5 + 0.07), rot_y), Vector3(3.6, 3.8, 0.16), rot_y, false, 0.4)


func build_fuel_station(origin: Vector3, rot_y: float) -> void:
	add_box("concrete", origin + Vector3(0.0, 0.12, 0.0), Vector3(18.0, 0.24, 13.0), rot_y, true, 0.2)
	add_box("awning_saffron", origin + Vector3(0.0, 5.2, 0.0), Vector3(15.5, 0.95, 10.5), rot_y, false, 0.25)
	add_box("metal_blue", origin + Vector3(0.0, 4.65, 0.0), Vector3(15.7, 0.22, 10.7), rot_y, false, 0.3)
	for px: float in [-5.2, 5.2]:
		for pz: float in [-3.0, 3.0]:
			add_box("concrete", _xform(origin, Vector3(px, 2.4, pz), rot_y), Vector3(0.55, 4.6, 0.55), rot_y, true, 0.35)
	for px: float in [-2.6, 2.6]:
		add_box("concrete", _xform(origin, Vector3(px, 0.38, 0.0), rot_y), Vector3(1.1, 0.5, 3.8), rot_y, true, 0.35)
		add_box("awning_crimson", _xform(origin, Vector3(px, 1.35, 0.0), rot_y), Vector3(0.75, 1.5, 0.9), rot_y, true, 0.4)
	add_box("plaster_cream", _xform(origin, Vector3(0.0, 1.9, -9.2), rot_y), Vector3(11.0, 3.8, 4.5), rot_y, true, 0.24)
	add_box("window_lit", _xform(origin, Vector3(0.0, 1.7, -6.9), rot_y), Vector3(5.2, 1.8, 0.14), rot_y, false, 0.5)


func build_water_tower(origin: Vector3) -> void:
	for ox: float in [-2.6, 2.6]:
		for oz: float in [-2.6, 2.6]:
			add_box("concrete", origin + Vector3(ox, 6.0, oz), Vector3(0.6, 12.0, 0.6), 0.0, true, 0.3)
	add_box("concrete", origin + Vector3(0.0, 5.5, 0.0), Vector3(5.6, 0.45, 5.6), 0.0, false, 0.3)
	add_box("sandstone", origin + Vector3(0.0, 13.8, 0.0), Vector3(7.4, 3.8, 7.4), 0.0, true, 0.22)
	add_box("sandstone_dark", origin + Vector3(0.0, 16.0, 0.0), Vector3(7.8, 0.55, 7.8), 0.0, false, 0.24)


func build_desert_dhani(origin: Vector3, rot_y: float) -> void:
	add_box("plaster_ochre", origin + Vector3(0.0, 1.5, 0.0), Vector3(5.6, 3.0, 4.8), rot_y, true, 0.28)
	add_box("sandstone_dark", origin + Vector3(0.0, 3.25, 0.0), Vector3(6.2, 0.45, 5.4), rot_y, false, 0.28)
	add_box("window_lit", _xform(origin, Vector3(0.0, 1.05, 2.44), rot_y), Vector3(1.1, 2.0, 0.12), rot_y, false, 0.5)


func commit_to_chunk(parent: Node3D, mat_lib: RefCounted, mesh_visibility_range: float) -> Array[MeshInstance3D]:
	var created_meshes: Array[MeshInstance3D] = []

	for mat_key: String in _buckets.keys():
		var st: SurfaceTool = _buckets[mat_key]
		st.generate_tangents()
		var arr_mesh: ArrayMesh = st.commit()
		if arr_mesh.get_surface_count() == 0:
			continue

		var mi := MeshInstance3D.new()
		mi.name = "Batch_" + mat_key
		mi.mesh = arr_mesh
		mi.material_override = mat_lib.get_mat(mat_key)
		mi.visibility_range_end = mesh_visibility_range
		parent.add_child(mi)
		created_meshes.append(mi)

	if not _colliders.is_empty():
		var body := StaticBody3D.new()
		body.name = "ChunkStaticColliders"
		body.collision_layer = 1
		body.collision_mask = 0
		for c_info: Dictionary in _colliders:
			var col := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = c_info["size"]
			col.shape = shape
			col.transform = Transform3D(Basis(Vector3.UP, float(c_info["rot_y"])), c_info["pos"])
			body.add_child(col)
		parent.add_child(body)

	# Attach up to 14 largest BoxOccluder3D volumes per chunk for hardware/software occlusion culling
	var occ_limit: int = mini(_occluders.size(), 14)
	for i: int in range(occ_limit):
		var o_info: Dictionary = _occluders[i]
		var occ_inst := OccluderInstance3D.new()
		var box_occ := BoxOccluder3D.new()
		box_occ.size = o_info["size"]
		occ_inst.occluder = box_occ
		occ_inst.transform = Transform3D(Basis(Vector3.UP, float(o_info["rot_y"])), o_info["pos"])
		parent.add_child(occ_inst)

	return created_meshes


func _get_bucket(mat_key: String) -> SurfaceTool:
	if not _buckets.has(mat_key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_buckets[mat_key] = st
	return _buckets[mat_key] as SurfaceTool


func _xform(origin: Vector3, local_offset: Vector3, rot_y: float) -> Vector3:
	return origin + local_offset.rotated(Vector3.UP, rot_y)


func _append_uv_box(st: SurfaceTool, center: Vector3, size: Vector3, rot_y: float, uv_scale: float, skip_bottom: bool) -> void:
	var hx: float = size.x * 0.5
	var hy: float = size.y * 0.5
	var hz: float = size.z * 0.5
	var u_x: float = size.x * uv_scale
	var u_y: float = size.y * uv_scale
	var u_z: float = size.z * uv_scale

	_append_quad(st, center, rot_y, Vector3(0.0, 0.0, 1.0), Vector3(-hx, hy, hz), Vector3(hx, hy, hz), Vector3(hx, -hy, hz), Vector3(-hx, -hy, hz), u_x, u_y)
	_append_quad(st, center, rot_y, Vector3(0.0, 0.0, -1.0), Vector3(hx, hy, -hz), Vector3(-hx, hy, -hz), Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz), u_x, u_y)
	_append_quad(st, center, rot_y, Vector3(1.0, 0.0, 0.0), Vector3(hx, hy, hz), Vector3(hx, hy, -hz), Vector3(hx, -hy, -hz), Vector3(hx, -hy, hz), u_z, u_y)
	_append_quad(st, center, rot_y, Vector3(-1.0, 0.0, 0.0), Vector3(-hx, hy, -hz), Vector3(-hx, hy, hz), Vector3(-hx, -hy, hz), Vector3(-hx, -hy, -hz), u_z, u_y)
	_append_quad(st, center, rot_y, Vector3(0.0, 1.0, 0.0), Vector3(-hx, hy, -hz), Vector3(hx, hy, -hz), Vector3(hx, hy, hz), Vector3(-hx, hy, hz), u_x, u_z)
	if not skip_bottom:
		_append_quad(st, center, rot_y, Vector3(0.0, -1.0, 0.0), Vector3(-hx, -hy, hz), Vector3(hx, -hy, hz), Vector3(hx, -hy, -hz), Vector3(-hx, -hy, -hz), u_x, u_z)


func _append_quad(st: SurfaceTool, center: Vector3, rot_y: float, local_normal: Vector3, a: Vector3, b: Vector3, c: Vector3, d: Vector3, u_max: float, v_max: float) -> void:
	var n: Vector3 = local_normal.rotated(Vector3.UP, rot_y) if rot_y != 0.0 else local_normal
	var va: Vector3 = center + (a.rotated(Vector3.UP, rot_y) if rot_y != 0.0 else a)
	var vb: Vector3 = center + (b.rotated(Vector3.UP, rot_y) if rot_y != 0.0 else b)
	var vc: Vector3 = center + (c.rotated(Vector3.UP, rot_y) if rot_y != 0.0 else c)
	var vd: Vector3 = center + (d.rotated(Vector3.UP, rot_y) if rot_y != 0.0 else d)

	st.set_normal(n); st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(va)
	st.set_normal(n); st.set_uv(Vector2(u_max, 0.0)); st.add_vertex(vb)
	st.set_normal(n); st.set_uv(Vector2(u_max, v_max)); st.add_vertex(vc)

	st.set_normal(n); st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(va)
	st.set_normal(n); st.set_uv(Vector2(u_max, v_max)); st.add_vertex(vc)
	st.set_normal(n); st.set_uv(Vector2(0.0, v_max)); st.add_vertex(vd)
