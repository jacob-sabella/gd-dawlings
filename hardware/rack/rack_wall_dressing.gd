class_name RackWallDressing
extends RefCounted

## The rack's case and what dresses it: the skiff and its border, the plaque, the pillars that grow with the
## loudness, the glow and halo in the venue's mood (`glow_with`, `_shine`). Moved out of `hardware/rack/rack_wall.gd` without
## change of behaviour; the state stays on the wall, which keeps a one-line delegate for each name reached from elsewhere.

var wall: RackWall


func _init(of: RackWall) -> void:
	wall = of


func _build_case() -> void:
	var case := MeshInstance3D.new()
	case.name = "Case"
	var box := BoxMesh.new()
	box.size = Vector3(RackWall.WIDE + RackWall.BORDER * 2.0, RackWall.TALL + RackWall.BORDER * 2.0, RackWall.CASE_DEEP)
	case.mesh = box
	case.position = Vector3(0, RackWall.TALL * 0.5, -RackWall.CASE_DEEP * 0.5 - 0.002)
	case.material_override = Materials.chassis()
	wall._put(case)
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		post.name = "Post"
		var bar := BoxMesh.new()
		var high := 1.26 + RackWall.TALL + RackWall.BORDER
		bar.size = Vector3(RackWall.POST, high, RackWall.POST)
		post.mesh = bar
		post.position = Vector3(side * (RackWall.WIDE * 0.5 - 0.05), -1.26 + high * 0.5, -RackWall.CASE_DEEP - RackWall.POST * 0.5 - 0.004)
		post.material_override = Materials.brushed_metal()
		post.add_to_group(&"presentation_chrome")
		wall._put(post)
	_build_dressing()
	_build_wing()
	_build_pillars()


## The wing's case round the corner (RackWall.WING_X): a backing as tall as the module rows, its rails, the lit
## edge lines and posts to the floor, like the case's. Its blanks and modules are put in it as the case's are.
func _build_wing() -> void:
	var wing := Node3D.new()
	wing.name = "Wing"
	wing.transform = wall._cell_frame(RackLayout.COLS + RackLayout.WING_COLS * 0.5, 0.0)
	var wide := RackWall.MODULE_WIDE * RackLayout.WING_COLS
	var foot := wall._row_foot(RackWall.ROWS - 1)
	var top := wall._row_foot(0) + RackWall.ROW_TALL
	var case := MeshInstance3D.new()
	case.name = "WingCase"
	var box := BoxMesh.new()
	box.size = Vector3(wide + RackWall.BORDER * 2.0, top - foot + RackWall.BORDER * 2.0, RackWall.CASE_DEEP)
	case.mesh = box
	case.position = Vector3(0, (foot + top) * 0.5, -RackWall.CASE_DEEP * 0.5 - 0.002)
	case.material_override = Materials.chassis()
	wing.add_child(case)
	for side in [-1.0, 1.0]:
		var line := MeshInstance3D.new()
		line.name = "WingEdge"
		var b := BoxMesh.new()
		b.size = Vector3(0.004, top - foot, 0.002)
		line.mesh = b
		line.position = Vector3(side * (wide * 0.5 + RackWall.BORDER * 0.5), (foot + top) * 0.5, -0.001)
		line.material_override = wall._edge_material
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wing.add_child(line)
	for k in 3:
		var post := MeshInstance3D.new()
		post.name = "WingPost"
		var bar := BoxMesh.new()
		var high := RackWall.MODULAR_FLOOR + foot
		bar.size = Vector3(RackWall.POST, high, RackWall.POST)
		post.mesh = bar
		post.position = Vector3((k - 1) * (wide * 0.5 - 0.05), -RackWall.MODULAR_FLOOR + high * 0.5, -RackWall.CASE_DEEP * 0.5)
		post.material_override = Materials.brushed_metal()
		post.add_to_group(&"presentation_chrome")
		wing.add_child(post)
	for row in RackWall.ROWS:
		for at in [0.0, RackWall.ROW_TALL]:
			var rail := MeshInstance3D.new()
			rail.name = "WingRail"
			var b := BoxMesh.new()
			b.size = Vector3(wide, 0.007, 0.006)
			rail.mesh = b
			rail.position = Vector3(0, wall._row_foot(row) + at, -0.001)
			rail.material_override = Materials.brushed_metal()
			wing.add_child(rail)
	# The case's halo behind it (the same material, so it glows with the rack), and work lamps over it as over
	# the case, one to each stretch of it.
	var halo := MeshInstance3D.new()
	halo.name = "WingHalo"
	var quad := QuadMesh.new()
	quad.size = Vector2(wide + 0.5, top - foot + 0.5)
	halo.mesh = quad
	halo.position = Vector3(0, (foot + top) * 0.5, -RackWall.CASE_DEEP - 0.012)
	halo.material_override = wall._halo_material
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.add_to_group(&"presentation_chrome")
	wing.add_child(halo)
	for k in 3:
		var lamp := SpotLight3D.new()
		lamp.name = "WingLamp%d" % k
		lamp.light_color = Color(1.0, 0.92, 0.8)
		lamp.light_energy = 1.2
		lamp.spot_range = 2.6
		lamp.spot_angle = 70.0
		lamp.shadow_enabled = false
		var x := (k - 1) * wide / 3.0
		var from := Vector3(x, top + RackWall.BORDER + 0.1, 0.3)
		lamp.transform = Transform3D(Basis.looking_at(Vector3(x, (foot + top) * 0.5, 0) - from, Vector3.UP), from)
		lamp.add_to_group(&"presentation_chrome")
		wing.add_child(lamp)
	wall._put(wing)


## What makes the case a thing to look at: the level bar along its top, glowing edge lines down its
## sides, and the rails the modules hang on.
func _build_dressing() -> void:
	wall._vu_off = _emissive(Color(0.12, 0.11, 0.1), 0.0)
	wall._vu_on = _emissive(Color(0.4, 1.0, 0.6), 2.5)
	wall._vu_peak = _emissive(Color(1.0, 0.45, 0.3), 3.0)
	var seg_wide := RackWall.WIDE / RackWall.VU_SEGMENTS
	for n in RackWall.VU_SEGMENTS:
		var seg := MeshInstance3D.new()
		seg.name = "Vu%d" % n
		var b := BoxMesh.new()
		b.size = Vector3(seg_wide - 0.005, RackWall.BORDER * 0.5, 0.002)
		seg.mesh = b
		seg.position = Vector3(-RackWall.WIDE * 0.5 + seg_wide * (n + 0.5), RackWall.TALL + RackWall.BORDER * 0.5, -0.001)
		seg.material_override = wall._vu_off
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wall._put(seg)
		wall._vu.append(seg)
	wall._edge_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wall._edge_material.albedo_color = Color(0.2, 0.2, 0.2)
	for side in [-1.0, 1.0]:
		var line := MeshInstance3D.new()
		line.name = "Edge"
		var b := BoxMesh.new()
		b.size = Vector3(0.004, RackWall.TALL, 0.002)
		line.mesh = b
		line.position = Vector3(side * (RackWall.WIDE * 0.5 + RackWall.BORDER * 0.5), RackWall.TALL * 0.5, -0.001)
		line.material_override = wall._edge_material
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wall._put(line)
	for row in RackWall.ROWS:
		for top in [0.0, RackWall.ROW_TALL]:
			var rail := MeshInstance3D.new()
			rail.name = "Rail"
			var b := BoxMesh.new()
			b.size = Vector3(RackWall.WIDE, 0.007, 0.006)
			rail.mesh = b
			rail.position = Vector3(0, wall._row_foot(row) + top, -0.001)
			rail.material_override = Materials.brushed_metal()
			wall._put(rail)


func _build_pillars() -> void:
	if not wall.pillars:
		return
	for n in RackWall.PILLARS:
		# Fanned from the left round the front to the right, leaving the middle open to see the case by.
		var side := -1.0 if n < RackWall.PILLARS / 2 else 1.0
		var k := (n % (RackWall.PILLARS / 2)) / float(RackWall.PILLARS / 2 - 1)
		var angle := deg_to_rad(side * lerpf(30.0, 88.0, k))
		var pillar := MeshInstance3D.new()
		pillar.name = "Pillar%d" % n
		var b := BoxMesh.new()
		b.size = Vector3(0.07, 1.0, 0.07)
		pillar.mesh = b
		pillar.position = Vector3(sin(angle) * RackWall.PILLAR_RADIUS, -RackWall.MODULAR_FLOOR + 0.03, cos(angle) * RackWall.PILLAR_RADIUS + 0.3)
		pillar.material_override = _emissive(Color(0.3, 0.3, 0.3), 2.0)
		pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pillar.add_to_group(&"presentation_chrome")
		wall.panel.add_child(pillar)
		wall._pillars.append(pillar)
		wall._pillar_level.append(0.0)
		wall._pillar_for.append("")
	_seat_pillars()


## Which module each pillar follows: the modules in order across the case, the rest left dark.
func _seat_pillars() -> void:
	var ids: Array = wall.patch["modules"].keys() if wall.patch.has("modules") else []
	ids.sort_custom(func(a, b): 
		var pa: Array = wall.patch["modules"][a]["at"]
		var pb: Array = wall.patch["modules"][b]["at"]
		return int(pa[0]) * 4 + int(pa[1]) < int(pb[0]) * 4 + int(pb[1]))
	for n in wall._pillars.size():
		wall._pillar_for[n] = ids[n] if n < ids.size() else ""
		var m := wall._pillars[n].material_override as StandardMaterial3D
		if wall._pillar_for[n] == "":
			m.albedo_color = Color(0.1, 0.1, 0.1)
			m.emission = Color(0.1, 0.1, 0.1)
		else:
			var t := wall.modules._tint_of(RackPatch.type_of(wall.patch, wall._pillar_for[n]))
			m.albedo_color = t
			m.emission = t
		_grow_pillar(n, 0.0)


func _grow_pillar(n: int, level: float) -> void:
	var h := 0.2 + clampf(level, 0.0, 1.0) * (RackWall.PILLAR_TALL - 0.2)
	wall._pillar_level[n] = level
	wall._pillars[n].scale = Vector3(1, h, 1)
	wall._pillars[n].position.y = -RackWall.MODULAR_FLOOR + 0.03 + h * 0.5


func _emissive(colour: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = colour
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = colour
		m.emission_energy_multiplier = energy
	return m


## The glow the rack gives the room: a halo behind the case, and a light in front of it, both in the
## venue's mood and both brighter with what it plays.
func _build_glow() -> void:
	wall._halo = MeshInstance3D.new()
	wall._halo.name = "Halo"
	var quad := QuadMesh.new()
	quad.size = Vector2(RackWall.WIDE + 0.5, RackWall.TALL + 0.5)
	wall._halo.mesh = quad
	wall._halo.position = Vector3(0, RackWall.TALL * 0.5, -RackWall.CASE_DEEP - 0.012)
	wall._halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wall._halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wall._halo_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	wall._halo_material.albedo_color = Color(0, 0, 0, 0)
	wall._halo.material_override = wall._halo_material
	wall._halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wall._halo.add_to_group(&"presentation_chrome")
	wall.panel.add_child(wall._halo)
	wall._glow = OmniLight3D.new()
	wall._glow.name = "Glow"
	wall._glow.position = Vector3(0, RackWall.TALL * 0.5, 0.5)
	wall._glow.omni_range = 3.0
	wall._glow.light_energy = 0.0
	wall._glow.shadow_enabled = false
	wall._glow.add_to_group(&"presentation_chrome")
	wall.panel.add_child(wall._glow)
	var lamp := SpotLight3D.new()
	lamp.name = "Lamp"
	lamp.light_color = Color(1.0, 0.92, 0.8)
	lamp.light_energy = 1.2
	lamp.spot_range = 2.4
	lamp.spot_angle = 75.0
	lamp.shadow_enabled = false
	var from := Vector3(0, RackWall.TALL + RackWall.BORDER + 0.1, 0.3)
	lamp.transform = Transform3D(Basis.looking_at(Vector3(0, RackWall.TALL * 0.5, 0) - from, Vector3.UP), from)
	lamp.add_to_group(&"presentation_chrome")
	wall.panel.add_child(lamp)


## What the rack plays, for the light: its loudness 0..1 and whether it just hit.
func glow_with(level: float, hit: float) -> void:
	wall._level = level
	wall._hit = maxf(wall._hit, hit)
	_shine()


func _shine() -> void:
	if wall._glow == null:
		return
	# Only when the light has actually moved: this is asked every frame, and it touches lights and
	# materials (and a light that is touched is a light the renderer redoes).
	var key := Vector3(roundf(wall._level * 150.0), roundf(wall._hit * 150.0), float(wall.mood.hash() & 0xffff))
	if key == wall._shone_key:
		return
	wall._shone_key = key
	var base: Color = wall.mood["base"]
	var flash: Color = wall.mood["hit"]
	var colour := base.lerp(flash, clampf(wall._hit, 0.0, 1.0))
	wall._glow.light_color = colour
	wall._glow.light_energy = float(wall.mood["glow"]) * (0.12 + wall._level * 0.8 + wall._hit * 0.3)
	wall._halo_material.albedo_color = Color(colour.r, colour.g, colour.b, clampf(0.03 + wall._level * 0.09 + wall._hit * 0.05, 0.0, 0.2))
	wall._edge_material.albedo_color = base.lerp(flash, clampf(wall._hit, 0.0, 1.0)) * (0.3 + wall._level * 0.6 + wall._hit * 0.2)
	if wall._vu_on != null:
		wall._vu_on.albedo_color = base
		wall._vu_on.emission = base
		wall._vu_peak.albedo_color = flash
		wall._vu_peak.emission = flash
		var lit := roundi(clampf(wall._level * 1.4, 0.0, 1.0) * RackWall.VU_SEGMENTS)
		for n in wall._vu.size():
			var want := wall._vu_off
			if n < lit:
				want = wall._vu_peak if n >= RackWall.VU_SEGMENTS - 5 or (n == lit - 1 and wall._hit > 0.5) else wall._vu_on
			if wall._vu[n].material_override != want:
				wall._vu[n].material_override = want
