class_name SignalView
extends Node3D

## Seeing the signal (docs/spatial_loop.md part three, A and B): the audio path drawn in the room as
## glowing pipes, while this player has the signal glasses on (or X at a desk). Nothing here is room
## state and nothing is sent: it is one player's view of the graph (SignalGraph) the mix describes.
##
## THE PIPES. One a road between two places (`place`, given by whoever builds the view): a source
## to its track, a track to its folder, a send to its destination, a track to the master, the
## master to OUT. A road between stages at the same place (a track's input, plugins and fader all
## stand at its voice) is no pipe; its stages are the trace's. Each pipe is an arc of segments,
## every segment in the room one instance of one MultiMesh (one draw call), on the lamp material:
## glowing. THICKNESS is the level it carries (SignalGraph.thickness, its peak smoothed: fast up,
## slow down). COLOUR is health: the track's own colour while under SignalGraph.HOT_DB, amber from
## there to 0 dBFS, red past it, pulsing (still at Ergonomics.motion_scale 0). Never colour alone:
## every amber stage on a fader carries its figure, every clip its CLIPPING tag, every break a sign.
##
## THE SIGNS. Where a road stops (a stage with SignalGraph.Stage.halt), the pipe on from it is a
## dim stub ending at a sign: the reason in capitals, the sentence, and the fix's name with its key.
## A track's own playback stopped is said once, on the master: TRANSPORT STOPPED.
##
## THE TRACE (`trace`, "why can't I hear this?"): the trace's roads light white-hot a stage at a time
## (TRACE_STEP, all at once at motion 0) and a card says each stage with its level, stopping at the
## first break with its reason and its fix: on the screen a panel (`card`), in a headset the sign at
## the break, with a FIX key either way.

## The most pipe segments the room draws at once.
const CAPACITY := 3000
const RADIUS_MIN := 0.003
const RADIUS_MAX := 0.016
## A road's arc: how high its middle rises over its ends, at least and per metre of it.
const LIFT := 0.15
const LIFT_PER_M := 0.12
const SEGMENT_M := 0.22
## How the level a pipe shows follows its stage, per second, up and down.
const ATTACK := 30.0
const RELEASE := 4.0
const AMBER := Color(1.0, 0.64, 0.16)
const RED := Color(1.0, 0.16, 0.1)
const DIM := Color(0.34, 0.36, 0.4)
const WHITE := Color(1.0, 0.97, 0.9)
## How much of a road a stopped stage's stub runs.
const STUB := 0.18
## Labels nearer than this across the floor (m) stack, STACK_GAP apart.
const STACK_NEAR := 0.6
const STACK_GAP := 0.04
## How long each stage of a trace takes to light (s), at motion 1.
const TRACE_STEP := 0.18
## Signs and tags: how many of each are kept to reuse.
const SIGNS := 24
const TAGS := 24
## The reasons a sign is put up for in the room; the rest are the trace's to say.
const SIGNED := [SignalGraph.MUTED, SignalGraph.SOLOED_OUT, SignalGraph.FADER_SILENT, SignalGraph.SEND_SILENT,
		SignalGraph.MONITOR_OFF, SignalGraph.NO_INPUT, SignalGraph.PLUGIN_SILENT, SignalGraph.INSTRUMENT_BYPASSED,
		SignalGraph.NO_ROUTE, SignalGraph.MASTER_SILENT]

## (stage id) -> Vector3 in world space, or null where that stage stands nowhere in this room.
var place: Callable = Callable()
## (track) -> Color: the track's own colour as the room draws it.
var colour_of: Callable = func(track: int) -> Color:
	return DAW.state.track(track).shown_colour() if DAW.state != null and DAW.state.tracks.has(track) else Color(0.6, 0.62, 0.66)
## Ergonomics.motion_scale, for the pulse and the trace's pace.
var motion := 1.0
## Halts not signed just now: a look-solo held (docs/spatial_loop.md part three, G) leaves every
## other track SOLOED_OUT on purpose, and a sign on each would bury what is being listened to.
var quiet: Array = []
## The key a fix is done with at a desk, as a sign says it.
var fix_key_words := "Shift-Y"

## What was drawn last, for the suite: {road key: [shown dB, radius, colour, segments]}, the signs'
## and tags' texts, and how many segments.
var shown := {}
var signs_shown: Array[String] = []
var tags_shown: Array[String] = []
var segments := 0

var _mm: MultiMesh
var _pipes: MultiMeshInstance3D
var _signs: Array[Label3D] = []
var _tags: Array[Label3D] = []
var _clock := 0.0
## The trace being shown: its stages, how many are lit, and the clock that lights the next.
var tracing: SignalGraph.Trace = null
var trace_title := ""
var lit := 0
var _trace_clock := 0.0
## The card on a screen (a CanvasLayer child, built when `screen_card` is set) and its FIX button;
## the key in the room, by the break's sign.
var screen_card := false
var card: PanelContainer
var card_text: Label
var card_fix: Button
var fix_key: FixKey
## Over OUT: where the room's sound leaves for the speakers, with the master's level in words.
var _out_label: Label3D
## The trace's head: a bead at the stage it has reached, white while the sound is still going and red
## once it has stopped there (said in words on the card, the toast and the sign).
var _head: MeshInstance3D
const HEAD_RADIUS := 0.035
## A fix asked for here (the card's button, the room's key): the studio does it.
signal fix_asked(fix: Dictionary)


func _ready() -> void:
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	var tube := CylinderMesh.new()
	tube.top_radius = 1.0
	tube.bottom_radius = 1.0
	tube.height = 1.0
	tube.radial_segments = 8
	tube.rings = 1
	tube.cap_top = false
	tube.cap_bottom = false
	_mm.mesh = tube
	_mm.instance_count = CAPACITY
	_mm.visible_instance_count = 0
	_mm.custom_aabb = AABB(Vector3(-40, -4, -40), Vector3(80, 24, 80))
	_pipes = MultiMeshInstance3D.new()
	_pipes.name = "Pipes"
	_pipes.multimesh = _mm
	_pipes.material_override = MeshBank._lamp_material()
	_pipes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pipes)
	for i in SIGNS:
		_signs.append(_label("Sign%d" % i, 40, 0.0015))
	for i in TAGS:
		_tags.append(_label("Tag%d" % i, 32, 0.0014))
	_out_label = _label("Out", 32, 0.0012)
	_head = MeshInstance3D.new()
	_head.name = "TraceHead"
	var bead := SphereMesh.new()
	bead.radius = HEAD_RADIUS
	bead.height = HEAD_RADIUS * 2.0
	_head.mesh = bead
	_head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_head.visible = false
	add_child(_head)
	fix_key = FixKey.new()
	fix_key.name = "FixKey"
	fix_key.visible = false
	fix_key.pressed.connect(func() -> void:
		if tracing != null and not tracing.fix.is_empty():
			fix_asked.emit(tracing.fix))
	add_child(fix_key)
	if screen_card:
		_build_card()


func _label(named: String, size: int, pixel: float) -> Label3D:
	var l := Label3D.new()
	l.name = named
	l.font_size = size
	l.pixel_size = pixel
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = false
	l.outline_size = 10
	l.outline_modulate = Color(0.02, 0.02, 0.03, 0.92)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.render_priority = 3
	l.outline_render_priority = 2
	l.visible = false
	add_child(l)
	return l


func _build_card() -> void:
	var layer := CanvasLayer.new()
	layer.name = "TraceCard"
	layer.layer = 40
	add_child(layer)
	card = PanelContainer.new()
	card.name = "Card"
	card.anchor_left = 1.0
	card.anchor_right = 1.0
	card.offset_left = -470.0
	card.offset_right = -24.0
	card.offset_top = 64.0
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.06, 0.065, 0.075, 0.9)
	box.border_color = Color(0.5, 0.52, 0.56, 0.6)
	box.set_border_width_all(1)
	box.set_content_margin_all(12)
	box.set_corner_radius_all(4)
	card.add_theme_stylebox_override("panel", box)
	var column := VBoxContainer.new()
	card.add_child(column)
	card_text = Label.new()
	card_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_text.custom_minimum_size = Vector2(420, 0)
	card_text.add_theme_font_size_override("font_size", 15)
	column.add_child(card_text)
	card_fix = Button.new()
	card_fix.focus_mode = Control.FOCUS_NONE
	card_fix.pressed.connect(func() -> void:
		if tracing != null and not tracing.fix.is_empty():
			fix_asked.emit(tracing.fix))
	column.add_child(card_fix)
	card.visible = false
	layer.add_child(card)


## Draw `g`: the pipes, the signs and the tags, and the trace's progress. Every frame while on.
func update(g: SignalGraph, delta: float) -> void:
	_clock += delta
	var used := 0
	var keep := {}
	var signs: Array = []
	var tags: Array = []
	var lit_roads := _lit_roads()
	for road in g.roads():
		var from: SignalGraph.Stage = g.stage(road[0])
		var to: SignalGraph.Stage = g.stage(road[1])
		var a: Variant = _where(from.id)
		var b: Variant = _where(to.id)
		if not (a is Vector3) or not (b is Vector3) or (a as Vector3).distance_to(b) < 0.05:
			continue
		var carried: SignalGraph.Stage = road[2]
		var key := "%s>%s" % [from.id, to.id]
		keep[key] = true
		var target := carried.peak_db if (carried.measured or carried.estimated) else SignalGraph.FLOOR_DB + 12.0
		var was: Array = shown.get(key, [target, 0.0, Color.BLACK, 0])
		var db: float = was[0]
		if not is_finite(db):
			db = SignalGraph.FLOOR_DB
		var aim := maxf(target, SignalGraph.FLOOR_DB - 6.0) if is_finite(target) else SignalGraph.FLOOR_DB - 6.0
		db = lerpf(db, aim, 1.0 - exp(-delta * (ATTACK if aim > db else RELEASE)))
		var stopped := from.halt != &"" or (carried != from and carried.halt != &"")
		var radius := lerpf(RADIUS_MIN, RADIUS_MAX, SignalGraph.thickness(db)) if not stopped else RADIUS_MIN
		# A road nothing measures (an instrument nobody is playing) is a thread: where it would go.
		if not stopped and not (carried.measured or carried.estimated):
			radius = RADIUS_MIN * 1.4
		var colour := _colour(carried, db, stopped)
		var reach := STUB if stopped else 1.0
		var n := clampi(int(ceil((a as Vector3).distance_to(b) / SEGMENT_M)), 3, 16)
		var drawn := 0
		for i in n:
			var t0 := float(i) / n * reach
			var t1 := float(i + 1) / n * reach
			if used >= CAPACITY:
				break
			_segment(used, _arc(a, b, t0), _arc(a, b, t1), radius, colour)
			used += 1
			drawn += 1
		# Lit by the trace: the same arc again, white-hot, a little thicker.
		if lit_roads.has(key) and not stopped:
			for i in n:
				if used >= CAPACITY:
					break
				_segment(used, _arc(a, b, float(i) / n), _arc(a, b, float(i + 1) / n), radius * 1.6 + 0.004, WHITE * 2.6)
				used += 1
				drawn += 1
		shown[key] = [db, radius, colour, drawn]
	for k in shown.keys():
		if not keep.has(k):
			shown.erase(k)
	_mm.visible_instance_count = used
	segments = used
	# The signs: a break in the room's roads, said where it is; the transport, once.
	var stopped_once := false
	for s: SignalGraph.Stage in g.stages.values():
		if s.halt in SIGNED and not quiet.has(s.halt):
			var at: Variant = _where(s.id)
			if at is Vector3:
				signs.append([at, _sign_text(s.halt, s.why, s.title, s.fix)])
		elif s.halt == SignalGraph.STOPPED and not stopped_once and _where("master") is Vector3:
			stopped_once = true
			signs.append([_where("master"), "TRANSPORT STOPPED\nthe tracks play when it rolls (Space, or PLAY on the tape deck)"])
		if (s.measured or s.estimated) and s.kind in [SignalGraph.Kind.FADER, SignalGraph.Kind.MASTER, SignalGraph.Kind.PLUGIN, SignalGraph.Kind.SEND]:
			var at2: Variant = _where(s.id)
			if not (at2 is Vector3):
				continue
			if s.peak_db > SignalGraph.CLIP_DB:
				tags.append([at2, SignalGraph.clip_words(s), RED])
			elif s.peak_db >= SignalGraph.HOT_DB and s.kind != SignalGraph.Kind.PLUGIN:
				tags.append([at2, "%s · %s" % [s.title, s.level_words()], AMBER])
	var out_at: Variant = _where("out")
	var master_stage: SignalGraph.Stage = g.stage("master")
	_out_label.visible = out_at is Vector3 and master_stage != null
	if _out_label.visible:
		_out_label.global_position = (out_at as Vector3) + Vector3.UP * 0.2
		_out_label.text = "OUT · TO THE SPEAKERS\nmaster %s" % master_stage.level_words()
	_show_labels(_signs, signs, Color(1.0, 0.86, 0.8), 0.48, signs_shown)
	_show_labels(_tags, tags, Color.WHITE, 0.2, tags_shown)
	_follow_trace(g, delta)


func _where(id: String) -> Variant:
	return place.call(id) if place.is_valid() else null


static func _arc(a: Vector3, b: Vector3, t: float) -> Vector3:
	# A short hop (a child's fader to its folder's strip) lifts less, or it reads as a spike.
	var d := a.distance_to(b)
	var lift := minf(LIFT, d * 0.3) + LIFT_PER_M * d
	return a.lerp(b, t) + Vector3.UP * lift * 4.0 * t * (1.0 - t)


func _segment(i: int, p: Vector3, q: Vector3, radius: float, colour: Color) -> void:
	var along := q - p
	var length := along.length()
	if length < 0.0001:
		_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), p))
		return
	var y := along / length
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	_mm.set_instance_transform(i, Transform3D(Basis(x * radius, y * length, z * radius), (p + q) * 0.5))
	_mm.set_instance_color(i, colour)


## A pipe's colour: its health, glowing more the louder it is. Red pulses but at motion 0.
func _colour(s: SignalGraph.Stage, db: float, stopped: bool) -> Color:
	if stopped:
		return DIM * 0.8
	if not s.measured and not s.estimated:
		return _track_colour(s.track) * 0.55
	var h := SignalGraph.health(db)
	var glow := 0.75 + 0.75 * SignalGraph.thickness(db)
	match h:
		&"clip":
			var pulse := 0.5 + 0.5 * sin(_clock * TAU * 2.0) if motion > 0.0 else 1.0
			return RED * (1.3 + 0.9 * pulse)
		&"hot":
			return AMBER * 1.5
		&"silent":
			return DIM * 0.7
	return _track_colour(s.track) * glow


func _track_colour(track: int) -> Color:
	return (colour_of.call(track) as Color) if track > 0 else Color(0.85, 0.86, 0.9)


static func _sign_text(reason: StringName, why: String, title: String, fix: Dictionary) -> String:
	var lines := [str(SignalGraph.HEADINGS.get(reason, String(reason).to_upper())), "%s: %s" % [title, why]]
	if not fix.is_empty():
		lines.append("fix: %s (Y, then Shift-Y)" % fix["label"])
	return "\n".join(lines)


func _show_labels(pool: Array[Label3D], rows: Array, ink: Color, rise: float, said: Array[String]) -> void:
	said.clear()
	for i in pool.size():
		var l := pool[i]
		if i >= rows.size():
			l.visible = false
			continue
		var row: Array = rows[i]
		l.visible = true
		# Two breaks at one place (two voices side by side on the stage table) stack, not overprint.
		l.text = row[1]
		var at := (row[0] as Vector3) + Vector3.UP * rise
		var tall := _tall(l)
		for again in 2:
			for n in i:
				var other := pool[n].global_position
				var gap := (_tall(pool[n]) + tall) * 0.5 + STACK_GAP
				if Vector2(other.x - at.x, other.z - at.z).length() < STACK_NEAR and absf(other.y - at.y) < gap:
					at.y = other.y + gap
		l.global_position = at
		l.modulate = row[2] if row.size() > 2 else ink
		said.append(row[1])


## How tall `l` stands in the room, its lines at its size (m).
static func _tall(l: Label3D) -> float:
	return (l.text.count("\n") + 1) * l.font_size * l.pixel_size * 1.45


# --- the trace ("why can't I hear this?") -----------------------------------------------------

## Show `tr`, traced from what is called `title`: its stages light from the first.
func trace(tr: SignalGraph.Trace, title: String) -> void:
	tracing = tr
	trace_title = title
	lit = tr.stages.size() if motion <= 0.0 else 1
	_trace_clock = 0.0
	_say_trace()


func clear_trace() -> void:
	tracing = null
	lit = 0
	_head.visible = false
	fix_key.visible = false
	if card != null:
		card.visible = false


## Whether every stage of the trace is lit.
func trace_done() -> bool:
	return tracing != null and lit >= tracing.stages.size()


func _follow_trace(g: SignalGraph, delta: float) -> void:
	if tracing == null:
		return
	if lit < tracing.stages.size():
		_trace_clock += delta
		while lit < tracing.stages.size():
			var step := _step_to(lit) / maxf(motion, 0.05)
			if _trace_clock < step:
				break
			_trace_clock -= step
			lit += 1
		_say_trace()
	_place_head()
	# The key by the break, once the trace has reached it.
	var at: Variant = _where(tracing.broke_at.id) if tracing.broke_at != null and trace_done() else null
	fix_key.visible = at is Vector3 and not tracing.fix.is_empty()
	if fix_key.visible:
		fix_key.global_position = (at as Vector3) + Vector3.UP * 0.12
		var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
		if cam != null:
			fix_key.look_at(fix_key.global_position + (fix_key.global_position - cam.global_position), Vector3.UP)
		fix_key.set_words(str(tracing.fix["label"]))
	if g != null and tracing.broke_at != null and g.stage(tracing.broke_at.id) == null:
		clear_trace()


## How long the trace takes to light stage `n`: TRACE_STEP, or a third of it for a stage standing
## where the one before it does (a track's input, plugins and fader all at its voice), so the eye
## is not kept waiting on a bead that does not move.
func _step_to(n: int) -> float:
	if n <= 0 or n >= tracing.stages.size():
		return TRACE_STEP
	var a: Variant = _where(tracing.stages[n - 1].id)
	var b: Variant = _where(tracing.stages[n].id)
	return TRACE_STEP / 3.0 if a is Vector3 and b is Vector3 and (a as Vector3).distance_to(b) < 0.05 else TRACE_STEP


## The head at the last stage lit that stands somewhere: white, or red on the break.
func _place_head() -> void:
	_head.visible = false
	if tracing == null or lit <= 0:
		return
	var reached := tracing.stages[mini(lit, tracing.stages.size()) - 1]
	var at: Variant = _where(reached.id)
	if not (at is Vector3):
		return
	_head.visible = true
	_head.global_position = (at as Vector3) + Vector3.UP * 0.05
	var broke := tracing.broke_at == reached
	_head.material_override = _head_material(RED * 2.0 if broke else WHITE * 1.8)


var _head_materials := {}


func _head_material(colour: Color) -> StandardMaterial3D:
	if not _head_materials.has(colour):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(minf(colour.r, 1.0), minf(colour.g, 1.0), minf(colour.b, 1.0))
		m.emission_enabled = true
		m.emission = colour.clamp()
		m.emission_energy_multiplier = maxf(colour.r, maxf(colour.g, colour.b))
		_head_materials[colour] = m
	return _head_materials[colour]


## The roads the trace has lit so far, as `update` keys them.
func _lit_roads() -> Dictionary:
	var out := {}
	if tracing == null:
		return out
	for i in range(1, mini(lit, tracing.stages.size())):
		out["%s>%s" % [tracing.stages[i - 1].id, tracing.stages[i].id]] = true
	return out


## The trace in words, a line a stage lit, as the card says it.
func trace_words() -> String:
	if tracing == null:
		return ""
	var lines := PackedStringArray(["WHY CAN'T I HEAR %s?" % trace_title.to_upper()])
	for i in mini(lit, tracing.stages.size()):
		var s := tracing.stages[i]
		var broke := tracing.broke_at == s
		lines.append("%s %s  %s" % ["✗" if broke else "✓", s.title, s.level_words() if not broke else ""])
		if broke:
			lines.append("   %s: %s" % [SignalGraph.HEADINGS.get(tracing.reason, String(tracing.reason).to_upper()), tracing.words])
	if trace_done():
		if tracing.heard():
			lines.append("HEARD: it reaches the speakers, %s at the master." % tracing.stages[-1].level_words())
		elif tracing.broke_at == null:
			lines.append("It goes no further: nothing past %s." % tracing.stages[-1].title)
		elif tracing.fix.is_empty():
			lines.append("No one-press fix: %s" % tracing.words)
	return "\n".join(lines)


func _say_trace() -> void:
	if card == null:
		return
	card.visible = tracing != null
	if tracing == null:
		return
	card_text.text = trace_words()
	card_fix.visible = trace_done() and not tracing.fix.is_empty()
	if card_fix.visible:
		card_fix.text = "FIX: %s  (%s)" % [tracing.fix["label"], fix_key_words]


## The key by a break's sign that does its fix: a click, a poke or a trigger.
class FixKey extends PanelButton:
	var _face: Label3D
	var _words := ""

	func _ready() -> void:
		led_colour = Color(0.95, 0.62, 0.2)
		hit_pad = Vector2(2.4, 2.4)
		scale = Vector3.ONE * 2.5
		super()
		_face = Label3D.new()
		_face.font_size = 30
		_face.pixel_size = 0.0003
		_face.position = Vector3(0, 0, 0.0055)
		_face.modulate = Color(0.95, 0.95, 0.95)
		add_child(_face)
		Lettering.dress(_face)

	func set_words(words: String) -> void:
		if words == _words:
			return
		_words = words
		_face.text = words
		Lettering.fit(_face, PanelButton.SIZE.x * 0.95, 30, 10)

	func _default_title() -> String:
		return "FIX: " + _words

	func _default_readout() -> String:
		return ""

	func hint() -> String:
		return "press to %s, one undo step (Shift-Y at a desk)" % _words.to_lower()
