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
const TITLE_CAP := 0.032
const LETTER_CAP := 0.018
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
## What is built on the wall, {module id: [type, column, row]}, and the blank plates' paint.
var _on_wall := {}
var _blank_paint: StandardMaterial3D
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
## The two knobs of a module's orb pad, or an empty Array when it has none: the `pad_knobs` of the
## `rack_module` entry that provides the type.
static func pad_knobs(type: String) -> Array:
	var e := ModRegistry.ensure_current().rack_module_entry(type)
	return e["pad_knobs"] if e.get("pad_knobs") is Array else []


## Pads and bars on the modules: id -> {"node", "keys": [knob ids]}.
var _pads := {}
## A module being carried about the case: its id, node, ghost cell and where it came from.
var _carry := {}
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


var _shone_key := Vector3(-1, -1, -1)


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
	# Only when the light has actually moved: this is asked every frame, and it touches lights and
	# materials (and a light that is touched is a light the renderer redoes).
	var key := Vector3(roundf(_level * 150.0), roundf(_hit * 150.0), float(mood.hash() & 0xffff))
	if key == _shone_key:
		return
	_shone_key = key
	var base: Color = mood["base"]
	var flash: Color = mood["hit"]
	var colour := base.lerp(flash, clampf(_hit, 0.0, 1.0))
	_glow.light_color = colour
	_glow.light_energy = float(mood["glow"]) * (0.12 + _level * 0.8 + _hit * 0.3)
	_halo_material.albedo_color = Color(colour.r, colour.g, colour.b, clampf(0.03 + _level * 0.09 + _hit * 0.05, 0.0, 0.2))
	_edge_material.albedo_color = base.lerp(flash, clampf(_hit, 0.0, 1.0)) * (0.3 + _level * 0.6 + _hit * 0.2)
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


func _letter(text: String, cap: float, at: Vector3, colour: Color, width := 0.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.pixel_size = 0.0002
	l.font_size = roundi(cap / l.pixel_size)
	l.modulate = colour
	l.position = at
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.double_sided = false
	if width > 0.0:
		Lettering.fit(l, width, l.font_size, 24)
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
	if not _carry.is_empty():
		var g: Variant = _carry.get("ghost")
		if g is Node and is_instance_valid(g):
			(g as Node).queue_free()
		_carry.clear()
	for n in module_nodes.values():
		if is_instance_valid(n):
			_drop(n)
	module_nodes.clear()
	_on_wall.clear()
	jacks.clear()
	knobs.clear()
	_pads.clear()
	_lamps.clear()
	_scopes.clear()
	_bands.clear()
	_settle_at.clear()
	_stream_due.clear()


## A blank plate in every place no module holds, so the case reads as a full rack with room left. Only
## the places that changed are touched: a module put down or lifted fills or frees its own cells.
func _build_blanks() -> void:
	var taken := {}
	for id in patch["modules"]:
		var m: Dictionary = patch["modules"][id]
		for c in RackLayout.width_in(patch, id):
			taken[Vector2i(int(m["at"][0]) + c, int(m["at"][1]))] = true
	for key: String in module_nodes.keys():
		if not key.begins_with("blank/"):
			continue
		var cell := key.trim_prefix("blank/").split("_")
		if taken.has(Vector2i(int(cell[0]), int(cell[1]))):
			if is_instance_valid(module_nodes[key]):
				_drop(module_nodes[key])
			module_nodes.erase(key)
	if _blank_paint == null:
		_blank_paint = StandardMaterial3D.new()
		_blank_paint.albedo_color = Color(0.085, 0.085, 0.09)
		_blank_paint.metallic = 0.4
		_blank_paint.roughness = 0.5
	for row in ROWS:
		for col in COLS:
			if taken.has(Vector2i(col, row)) or module_nodes.has("blank/%d_%d" % [col, row]):
				continue
			var holder := Node3D.new()
			holder.name = "Blank_%d_%d" % [col, row]
			holder.position = Vector3(_x_of(col + 0.5), _row_foot(row), 0)
			var plate := MeshInstance3D.new()
			var face := BoxMesh.new()
			face.size = Vector3(MODULE_WIDE - 0.003, ROW_TALL - 0.004, 0.004)
			plate.mesh = face
			plate.position = Vector3(0, ROW_TALL * 0.5, -0.002)
			plate.material_override = _blank_paint
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


## The modules on the wall made to be the patch's, by the difference: one put in is built, one taken out
## is dropped, one moved is set in its new place. Rebuilding every module for one of them cost a visible
## stall when a module was let go. The ids whose nodes changed.
func _sync_modules() -> Dictionary:
	var changed := {}
	var now: Dictionary = patch["modules"]
	for id: String in _on_wall.keys():
		if not now.has(id) or now[id]["type"] != _on_wall[id][0]:
			_remove_module(id)
			_on_wall.erase(id)
			changed[id] = true
	for id: String in now:
		var m: Dictionary = now[id]
		var seen := [String(m["type"]), int(m["at"][0]), int(m["at"][1])]
		if not _on_wall.has(id):
			_build_module(id)
			changed[id] = true
		elif _on_wall[id] != seen:
			_move_module(id)
			changed[id] = true
		else:
			continue
		_on_wall[id] = seen
	return changed


func _remove_module(id: String) -> void:
	if not _carry.is_empty() and _carry["id"] == id:
		var g: Variant = _carry.get("ghost")
		if g is Node and is_instance_valid(g):
			(g as Node).queue_free()
		_carry.clear()
	var holder: Variant = module_nodes.get(id)
	if holder is Node and is_instance_valid(holder):
		_drop(holder as Node)
	module_nodes.erase(id)
	module_nodes.erase(id + "/x")
	for d: Dictionary in [jacks, knobs, _settle_at, _stream_due]:
		for key: String in d.keys():
			if key.begins_with(id + "."):
				d.erase(key)
	for d: Dictionary in [_pads, _lamps, _scopes, _bands]:
		d.erase(id)


## A module set in the cell the patch now has for it. The one a hand is carrying stays under the hand,
## and goes home to the new place when let go.
func _move_module(id: String) -> void:
	var m: Dictionary = patch["modules"][id]
	var holder: Node3D = module_nodes.get(id)
	if holder == null or not is_instance_valid(holder):
		return
	var col := int(m["at"][0])
	var row := int(m["at"][1])
	var to := Vector3(_x_of(col + RackLayout.width_in(patch, id) * 0.5), _row_foot(row), 0)
	if not _carry.is_empty() and _carry["id"] == id:
		_carry["home"] = to
	else:
		holder.position = to
	var plate := holder.get_node_or_null("Plate") as MeshInstance3D
	if plate != null:
		(plate.material_override as StandardMaterial3D).albedo_color = RackSkin.face(String(m["type"]), (col + row) % 2 == 1)


func _build_module(id: String) -> void:
	var m: Dictionary = patch["modules"][id]
	var type: String = m["type"]
	# A module no mod here provides is a plain plate (title: its type, "not installed"), in its place.
	var absent: bool = m.get("missing", false)
	var spec := {"title": "%s not installed" % type, "knobs": [], "ins": [], "outs": []} if absent else RackCatalogue.spec(type)
	var w := RackLayout.width_in(patch, id)
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
	holder.add_child(_letter(title, TITLE_CAP, Vector3(0, ROW_TALL - 0.03, 0.001), Color(1.0, 0.96, 0.84), wide - 0.05))
	var tint := _tint_of(type)
	var print_strip := RackSkin.print_pattern(type, wide - 0.016, 0.012)
	if print_strip != null:
		print_strip.position = Vector3(0, ROW_TALL - 0.064, 0.0006)
		holder.add_child(print_strip)
	var tag := RackSkin.tagline(type)
	if tag != "":
		var tag_label := _letter(tag, LETTER_CAP * 0.66, Vector3(0, 0.015, 0.001), tint.lerp(Color(1, 1, 1), 0.5), wide - 0.01)
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
	if type != RackPatch.OUT_MODULE:
		var gone := _key("x", Vector2(0.02, 0.02), Vector3(wide * 0.5 - 0.014, ROW_TALL - 0.026, 0.0),
				"take %s out of the case, and its cables with it" % title, func() -> void: edit_asked.emit("remove", [id]))
		holder.add_child(gone)
		module_nodes[id + "/x"] = gone
	# The grip along the title, clear of the take-out key: drag the module about the case.
	var grip := RackHandle.new()
	grip.name = "Grip"
	grip.module_id = id
	grip.module_title = title
	grip.size = Vector2(wide - 0.05, 0.034)
	grip.position = Vector3(-0.008, ROW_TALL - 0.026, 0.0)
	grip.drag_began.connect(_on_grip_began)
	grip.drag_moved.connect(_on_grip_moved)
	grip.drag_finished.connect(_on_grip_finished)
	holder.add_child(grip)
	# Knobs, down from under the title, a row of 2*w.
	var per := 2 * w
	var ks: Array = spec["knobs"]
	for n in ks.size():
		var r := n / per
		var inrow := mini(per, ks.size() - r * per)
		var c := n % per
		var at := Vector3((c - (inrow - 1) * 0.5) * KNOB_PITCH, ROW_TALL - 0.1 - r * KNOB_ROW, 0.0)
		_build_knob(holder, id, ks[n], at)
	if type == "builtin.scope":
		var screen := ScopeScreen.new()
		screen.size = Vector2(wide - 0.03, 0.2)
		screen.tint = _tint_of(type)
		screen.position = Vector3(0, 0.24, 0.003)
		holder.add_child(screen)
		_scopes[id] = screen
	_build_second_face(holder, id, type, spec, w, wide, tint)
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


## The free band of the panel between the knobs and the jacks, which a module's second face fills: an
## orb pad on two of its knobs, or for a sequencer its steps as bars to paint.
func _build_second_face(holder: Node3D, id: String, type: String, spec: Dictionary, w: int, wide: float, tint: Color) -> void:
	var per := 2 * w
	var krows := maxi(1, ceili(float((spec["knobs"] as Array).size()) / per))
	var jacks_n: int = (spec["ins"] as Array).size() + (spec["outs"] as Array).size()
	var jrows := maxi(1, ceili(float(jacks_n) / per))
	var top := 0.05 + (jrows - 1) * JACK_ROW + 0.035
	var bottom := ROW_TALL - 0.1 - (krows - 1) * KNOB_ROW - 0.03
	var band := bottom - top
	if type == "builtin.seq":
		var bars := RackBars.new()
		bars.name = "Steps"
		bars.count = 16
		bars.wide = wide - 0.02
		bars.tall = minf(0.15, band - 0.02)
		bars.tint = tint.lightened(0.25)
		bars.position = Vector3(0, top + 0.01, 0.0)
		var keys: Array = []
		for n in 16:
			keys.append("s%d" % (n + 1))
		holder.add_child(bars)
		for n in 16:
			bars.set_step(n, RackPatch.knob_of(patch, id, keys[n]))
		bars.painted.connect(func(step: int, v: float) -> void: _face_to(id, keys[step], v))
		bars.released.connect(func(steps: Array) -> void: _face_done(id, steps.map(func(n: int) -> String: return keys[n])))
		_pads[id] = {"node": bars, "keys": keys}
		return
	var ids := pad_knobs(type)
	if ids.is_empty():
		return
	var size := minf(minf(wide - 0.024, band - 0.012), 0.09)
	if size < 0.045:
		return
	if RackCatalogue.knob(type, ids[0]).is_empty() or RackCatalogue.knob(type, ids[1]).is_empty():
		return
	var pad := RackPad.new()
	pad.name = "Orb"
	pad.size = size
	pad.tint = tint.lightened(0.3)
	pad.position = Vector3(0, top + band * 0.5, 0.0)
	holder.add_child(pad)
	pad.set_xy(RackPatch.knob_of(patch, id, ids[0]), RackPatch.knob_of(patch, id, ids[1]))
	_pads[id] = {"node": pad, "keys": ids, "type": type}
	_refresh_curve(id)
	pad.moved.connect(func(x: float, y: float) -> void:
		_face_to(id, ids[0], x)
		_face_to(id, ids[1], y)
		_refresh_curve(id, {ids[0]: x, ids[1]: y}))
	pad.released.connect(func(_x: float, _y: float) -> void: _face_done(id, ids))


## A knob set from a module's second face: the knob on the wall goes there, and the turn is streamed
## to the room as a knob's own would be.
func _face_to(id: String, k: String, v: float) -> void:
	var node: Knob = knobs.get("%s.%s" % [id, k])
	if node != null:
		node.apply_remote(v)
	_on_knob_turned(id, k, v)


## Let go: the knobs it moved are asked for once more, at rest, when the echoes of the stream have passed.
func _face_done(id: String, keys: Array) -> void:
	var now := int(clock.call())
	for k in keys:
		_settle_at["%s.%s" % [id, k]] = now + roundi(SETTLE * 1000.0)


## The shape a module's knobs make (an envelope, a filter's response), drawn on its pad. `over` holds
## knob positions that are newer than the patch's, as while an orb is being dragged.
func _refresh_curve(id: String, over := {}) -> void:
	var f: Dictionary = _pads.get(id, {})
	if not (f.get("node") is RackPad):
		return
	var type: String = f.get("type", "")
	var values := {}
	for k in RackCatalogue.knob_ids(type):
		var pos: float = over[k] if over.has(k) else RackPatch.knob_of(patch, id, k)
		values[k] = RackCatalogue.real(RackCatalogue.knob(type, k), pos)
	var c := RackCurves.of(type, values)
	if c.size() > 1:
		(f["node"] as RackPad).set_curve(c)


## The second faces take their knobs' values, where a hand is not on them.
func _refresh_faces(only := "") -> void:
	for id: String in _pads:
		if only != "" and id != only:
			continue
		var f: Dictionary = _pads[id]
		var node: Node = f["node"]
		if not is_instance_valid(node):
			continue
		if node is RackPad:
			(node as RackPad).set_xy(RackPatch.knob_of(patch, id, f["keys"][0]), RackPatch.knob_of(patch, id, f["keys"][1]))
			_refresh_curve(id)
		elif node is RackBars and not (node as RackBars).is_held():
			for n in 16:
				(node as RackBars).set_step(n, RackPatch.knob_of(patch, id, f["keys"][n]))


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
	holder.add_child(_letter(label.substr(0, 6), LETTER_CAP * 0.9, at + Vector3(0, -0.022, 0.001), Color(0.95, 0.93, 0.88), KNOB_PITCH - 0.004))


func _tint_of(type: String) -> Color:
	return RackSkin.accent(type)


# --- the palette ------------------------------------------------------------------------------

func _build_palette() -> void:
	for n in _palette_nodes:
		if is_instance_valid(n):
			_drop(n)
	_palette_nodes.clear()
	var groups: Array = RackCatalogue.groups()
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
			func() -> void: record_asked.emit(), _recording, "rec"],
			[15.5, "TIDY", "lay the modules out as the signal flows, sources at the left and the OUT at the right",
			func() -> void: edit_asked.emit("tidy", []), false, "tidy"]]
	for e in extra:
		var xk := _key(String(e[1]), key_size, Vector3(_x_of(e[0]), PALETTE_TALL - 0.04, 0.0), String(e[2]), e[3], e[4])
		_palette_nodes.append(xk)
		panel.add_child(xk)
		xk.set_meta("built", true)
		_extras[e[5]] = xk
		if e[5] == "play":
			play_key = xk
	# What the cables' colours mean.
	var legend := [["AUDIO", RackSkin.SIGNAL_AUDIO], ["PITCH", RackSkin.SIGNAL_PITCH],
			["GATE", RackSkin.SIGNAL_GATE], ["CV", RackSkin.SIGNAL_CV]]
	for n in legend.size():
		var tag := _letter("o " + String(legend[n][0]), LETTER_CAP, Vector3(_x_of(18.5 + n * 2.2), PALETTE_TALL - 0.04, 0.0), legend[n][1])
		_palette_nodes.append(tag)
		panel.add_child(tag)
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
	var changed := {}
	var first := _palette_nodes.is_empty()
	if first:
		_clear_modules()
	var shape := _shape_of(patch)
	if shape != _shape_key or first:
		_shape_key = shape
		changed = _sync_modules()
		_build_blanks()
		_seat_pillars()
		if first:
			_build_palette()
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
	_refresh_faces()
	_lay_cables(changed)
	_apply_reach()


func _shape_of(p: Dictionary) -> String:
	var parts: Array = []
	for id in RackPatch.module_ids(p):
		parts.append("%s:%s@%s,%s" % [id, p["modules"][id]["type"], p["modules"][id]["at"][0], p["modules"][id]["at"][1]])
	return "|".join(parts)


func show_knob(id: String, k: String, v: float) -> void:
	RackPatch.set_knob(patch, id, k, v)
	var node: Knob = knobs.get("%s.%s" % [id, k])
	if node != null:
		node.apply_remote(v)
	if _pads.has(id):
		_refresh_faces(id)


## How loud each module is now ({id: peak}), on its lamp.
## The module meters in the order of the modules across the case, for the room's own lights.
func module_levels(meters: Dictionary) -> Array:
	var out := []
	for id in _pillar_for:
		out.append(float(meters.get(id, 0.0)) if id != "" else 0.0)
	return out


## The traces of the SCOPE modules' screens: module id -> points.
## The step each sequencer is on, lit on its bars.
func show_steps(on: Dictionary) -> void:
	for id: String in _pads:
		var node: Node = _pads[id]["node"]
		if node is RackBars and is_instance_valid(node):
			(node as RackBars).set_playhead(int(on.get(id, -1)))


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
			band.emission_energy_multiplier = 0.8 + clampf(float(meters.get(id, 0.0)), 0.0, 1.0) * 1.6
	# Each cable glows with what its source is putting out, so the signal can be followed by eye.
	for cable in cables:
		if is_instance_valid(cable):
			var ends: Array = cable.get_meta(&"cable", [])
			if ends.size() == 2:
				cable.set_glow(clampf(float(meters.get(String(ends[0]).get_slice(".", 0), 0.0)) * 1.6, 0.0, 1.0))


func turning() -> Dictionary:
	var out := {}
	for key: String in knobs:
		var k: Knob = knobs[key]
		if k.is_held() or _settle_at.has(key):
			out[key] = k.value
	return out


## The cables the patch has, each stood between its two plugs. A cable already stood and unchanged is
## kept: only those that are new, whose plug-in module is in `touching` (one moved, put in or lifted), or
## whose fan-out place changed are made again, so a module let go costs its own cables and not the case's.
func _lay_cables(touching := {}) -> void:
	var standing := {}
	for c in cables:
		if is_instance_valid(c):
			var ends: Array = c.get_meta(&"cable", [])
			if ends.size() == 2 and is_inside_tree():
				standing[String(ends[0]) + ">" + String(ends[1])] = c
				continue
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
		var fan: int = fanned.get(c[0], 0)
		fanned[c[0]] = fan + 1
		if a == null or b == null:
			continue
		var key := String(c[0]) + ">" + String(c[1])
		var old: PatchCable = standing.get(key)
		if old != null and int(old.get_meta(&"fan", 0)) == fan \
				and not touching.has(String(c[0]).get_slice(".", 0)) and not touching.has(String(c[1]).get_slice(".", 0)):
			standing.erase(key)
			cables.append(old)
			continue
		var tint := RackSkin.signal_of(String(c[0]).get_slice(".", 1))
		# A second cable from one output stands its plug further out, so the plugs never share a face.
		var from_plug := a.plug_transform()
		from_plug.origin += from_plug.basis.z.normalized() * 0.014 * fan
		var cable := PatchCable.create(from_plug, b.plug_transform(), tint, hash(c))
		cable.name = "Cable_%s_%s" % [c[0], c[1]]
		# Lit from within and drawn thicker than life: the wall is dark and seen from across the room.
		cable.lit = true
		cable.thickness = 2.0
		var span := a.plug_transform().origin.distance_to(b.plug_transform().origin)
		cable.sag_ratio = CABLE_SAG if absf(a.global_position.x - b.global_position.x) < MODULE_WIDE * 2.0 \
				else clampf(0.25 / maxf(span, 0.05), CABLE_SAG, 0.6)
		cable.set_meta(&"cable", [c[0], c[1]])
		cable.set_meta(&"fan", fan)
		if old != null:
			standing.erase(key)
			_drop(old)
		add_child(cable)
		cables.append(cable)
	for gone: PatchCable in standing.values():
		_drop(gone)


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


## Controls elsewhere in the room that this wall's hand reaches too (the CV bench's knobs).
var extra_controls: Array[ControlAffordance] = []


func reach_controls() -> Array[ControlAffordance]:
	var out: Array[ControlAffordance] = []
	out.append_array(extra_controls)
	for j: RackJack in jacks.values():
		out.append(j)
	for k: Knob in knobs.values():
		out.append(k)
	for t in touch_keys:
		out.append(t)
	for id: String in _pads:
		if is_instance_valid(_pads[id]["node"]):
			out.append(_pads[id]["node"])
	for key in module_nodes:
		var grip := (module_nodes[key] as Node).get_node_or_null("Grip") if not str(key).ends_with("/x") else null
		if grip is ControlAffordance:
			out.append(grip)
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


# --- carrying a module -----------------------------------------------------------------------

## The cell (column, row) whose module of `w` columns has its middle under `local`, a point of the panel.
func _cell_under(local: Vector3, w: int) -> Vector2i:
	var col := roundi((local.x + WIDE * 0.5) / MODULE_WIDE - w * 0.5)
	var up := (local.y - PALETTE_TALL) / (ROW_TALL + ROW_GAP)
	var row := ROWS - 1 - clampi(floori(up), 0, ROWS - 1)
	return Vector2i(clampi(col, 0, COLS - w), row)


func _on_grip_began(from: RackHandle, at: Vector3) -> void:
	var holder: Node3D = module_nodes.get(from.module_id)
	if holder == null:
		return
	var local: Vector3 = panel.to_local(at)
	var type := RackPatch.type_of(patch, from.module_id)
	var ghost := MeshInstance3D.new()
	ghost.name = "MoveGhost"
	var box := BoxMesh.new()
	var w := RackLayout.width_in(patch, from.module_id)
	box.size = Vector3(MODULE_WIDE * w - 0.003, ROW_TALL - 0.004, 0.006)
	ghost.mesh = box
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost.material_override = m
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	panel.add_child(ghost)
	_carry = {"id": from.module_id, "holder": holder, "ghost": ghost, "w": w, "type": type,
			"grab": holder.position - Vector3(local.x, local.y, 0.0), "home": holder.position, "cell": Vector2i(-1, -1), "relaid": 0}
	_carry_to(local)


func _on_grip_moved(from: RackHandle, at: Vector3) -> void:
	if _carry.is_empty() or _carry["id"] != from.module_id:
		return
	_carry_to(panel.to_local(at))


## The module lifted to follow the hand, and the cell it would settle in outlined: green where it fits.
func _carry_to(local: Vector3) -> void:
	var holder: Node3D = _carry["holder"]
	var w: int = _carry["w"]
	var lifted: Vector3 = local + (_carry["grab"] as Vector3)
	holder.position = Vector3(lifted.x, lifted.y, 0.05)
	var cell := _cell_under(Vector3(lifted.x, lifted.y + ROW_TALL * 0.5, 0.0), w)
	var fits := RackLayout.fits(patch, String(_carry["type"]), cell, String(_carry["id"]))
	var ghost: MeshInstance3D = _carry["ghost"]
	ghost.position = Vector3(_x_of(cell.x + w * 0.5), _row_foot(cell.y) + ROW_TALL * 0.5, 0.004)
	(ghost.material_override as StandardMaterial3D).albedo_color = Color(0.3, 1.0, 0.5, 0.22) if fits else Color(1.0, 0.3, 0.25, 0.2)
	_carry["cell"] = cell
	_carry["fits"] = fits
	# Its cables follow, as often as the wall can afford to lay them again.
	_carry["relaid"] = int(_carry["relaid"]) + 1
	if int(_carry["relaid"]) % 4 == 0:
		_lay_cables({String(_carry["id"]): true})


func _on_grip_finished(from: RackHandle, _at: Vector3) -> void:
	if _carry.is_empty() or _carry["id"] != from.module_id:
		return
	var holder: Node3D = _carry["holder"]
	var ghost: MeshInstance3D = _carry["ghost"]
	var cell: Vector2i = _carry["cell"]
	var id: String = _carry["id"]
	var home: Vector3 = _carry["home"]
	var fits: bool = _carry.get("fits", false)
	var here: Array = patch["modules"][id]["at"]
	_carry.clear()
	if is_instance_valid(ghost):
		ghost.queue_free()
	if is_instance_valid(holder):
		holder.position = home
	# Its cables back to where it stands, whatever the answer to the ask is (a refusal changes nothing).
	_lay_cables({id: true})
	if fits and (cell.x != int(here[0]) or cell.y != int(here[1])):
		Foley.play(holder, Foley.plug_seat(), -6.0)
		edit_asked.emit("move", [id, cell.x, cell.y])


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
