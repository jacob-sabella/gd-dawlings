class_name RackWall
extends Surface

## The modular room's rack (docs/architecture.md, "The modular room"): the case over the synth zone's
## keyboard stand, a skiff of ROWS rows by COLS columns that holds any of the engine's modules
## (RackCatalogue) in any place, patched with cables. Under the modules a palette: a row of groups, a
## row of what is in the group, and a press on one puts it in the next free place.
##
## It shows the room's patch (`show_patch`) and never changes it: a cable, a module put in or taken out,
## a knob let go are asks (`edit_asked`, `knob_set`) the studio puts to the room, whose answer comes back
## through `show_patch`. A knob turning is streamed to the band (`knob_streamed`) at most
## Session.KNOBS_PER_SECOND, and the room's only when it has rested for SETTLE.
##
## It lights up with what it plays: each module's lamp follows its meter (`show_meters`), and the case
## glows in the venue's mood (`mood`, RackMood) brighter with the rack's loudness and flashing on a hit,
## which the studio also gives to the room's own lights.
##
## Hardware: it knows nothing of the session.

signal edit_asked(op: String, args: Array)
signal knob_turning(id: String, knob: String, v: float)
signal knob_streamed(id: String, knob: String, v: float)
signal knob_set(id: String, knob: String, v: float)
signal touched(pitch: int, down: bool)
signal keys_asked()
signal told(text: String)
signal track_asked()
signal record_asked()

const COLS := RackLayout.COLS
const ROWS := RackLayout.ROWS
const MODULE_WIDE := 0.11
const WIDE := MODULE_WIDE * COLS
const ROW_TALL := 0.55
const ROW_GAP := 0.02
const PALETTE_TALL := 0.15
const TALL := ROW_TALL * ROWS + ROW_GAP * (ROWS - 1) + PALETTE_TALL
const BORDER := 0.025
## The floor, below the case's foot (Venue.MODULAR_BOTTOM).
const MODULAR_FLOOR := 1.26
const CASE_DEEP := 0.05
const KNOB_PITCH := 0.055
const KNOB_ROW := 0.062
const JACK_ROW := 0.06
const TITLE_CAP := 0.024
const LETTER_CAP := 0.0135
const TOUCH_COUNT := 13
const TOUCH_SIZE := Vector2(0.078, 0.17)
const TOUCH_X := 0.08
const TOUCH_Y := 1.0325 - 1.26
const TOUCH_Z := 0.14
const PLAQUE_WIDE := 0.42
const PLAQUE_GAP := 0.03
const PLAQUE_X := WIDE * 0.5 + BORDER + PLAQUE_GAP + PLAQUE_WIDE * 0.5
const PLAQUE_Z := 0.01
## How far the whole of it is off its middle toward the plaque: the venue hangs it this far the other
## way (Venue.modular_spot).
const OFF_MIDDLE := (PLAQUE_X + PLAQUE_WIDE * 0.5 - WIDE * 0.5 - BORDER) * 0.5
const POST := 0.04
const LOOK := Vector3(0, 0.3, 0.1)
const FRAME_TOP := Vector3(0, TALL + BORDER, 0)
const FRAME_FOOT := Vector3(0, TOUCH_Y, TOUCH_Z + TOUCH_SIZE.y * 0.5)
const SETTLE := 0.3
const STREAM_GAP_MSEC := 34
const CABLE_SAG := 0.16
const GROUP_PRESETS := "PRESETS"

const CABLE_COLOURS := [Color(0.95, 0.78, 0.25), Color(0.4, 0.8, 1.0), Color(0.75, 0.75, 0.75),
		Color(1.0, 0.45, 0.3), Color(0.95, 0.4, 0.65), Color(0.55, 0.9, 0.5), Color(0.7, 0.55, 1.0),
		Color(0.3, 0.95, 0.85), Color(1.0, 0.6, 0.2), Color(0.85, 0.85, 0.4), Color(1, 1, 1)]

var within_reach := true:
	set(v):
		if within_reach == v:
			return
		within_reach = v
		_apply_reach()
var clock: Callable = func() -> int: return Time.get_ticks_msec()

var patch := RackPatch.empty()
## {"id.port": RackJack}, {"id.knob": Knob}, {module id: Node3D}
var jacks := {}
var knobs := {}
var module_nodes := {}
var touch_keys: Array[ModularTouch] = []
var play_key: EqWall.WallKey
var cables: Array[PatchCable] = []
var touch_base := 48
var panel: Node3D
## The group the palette shows.
var group := "Source"
## The venue's mood, RackMood.palette: {base, hit, glow}.
var mood := RackMood.palette(&"")
var _built := false
var _shape_key := ""
var _lamps := {}
## The screens of the SCOPE modules, by module id.
var _scopes := {}
var _track := 0
var _track_name := ""
var _recording := false
var _playing := false
var _extras := {}
var _lamp_hot: StandardMaterial3D
var _lamp_cold: StandardMaterial3D
var _glow: OmniLight3D
var _halo: MeshInstance3D
var _halo_material := StandardMaterial3D.new()
var _drag := {}
var _streamed_at := {}
var _stream_due := {}
var _settle_at := {}
var _palette_nodes: Array[Node] = []
var _level := 0.0
var _hit := 0.0
## The level bar along the case's top edge, its segments, and the lit materials they take; the case's
## edge lines; and each module's colour band by id (it lights while the module sounds).
const VU_SEGMENTS := 36
var _vu: Array[MeshInstance3D] = []
var _vu_off: StandardMaterial3D
var _vu_on: StandardMaterial3D
var _vu_peak: StandardMaterial3D
var _edge_material := StandardMaterial3D.new()
var _bands := {}
## The room's own part of the rack: light pillars standing in an arc around the player, one for each
## module (in order across the case), each as tall as its module is loud and in its module's colour.
const PILLARS := 12
const PILLAR_RADIUS := 1.55
const PILLAR_TALL := 1.7
## Whether the floor pillars stand in front of the case (a room that has its own skyline turns them off).
var pillars := true
var _pillars: Array[MeshInstance3D] = []
var _pillar_for: Array = []
var _pillar_level: Array[float] = []


func _ready() -> void:
	surface_kind = &"modular"
	if surface_id == &"":
		surface_id = &"modular"
	super()
	_rebuild()
	child_entered_tree.connect(func(n: Node) -> void:
		if n is SurfaceHandle:
			_apply_reach.call_deferred())


func _on_shape_changed(_index: int) -> void:
	pass


func _on_connection_changed() -> void:
	pass


func _rebuild() -> void:
	if _built:
		return
	_built = true
	panel = Node3D.new()
	panel.name = "Panel"
	_adopt(panel)
	_lamp_hot = Materials.led(Color(0.4, 1.0, 0.5), true)
	_lamp_cold = Materials.led(Color(0.4, 1.0, 0.5), false)
	_build_case()
	_build_touch()
	_build_glow()
	var plaque := Stations.plaque(Modular.STATION, PLAQUE_WIDE)
	plaque.position = Vector3(PLAQUE_X, TALL - float(plaque.get_meta(&"plaque_tall")) * 0.5, PLAQUE_Z)
	_adopt(plaque)
	show_patch(patch)
	_apply_reach()


func framing_root() -> Node3D:
	return panel if panel != null else self


func _process(delta: float) -> void:
	super(delta)
	var now := int(clock.call())
	for id: String in _stream_due.keys():
		if now - int(_streamed_at.get(id, -100000)) >= STREAM_GAP_MSEC:
			_streamed_at[id] = now
			var d: Array = _stream_due[id]
			knob_streamed.emit(d[0], d[1], float(d[2]))
			_stream_due.erase(id)
	for id: String in _settle_at.keys():
		var k: Knob = knobs.get(id)
		if k != null and k.is_held():
			continue
		if now >= int(_settle_at[id]):
			_settle_at.erase(id)
			if k != null:
				knob_set.emit(String(id).get_slice(".", 0), String(id).get_slice(".", 1), k.value)
	_hit = maxf(_hit - delta * 3.0, 0.0)
	_shine()


# --- the case ---------------------------------------------------------------------------------

func _put(node: Node) -> void:
	node.set_meta("built", true)
	panel.add_child(node)


func _x_of(col: float) -> float:
	return -WIDE * 0.5 + MODULE_WIDE * col


## The foot of module row `row`, up the case: row 0 is the top one, over the palette.
func _row_foot(row: int) -> float:
	return PALETTE_TALL + (ROWS - 1 - row) * (ROW_TALL + ROW_GAP)


func _build_case() -> void:
	var case := MeshInstance3D.new()
	case.name = "Case"
	var box := BoxMesh.new()
	box.size = Vector3(WIDE + BORDER * 2.0, TALL + BORDER * 2.0, CASE_DEEP)
	case.mesh = box
	case.position = Vector3(0, TALL * 0.5, -CASE_DEEP * 0.5 - 0.002)
	case.material_override = Materials.chassis()
	_put(case)
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		post.name = "Post"
		var bar := BoxMesh.new()
		var high := 1.26 + TALL + BORDER
		bar.size = Vector3(POST, high, POST)
		post.mesh = bar
		post.position = Vector3(side * (WIDE * 0.5 - 0.05), -1.26 + high * 0.5, -CASE_DEEP - POST * 0.5 - 0.004)
		post.material_override = Materials.brushed_metal()
		post.add_to_group(&"presentation_chrome")
		_put(post)
	_build_dressing()
	_build_pillars()


## What makes the case a thing to look at: the level bar along its top, glowing edge lines down its
## sides, and the rails the modules hang on.
func _build_dressing() -> void:
	_vu_off = _emissive(Color(0.12, 0.11, 0.1), 0.0)
	_vu_on = _emissive(Color(0.4, 1.0, 0.6), 2.5)
	_vu_peak = _emissive(Color(1.0, 0.45, 0.3), 3.0)
	var seg_wide := WIDE / VU_SEGMENTS
	for n in VU_SEGMENTS:
		var seg := MeshInstance3D.new()
		seg.name = "Vu%d" % n
		var b := BoxMesh.new()
		b.size = Vector3(seg_wide - 0.005, BORDER * 0.5, 0.002)
		seg.mesh = b
		seg.position = Vector3(-WIDE * 0.5 + seg_wide * (n + 0.5), TALL + BORDER * 0.5, -0.001)
		seg.material_override = _vu_off
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_put(seg)
		_vu.append(seg)
	_edge_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_edge_material.albedo_color = Color(0.2, 0.2, 0.2)
	for side in [-1.0, 1.0]:
		var line := MeshInstance3D.new()
		line.name = "Edge"
		var b := BoxMesh.new()
		b.size = Vector3(0.004, TALL, 0.002)
		line.mesh = b
		line.position = Vector3(side * (WIDE * 0.5 + BORDER * 0.5), TALL * 0.5, -0.001)
		line.material_override = _edge_material
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_put(line)
	for row in ROWS:
		for top in [0.0, ROW_TALL]:
			var rail := MeshInstance3D.new()
			rail.name = "Rail"
			var b := BoxMesh.new()
			b.size = Vector3(WIDE, 0.007, 0.006)
			rail.mesh = b
			rail.position = Vector3(0, _row_foot(row) + top, -0.001)
			rail.material_override = Materials.brushed_metal()
			_put(rail)


func _build_pillars() -> void:
	if not pillars:
		return
	for n in PILLARS:
		# Fanned from the left round the front to the right, leaving the middle open to see the case by.
		var side := -1.0 if n < PILLARS / 2 else 1.0
		var k := (n % (PILLARS / 2)) / float(PILLARS / 2 - 1)
		var angle := deg_to_rad(side * lerpf(30.0, 88.0, k))
		var pillar := MeshInstance3D.new()
		pillar.name = "Pillar%d" % n
		var b := BoxMesh.new()
		b.size = Vector3(0.07, 1.0, 0.07)
		pillar.mesh = b
		pillar.position = Vector3(sin(angle) * PILLAR_RADIUS, -MODULAR_FLOOR + 0.03, cos(angle) * PILLAR_RADIUS + 0.3)
		pillar.material_override = _emissive(Color(0.3, 0.3, 0.3), 2.0)
		pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pillar.add_to_group(&"presentation_chrome")
		panel.add_child(pillar)
		_pillars.append(pillar)
		_pillar_level.append(0.0)
		_pillar_for.append("")
	_seat_pillars()


## Which module each pillar follows: the modules in order across the case, the rest left dark.
func _seat_pillars() -> void:
	var ids: Array = patch["modules"].keys() if patch.has("modules") else []
	ids.sort_custom(func(a, b): 
		var pa: Array = patch["modules"][a]["at"]
		var pb: Array = patch["modules"][b]["at"]
		return int(pa[0]) * 4 + int(pa[1]) < int(pb[0]) * 4 + int(pb[1]))
	for n in _pillars.size():
		_pillar_for[n] = ids[n] if n < ids.size() else ""
		var m := _pillars[n].material_override as StandardMaterial3D
		if _pillar_for[n] == "":
			m.albedo_color = Color(0.1, 0.1, 0.1)
			m.emission = Color(0.1, 0.1, 0.1)
		else:
			var t := _tint_of(RackPatch.type_of(patch, _pillar_for[n]))
			m.albedo_color = t
			m.emission = t
		_grow_pillar(n, 0.0)


func _grow_pillar(n: int, level: float) -> void:
	var h := 0.2 + clampf(level, 0.0, 1.0) * (PILLAR_TALL - 0.2)
	_pillar_level[n] = level
	_pillars[n].scale = Vector3(1, h, 1)
	_pillars[n].position.y = -MODULAR_FLOOR + 0.03 + h * 0.5


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
	_halo = MeshInstance3D.new()
	_halo.name = "Halo"
	var quad := QuadMesh.new()
	quad.size = Vector2(WIDE + 0.5, TALL + 0.5)
	_halo.mesh = quad
	_halo.position = Vector3(0, TALL * 0.5, -CASE_DEEP - 0.012)
	_halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_halo_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_halo_material.albedo_color = Color(0, 0, 0, 0)
	_halo.material_override = _halo_material
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo.add_to_group(&"presentation_chrome")
	panel.add_child(_halo)
	_glow = OmniLight3D.new()
	_glow.name = "Glow"
	_glow.position = Vector3(0, TALL * 0.5, 0.5)
	_glow.omni_range = 3.0
	_glow.light_energy = 0.0
	_glow.shadow_enabled = false
	_glow.add_to_group(&"presentation_chrome")
	panel.add_child(_glow)
	var lamp := SpotLight3D.new()
	lamp.name = "Lamp"
	lamp.light_color = Color(1.0, 0.92, 0.8)
	lamp.light_energy = 1.2
	lamp.spot_range = 2.4
	lamp.spot_angle = 75.0
	lamp.shadow_enabled = false
	var from := Vector3(0, TALL + BORDER + 0.1, 0.3)
	lamp.transform = Transform3D(Basis.looking_at(Vector3(0, TALL * 0.5, 0) - from, Vector3.UP), from)
	lamp.add_to_group(&"presentation_chrome")
	panel.add_child(lamp)


## What the rack plays, for the light: its loudness 0..1 and whether it just hit.
func glow_with(level: float, hit: float) -> void:
	_level = level
	_hit = maxf(_hit, hit)
	_shine()


func _shine() -> void:
	if _glow == null:
		return
	var base: Color = mood["base"]
	var flash: Color = mood["hit"]
	var colour := base.lerp(flash, clampf(_hit, 0.0, 1.0))
	_glow.light_color = colour
	_glow.light_energy = float(mood["glow"]) * (0.15 + _level * 2.2 + _hit * 1.6)
	_halo_material.albedo_color = Color(colour.r, colour.g, colour.b, clampf(0.04 + _level * 0.25 + _hit * 0.2, 0.0, 0.5))
	_edge_material.albedo_color = base.lerp(flash, clampf(_hit, 0.0, 1.0)) * (0.35 + _level * 1.6 + _hit * 0.8)
	if _vu_on != null:
		_vu_on.albedo_color = base
		_vu_on.emission = base
		_vu_peak.albedo_color = flash
		_vu_peak.emission = flash
		var lit := roundi(clampf(_level * 1.4, 0.0, 1.0) * VU_SEGMENTS)
		for n in _vu.size():
			var want := _vu_off
			if n < lit:
				want = _vu_peak if n >= VU_SEGMENTS - 5 or (n == lit - 1 and _hit > 0.5) else _vu_on
			if _vu[n].material_override != want:
				_vu[n].material_override = want


func set_mood(m: Dictionary) -> void:
	mood = m
	_shine()


func _build_touch() -> void:
	var holder := Node3D.new()
	holder.name = "TouchKeys"
	holder.position = Vector3(TOUCH_X, TOUCH_Y, TOUCH_Z)
	_adopt(holder)
	var plate := MeshInstance3D.new()
	plate.name = "TouchPlate"
	var board := BoxMesh.new()
	board.size = Vector3(TOUCH_SIZE.x * TOUCH_COUNT + 0.02, 0.006, TOUCH_SIZE.y + 0.02)
	plate.mesh = board
	plate.position = Vector3(0, -0.001, 0)
	plate.material_override = Materials.chassis()
	holder.add_child(plate)
	for n in TOUCH_COUNT:
		var key := ModularTouch.new()
		key.name = "Touch%d" % n
		key.step = n
		key.base = touch_base
		key.size = TOUCH_SIZE
		key.position = Vector3(-TOUCH_SIZE.x * (TOUCH_COUNT - 1) * 0.5 + TOUCH_SIZE.x * n, 0.002, 0)
		key.pressed.connect(func(p: int, down: bool) -> void: touched.emit(p, down))
		key.octave_asked.connect(_move_octave)
		holder.add_child(key)
		touch_keys.append(key)


func _move_octave(by: int) -> void:
	touch_base = clampi(touch_base + by * 12, 24, 84)
	for key in touch_keys:
		key.set_base(touch_base)


func _letter(text: String, cap: float, at: Vector3, colour: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.pixel_size = 0.0002
	l.font_size = roundi(cap / l.pixel_size)
	l.modulate = colour
	l.position = at
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.double_sided = false
	Lettering.range_to_legibility(l)
	return l


# --- the modules ------------------------------------------------------------------------------

## A key on the panel.
func _key(legend: String, size: Vector2, at: Vector3, says: String, press: Callable, lit := false) -> EqWall.WallKey:
	var k := EqWall.WallKey.new()
	k.legend = legend
	k.size = size
	k.says = says
	k.position = at
	k.lit = lit
	k.describe_title = func() -> String: return "RACK  %s" % legend
	k.pressed.connect(press)
	# A legend that is longer than its key is set smaller, to fit.
	k.ready.connect(func() -> void:
		var l := k.get_node_or_null("Legend") as Label3D
		var need := legend.length() * 0.0195
		if l != null and need > size.x - 0.012:
			l.font_size = maxi(8, roundi(l.font_size * (size.x - 0.012) / need)))
	return k


## A node out of the tree at once and freed at the frame's end: what replaces it never stands over it.
func _drop(n: Node) -> void:
	if n.get_parent() != null:
		n.get_parent().remove_child(n)
	n.queue_free()


## A jack's key in `jacks`: a module can have an input and an output of one name (a reverb's `l`), so an
## output's carries a mark.
static func _jack_key(path: String, is_output: bool) -> String:
	return path + ">" if is_output else path


func _clear_modules() -> void:
	for n in module_nodes.values():
		if is_instance_valid(n):
			_drop(n)
	module_nodes.clear()
	jacks.clear()
	knobs.clear()
	_lamps.clear()
	_scopes.clear()
	_bands.clear()
	_settle_at.clear()
	_stream_due.clear()


## A blank plate in every place no module holds, so the case reads as a full rack with room left.
func _build_blanks() -> void:
	var taken := {}
	for id in patch["modules"]:
		var m: Dictionary = patch["modules"][id]
		for c in RackLayout.width_of(m["type"]):
			taken[Vector2i(int(m["at"][0]) + c, int(m["at"][1]))] = true
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.085, 0.085, 0.09)
	paint.metallic = 0.4
	paint.roughness = 0.5
	for row in ROWS:
		for col in COLS:
			if taken.has(Vector2i(col, row)):
				continue
			var holder := Node3D.new()
			holder.name = "Blank_%d_%d" % [col, row]
			holder.position = Vector3(_x_of(col + 0.5), _row_foot(row), 0)
			var plate := MeshInstance3D.new()
			var face := BoxMesh.new()
			face.size = Vector3(MODULE_WIDE - 0.003, ROW_TALL - 0.004, 0.004)
			plate.mesh = face
			plate.position = Vector3(0, ROW_TALL * 0.5, -0.002)
			plate.material_override = paint
			holder.add_child(plate)
			for y in [0.014, ROW_TALL - 0.014]:
				var screw := MeshInstance3D.new()
				var disc := CylinderMesh.new()
				disc.top_radius = 0.0045
				disc.bottom_radius = 0.0045
				disc.height = 0.002
				screw.mesh = disc
				screw.rotation_degrees = Vector3(90, 0, 0)
				screw.position = Vector3(0, y, 0.001)
				screw.material_override = Materials.brushed_metal()
				holder.add_child(screw)
			_put(holder)
			module_nodes["blank/%d_%d" % [col, row]] = holder


func _build_module(id: String) -> void:
	var m: Dictionary = patch["modules"][id]
	var type: String = m["type"]
	var spec := RackCatalogue.spec(type)
	var w := RackLayout.width_of(type)
	var col := int(m["at"][0])
	var row := int(m["at"][1])
	var holder := Node3D.new()
	holder.name = "Module_%s" % id
	holder.position = Vector3(_x_of(col + w * 0.5), _row_foot(row), 0)
	var wide := MODULE_WIDE * w
	var plate := MeshInstance3D.new()
	plate.name = "Plate"
	var face := BoxMesh.new()
	face.size = Vector3(wide - 0.003, ROW_TALL - 0.004, 0.004)
	plate.mesh = face
	plate.position = Vector3(0, ROW_TALL * 0.5, -0.002)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = RackSkin.face(type, (col + row) % 2 == 1)
	paint.roughness = 0.6
	plate.material_override = paint
	holder.add_child(plate)
	var title: String = spec["title"]
	holder.add_child(_letter(title, TITLE_CAP, Vector3(0, ROW_TALL - 0.026, 0.001), Color(0.95, 0.9, 0.78)))
	var tint := _tint_of(type)
	var print_strip := RackSkin.print_pattern(type, wide - 0.016, 0.012)
	if print_strip != null:
		print_strip.position = Vector3(0, ROW_TALL - 0.064, 0.0006)
		holder.add_child(print_strip)
	var tag := RackSkin.tagline(type)
	if tag != "":
		var tag_label := _letter(tag, LETTER_CAP * 0.62, Vector3(0, 0.015, 0.001), tint.lerp(Color(1, 1, 1), 0.35))
		holder.add_child(tag_label)
	var band := MeshInstance3D.new()
	band.name = "Band"
	var strip := BoxMesh.new()
	strip.size = Vector3(wide - 0.01, 0.005, 0.001)
	band.mesh = strip
	band.position = Vector3(0, ROW_TALL - 0.045, 0.0005)
	var colour := StandardMaterial3D.new()
	colour.albedo_color = tint
	colour.emission = tint
	band.material_override = colour
	_bands[id] = colour
	holder.add_child(band)
	var lamp := MeshInstance3D.new()
	lamp.name = "Lamp"
	var disc := CylinderMesh.new()
	disc.top_radius = 0.005
	disc.bottom_radius = 0.005
	disc.height = 0.003
	lamp.mesh = disc
	lamp.rotation_degrees = Vector3(90, 0, 0)
	lamp.position = Vector3(-wide * 0.5 + 0.012, ROW_TALL - 0.026, 0.002)
	lamp.material_override = _lamp_cold
	holder.add_child(lamp)
	_lamps[id] = lamp
	if type != "out":
		var gone := _key("x", Vector2(0.02, 0.02), Vector3(wide * 0.5 - 0.014, ROW_TALL - 0.026, 0.0),
				"take %s out of the case, and its cables with it" % title, func() -> void: edit_asked.emit("remove", [id]))
		holder.add_child(gone)
		module_nodes[id + "/x"] = gone
	# Knobs, down from under the title, a row of 2*w.
	var per := 2 * w
	var ks: Array = spec["knobs"]
	for n in ks.size():
		var r := n / per
		var inrow := mini(per, ks.size() - r * per)
		var c := n % per
		var at := Vector3((c - (inrow - 1) * 0.5) * KNOB_PITCH, ROW_TALL - 0.1 - r * KNOB_ROW, 0.0)
		_build_knob(holder, id, ks[n], at)
	if type == "scope":
		var screen := ScopeScreen.new()
		screen.size = Vector2(wide - 0.03, 0.2)
		screen.tint = _tint_of(type)
		screen.position = Vector3(0, 0.24, 0.003)
		holder.add_child(screen)
		_scopes[id] = screen
	# Jacks, up from the foot: inputs, then outputs (pale), per rows of 2*w.
	var paths: Array = []
	for port in spec["ins"]:
		paths.append([port, false])
	for port in spec["outs"]:
		paths.append([port, true])
	for n in paths.size():
		var r := n / per
		var inrow := mini(per, paths.size() - r * per)
		var c := n % per
		var path := "%s.%s" % [id, paths[n][0]]
		var j := RackJack.make(path, paths[n][1], title)
		j.position = Vector3((c - (inrow - 1) * 0.5) * KNOB_PITCH, 0.05 + r * JACK_ROW, 0.0)
		j.drag_began.connect(_on_drag_began)
		j.drag_moved.connect(_on_drag_moved)
		j.drag_finished.connect(_on_drag_finished)
		holder.add_child(j)
		jacks[_jack_key(path, paths[n][1])] = j
	_put(holder)
	module_nodes[id] = holder


func _build_knob(holder: Node3D, id: String, k: Dictionary, at: Vector3) -> void:
	var key := "%s.%s" % [id, k["id"]]
	var knob := Knob.new()
	knob.name = "Knob_%s" % key.replace(".", "_")
	knob.position = at + Vector3(0, 0.008, 0.008)
	knob.value = RackPatch.knob_of(patch, id, k["id"])
	var title := "%s  %s" % [RackCatalogue.spec(RackPatch.type_of(patch, id))["title"], k["label"]]
	knob.describe_title = func() -> String: return "RACK  %s" % title
	knob.describe_value = func(v: float) -> String: return RackCatalogue.readout(k, v)
	knob.turned.connect(func(v: float) -> void: _on_knob_turned(id, k["id"], v))
	knob.value_committed.connect(func(_v: float) -> void: _settle_at[key] = int(clock.call()) + roundi(SETTLE * 1000.0))
	holder.add_child(knob)
	knobs[key] = knob
	var label := String(k["label"])
	holder.add_child(_letter(label.substr(0, 5), LETTER_CAP * 0.85, at + Vector3(0, -0.02, 0.001), Color(0.85, 0.83, 0.78)))


func _tint_of(type: String) -> Color:
	return RackSkin.accent(type)


# --- the palette ------------------------------------------------------------------------------

func _build_palette() -> void:
	for n in _palette_nodes:
		if is_instance_valid(n):
			_drop(n)
	_palette_nodes.clear()
	var groups: Array = RackCatalogue.GROUPS.duplicate()
	groups.append(GROUP_PRESETS)
	var key_size := Vector2(MODULE_WIDE - 0.008, 0.05)
	for i in groups.size():
		var g: String = groups[i]
		var k := _key(g.to_upper(), key_size,
				Vector3(_x_of(i + 0.5), PALETTE_TALL - 0.04, 0.0), "show the %s modules" % g.to_lower(),
				func() -> void: show_group(g), g == group)
		_palette_nodes.append(k)
		panel.add_child(k)
		k.set_meta("built", true)
	_extras.clear()
	var extra := [[9.5, "PLAY", "play the rack from the computer keys", func() -> void: keys_asked.emit(), _playing, "play"],
			[11.5, _track_legend(), "choose the track the rack sounds through (round the tracks, then none)",
			func() -> void: track_asked.emit(), _track > 0, "track"],
			[13.5, "REC", "record what the rack plays onto its track; again to keep it",
			func() -> void: record_asked.emit(), _recording, "rec"]]
	for e in extra:
		var xk := _key(String(e[1]), key_size, Vector3(_x_of(e[0]), PALETTE_TALL - 0.04, 0.0), String(e[2]), e[3], e[4])
		_palette_nodes.append(xk)
		panel.add_child(xk)
		xk.set_meta("built", true)
		_extras[e[5]] = xk
		if e[5] == "play":
			play_key = xk
	var items: Array = []
	if group == GROUP_PRESETS:
		for p in RackPatch.presets():
			items.append([String(p), RackPatch.preset_title(p), "preset", [String(p)]])
	else:
		for t in RackCatalogue.in_group(group):
			items.append([t, String(RackCatalogue.spec(t)["title"]), "add", [t, -1, 0]])
	for i in mini(items.size(), COLS):
		var it: Array = items[i]
		var says := ("put a %s in the next free place in the case" % it[1]) if it[2] == "add" \
				else "replace the case with the preset %s" % it[1]
		var op: String = it[2]
		var args: Array = it[3]
		var k := _key(String(it[1]).substr(0, 8), key_size, Vector3(_x_of(i + 0.5), 0.045, 0.0), says,
				func() -> void: edit_asked.emit(op, args))
		_palette_nodes.append(k)
		panel.add_child(k)
		k.set_meta("built", true)
	_apply_reach()


func _track_legend() -> String:
	if _track <= 0:
		return "TRK -"
	return ("T%d %s" % [_track, _track_name]).substr(0, 8)


## The track the rack sounds through (0 for none) and its name, on the TRK key.
func set_track(t: int, track_name := "") -> void:
	if t == _track and track_name == _track_name:
		return
	_track = t
	_track_name = track_name
	_build_palette()


func set_recording(on: bool) -> void:
	if on != _recording:
		_recording = on
		_build_palette()


func is_recording() -> bool:
	return _recording


func show_group(g: String) -> void:
	group = g
	_build_palette()


# --- what it shows ----------------------------------------------------------------------------

## The room's patch, shown. The modules are rebuilt only when their shape changes (one put in, taken
## out, moved, or a different set of knobs); a cable or a knob value changes in place.
func show_patch(to: Dictionary) -> void:
	patch = RackPatch.sanitize(to)
	var shape := _shape_of(patch)
	if shape != _shape_key or panel.get_node_or_null("Palette") == null and _palette_nodes.is_empty():
		_shape_key = shape
		var held := turning()
		_clear_modules()
		for id in patch["modules"]:
			_build_module(id)
		_build_blanks()
		_seat_pillars()
		_build_palette()
		for key in held:
			if knobs.has(key):
				(knobs[key] as Knob).apply_remote(held[key])
	for key: String in knobs:
		var k: Knob = knobs[key]
		if not k.is_held() and not _settle_at.has(key):
			k.apply_remote(RackPatch.knob_of(patch, key.get_slice(".", 0), key.get_slice(".", 1)))
	for key: String in jacks:
		var j: RackJack = jacks[key]
		var path := String(j.jack)
		j.plugged_to.clear()
		for c in patch["cables"]:
			if j.output and c[0] == path:
				j.plugged_to.append(StringName(c[1]))
			elif not j.output and c[1] == path:
				j.plugged_to.append(StringName(c[0]))
	_lay_cables()
	_apply_reach()


func _shape_of(p: Dictionary) -> String:
	var parts: Array = []
	for id in RackPatch.module_ids(p):
		parts.append("%s:%s@%s,%s" % [id, p["modules"][id]["type"], p["modules"][id]["at"][0], p["modules"][id]["at"][1]])
	return "|".join(parts)


func show_knob(id: String, k: String, v: float) -> void:
	var node: Knob = knobs.get("%s.%s" % [id, k])
	if node != null:
		node.apply_remote(v)


## How loud each module is now ({id: peak}), on its lamp.
## The module meters in the order of the modules across the case, for the room's own lights.
func module_levels(meters: Dictionary) -> Array:
	var out := []
	for id in _pillar_for:
		out.append(float(meters.get(id, 0.0)) if id != "" else 0.0)
	return out


## The traces of the SCOPE modules' screens: module id -> points.
func show_scopes(waves: Dictionary) -> void:
	for id: String in _scopes:
		if is_instance_valid(_scopes[id]):
			(_scopes[id] as ScopeScreen).set_wave(waves.get(id, PackedFloat32Array()))


func show_meters(meters: Dictionary) -> void:
	for n in _pillars.size():
		var id: String = _pillar_for[n]
		var want := clampf(float(meters.get(id, 0.0)), 0.0, 1.0) if id != "" else 0.0
		var now := _pillar_level[n]
		_grow_pillar(n, lerpf(now, want, 0.5 if want > now else 0.15))
	for id: String in _lamps:
		var on := float(meters.get(id, 0.0)) > 0.02
		var lamp: MeshInstance3D = _lamps[id]
		if is_instance_valid(lamp):
			var want := _lamp_hot if on else _lamp_cold
			if lamp.material_override != want:
				lamp.material_override = want
		var band: StandardMaterial3D = _bands.get(id)
		if band != null:
			band.emission_enabled = on
			band.emission_energy_multiplier = 1.8


func turning() -> Dictionary:
	var out := {}
	for key: String in knobs:
		var k: Knob = knobs[key]
		if k.is_held() or _settle_at.has(key):
			out[key] = k.value
	return out


func _lay_cables() -> void:
	for c in cables:
		if is_instance_valid(c):
			# Out of the tree at once, so a laid-again cable never stands over its predecessor.
			if c.get_parent() != null:
				c.get_parent().remove_child(c)
			c.queue_free()
	cables.clear()
	if not is_inside_tree():
		return
	var fanned := {}
	for c: Array in patch["cables"]:
		var a: RackJack = jacks.get(_jack_key(c[0], true))
		var b: RackJack = jacks.get(_jack_key(c[1], false))
		if a == null or b == null:
			continue
		var tint := _tint_of(RackPatch.type_of(patch, String(c[0]).get_slice(".", 0)))
		# A second cable from one output stands its plug further out, so the plugs never share a face.
		var from_plug := a.plug_transform()
		var fan: int = fanned.get(c[0], 0)
		fanned[c[0]] = fan + 1
		from_plug.origin += from_plug.basis.z.normalized() * 0.014 * fan
		var cable := PatchCable.create(from_plug, b.plug_transform(), tint, hash(c))
		cable.name = "Cable_%s_%s" % [c[0], c[1]]
		var span := a.plug_transform().origin.distance_to(b.plug_transform().origin)
		cable.sag_ratio = CABLE_SAG if absf(a.global_position.x - b.global_position.x) < MODULE_WIDE * 2.0 \
				else clampf(0.25 / maxf(span, 0.05), CABLE_SAG, 0.6)
		cable.set_meta(&"cable", [c[0], c[1]])
		add_child(cable)
		cables.append(cable)


func show_keys(pitch: int, gate: bool) -> void:
	if play_key != null:
		play_key.lit = gate


func show_playing(on: bool) -> void:
	_playing = on
	if play_key != null:
		play_key.lit = on


func _apply_reach() -> void:
	for c in reach_controls():
		for node in c.get_children():
			if node is CollisionShape3D:
				(node as CollisionShape3D).disabled = not within_reach


func reach_controls() -> Array[ControlAffordance]:
	var out: Array[ControlAffordance] = []
	for j: RackJack in jacks.values():
		out.append(j)
	for k: Knob in knobs.values():
		out.append(k)
	for t in touch_keys:
		out.append(t)
	for n in _palette_nodes:
		if n is ControlAffordance:
			out.append(n)
	for key in module_nodes:
		if str(key).ends_with("/x"):
			out.append(module_nodes[key])
	for n in get_children():
		if n is SurfaceHandle:
			out.append(n)
	return out


# --- a knob's turn ----------------------------------------------------------------------------

func _on_knob_turned(id: String, k: String, v: float) -> void:
	knob_turning.emit(id, k, v)
	var key := "%s.%s" % [id, k]
	var now := int(clock.call())
	if now - int(_streamed_at.get(key, -100000)) >= STREAM_GAP_MSEC:
		_streamed_at[key] = now
		_stream_due.erase(key)
		knob_streamed.emit(id, k, v)
	else:
		_stream_due[key] = [id, k, v]


# --- carrying a cable -------------------------------------------------------------------------

func _on_drag_began(from: ModularJack, at: Vector3) -> void:
	var path := String(from.jack)
	var fixed: Transform3D = from.plug_transform()
	var tint := _tint_of(RackPatch.type_of(patch, path.get_slice(".", 0)))
	var lifted_from := ""
	var hidden: PatchCable = null
	if not from.output:
		# An input with cables gives up the newest: its plug comes out of here.
		for i in range(patch["cables"].size() - 1, -1, -1):
			if patch["cables"][i][1] == path:
				lifted_from = patch["cables"][i][0]
				break
		if lifted_from != "" and jacks.has(_jack_key(lifted_from, true)):
			fixed = (jacks[_jack_key(lifted_from, true)] as RackJack).plug_transform()
			tint = _tint_of(RackPatch.type_of(patch, lifted_from.get_slice(".", 0)))
			hidden = _cable_between(lifted_from, path)
			if hidden != null:
				hidden.visible = false
	var carried := PatchCable.create(fixed, _loose_end(at), tint, from.get_instance_id())
	carried.name = "CarriedCable"
	carried.sag_ratio = CABLE_SAG
	add_child(carried)
	_drag = {"from": from, "lifted": lifted_from, "cable": carried, "hidden": hidden, "target": null}
	for j in _candidates(from, lifted_from):
		j.set_light(ModularJack.Light.CANDIDATE)


func _cable_between(a: String, b: String) -> PatchCable:
	for c in cables:
		if is_instance_valid(c) and (c.get_meta(&"cable") as Array) == [a, b]:
			return c
	return null


func _on_drag_moved(from: ModularJack, at: Vector3, over: ControlAffordance) -> void:
	if _drag.is_empty() or _drag["from"] != from:
		return
	var target := _target_for(from, over)
	var before: RackJack = _drag["target"]
	if before != target:
		if before != null:
			before.set_light(ModularJack.Light.CANDIDATE)
		if target != null:
			target.set_light(ModularJack.Light.TARGET)
		_drag["target"] = target
	var cable: PatchCable = _drag["cable"]
	cable.to_xform = target.plug_transform() if target != null else _loose_end(at)
	cable.rebuild()


func _on_drag_finished(from: ModularJack, over: ControlAffordance) -> void:
	if _drag.is_empty() or _drag["from"] != from:
		return
	var target := _target_for(from, over)
	var lifted: String = _drag["lifted"]
	var carried: PatchCable = _drag["cable"]
	if is_instance_valid(carried):
		carried.queue_free()
	var hidden: PatchCable = _drag["hidden"]
	if hidden != null and is_instance_valid(hidden):
		hidden.visible = true
	_drag.clear()
	for j: RackJack in jacks.values():
		j.set_light(ModularJack.Light.PLAIN)
	if lifted != "":
		if over == from:
			return
		edit_asked.emit("pull_one", [lifted, String(from.jack)])
		if target != null:
			edit_asked.emit("cable", [lifted, String(target.jack)])
			Foley.play(target, Foley.plug_seat(), -6.0)
		return
	if target == null:
		return
	var source := from if from.output else target
	var sink := target if from.output else from
	edit_asked.emit("cable", [String(source.jack), String(sink.jack)])
	Foley.play(target, Foley.plug_seat(), -6.0)


## The jacks a cable carried from `from` could be let go on: from an output, every input of another
## module; from an input, every output of another module.
func _candidates(from: RackJack, lifted: String) -> Array[RackJack]:
	var out: Array[RackJack] = []
	var mine := String(from.jack).get_slice(".", 0)
	for j: RackJack in jacks.values():
		if j == from or String(j.jack).get_slice(".", 0) == mine and lifted == "":
			continue
		if lifted != "":
			if not j.output and String(j.jack).get_slice(".", 0) != lifted.get_slice(".", 0):
				out.append(j)
		elif j.output != from.output:
			out.append(j)
	return out


func _target_for(from: RackJack, over: ControlAffordance) -> RackJack:
	var j := over as RackJack
	if j == null or j == from:
		return null
	return j if _candidates(from, _drag.get("lifted", "")).has(j) else null


func _loose_end(at: Vector3) -> Transform3D:
	var basis := global_transform.basis.orthonormalized()
	return Transform3D(basis, at + basis.z * 0.03)
