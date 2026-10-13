class_name TimelineHighway
extends Node3D

## The arrangement as a road: tracks are lanes side by side, time runs away from you, and the
## playhead is a lit gate at your end of it. What is about to play comes down the road toward the
## gate; what the gate is over is lit in its lane.
##
## This is the one use of depth in the timeline that has been proven elsewhere -- it is the note
## highway every rhythm game since GuitarFreaks has used -- and it is a VIEW, not an editor. The
## flat lanes are where an arrangement is cut, moved and trimmed, because that wants a surface
## with millimetre precision and a ruler; this is for watching a song arrive while it plays, or
## for reading what is coming without scrolling. It takes no presses of its own.
##
## It is built once per set of lanes (`configure`) and moved every frame it is shown (`_process`),
## from the same MixState the flat view draws, so there is nothing here to keep in step.

## How much of the song is on the road, in bars from the playhead.
const AHEAD_BARS := 6.0
## How far the road is laid back from the panel, degrees from flat on the panel. Steeper reads
## more like a wall; shallower, more like a floor seen at a grazing angle.
const TILT_DEGREES := 58.0
const BLOCK_HEIGHT := 0.009
const BLOCK_SELECTED_LIFT := 0.006
## A gap between a block and the next on its lane, and between a block and the lane's edge.
const LANE_MARGIN := 0.0045
const GAP := 0.0015
const MAX_NAMES := 28
const APRON := 0.040

const ROAD_BED := Color(0.022, 0.026, 0.036)
const LANE_STRIPE := Color(0.045, 0.052, 0.068)
const LANE_RULE := Color(0.20, 0.23, 0.30)
const BAR_LINE := Color(0.34, 0.37, 0.45)
const BEAT_LINE := Color(0.075, 0.085, 0.11)
const GATE_COLOUR := Color(1.0, 0.92, 0.55)

static var _block_shader: Shader

var _road: Node3D
var _tracks: Array = []
var _width := 0.8
var _length := 0.4
var _blocks: MeshBank
var _lines: MeshBank
var _pads: Array[MeshInstance3D] = []
var _pad_lit: Array[bool] = []
var _names: Array[Label3D] = []
var _lane_names: Array[Label3D] = []
var _lane_colours: Array[Color] = []


## Lay the road over a lane area: `area_x`/`width` across it, `bottom`/`top` its height on the
## panel, `tracks` the track indices a lane each, left to right.
func configure(area_x: float, width: float, bottom: float, top: float, tracks: Array) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_pads.clear()
	_pad_lit.clear()
	_names.clear()
	_lane_names.clear()
	_lane_colours.clear()
	_tracks = tracks.duplicate()
	_width = width
	var tilt := deg_to_rad(TILT_DEGREES)
	_length = maxf(top - bottom - APRON * sin(tilt), 0.05) / sin(tilt)

	_road = Node3D.new()
	_road.name = "Road"
	_road.position = Vector3(area_x + width * 0.5, bottom + APRON * sin(tilt), 0.006)
	# Laid back: far end up and away. About x by +tilt takes the road's -z (forward) to up and away.
	_road.rotation.x = tilt
	add_child(_road)

	var lanes := maxi(_tracks.size(), 1)
	var lane_w := width / lanes
	# Behind the far end, a dark wall, so the road is seen against something and not the room.
	var back := (top - bottom) + 0.01
	var depth := _length * cos(tilt) + 0.03
	add_child(_flat(Vector3(width + 0.03, back + 0.01, 0.001),
			Vector3(area_x + width * 0.5, (top + bottom) * 0.5, 0.006 - depth), Color(0.012, 0.014, 0.021)))
	# The bed, and the apron under the gate that the track names stand on.
	_road.add_child(_flat(Vector3(width, 0.0016, _length + APRON), Vector3(0, -0.0010, -_length * 0.5 + APRON * 0.5), ROAD_BED))
	for i in lanes:
		var x := -width * 0.5 + (i + 0.5) * lane_w
		var track := DAW.state.track(_tracks[i]) if i < _tracks.size() else null
		var colour := track.colour if track != null else Color(0.5, 0.5, 0.55)
		_lane_colours.append(colour)
		if i % 2 == 0:
			_road.add_child(_flat(Vector3(lane_w, 0.0006, _length), Vector3(x, 0.0, -_length * 0.5),
					LANE_STRIPE.lerp(colour, 0.10)))
		else:
			_road.add_child(_flat(Vector3(lane_w, 0.0006, _length), Vector3(x, 0.0, -_length * 0.5),
					ROAD_BED.lerp(colour, 0.06)))
		# The lane's edge: a rule down the road, brighter in its own colour near the gate.
		_road.add_child(_flat(Vector3(0.0007, 0.0012, _length), Vector3(x - lane_w * 0.5, 0.0004, -_length * 0.5),
				LANE_RULE.lerp(colour, 0.35)))
		# The receptor under the gate, lit while its lane has something under the gate.
		var pad := MeshInstance3D.new()
		var pad_mesh := BoxMesh.new()
		pad_mesh.size = Vector3(lane_w - 0.004, 0.003, 0.016)
		pad.mesh = pad_mesh
		pad.position = Vector3(x, 0.0016, 0.012)
		pad.material_override = Materials.led(colour, false)
		pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_road.add_child(pad)
		_pads.append(pad)
		_pad_lit.append(false)
		# The track's name on the apron, lying in the road's plane so it is read as the road is.
		if track != null:
			var name_label := _label(track.display_name(), 56, Color(1.0, 0.97, 0.9))
			name_label.rotation.x = -PI * 0.5
			name_label.position = Vector3(x, 0.002, APRON * 0.66)
			Lettering.fit(name_label, lane_w - 0.006, 56 * 4, 26 * 4)
			_road.add_child(name_label)
			_lane_names.append(name_label)
	_road.add_child(_flat(Vector3(width + 0.012, 0.0012, 0.0016), Vector3(0, 0.0004, APRON * 0.5), LANE_RULE))

	# The gate: a bar across the road at its near end, and a standing sheet of the same light.
	var gate := MeshInstance3D.new()
	var gate_mesh := BoxMesh.new()
	gate_mesh.size = Vector3(width + 0.012, 0.0034, 0.0034)
	gate.mesh = gate_mesh
	gate.position = Vector3(0, 0.0018, 0.0)
	gate.material_override = Materials.led(GATE_COLOUR, true)
	gate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_road.add_child(gate)
	var sheet := MeshInstance3D.new()
	var sheet_mesh := BoxMesh.new()
	sheet_mesh.size = Vector3(width, 0.020, 0.0001)
	sheet.mesh = sheet_mesh
	sheet.position = Vector3(0, 0.011, 0.0)
	sheet.material_override = TimelineSurface._halo_finish()
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_road.add_child(sheet)

	# Every block on every lane, banked: one draw call however big the project is.
	var total := 0
	for index in _tracks:
		total += DAW.state.track(index).items.size()
	_blocks = MeshBank.strips()
	_blocks.name = "Blocks"
	_blocks.material_override = _block_material()
	_blocks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blocks.extra_cull_margin = 2.0
	_road.add_child(_blocks)
	for i in maxi(total, 1):
		_blocks.claim(Transform3D(), Color.WHITE)
	_blocks.commit()
	_blocks.show_first(0)

	_lines = MeshBank.strips()
	_lines.name = "Lines"
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_road.add_child(_lines)
	for i in int(AHEAD_BARS) * 8 + 16:
		_lines.claim(Transform3D(), Color.WHITE)
	_lines.commit()
	_lines.show_first(0)

	for i in MAX_NAMES:
		var l := _label("", 40, Color(0.04, 0.045, 0.06))
		l.rotation.x = -PI * 0.5
		l.visible = false
		_road.add_child(l)
		_names.append(l)
	update_now()


func _process(_delta: float) -> void:
	if visible:
		update_now()


## Put every block, line and lamp where the song is now.
func update_now() -> void:
	if _road == null or _blocks == null:
		return
	var s := DAW.state
	var now := s.position_seconds
	var bar_now := s.bar_at(now)
	var end := s.bar_to_seconds(bar_now + 1.0 + AHEAD_BARS)
	var window := maxf(end - now, 0.001)
	var per_second := _length / window
	var lanes := maxi(_tracks.size(), 1)
	var lane_w := _width / lanes

	var slot := 0
	var names_used := 0
	for i in _tracks.size():
		var t := s.track(_tracks[i])
		var x := -_width * 0.5 + (i + 0.5) * lane_w
		var under_gate := false
		for item in t.items:
			var a := maxf(item.start, now)
			var b := minf(item.end(), end)
			if item.start <= now and item.end() > now and not item.muted and not t.mute:
				under_gate = true
			if b <= a or slot >= _blocks.count():
				continue
			var z_near := -(a - now) * per_second
			var z_far := -(b - now) * per_second
			var length := z_near - z_far - GAP
			if length <= 0.0006:
				continue
			var dim: bool = item.muted or t.mute
			var lift := BLOCK_SELECTED_LIFT if item.selected else 0.0
			var height := BLOCK_HEIGHT + lift
			# A block's top is higher the nearer it is to the gate, as if it had a ramp: that is what
			# makes what is next stand out of what is later.
			_blocks.move_slot(slot, Transform3D(Basis.IDENTITY.scaled(Vector3(lane_w - LANE_MARGIN * 2.0, height, length)),
					Vector3(x, height * 0.5 + 0.0003, (z_near + z_far) * 0.5 - GAP * 0.5)))
			_blocks.set_colour(slot, TimelineSurface.item_body(t.colour, dim, item.selected).srgb_to_linear())
			slot += 1
			# Its name, lying on it at its near end, while it is near enough to read.
			if names_used < _names.size() and not dim and absf(z_near) < _length * 0.55 and length > 0.02:
				var l := _names[names_used]
				var shown := TimelineSurface.shown_item_name(item.name, t.display_name())
				if shown != "":
					l.text = shown
					l.position = Vector3(x, height + 0.0006, z_near - 0.011)
					l.visible = true
					Lettering.fit(l, lane_w - 0.008, 40 * 4, 20 * 4)
					names_used += 1
		_light_pad(i, under_gate)
	for k in range(names_used, _names.size()):
		_names[k].visible = false
	_blocks.show_first(slot)

	# Bar and beat lines, scrolling down the road to the gate.
	var line := 0
	var first_bar := floorf(s.bar_at(now))
	var bar_n := first_bar
	while line < _lines.count() - 1:
		var at := s.bar_to_seconds(bar_n + 1.0)
		if at > end:
			break
		var beats := int(s.beats_per_bar)
		for beat in beats:
			var when := at + (s.bar_to_seconds(bar_n + 2.0) - at) * float(beat) / float(beats)
			if when < now or when > end or line >= _lines.count():
				continue
			var z := -(when - now) * per_second
			var is_bar := beat == 0
			_lines.move_slot(line, Transform3D(Basis.IDENTITY.scaled(Vector3(_width, 0.0004, 0.0018 if is_bar else 0.0008)),
					Vector3(0, 0.0007, z)))
			_lines.set_colour(line, (BAR_LINE if is_bar else BEAT_LINE).srgb_to_linear())
			line += 1
		bar_n += 1.0
	_lines.show_first(line)


func _light_pad(lane: int, lit: bool) -> void:
	if lane >= _pads.size() or _pad_lit[lane] == lit:
		return
	_pad_lit[lane] = lit
	_pads[lane].material_override = Materials.led(_lane_colours[lane], lit)


func lane_count() -> int:
	return _tracks.size()


func _flat(size: Vector3, at: Vector3, colour: Color) -> MeshInstance3D:
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	box.mesh = mesh
	box.position = at
	box.material_override = TimelineSurface.flat(colour)
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return box


func _label(content: String, size: int, tint: Color) -> Label3D:
	var l := Label3D.new()
	l.text = content
	l.font_size = size * 4
	l.pixel_size = 0.000078
	l.modulate = tint
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.double_sided = false
	l.shaded = false
	return l


## A block's finish: the instance's colour, shaded by which face is which -- top brightest, the
## end toward the gate next, the sides darker -- so a block reads as a solid slab on the road
## without the room's lamps, which would colour it by whatever they happen to be.
static func _block_material() -> ShaderMaterial:
	if _block_shader == null:
		_block_shader = Shader.new()
		_block_shader.code = """
shader_type spatial;
render_mode unshaded, shadows_disabled;

varying vec3 face;

void vertex() {
	face = NORMAL;
}

void fragment() {
	float shade = 0.46 + 0.54 * max(face.y, 0.0) + 0.24 * max(face.z, 0.0) - 0.10 * max(-face.z, 0.0);
	// Brighter than 1 on the top, so the glow pass picks the road's blocks up as lit.
	ALBEDO = COLOR.rgb * shade * 1.18;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _block_shader
	return m
