class_name ModularWall
extends Surface

## A modular synth wall (docs/spatial_loop.md part two, slice 51; idea #25): eleven modules in a case
## over the synth zone's keyboard stand (Venue.modular_spot), patched with cables, played with this
## player's keys while they stand at the stand. A station (`modular`, in the synth zone) and a surface,
## so F visits it and G brings it.
##
## THE MODULES (Modular.MODULES), from the left: KEYS (this player's keys' pitch, gate and velocity
## out, its newest note lettered and a lamp lit while one is held, and PLAY, which takes the computer
## keys A to ' for it), LFO, NOISE, two VCOs (saw, square or sine; tune; FM in), MIX of four, the VCF
## (low-pass: cutoff, resonance, CV in), two ENVs (ADSR, gate in), the VCA, and OUT, whose tag says
## which road the sound takes and its figure (ModularVoice.tag). Under the panel, on the stand's upper
## deck, a row of touch keys (ModularTouch) plays it with a fingertip or a click; beside it, its
## plaque; over it, a lamp.
##
## THE PATCH is the room's (Modular, the row `modular`), shown here (`show_patch`): each cable a
## PatchCable from an output's jack to an input's, coloured by the module it comes from, each knob the
## console's Knob at its value. A drag from a jack carries a cable (ModularJack):
## the jacks it could go into light, and letting go over one asks for it (`patch_asked`, from and to;
## an empty `to` pulls the cable at `from`). An input with a cable in it gives up its plug instead,
## to another input (pulled, then patched) or off the jacks (pulled). The wall never changes its own
## patch: the studio asks the room, and the room's answer comes back through `show_patch`.
##
## A KNOB'S TURN is heard as it turns (`knob_turning`, every change), streamed to the band at most
## Session.KNOBS_PER_SECOND (`knob_streamed`), and the room's only when let go (`knob_set`, once the
## hand or the wheel has rested for SETTLE), so a sweep is one room ask, not one a step.
##
## WITHIN REACH. Its jacks, knobs, keys and the mount's handle take the pointer only while this
## player is at it (`within_reach`, the studio's: standing at the stand, or the wall visited or
## brought), so from the desk, six metres off, a click past a 2 cm jack is never taken by it.
##
## THE WORLD (slice 53). An input may take a cable from one of the world's sockets out in the room
## (WorldSocket: the weather, the venue's instrument, the looper's rings, the marble run). That cable
## is the socket's to draw, from there to the input's plug; here the input's card says where it comes
## from, and dragging its plug out pulls it or moves it to another input, as any cable's.
##
## Hardware: it knows nothing of the session. The studio wires it, as StageLink does the stage table.

signal patch_asked(from: StringName, to: StringName)
signal knob_turning(id: StringName, v: float)
signal knob_streamed(id: StringName, v: float)
signal knob_set(id: StringName, v: float)
signal touched(pitch: int, down: bool)
signal keys_asked()
## Something this player did that is refused here, in words (a cable into an input that has one).
signal told(text: String)

## A module's width, and the panel's.
const MODULE_WIDE := 0.11
const WIDE := MODULE_WIDE * 11
const TALL := 0.6
## The case round the modules, and how deep it is behind the panel.
const BORDER := 0.025
const CASE_DEEP := 0.05
## Where things sit on a module, up from the panel's foot (m), and across from its middle.
const TITLE_Y := TALL - 0.032
const TITLE_CAP := 0.022
const KNOB_ROWS := [0.47, 0.37]
const JACK_ROWS := [0.235, 0.15, 0.065]
const COLUMN := 0.03
const LETTER_CAP := 0.0115
## The touch keys: on the stand's upper deck just under the panel, in the wall's frame (the deck's
## top, ZoneKit's, under the wall's foot at Venue.MODULAR_BOTTOM, in front of the panel's face), a
## little toward the plaque's side to sit on the deck's length. Close under the panel, so a desk at
## the stand sees the keys and the jacks in one view, and the lower deck is free for a keyboard.
const TOUCH_COUNT := 13
const TOUCH_SIZE := Vector2(0.078, 0.17)
const TOUCH_X := 0.08
const TOUCH_Y := 1.0325 - 1.26
const TOUCH_Z := 0.14
## The plaque: beside the panel on an arm off the case, its top level with the panel's, so it is in
## view with the modules from the stand (the bricks table leaves a desk little room to stand back).
const PLAQUE_WIDE := 0.42
const PLAQUE_GAP := 0.03
const PLAQUE_X := WIDE * 0.5 + BORDER + PLAQUE_GAP + PLAQUE_WIDE * 0.5
const PLAQUE_TOP := TALL
const PLAQUE_Z := 0.01
## How far the whole of it (the panel and its plaque) is off its middle toward the plaque: the
## venue hangs it this far the other way (Venue.modular_spot), so the two stand over the stand.
const OFF_MIDDLE := (PLAQUE_X + PLAQUE_WIDE * 0.5 - WIDE * 0.5 - BORDER) * 0.5
## The posts it stands on, from the floor up its back, and how far back they are.
const POST := 0.04
## What a player looks at, and the top and foot of what they should see (Stations' frame): the
## case's top, and the touch keys' near edge.
const LOOK := Vector3(0, 0.15, 0.1)
const FRAME_TOP := Vector3(0, TALL + BORDER, 0)
const FRAME_FOOT := Vector3(0, TOUCH_Y, TOUCH_Z + TOUCH_SIZE.y * 0.5)
## How long a knob rests before its value is the room's (s): a wheel's notches closer than this
## are one turn.
const SETTLE := 0.3
## The least gap between two streamed values of one knob (ms): Session.KNOBS_PER_SECOND, and a
## little over, so a turn never streams more than that.
const STREAM_GAP_MSEC := 34
## Each module's cable colour, by MODULES index: told apart by their source's plate as much as by
## colour, and each a plain bright one against the dark panel.
const CABLE_COLOURS := [Color(0.95, 0.78, 0.25), Color(0.4, 0.8, 1.0), Color(0.75, 0.75, 0.75),
		Color(1.0, 0.45, 0.3), Color(0.95, 0.4, 0.65), Color(0.55, 0.9, 0.5), Color(0.7, 0.55, 1.0),
		Color(0.3, 0.95, 0.85), Color(1.0, 0.6, 0.2), Color(0.85, 0.85, 0.4), Color(1, 1, 1)]

## How far a cable droops, as a share of its span (PatchCable.sag_ratio), and the run past which it
## is a long one (m across): a long cable hangs instead to CABLE_FLOOR, the panel's foot under its
## lowest row of jacks, so it crosses the modules between its ends below their jacks and their
## names rather than over them.
const CABLE_SAG := 0.16
const LONG_CABLE := MODULE_WIDE * 1.5
const CABLE_FLOOR := 0.01

## Whether its controls take the pointer (the studio's, each frame).
var within_reach := true:
	set(v):
		if within_reach == v:
			return
		within_reach = v
		_apply_reach()
## The clock streaming and settling run on (ms), the suite's to replace.
var clock: Callable = func() -> int: return Time.get_ticks_msec()

## What it shows: the room's patch.
var patch := Modular.default_patch()
var jacks := {}
var knobs := {}
var touch_keys: Array[ModularTouch] = []
var play_key: EqWall.WallKey
var cables: Array[PatchCable] = []
var touch_base := 48
var panel: Node3D
var _built := false
var _tag: Label3D
## OUT's REC, on a line of its own under the tag and at the size of a module's title: a take going
## through the wall records its sound (`set_recording`). The word says it; the red only adds to it.
var _rec: Label3D
var _note: Label3D
var _lamp: MeshInstance3D
var _lamp_on := StandardMaterial3D.new()
var _drag := {}
## Each knob's last streamed time (ms) and the value waiting to go out after it.
var _streamed_at := {}
var _stream_due := {}
## Each knob's let-go waiting (its time, s, on `clock`).
var _settle_at := {}


func _ready() -> void:
	surface_kind = &"modular"
	if surface_id == &"":
		surface_id = &"modular"
	super()
	# Built at once: nothing on it waits for the DAW's news, and the studio shows the room's patch on
	# it before its first frame.
	_rebuild()
	# The mount's handle, clipped on after it is built, takes the pointer only within reach too.
	child_entered_tree.connect(func(n: Node) -> void:
		if n is SurfaceHandle:
			_apply_reach.call_deferred())


## Built once: nothing on it follows the project's shape.
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
	_build_case()
	for i in Modular.MODULES.size():
		_build_module(i)
	_build_touch()
	_build_lamp()
	var plaque := Stations.plaque(Modular.STATION, PLAQUE_WIDE)
	plaque.position = Vector3(PLAQUE_X, PLAQUE_TOP - float(plaque.get_meta(&"plaque_tall")) * 0.5, PLAQUE_Z)
	_adopt(plaque)
	var arm := MeshInstance3D.new()
	arm.name = "PlaqueArm"
	var bar := BoxMesh.new()
	bar.size = Vector3(PLAQUE_GAP + 0.04, 0.03, 0.02)
	arm.mesh = bar
	arm.position = Vector3(WIDE * 0.5 + BORDER + PLAQUE_GAP * 0.5, PLAQUE_TOP - 0.05, -0.006)
	arm.material_override = Materials.brushed_metal()
	_adopt(arm)
	show_patch(patch)
	_apply_reach()


func _process(delta: float) -> void:
	super(delta)
	var now := int(clock.call())
	for id: StringName in _stream_due.keys():
		if now - int(_streamed_at.get(id, -100000)) >= STREAM_GAP_MSEC:
			_streamed_at[id] = now
			knob_streamed.emit(id, float(_stream_due[id]))
			_stream_due.erase(id)
	for id: StringName in _settle_at.keys():
		var k: Knob = knobs.get(id)
		if k != null and k.is_held():
			continue
		if now >= int(_settle_at[id]):
			_settle_at.erase(id)
			if k != null:
				knob_set.emit(id, k.value)


# --- building ---------------------------------------------------------------------------------

## The panel's parts: under `panel`, which is what a visit frames (`framing_root`), so F stands a
## desk where the modules fill the view rather than back past the bricks table for the keys and the
## plaque too.
func _put(node: Node) -> void:
	node.set_meta("built", true)
	panel.add_child(node)


func framing_root() -> Node3D:
	return panel if panel != null else self


func _x_of(module: int) -> float:
	return -WIDE * 0.5 + MODULE_WIDE * (module + 0.5)


func _build_case() -> void:
	var case := MeshInstance3D.new()
	case.name = "Case"
	var box := BoxMesh.new()
	box.size = Vector3(WIDE + BORDER * 2.0, TALL + BORDER * 2.0, CASE_DEEP)
	case.mesh = box
	case.position = Vector3(0, TALL * 0.5, -CASE_DEEP * 0.5 - 0.002)
	case.material_override = Materials.chassis()
	_put(case)
	# Two posts up its back from the floor: it stands on its own wherever the venue has no wall
	# to hang it on. Carcass, not panel, so a visit frames the modules and not the floor.
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


func _build_module(i: int) -> void:
	var m: Dictionary = Modular.MODULES[i]
	var x := _x_of(i)
	var plate := MeshInstance3D.new()
	plate.name = "Module_%s" % m["id"]
	var face := BoxMesh.new()
	face.size = Vector3(MODULE_WIDE - 0.003, TALL - 0.006, 0.004)
	plate.mesh = face
	plate.position = Vector3(x, TALL * 0.5, -0.002)
	var paint := StandardMaterial3D.new()
	# Every other module a shade lighter, so where one ends is plain from across the room.
	paint.albedo_color = Color(0.16, 0.16, 0.17) if i % 2 == 0 else Color(0.21, 0.205, 0.2)
	paint.roughness = 0.6
	plate.material_override = paint
	_put(plate)
	_put(_letter(m["title"], TITLE_CAP, Vector3(x, TITLE_Y, 0.001), Color(0.95, 0.9, 0.78)))
	var ids: Array = []
	for k: StringName in m["knobs"]:
		ids.append(StringName("%s.%s" % [m["id"], k]))
	for n in ids.size():
		var at := _grid(x, n, ids.size(), KNOB_ROWS)
		_build_knob(ids[n], at)
	var js: Array = []
	for name: StringName in m["ins"]:
		js.append(StringName("%s.%s" % [m["id"], name]))
	for name: StringName in m["outs"]:
		js.append(StringName("%s.%s" % [m["id"], name]))
	for n in js.size():
		var j := ModularJack.create(js[n])
		j.position = _grid(x, n, js.size(), JACK_ROWS)
		j.drag_began.connect(_on_drag_began)
		j.drag_moved.connect(_on_drag_moved)
		j.drag_finished.connect(_on_drag_finished)
		_put(j)
		jacks[js[n]] = j
	if m["id"] == &"keys":
		_build_keys_face(x)
	elif m["id"] == &"out":
		_tag = _letter("", LETTER_CAP, Vector3(x, KNOB_ROWS[1] - 0.01, 0.001), Color(0.85, 0.9, 0.95))
		_tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_tag.width = (MODULE_WIDE - 0.014) / _tag.pixel_size
		_tag.name = "Tag"
		_put(_tag)
		_rec = _letter("REC", TITLE_CAP, Vector3(x, (KNOB_ROWS[1] + JACK_ROWS[0]) * 0.5 - 0.004, 0.001),
				Color(1.0, 0.45, 0.4))
		_rec.name = "Rec"
		_rec.visible = false
		_put(_rec)
	elif m["id"] == &"noise":
		_put(_letter("WHITE", LETTER_CAP, Vector3(x, KNOB_ROWS[0], 0.001), Color(0.6, 0.6, 0.6)))


## Where the `n`th of `count` things goes on a module whose middle is at `x`: two to a row, down
## `rows`, an odd last one in the middle.
func _grid(x: float, n: int, count: int, rows: Array) -> Vector3:
	var row := n / 2
	var alone := n == count - 1 and count % 2 == 1
	var across := 0.0 if alone else (-COLUMN if n % 2 == 0 else COLUMN)
	return Vector3(x + across, float(rows[mini(row, rows.size() - 1)]), 0.0)


func _build_knob(id: StringName, at: Vector3) -> void:
	var k := Knob.new()
	k.name = "Knob_%s" % String(id).replace(".", "_")
	k.position = at + Vector3(0, 0.008, 0.008)
	k.value = float((patch["knobs"] as Dictionary).get(id, Modular.KNOB_REST[id]))
	k.describe_title = func() -> String: return "MODULAR  %s" % Modular.knob_title(id)
	k.describe_value = func(v: float) -> String: return Modular.knob_text(id, v)
	k.turned.connect(func(v: float) -> void: _on_knob_turned(id, v))
	k.value_committed.connect(func(_v: float) -> void: _settle_at[id] = int(clock.call()) + roundi(SETTLE * 1000.0))
	_put(k)
	knobs[id] = k
	_put(_letter(Modular.knob_letter(id), LETTER_CAP, at + Vector3(0, -0.019, 0.001), Color(0.85, 0.83, 0.78)))


func _build_keys_face(x: float) -> void:
	_note = _letter("—", 0.03, Vector3(x - 0.012, KNOB_ROWS[0] + 0.01, 0.001), Color(0.95, 0.9, 0.78))
	_note.name = "Note"
	_put(_note)
	_lamp = MeshInstance3D.new()
	_lamp.name = "Gate"
	var disc := CylinderMesh.new()
	disc.top_radius = 0.008
	disc.bottom_radius = 0.008
	disc.height = 0.004
	_lamp.mesh = disc
	_lamp.rotation_degrees = Vector3(90, 0, 0)
	_lamp.position = Vector3(x + 0.04, KNOB_ROWS[0] + 0.012, 0.002)
	_lamp.material_override = Materials.led(Color(1.0, 0.5, 0.2), false)
	_put(_lamp)
	_put(_letter("GATE", LETTER_CAP * 0.8, Vector3(x + 0.04, KNOB_ROWS[0] - 0.006, 0.001), Color(0.7, 0.7, 0.68)))
	play_key = EqWall.WallKey.new()
	play_key.name = "Play"
	play_key.legend = "PLAY"
	play_key.size = Vector2(MODULE_WIDE - 0.016, 0.05)
	play_key.says = "the computer keys play the modular: A to ' from C, Z and X the octave, Esc gives them back"
	play_key.position = Vector3(x, KNOB_ROWS[1] - 0.01, 0.0)
	play_key.describe_title = func() -> String: return "MODULAR  PLAY"
	play_key.pressed.connect(func() -> void: keys_asked.emit())
	_put(play_key)


## A lamp on a stalk over the case, lighting the modules from above and in front as a rack light
## does: the synth corner of most venues is dark, and a jack is found by its ring and its letters.
func _build_lamp() -> void:
	var lamp := Node3D.new()
	lamp.name = "Lamp"
	lamp.position = Vector3(0, TALL + BORDER + 0.08, 0.2)
	_adopt(lamp)
	var shade := MeshInstance3D.new()
	shade.name = "Shade"
	var bar := BoxMesh.new()
	bar.size = Vector3(WIDE * 0.6, 0.025, 0.05)
	shade.mesh = bar
	shade.material_override = Materials.chassis()
	shade.add_to_group(&"presentation_chrome")
	lamp.add_child(shade)
	var stalk := MeshInstance3D.new()
	stalk.name = "Stalk"
	var rod := BoxMesh.new()
	rod.size = Vector3(0.02, 0.02, 0.22)
	stalk.mesh = rod
	stalk.position = Vector3(0, -0.02, -0.12)
	stalk.material_override = Materials.brushed_metal()
	stalk.add_to_group(&"presentation_chrome")
	lamp.add_child(stalk)
	var light := SpotLight3D.new()
	light.name = "Light"
	light.light_color = Color(1.0, 0.92, 0.8)
	light.light_energy = 1.1
	light.spot_range = 1.8
	light.spot_attenuation = 0.6
	light.spot_angle = 70.0
	light.shadow_enabled = false
	# Down the panel's face from in front of its top.
	var from := Vector3(0, -0.015, 0)
	light.transform = Transform3D(Basis.looking_at(Vector3(0, -TALL * 0.55, -0.12) - from, Vector3.UP), from)
	light.add_to_group(&"presentation_chrome")
	lamp.add_child(light)


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


# --- what it shows ----------------------------------------------------------------------------

## The room's patch, shown: every cable as a cable, every knob at its value (but one in a hand here,
## whose value is the hand's until it is let go), every jack's card saying what it carries.
func show_patch(to: Dictionary) -> void:
	patch = Modular.clean(to)
	for id: StringName in knobs:
		var k: Knob = knobs[id]
		if not k.is_held() and not _settle_at.has(id):
			k.apply_remote(float(patch["knobs"].get(id, Modular.KNOB_REST[id])))
	for id: StringName in jacks:
		var j: ModularJack = jacks[id]
		j.plugged_to.clear()
		if j.output:
			j.plugged_to.assign(Modular.sinks_of(patch, id))
		elif Modular.source_of(patch, id) != &"":
			j.plugged_to.append(Modular.source_of(patch, id))
	_lay_cables()


## A bandmate's knob as they turn it (Session.knob_turned): turned here, unless a hand here has it.
func show_knob(id: StringName, v: float) -> void:
	var k: Knob = knobs.get(id)
	if k != null:
		k.apply_remote(v)


func _lay_cables() -> void:
	for c in cables:
		if is_instance_valid(c):
			c.queue_free()
	cables.clear()
	if not is_inside_tree():
		return
	for c: Array in patch["cables"]:
		var a: ModularJack = jacks.get(c[0])
		var b: ModularJack = jacks.get(c[1])
		if a == null or b == null:
			continue
		var tint: Color = CABLE_COLOURS[Modular.MODULES.find(Modular.module_row(Modular.module_of(c[0])))]
		var cable := PatchCable.create(a.plug_transform(), b.plug_transform(), tint, hash(c))
		cable.name = "Cable_%s_%s" % [c[0], c[1]]
		cable.sag_ratio = cable_sag(a.position, b.position, a.plug_transform().origin.distance_to(b.plug_transform().origin))
		cable.set_meta(&"cable", [c[0], c[1]])
		add_child(cable)
		cables.append(cable)


## The sag (a share of `span`, PatchCable's) for a cable from the jack at `a` to the one at `b`, the
## wall's frame: CABLE_SAG between neighbours, and for a long run as much as brings its middle down
## to CABLE_FLOOR (a cubic's middle droops three quarters of its sag), never less.
static func cable_sag(a: Vector3, b: Vector3, span: float) -> float:
	if absf(a.x - b.x) <= LONG_CABLE or span <= 0.001:
		return CABLE_SAG
	var drop := (a.y + b.y) * 0.5 - CABLE_FLOOR
	return maxf(CABLE_SAG, drop / 0.75 / span)


## The cable into input `to`, if one is drawn.
func cable_into(to: StringName) -> PatchCable:
	for c in cables:
		if is_instance_valid(c) and (c.get_meta(&"cable") as Array)[1] == to:
			return c
	return null


## This player's keys on KEYS: their newest note, and whether one is held.
func show_keys(pitch: int, gate: bool) -> void:
	if _note != null:
		_note.text = "%s%d" % [ModularTouch.NAMES[pitch % 12], pitch / 12 - 1] if pitch >= 0 else "—"
	if _lamp != null:
		_lamp.material_override = Materials.led(Color(1.0, 0.5, 0.2), gate)


## The knobs a hand here has, or has just let go and not yet given the room: {id: value}.
func turning() -> Dictionary:
	var out := {}
	for id: StringName in knobs:
		var k: Knob = knobs[id]
		if k.is_held() or _settle_at.has(id):
			out[id] = k.value
	return out


## OUT's tag: the road the sound takes and its figure (ModularVoice.tag).
func set_tag(text: String) -> void:
	if _tag != null and _tag.text != text:
		_tag.text = text


func tag_text() -> String:
	return _tag.text if _tag != null else ""


## OUT's REC shown while a take records through the wall, and hidden after.
func set_recording(on: bool) -> void:
	if _rec != null:
		_rec.visible = on


func is_recording() -> bool:
	return _rec != null and _rec.visible


## PLAY lit while the computer keys play it.
func show_playing(on: bool) -> void:
	if play_key != null:
		play_key.lit = on


## Its own controls' shapes on or off with `within_reach`: its jacks, knobs and keys. Not its plaque's
## keys, which are the way on and back from anywhere a station's are, nor the mount's handle.
func _apply_reach() -> void:
	for c in reach_controls():
		for node in c.get_children():
			if node is CollisionShape3D:
				(node as CollisionShape3D).disabled = not within_reach


## The controls that take the pointer only within reach.
func reach_controls() -> Array[ControlAffordance]:
	var out: Array[ControlAffordance] = []
	for j: ModularJack in jacks.values():
		out.append(j)
	for k: Knob in knobs.values():
		out.append(k)
	for t in touch_keys:
		out.append(t)
	if play_key != null:
		out.append(play_key)
	for n in get_children():
		if n is SurfaceHandle:
			out.append(n)
	return out


# --- a knob's turn -----------------------------------------------------------------------------

func _on_knob_turned(id: StringName, v: float) -> void:
	knob_turning.emit(id, v)
	var now := int(clock.call())
	if now - int(_streamed_at.get(id, -100000)) >= STREAM_GAP_MSEC:
		_streamed_at[id] = now
		_stream_due.erase(id)
		knob_streamed.emit(id, v)
	else:
		_stream_due[id] = v


# --- carrying a cable --------------------------------------------------------------------------

func _on_drag_began(from: ModularJack, at: Vector3) -> void:
	var fixed: Transform3D = from.plug_transform()
	var tint: Color = CABLE_COLOURS[Modular.MODULES.find(Modular.module_row(Modular.module_of(from.jack)))]
	var lifted := &""
	var hidden: PatchCable = null
	if not from.output:
		var source := Modular.source_of(patch, from.jack)
		if source != &"":
			# Its plug comes out of here, and the cable stays in the output it comes from. A world
			# socket's (slice 53) runs off across the room: carried from here, its plug trails a stub.
			lifted = from.jack
			if jacks.has(source):
				fixed = (jacks[source] as ModularJack).plug_transform()
				tint = CABLE_COLOURS[Modular.MODULES.find(Modular.module_row(Modular.module_of(source)))]
			else:
				tint = WorldSocket.CABLE_COLOUR
			hidden = cable_into(from.jack)
			if hidden != null:
				hidden.visible = false
	var carried := PatchCable.create(fixed, _loose_end(at), tint, from.get_instance_id())
	carried.name = "CarriedCable"
	carried.sag_ratio = CABLE_SAG
	add_child(carried)
	_drag = {"from": from, "lifted": lifted, "cable": carried, "hidden": hidden, "target": null,
			"source": Modular.source_of(patch, from.jack) if lifted != &"" else &""}
	for j in _candidates(from, lifted):
		j.set_light(ModularJack.Light.CANDIDATE)


func _on_drag_moved(from: ModularJack, at: Vector3, over: ControlAffordance) -> void:
	if _drag.is_empty() or _drag["from"] != from:
		return
	var target := _target_for(from, over)
	var before: ModularJack = _drag["target"]
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
	var lifted: StringName = _drag["lifted"]
	var source: StringName = _drag["source"]
	var carried: PatchCable = _drag["cable"]
	if is_instance_valid(carried):
		carried.queue_free()
	var hidden: PatchCable = _drag["hidden"]
	if hidden != null and is_instance_valid(hidden):
		hidden.visible = true
	_drag.clear()
	for j: ModularJack in jacks.values():
		j.set_light(ModularJack.Light.PLAIN)
	if lifted != &"":
		if over == from:
			return
		# Pulled out of here, and, let go over another free input, into that.
		patch_asked.emit(lifted, &"")
		if target != null:
			patch_asked.emit(source, target.jack)
			Foley.play(target, Foley.plug_seat(), -6.0)
		return
	if target == null:
		var taken := over as ModularJack
		if taken != null and taken != from and taken.output != from.output and not taken.output \
				and Modular.source_of(patch, taken.jack) != &"":
			told.emit("%s has a cable in it already: pull that one out first." % Modular.jack_title(taken.jack))
		return
	patch_asked.emit(from.jack, target.jack)
	Foley.play(target, Foley.plug_seat(), -6.0)


## The jacks a cable carried from `from` could be let go on: from an output, every input with no
## cable in it; from an input, every output; a plug lifted out of an input, every other free input.
func _candidates(from: ModularJack, lifted: StringName) -> Array[ModularJack]:
	var out: Array[ModularJack] = []
	for j: ModularJack in jacks.values():
		if j == from:
			continue
		if lifted != &"" or from.output:
			if not j.output and Modular.source_of(patch, j.jack) == &"":
				out.append(j)
		elif j.output:
			out.append(j)
	return out


func _target_for(from: ModularJack, over: ControlAffordance) -> ModularJack:
	var j := over as ModularJack
	if j == null or j == from:
		return null
	return j if _candidates(from, _drag.get("lifted", &"")).has(j) else null


func _loose_end(at: Vector3) -> Transform3D:
	var basis := global_transform.basis.orthonormalized()
	return Transform3D(basis, at + basis.z * 0.03)
