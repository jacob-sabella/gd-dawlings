class_name GearShape
extends RefCounted

## The venue's own fittings on the gear's furniture: the shape half of dressing the gear to its
## venue, where `GearStyle` is the finish half.
##
## Every furniture box that `GearTrim.edges` outlines (the console body, the rack plinth, the
## patch cabinet...) is also handed here, and gets the current venue's kit fitted to it: road
## case corners, handles and latches in the club, log uprights and iron straps in the cabin, iron
## pipe in the loft, portholes in the dome, a chalk outline in the chalk zone. A kit is one model
## per venue, assets/models/gear_kit_<venue>.glb from tools/blender/gear_kits.py, whose parts are
## named for where they go; see that script's header for the slots. The boxes resize with the
## session, which is why the shape is fittings on a box rather than a model of a whole desk.
##
## A part's surfaces wear the shared finish its material is named for (`Materials.furniture`,
## `brushed_metal`, ...), so the fittings take the venue's GearStyle and follow it in place.

const SLOTS: Array[String] = ["corner", "corner_top", "edge", "handle", "latch", "face", "finial"]
const KIT_PATH := "res://assets/models/gear_kit_%s.glb"

## The venue the gear is dressed for now, and that venue's parts: slot name -> Mesh.
static var _venue: StringName = &""
static var _parts: Dictionary = {}
static var _chalk := false
static var _cache: Dictionary = {}


## Dress the gear for `venue`: load its kit (or none) and refit every furniture box in `tree`.
static func use(venue: StringName, chalk: bool, tree: SceneTree) -> void:
	_venue = venue
	_chalk = chalk
	_parts = parts_of(venue)
	if tree == null:
		return
	for box in tree.get_nodes_in_group(&"gear_box"):
		dress(box as MeshInstance3D)


## A venue's kit, slot -> Mesh: empty for a venue without one (the studio, whose plain powder
## coat is the gear as it was designed).
static func parts_of(venue: StringName) -> Dictionary:
	if _cache.has(venue):
		return _cache[venue]
	var found := {}
	var path := KIT_PATH % venue
	if ResourceLoader.exists(path):
		var scene := (load(path) as PackedScene).instantiate()
		for mesh: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			if SLOTS.has(String(mesh.name)):
				found[String(mesh.name)] = mesh.mesh
		scene.free()
	_cache[venue] = found
	return found


## The current kit fitted to `box`, replacing whatever kit it wore before.
static func dress(box: MeshInstance3D) -> void:
	for old in box.get_children():
		if old.has_meta(&"gear_shape"):
			box.remove_child(old)
			old.queue_free()
	var size: Vector3 = (box.mesh as BoxMesh).size
	var h := size * 0.5
	var smallest := minf(size.x, minf(size.y, size.z))
	if _chalk:
		_sketch(box, size)
	if _parts.has("corner") and smallest >= 0.2:
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					_fit(box, "corner", Vector3(sx * h.x, sy * h.y, sz * h.z), Vector3(sx, sy, sz))
	if _parts.has("corner_top") and smallest >= 0.2:
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				_fit(box, "corner_top", Vector3(sx * h.x, h.y, sz * h.z), Vector3(sx, 1, sz))
	if _parts.has("edge") and size.y >= 0.25 and minf(size.x, size.z) >= 0.1:
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				_fit(box, "edge", Vector3(sx * h.x, 0, sz * h.z), Vector3(sx, size.y, sz))
	if _parts.has("handle") and size.y >= 0.2 and size.z >= 0.2:
		for sx in [-1.0, 1.0]:
			_fit(box, "handle", Vector3(sx * h.x, h.y * 0.3, 0), Vector3(sx, 1, 1))
	if _parts.has("latch") and size.y >= 0.2 and size.x >= 0.3:
		var across: Array = [-0.6 * h.x, 0.6 * h.x] if size.x > 0.8 else [0.0]
		for sz in [-1.0, 1.0]:
			for x in across:
				_fit(box, "latch", Vector3(x, h.y - 0.05, sz * h.z), Vector3(1, 1, sz))
	if _parts.has("face") and size.y >= 0.25 and size.x >= 0.3:
		var s := clampf(minf(size.x, size.y) * 0.55 / 0.2, 0.6, 1.6)
		for sz in [-1.0, 1.0]:
			_fit(box, "face", Vector3(0, 0, sz * h.z), Vector3(s, s, sz))
	if _parts.has("finial") and smallest >= 0.1:
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				_fit(box, "finial", Vector3(sx * h.x, h.y, sz * h.z), Vector3.ONE)


static func _fit(box: MeshInstance3D, slot: String, at: Vector3, scale: Vector3) -> void:
	var part := MeshInstance3D.new()
	part.name = "Kit_" + slot
	part.set_meta(&"gear_shape", true)
	part.mesh = _parts[slot]
	part.position = at
	part.scale = scale
	for s in part.mesh.get_surface_count():
		var m := part.mesh.surface_get_material(s)
		if m != null:
			part.set_surface_override_material(s, finish(m.resource_name))
	box.add_child(part, true)


## The shared material a kit's surface named `name` wears.
static func finish(name: String) -> Material:
	match name:
		"furniture": return Materials.furniture()
		"brushed": return Materials.brushed_metal()
		"trim": return Materials.trim()
		"end_cheek": return Materials.end_cheek()
		"chassis": return Materials.chassis()
		"glass": return _glass()
		"rope": return _rope()
	return Materials.furniture()


static func _glass() -> StandardMaterial3D:
	if not _cache.has("glass"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.25, 0.55, 0.55, 0.45)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.05
		m.metallic = 0.3
		_cache["glass"] = m
	return _cache["glass"]


static func _rope() -> StandardMaterial3D:
	if not _cache.has("rope"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.62, 0.52, 0.36)
		m.roughness = 0.95
		m.normal_enabled = true
		m.normal_texture = Materials.grain("rope", 2.0, 2.0, 6.0)
		_cache["rope"] = m
	return _cache["rope"]


## The chalk zone draws its gear rather than fitting it: each box gone round in chalk, a little
## off the true edges and over twice, the way everything else there is drawn.
static func _sketch(box: MeshInstance3D, size: Vector3) -> void:
	var h := size * 0.5 + Vector3.ONE * 0.012
	var corners := []
	for sy in [-1.0, 1.0]:
		corners.append([Vector3(-h.x, sy * h.y, -h.z), Vector3(h.x, sy * h.y, -h.z),
				Vector3(h.x, sy * h.y, h.z), Vector3(-h.x, sy * h.y, h.z)])
	var lines := []
	for ring in corners:
		var loop := PackedVector3Array()
		for p in ring:
			loop.append(p)
		# Past where it started: a hand closing a loop overshoots.
		loop.append(ring[0])
		loop.append(ring[0].lerp(ring[1], 0.08))
		lines.append(Chalk.wobble(_subdivided(loop, 0.08), 0.004, _rng(box)))
	for i in 4:
		var up := PackedVector3Array([corners[0][i], corners[1][i]])
		lines.append(Chalk.wobble(_subdivided(up, 0.08), 0.004, _rng(box)))
	var drawn := Chalk.drawing(lines, Chalk.WHITE, 0.0035, false, 2, hash(box.name))
	drawn.name = "Kit_chalk"
	drawn.set_meta(&"gear_shape", true)
	box.add_child(drawn)


static func _rng(box: Node) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(box.get_path()) if box.is_inside_tree() else String(box.name))
	return rng


static func _subdivided(line: PackedVector3Array, step: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		var n := maxi(1, int(a.distance_to(b) / step))
		for k in n:
			out.append(a.lerp(b, float(k) / n))
	out.append(line[line.size() - 1])
	return out
