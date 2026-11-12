class_name SingerBooth
extends Node3D

## The singer's station in the vocal booth: its head on a pedestal (SingerHead), and under it a sloped desk with
## everything the singer is played by. Across the top are the MODE keys (SING, VOWEL, BEAT, BEAST), SPEAK (type a
## line for it to say), PART (which MIDI track it sings), TRACK (which track it sounds and records on) and SEQ (the
## beat pattern with the song). Under them sit the vowel pad (VOWEL across, OPEN up: SingerRow `vowel`, `open`) and
## the BODY, CHILD and VIBRATO knobs. Then a row of ten pads whose job is the mode's: the scale's notes in SING and
## VOWEL (a key: the next syllable, or a breath), the beatbox sounds in BEAT, the calls and the animal in BEAST. Last
## comes the beat's sixteen steps; a press puts the sound last played on a step, or takes it off.
##
## It only asks (`asked` op, args as SingerRow.answer takes them, and the moments), and shows what the room's row
## is (`show_row`) and what the voice is doing (`show_voice`). Its frame: the floor under the pedestal, +Z toward
## whoever plays it (the head's cut side faces them), +X to their right.

signal asked(op: String, args: Array)
## SPEAK pressed: the booth wants a line typed (SingerHost opens the typing pad or the desk's prompt).
signal speak_asked()
## LYRICS pressed: the song's lyrics to edit (the session panel's LYRICS box at a desk, the typing pad in a headset).
signal lyrics_asked()
## REC pressed: the song records, or stops recording.
signal rec_asked()

const PEDESTAL := 1.12
## Where the head's origin (its glottis) sits over the pedestal: high enough that its neck clears the halo, the
## face at a standing player's eye.
const HEAD_AT := Vector3(-0.06, PEDESTAL + 0.09 * SingerHead.GROWN, -0.02)
const DESK_AT := Vector3(0.0, 0.98, 0.22)
## Steep enough that a standing player reads it face on (it was 38 degrees, read from above at a slant).
const DESK_TILT := deg_to_rad(-24.0)
const DESK := Vector2(0.78, 0.4)
## The prompter beside the face: its left edge, turned toward the desk, and its lines' sizes (m).
## Clear of the face: the head's nose comes to about x 0.15 (SingerHead.SCALE, HEAD_AT).
const PROMPTER_AT := Vector3(0.25, PEDESTAL + 0.25, 0.02)
const PROMPTER_TURN := deg_to_rad(-12.0)
const PROMPTER_WIDE := 0.46
const CAP_NOW := 0.034
const CAP_NEXT := 0.02
const CAP_STATUS := 0.017
## The prompter frame's width (m).
const FRAME := 0.003
const INK := Color(0.85, 0.95, 1.0)
## The desk lamp's light at rest; a loud voice doubles it.
const LAMP_ENERGY := 0.7
const LIT := Color(0.36, 0.89, 0.51)
## The pads' notes in SING and VOWEL: a C major scale from C3, two octaves' worth of keys folded to ten.
const SCALE := [48, 50, 52, 53, 55, 57, 59, 60, 62, 64]

var head: SingerHead
var row := SingerRow.fresh()
var mode_keys: Array[BoothKey] = []
var pads: Array[BoothKey] = []
var steps: Array[BoothKey] = []
var keys := {}
var knobs := {}
var vowel_pad: RackPad
var status: Label3D
var syllable: Label3D
var prompt_now: Label3D
var prompt_sung: Label3D
var prompt_next: Label3D
## The sound a step press puts on (the beat pad last hit).
var brush := 0
## Which step the voice's sequencer is on (-1 none), lit on the steps.
var at_step := -1
var _track_names: Callable = Callable()
## The venue's lettering (SingerStyle), and the desk's own words it is put on.
var style := {}
var _desk_labels: Array[Label3D] = []
var _prompt_panel: StandardMaterial3D
var _frame_mat := _glow_mat(Color(0.3, 0.5, 0.6))
var _track_mat := _glow_mat(Color(0.12, 0.14, 0.16))
var _fill_mat := _glow_mat(SingerHead.AMBER)
var _fill: MeshInstance3D


func _ready() -> void:
	_build_pedestal()
	head = SingerHead.new()
	head.name = "Head"
	head.position = HEAD_AT
	add_child(head)
	var desk := Node3D.new()
	desk.name = "Desk"
	desk.position = DESK_AT
	desk.rotation.x = DESK_TILT
	add_child(desk)
	_build_desk(desk)
	_build_prompter()
	# a lamp over the desk, so the keys read in a dark booth; it warms with the voice (show_voice)
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp"
	lamp.position = Vector3(0.0, 1.45, 0.45)
	lamp.omni_range = 1.4
	lamp.light_energy = LAMP_ENERGY
	lamp.light_color = SingerHead.BLUE
	lamp.shadow_enabled = false
	lamp.light_volumetric_fog_energy = 0.0
	add_child(lamp)
	show_row(row)


## A name for track index `i` (the booth's PART and TRACK keys say it): `f(i) -> String`.
func names_tracks_with(f: Callable) -> void:
	_track_names = f


func _build_pedestal() -> void:
	var post := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.035 * SingerHead.GROWN
	cyl.bottom_radius = 0.05 * SingerHead.GROWN
	cyl.height = PEDESTAL
	post.mesh = cyl
	post.position.y = PEDESTAL * 0.5
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.08, 0.09, 0.1)
	metal.metallic = 0.7
	metal.roughness = 0.35
	post.material_override = metal
	add_child(post)
	var foot := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.24
	disc.bottom_radius = 0.26
	disc.height = 0.03
	foot.mesh = disc
	foot.position.y = 0.015
	foot.material_override = metal
	add_child(foot)
	# a ring of light at the head's base: lit by the voice
	var ring := MeshInstance3D.new()
	ring.name = "Halo"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.07 * SingerHead.GROWN
	torus.outer_radius = 0.078 * SingerHead.GROWN
	ring.mesh = torus
	ring.position.y = PEDESTAL
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = SingerHead.BLUE
	ring.material_override = glow
	add_child(ring)


func _build_desk(desk: Node3D) -> void:
	var slab := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(DESK.x, DESK.y, 0.025)
	slab.mesh = box
	slab.position.z = -0.0125
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.03, 0.04, 0.05)
	paint.roughness = 0.6
	slab.material_override = paint
	desk.add_child(slab)
	var top := DESK.y * 0.5
	var left := -DESK.x * 0.5
	var right := DESK.x * 0.5
	# the top row: the modes, then SPEAK, LYRICS and SEQ
	for i in SingerRow.MODES.size():
		var k := _key(desk, SingerRow.MODES[i], Vector2(left + 0.05 + i * 0.09, top - 0.035), Vector2(0.084, 0.046))
		k.tip = "%s: %s" % [SingerRow.MODES[i], ["sing the lyrics, a syllable a note", "play the mouth: the pad and the head's grips",
				"beatbox: pads hit, the steps make a pattern", "a creature: pads sound its calls"][i]]
		k.down.connect(func(d: bool) -> void:
			if d:
				asked.emit("set", ["mode", i]))
		mode_keys.append(k)
	var named := [["SPEAK", "type a line for it to say"], ["LYRICS", "the song's lyrics, all of them (paste them in)"],
			["SEQ", "the beat pattern plays with the song"]]
	for j in named.size():
		var nk := _key(desk, named[j][0], Vector2(left + 0.45 + j * 0.105, top - 0.035), Vector2(0.098, 0.046))
		nk.tip = named[j][1]
		keys[named[j][0]] = nk
	# the song keys, big, down the right: what it sings, where it goes, and recording
	var song := [["PART", "the MIDI track whose notes it sings: round the tracks that have notes, then none"],
			["TRACK", "the track it sounds and records on: the first press makes a Singer track"],
			["REC", "record the song: the singer's take lands on its TRACK"]]
	for j in song.size():
		var sk := _key(desk, song[j][0], Vector2(right - 0.105, top - 0.105 - j * 0.06), Vector2(0.19, 0.052))
		sk.tip = song[j][1]
		keys[song[j][0]] = sk
	keys["SPEAK"].down.connect(func(d: bool) -> void:
		if d:
			speak_asked.emit())
	keys["LYRICS"].down.connect(func(d: bool) -> void:
		if d:
			lyrics_asked.emit())
	keys["PART"].down.connect(func(d: bool) -> void:
		if d:
			asked.emit("part", []))
	keys["TRACK"].down.connect(func(d: bool) -> void:
		if d:
			asked.emit("track", []))
	keys["REC"].down.connect(func(d: bool) -> void:
		if d:
			rec_asked.emit())
	keys["SEQ"].down.connect(func(d: bool) -> void:
		if d:
			asked.emit("set", ["seq", not bool(row["seq"])]))
	# the vowel pad and the knobs
	vowel_pad = RackPad.new()
	vowel_pad.name = "VowelPad"
	vowel_pad.size = 0.1
	vowel_pad.tint = SingerHead.GRIP_COLOURS["tongue"]
	vowel_pad.position = Vector3(left + 0.075, top - 0.135, 0.005)
	vowel_pad.moved.connect(func(x: float, y: float) -> void:
		asked.emit("set", ["vowel", x])
		asked.emit("set", ["open", y]))
	desk.add_child(vowel_pad)
	_text(desk, "EE · AH · OO", Vector2(left + 0.075, top - 0.198), 0.016)
	for i in 3:
		var kname: String = ["body", "child", "vibrato"][i]
		var kn := Knob.new()
		kn.name = "Knob_" + kname
		kn.scale = Vector3.ONE * 2.4
		kn.position = Vector3(left + 0.2 + i * 0.1, top - 0.125, 0.012)
		kn.turned.connect(func(v: float) -> void: asked.emit("set", [kname, v]))
		# On the next idle frame, not now: a knob loads the moulded knob (Part.mesh) as it enters the tree, and
		# loaded here, while the venue is being stood up (SingerHost.stand, before the desk and the rack load it
		# for their banks), the sun's shadow cascades drew about 620 more calls a frame at 90 tracks for as long
		# as the room stood (tools/budget.sh 90, wide pose; docs/performance.md). Loaded a frame later, nothing.
		desk.add_child.call_deferred(kn)
		knobs[kname] = kn
		_text(desk, ["BODY ♂—♀", "CHILD", "VIBRATO"][i], Vector2(left + 0.2 + i * 0.1, top - 0.188), 0.017)
	# the pads
	for i in 10:
		var p := _key(desk, "", Vector2(left + 0.045 + i * 0.0765, top - 0.265), Vector2(0.07, 0.052))
		p.down.connect(_on_pad.bind(i))
		pads.append(p)
	# the steps
	for i in SingerRow.STEPS:
		var st := _key(desk, "", Vector2(left + 0.03 + i * 0.0452 + (i / 4) * 0.004, top - 0.335), Vector2(0.04, 0.042))
		st.tip = "step %d of the beat: a press puts the last pad's sound here, or takes it off" % (i + 1)
		st.down.connect(func(d: bool) -> void:
			if d:
				var steps_now := SingerRow.steps_of(String(row["beat"]))
				var put: String = "" if steps_now[i] == SingerRow.SOUNDS[brush] else SingerRow.SOUNDS[brush]
				asked.emit("step", [i, put]))
		steps.append(st)


## The prompter: beside the singer's face at eye height, turned a little to whoever stands at the desk, the words
## it is singing (the line now, its syllables marked, the one sung lit), the next line, and under them a line of
## status (how the words fit the notes, what to do next).
func _build_prompter() -> void:
	var p := Node3D.new()
	p.name = "Prompter"
	p.position = PROMPTER_AT
	p.rotation.y = PROMPTER_TURN
	add_child(p)
	var back := MeshInstance3D.new()
	var plate := QuadMesh.new()
	plate.size = Vector2(PROMPTER_WIDE + 0.04, 0.2)
	back.mesh = plate
	back.position = Vector3(PROMPTER_WIDE * 0.5, -0.03, -0.004)
	var m := StandardMaterial3D.new()
	# opaque: a see-through panel is sorted with the words by their middles, and drawn over some of them
	m.albedo_color = Color(0.01, 0.02, 0.03)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	back.material_override = m
	_prompt_panel = m
	p.add_child(back)
	# a thin frame in the venue's accent, and under the line sung a bar that fills as the line is sung
	var h := 0.2
	var w := PROMPTER_WIDE + 0.04
	for edge in [[Vector2(w, FRAME), Vector2(PROMPTER_WIDE * 0.5, -0.03 + h * 0.5)], [Vector2(w, FRAME), Vector2(PROMPTER_WIDE * 0.5, -0.03 - h * 0.5)],
			[Vector2(FRAME, h), Vector2(-0.02, -0.03)], [Vector2(FRAME, h), Vector2(PROMPTER_WIDE + 0.02, -0.03)]]:
		p.add_child(_strip(edge[0], edge[1], _frame_mat))
	p.add_child(_strip(Vector2(PROMPTER_WIDE, 0.004), Vector2(PROMPTER_WIDE * 0.5, -0.026), _track_mat))
	_fill = _strip(Vector2(PROMPTER_WIDE, 0.004), Vector2(PROMPTER_WIDE * 0.5, -0.026), _fill_mat)
	_fill.position.z += 0.0005
	_fill.visible = false
	p.add_child(_fill)
	prompt_now = _prompt_label(p, 0.0, CAP_NOW, INK)
	prompt_sung = _prompt_label(p, 0.0, CAP_NOW, SingerHead.AMBER)
	prompt_sung.position.z += 0.0008
	prompt_sung.visible = false
	prompt_next = _prompt_label(p, -0.05, CAP_NEXT, Color(0.6, 0.66, 0.72))
	status = _prompt_label(p, -0.095, CAP_STATUS, Color(0.62, 0.8, 0.7))
	syllable = prompt_sung


func _strip(size: Vector2, at: Vector2, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	mi.position = Vector3(at.x, at.y, -0.002)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _glow_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


func _prompt_label(parent: Node3D, y: float, cap: float, colour: Color) -> Label3D:
	var l := Label3D.new()
	l.pixel_size = 0.0002
	l.font_size = roundi(cap / l.pixel_size)
	l.modulate = colour
	l.shaded = false
	l.double_sided = false
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.position = Vector3(0.0, y, 0.0)
	Lettering.range_to_legibility(l)
	parent.add_child(l)
	return l


## The words on the prompter: the line now (`now`, its syllable breaks marked with a middle dot), lit up to the end
## of the syllable sung (`lit`: its first character and count in `now`, x < 0 for none), the next line and the status line.
func show_prompt(now: String, lit: Vector2i, next: String, words: String) -> void:
	if prompt_now == null:
		return
	_fit_line(prompt_now, now, CAP_NOW)
	_fit_line(prompt_next, next, CAP_NEXT)
	_fit_line(status, words, CAP_STATUS)
	var ok := lit.x >= 0 and lit.y > 0 and lit.x + lit.y <= now.length()
	prompt_sung.visible = ok
	# the bar under the line: filled to the end of the syllable sung
	_fill.visible = ok
	if ok:
		var through := float(lit.x + lit.y) / maxf(now.length(), 1.0)
		_fill.scale.x = maxf(through, 0.001)
		_fill.position.x = PROMPTER_WIDE * through * 0.5
	if ok:
		prompt_sung.font_size = prompt_now.font_size
		prompt_sung.outline_size = prompt_now.outline_size
		# karaoke: the line up to the end of the syllable sung, drawn over the line from the same place in the
		# same face, so it lies on its letters exactly in any venue's lettering (a slanted face is not measured
		# true by get_string_size, and a syllable measured into place drifted off its word)
		prompt_sung.text = now.left(lit.x + lit.y)
		prompt_sung.position = prompt_now.position + Vector3(0.0, 0.0, 0.0008)


func _fit_line(l: Label3D, words: String, cap: float) -> void:
	if l.text != words:
		l.text = words
		Lettering.fit(l, PROMPTER_WIDE, roundi(cap / l.pixel_size), roundi(cap * 0.45 / l.pixel_size))


func _on_pad(d: bool, i: int) -> void:
	match int(row["mode"]):
		SingerRow.Mode.BEAT:
			if d:
				brush = i
				asked.emit("hit", [SingerRow.SOUNDS[i]])
		SingerRow.Mode.BEAST:
			if not d:
				return
			if i < 4:
				asked.emit("set", ["call", i])
				asked.emit("cry", [i])
			elif i >= 6:
				asked.emit("set", ["beast", i - 6])
		_:
			asked.emit("play", [SCALE[i], d])


func _key(desk: Node3D, legend: String, at: Vector2, size: Vector2) -> BoothKey:
	var k := BoothKey.new()
	k.size = size
	k.legend_text = legend
	k.name = "Key_" + (legend if legend != "" else str(desk.get_child_count()))
	k.position = Vector3(at.x, at.y, 0.0)
	desk.add_child(k)
	return k


func _text(desk: Node3D, words: String, at: Vector2, px: float) -> Label3D:
	var l := Label3D.new()
	l.text = words
	l.pixel_size = px / 40.0
	l.font_size = 40
	l.modulate = INK
	l.outline_size = 0
	l.position = Vector3(at.x, at.y, 0.003)
	l.double_sided = false
	desk.add_child(l)
	_desk_labels.append(l)
	return l


## The room's row: the lit mode, the knobs and the pad where it says, the pads' legends for the mode, the steps.
func show_row(r: Dictionary) -> void:
	row = SingerRow.sanitize(r)
	var mode := int(row["mode"])
	for i in mode_keys.size():
		mode_keys[i].lit = i == mode
	if keys.has("SEQ"):
		keys["SEQ"].lit = bool(row["seq"])
		keys["PART"].legend_text = "PART  %s" % _track_word(int(row["part"]))
		keys["TRACK"].legend_text = "TRACK  %s" % _track_word(int(row["track"]))
		keys["PART"].lit = int(row["part"]) > 0
		keys["TRACK"].lit = int(row["track"]) > 0
	for k in knobs:
		var kn: Knob = knobs[k]
		if kn.held_by == null:
			kn.value = float(row[k])
	if vowel_pad != null and vowel_pad.held_by == null:
		vowel_pad.set_xy(float(row["vowel"]), float(row["open"]))
	for i in pads.size():
		var p := pads[i]
		match mode:
			SingerRow.Mode.BEAT:
				p.legend_text = SingerRow.SOUND_NAMES[i]
				p.tip = "beatbox %s" % SingerRow.SOUND_NAMES[i].to_lower()
				p.lit = i == brush
			SingerRow.Mode.BEAST:
				var beast := int(row["beast"])
				p.legend_text = "CALL %d" % (i + 1) if i < 4 else (SingerRow.BEAST_NAMES[i - 6] if i >= 6 else "")
				p.tip = "the %s's call %d" % [SingerRow.BEASTS[beast], i + 1] if i < 4 else ("be a %s" % SingerRow.BEASTS[i - 6] if i >= 6 else "")
				p.lit = (i < 4 and i == int(row["call"])) or (i >= 6 and i - 6 == beast)
			_:
				p.legend_text = ["C", "D", "E", "F", "G", "A", "B", "C", "D", "E"][i]
				p.tip = "sing the next syllable on this note" if mode == SingerRow.Mode.SING else "breathe the mouth at this note"
				p.lit = false
	var s := SingerRow.steps_of(String(row["beat"]))
	for i in steps.size():
		steps[i].legend_text = s[i]
		steps[i].lit = i == at_step


func _track_word(i: int) -> String:
	if i <= 0:
		return "—"
	return String(_track_names.call(i)) if _track_names.is_valid() else str(i)


## What the voice is doing: the head, the step the beat is on, the syllable being sung, a line of status.
func show_voice(body: Dictionary, frame: Dictionary, sung: String, step: int, words: String) -> void:
	head.show_voice(body, frame)
	if step != at_step:
		at_step = step
		for i in steps.size():
			steps[i].lit = i == at_step
	if keys.has("REC"):
		var rec := DAW.state != null and DAW.state.recording
		if keys["REC"].lit != rec:
			keys["REC"].lit = rec
			keys["REC"].legend_text = "● REC" if rec else "REC"
	var halo := get_node_or_null("Halo") as MeshInstance3D
	if halo != null:
		var m := halo.material_override as StandardMaterial3D
		var rms := float(body.get("rms", 0.0))
		m.albedo_color = SingerHead.BLUE.lerp(SingerHead.AMBER, clampf(rms * 12.0, 0.0, 1.0))
	var lamp := get_node_or_null("Lamp") as OmniLight3D
	if lamp != null:
		var loud := clampf(float(body.get("rms", 0.0)) * 12.0, 0.0, 1.0)
		lamp.light_color = SingerHead.BLUE.lerp(SingerHead.AMBER, loud)
		lamp.light_energy = LAMP_ENERGY * (1.0 + loud)


## A key on the booth's desk: a slab with a legend that lights, pressed (and let go) by a hand or a click.
class BoothKey extends ControlAffordance:
	signal down(pressed: bool)
	var size := Vector2(0.07, 0.04)
	var legend_text := "":
		set(v):
			legend_text = v
			if _legend != null:
				_legend.text = v
	var tip := ""
	var lit := false:
		set(v):
			lit = v
			if _paint != null:
				# unshaded, so the booth's lamp cannot wash a key out behind its letters: lit is the venue's colour
				# made as deep as its legend needs (SingerStyle.key_paint)
				_paint.albedo_color = SingerStyle.key_paint(style) if v else Color(0.1, 0.11, 0.13)
	var _legend: Label3D
	var _paint: StandardMaterial3D
	## The venue's lettering (SingerStyle): the legend's face, and the colour a lit key glows.
	var style := {}:
		set(v):
			style = v
			_restyle()

	func _ready() -> void:
		collision_layer = 1 << (Interactor.CONTROL_LAYER - 1)
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(size.x, size.y, 0.03)
		shape.shape = box
		add_child(shape)
		var cap := MeshInstance3D.new()
		cap.name = "Cap"
		var slab := BoxMesh.new()
		slab.size = Vector3(size.x - 0.006, size.y - 0.006, 0.01)
		cap.mesh = slab
		cap.position.z = 0.005
		_paint = StandardMaterial3D.new()
		_paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cap.material_override = _paint
		add_child(cap)
		_legend = Label3D.new()
		_legend.text = legend_text
		_legend.font_size = 40
		_legend.pixel_size = minf(size.y * 0.4, 0.016) / 40.0
		_legend.modulate = SingerBooth.INK
		_legend.position.z = 0.0105
		_legend.width = size.x / _legend.pixel_size
		_legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(_legend)
		lit = lit
		_restyle()

	func _restyle() -> void:
		if _legend != null and not style.is_empty():
			SingerStyle.dress(_legend, style, "key")
			lit = lit

	func personal() -> bool:
		return false

	func _default_title() -> String:
		return ("SINGER  " + legend_text).strip_edges()

	func _default_readout() -> String:
		return "on" if lit else ""

	func hint() -> String:
		return tip

	func _on_grab_begin(_at: Vector3) -> void:
		down.emit(true)

	func _on_grab_end() -> void:
		down.emit(false)


## The venue's lettering on everything here with words (SingerStyle.of): the prompter, the desk, every key.
func apply_style(s: Dictionary) -> void:
	style = s
	if prompt_now == null:
		return
	SingerStyle.dress(prompt_now, s, "line")
	SingerStyle.dress(prompt_sung, s, "lit")
	SingerStyle.dress(prompt_next, s, "dim")
	SingerStyle.dress(status, s, "status")
	if _prompt_panel != null:
		var panel: Color = s["panel"]
		_prompt_panel.albedo_color = Color(panel.r, panel.g, panel.b, 1.0)
	var lit: Color = s["lit"]
	_frame_mat.albedo_color = lit.darkened(0.35)
	_fill_mat.albedo_color = lit
	_track_mat.albedo_color = (s["panel"] as Color).lightened(0.12)
	for l in _desk_labels:
		SingerStyle.dress(l, s, "key")
	for k in mode_keys + pads + steps:
		k.style = s
	for k in keys.values():
		k.style = s
	# the words change size with the face: fitted again
	for l: Label3D in [prompt_now, prompt_next, status]:
		var was: String = l.text
		l.text = ""
		_fit_line(l, was, CAP_NOW if l == prompt_now else (CAP_NEXT if l == prompt_next else CAP_STATUS))
