class_name RackUnit
extends Node3D

## One FX plugin as one piece of rack-mount gear.
##
## 19 inches wide and 2U tall because that is what the thing it is standing in for would be, and
## because a rack whose units are arbitrary sizes stops reading as a rack. The knobs are the
## plugin's own first few parameters, in Reaper's order, with Reaper's names -- NOT a curated
## mapping. A curated mapping per plugin would look better and would be a lie about what is
## actually loaded, and would silently show the wrong four knobs the moment someone swaps ReaComp
## for a third-party compressor.
##
## Eight knobs is the ceiling on a faceplate this size. A plugin with forty parameters gets its
## first eight and a PAGE CONTROL, which is the same compromise every real controller makes.
##
## The page control is not optional dressing. Without it this showed a plugin's first eight
## parameters and nothing said there were thirty-two more -- the unit looked like a complete
## unit for a simpler plugin than the one that is loaded, which is the same failure the
## console's BankSelector exists to prevent and is stated at length there. It is built only
## when the plugin overflows, for the same reason: a faceplate carrying two dead buttons
## invites the question of what they are for.

## The grip on the name strip was pulled (or clicked): this plugin wants a tablet. `at` is where
## the hand let go, in world space.
signal tear_requested(track: int, fx: int, at: Vector3)

const RACK_WIDTH := 0.483
const U := 0.0445
const UNITS_TALL := 2
const RACK_HIT_PAD := Vector2(1.3, 2.1)
const MAX_KNOBS := 8
const MESH_PATH := "res://assets/hardware/rack_panel.glb"

## Where the knob row sits, measured from the middle of the faceplate.
##
## It was at a quarter of the plate height below centre, which put the knobs in the bottom
## fifth with 35mm of empty metal between them and the title and 3mm of clearance under their
## captions. In a photograph that reads as controls that slid down the panel: the dead space
## is in the MIDDLE, where nothing on real hardware leaves it, and the labels are pressed
## against the lower edge. Raised so the knob-and-caption group is centred in the area the
## header leaves, which gives a bottom margin instead of a hole.
##
## Raised again, by 5mm, when captions went to two lines. They had to: at a size that reads on
## a monitor, "BAND 1 FREQ" is 70mm on one line and the knobs are 52mm apart. Two lines of a
## readable size need the space a squeezed single line was leaving empty below it.
const KNOB_ROW_Y := -0.007
## Centre-to-centre along the row. A knob is 22mm across, so this is 30mm of fascia between
## neighbours -- enough for a caption that is wider than its knob, which most of them are.
const KNOB_PITCH := 0.052
## From the knob's centre to the TOP of its caption, which hangs down from there.
const CAPTION_DROP := 0.0125
## Caption size before fitting. Was 36, which measured 6.3px with the rack focused at 1600x900 --
## about 4.5px of capital. 50, wrapped, is as large as the slot under a knob holds.
const CAPTION_SIZE := 50
## Font pixels between wrapped lines, tightened from the face's default so two lines fit the
## space a single one used to stand in.
const CAPTION_LEADING := -12
## The silkscreened rule under the title. Every processor that has a title bar has one, and
## without it the header and the controls are two things floating on the same slab.
const RULE_Y := U * UNITS_TALL * 0.5 - 0.027
## The name's own territory, left to right: the TearTab's width, since the grip IS the name and
## the two should cover the same ground. Unconstrained before this, the label ran straight
## through the bypass button and, on a plugin past MAX_KNOBS, the page readout too -- the rack's
## only label nothing ever called `Lettering.fit` on (2026-10-11: "Rack unit labels can overlap
## their first knob caption on long plugin names" -- the actual collision, measured off a
## screenshot, lands on the header icons rather than a caption a full row below, but the cause
## and the fix are the same one a name-sizing miss always is here).
const NAME_SPAN := 0.24
const NAME_SIZE := 64
const NAME_SIZE_MIN := 32

var track_index: int = 0
## How often a hovered knob may ask Reaper for its reading, and when it last did.
const TEXT_ASK_MSEC := 150
var _text_asked_msec := -100000
var fx_index: int = 0

## Which eight parameters the knobs currently mean. Always a multiple of MAX_KNOBS.
var page_offset := 0

## Where the faceplates, knobs and power buttons are drawn, if the rack gave this unit somewhere:
## a dozen units is a dozen identical plates and a hundred identical knobs, one object each. Set
## before the unit enters the tree; the rack commits them once every unit has claimed its slots.
var panel_bank: MeshBank
var knob_bank: MeshBank
var body_bank: MeshBank
var lamp_bank: MeshBank

var _knobs: Array[Knob] = []
var _bypass: PanelButton
var _name_label: Label3D
var _page_label: Label3D
var _page_prev: PanelButton
var _page_next: PanelButton
## A page change asked for while a hand is on a knob, held until the hand lets go.
##
## THE RULE A PAGE MUST NOT BREAK, and it is the console's rule in a smaller place: a knob may
## never change which parameter it means while someone is turning it. Applying immediately
## would send the new parameter the old hand position -- a value nobody asked for, written to
## a parameter nobody was looking at, with nothing about it resembling an error.
var _pending_page := -1


static func create(track_idx: int, fx_idx: int) -> RackUnit:
	var u := RackUnit.new()
	u.track_index = track_idx
	u.fx_index = fx_idx
	u.name = "Rack_t%d_fx%d" % [track_idx, fx_idx]
	return u


func height() -> float:
	return U * UNITS_TALL


## The pre-Blender faceplate: a slab, two raised ear plates and four pegs. Kept so a missing
## asset is a plainer rack rather than knobs floating in mid air.
func _stand_in(h: float) -> Node3D:
	var holder := Node3D.new()

	var face := MeshInstance3D.new()
	var face_mesh := BoxMesh.new()
	face_mesh.size = Vector3(RACK_WIDTH, h - 0.002, 0.012)
	face.mesh = face_mesh
	face.position = Vector3(0, 0, -0.006)
	face.material_override = Materials.chassis()
	holder.add_child(face)

	for side in [-1.0, 1.0]:
		var ear := MeshInstance3D.new()
		var ear_mesh := BoxMesh.new()
		ear_mesh.size = Vector3(0.016, h - 0.004, 0.004)
		ear.mesh = ear_mesh
		ear.position = Vector3(side * (RACK_WIDTH * 0.5 - 0.009), 0, 0.002)
		ear.material_override = Materials.brushed_metal()
		holder.add_child(ear)
		for sy in [-1.0, 1.0]:
			var screw := MeshInstance3D.new()
			var screw_mesh := CylinderMesh.new()
			screw_mesh.top_radius = 0.0022
			screw_mesh.bottom_radius = 0.0022
			screw_mesh.height = 0.002
			screw_mesh.radial_segments = 8
			screw.mesh = screw_mesh
			screw.rotation_degrees = Vector3(90, 0, 0)
			screw.position = Vector3(side * (RACK_WIDTH * 0.5 - 0.009), sy * U * 0.5, 0.005)
			screw.material_override = Materials.cap_plastic(Color(0.3, 0.31, 0.33))
			holder.add_child(screw)
	return holder


func _ready() -> void:
	var h := height()

	# The faceplate, ears and mounting hardware as one authored part. The ears are not bolted
	# on: the ends of a rack panel ARE its ears, with oblong holes through them, which is what
	# the four raised plates this used to draw were getting wrong.
	var panel: Node3D = null
	if panel_bank != null:
		panel = Node3D.new()
		panel.name = "Panel"
	else:
		panel = Part.build(
			MESH_PATH,
			Materials.chassis(),
			{"screw": Materials.brushed_metal()},
		)
	if panel != null:
		# Modelled standing, so no correcting rotation -- only the shift that puts its front
		# face on z = 0, where every knob and label on this unit was laid out against.
		panel.position = Vector3(0, 0, -0.006)
		add_child(panel)
		if panel_bank != null:
			panel_bank.place(panel, Color.WHITE)
	else:
		add_child(_stand_in(h))

	var rule := MeshInstance3D.new()
	var rule_mesh := BoxMesh.new()
	# In the track's colour: which track's chain a unit is in, read off the unit itself, on a
	# pulled tablet's stand or across the room.
	rule_mesh.size = Vector3(RACK_WIDTH - 0.056, 0.0016, 0.001)
	rule.mesh = rule_mesh
	rule.name = "TrackRule"
	rule.position = Vector3(0, RULE_Y, 0.0015)
	rule.material_override = Materials.track_stripe(DAW.state.track(track_index).shown_colour()) \
			if DAW.state.tracks.has(track_index) else Materials.cap_plastic(Color(0.34, 0.35, 0.37))
	add_child(rule)

	_name_label = Label3D.new()
	_name_label.font_size = NAME_SIZE
	_name_label.pixel_size = 0.00019
	_name_label.position = Vector3(-RACK_WIDTH * 0.5 + 0.03, h * 0.5 - 0.016, 0.002)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_name_label.modulate = Color(0.85, 0.86, 0.88)
	Lettering.range_to_legibility(_name_label)
	add_child(_name_label)

	# Over the name, from the left ear to the page readout: the name is what you take hold of.
	var tab := TearTab.new()
	tab.name = "TearTab"
	tab.size = Vector2(NAME_SPAN, 0.02)
	tab.position = Vector3(-RACK_WIDTH * 0.5 + 0.018, h * 0.5 - 0.016, 0.001)
	tab.ghost_colour = DAW.state.track(track_index).shown_colour()
	tab.describe_title = func() -> String: return "%s  ON A TABLET" % _unit_caption()
	tab.describe_value = func(_v: float) -> String: return "pull to take it off the rack"
	tab.torn.connect(func(at: Vector3): tear_requested.emit(track_index, fx_index, at))
	add_child(tab)

	# A rack is the furthest thing from the seat that has buttons this small on it.
	_bypass = PanelButton.new()
	_bypass.body_bank = body_bank
	_bypass.lamp_bank = lamp_bank
	_bypass.hit_pad = RACK_HIT_PAD
	_bypass.led_colour = Color(0.4, 0.95, 0.5)
	_bypass.position = Vector3(RACK_WIDTH * 0.5 - 0.035, h * 0.5 - 0.016, 0.004)
	_bypass.describe_title = func() -> String: return "%s  POWER" % _unit_caption()
	_bypass.describe_value = func(_v: float) -> String:
		return ("ACTIVE" if _bypass.lit else "BYPASSED") + "  ·  fine press removes it"
	_bypass.pressed.connect(_power)
	add_child(_bypass)

	# Right of the name, left of the bypass: the readout is about the knobs, so it sits with
	# them rather than with the on/off at the far end.
	_page_label = Label3D.new()
	_page_label.font_size = 42
	_page_label.pixel_size = 0.00019
	_page_label.position = Vector3(RACK_WIDTH * 0.5 - 0.112, h * 0.5 - 0.016, 0.002)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_page_label.modulate = Color(0.60, 0.63, 0.68)
	Lettering.range_to_legibility(_page_label)
	add_child(_page_label)

	_page_prev = PanelButton.new()
	_page_prev.hit_pad = RACK_HIT_PAD
	_page_prev.led_colour = Color(0.45, 0.68, 0.95)
	_page_prev.position = Vector3(RACK_WIDTH * 0.5 - 0.090, h * 0.5 - 0.016, 0.004)
	_page_prev.pressed.connect(func(): _step_page(-1))
	_page_prev.describe_title = func() -> String: return "%s  PREVIOUS PAGE" % _unit_caption()
	_page_prev.describe_value = func(_v: float) -> String: return _page_label.text
	add_child(_page_prev)

	_page_next = PanelButton.new()
	_page_next.hit_pad = RACK_HIT_PAD
	_page_next.led_colour = Color(0.45, 0.68, 0.95)
	_page_next.position = Vector3(RACK_WIDTH * 0.5 - 0.068, h * 0.5 - 0.016, 0.004)
	_page_next.pressed.connect(func(): _step_page(1))
	_page_next.describe_title = func() -> String: return "%s  NEXT PAGE" % _unit_caption()
	_page_next.describe_value = func(_v: float) -> String: return _page_label.text
	add_child(_page_next)

	# All eight now, used or not: a bank is sized once, so a knob made later -- when a plugin's
	# parameters arrive after its name, as Reaper's do -- would have nowhere to be drawn.
	while _knobs.size() < MAX_KNOBS:
		_add_knob()

	DAW.fx_changed.connect(_on_fx_changed)
	set_process(true)
	refresh()


## Only ever running to land a deferred page change; see `_pending_page`.
## POWER bypasses the plugin; a fine press (shift on a monitor) takes it out of the chain.
func _power() -> void:
	var by: Node = _bypass.held_by
	if by != null and by.has_method("fine") and by.fine():
		DAW.remove_fx(track_index, fx_index)
		return
	var f := DAW.state.fx(track_index, fx_index)
	DAW.set_fx_enabled(track_index, fx_index, not f.enabled)


func _process(_delta: float) -> void:
	if _pending_page < 0 or _anything_held():
		return
	page_offset = _pending_page
	_pending_page = -1
	refresh()


func _anything_held() -> bool:
	for k in _knobs:
		if k.is_held():
			return true
	return false


## Asked for by the page buttons. Deferred rather than refused: refusing would mean a press
## that did nothing, and the hand on the knob is usually the other hand.
func _step_page(direction: int) -> void:
	var wanted := (_pending_page if _pending_page >= 0 else page_offset) \
			+ direction * MAX_KNOBS
	if wanted < 0 or wanted >= _param_count():
		return
	if _anything_held():
		_pending_page = wanted
		return
	page_offset = wanted
	refresh()


func _param_count() -> int:
	var f := DAW.state.fx(track_index, fx_index, false)
	return f.params.size() if f != null else 0


## The parameter index a given knob currently means.
##
## Read at the moment of the turn rather than captured when the knob was built, because a knob
## is re-pointed by a page change and a captured index would keep writing the parameter it was
## created for. -1 when this slot is past the end of the plugin.
## "KICK  REAEQ", for the hover card. Asked at hover time, like the knob's parameter, because
## the unit is re-pointed rather than rebuilt.
func _unit_caption() -> String:
	var f := DAW.state.fx(track_index, fx_index, false)
	var track := DAW.state.track(track_index)
	return "%s  %s" % [track.display_name().to_upper(), f.name.to_upper() if f != null else "FX"]


func _param_name(slot: int) -> String:
	var f := DAW.state.fx(track_index, fx_index, false)
	var index := _param_for(slot)
	if f == null or index < 0:
		return "?"
	return str(f.param_names.get(index, "P%d" % index)).to_upper()


## The plugin's own words for a knob's value when Reaper has said them, else a percentage.
##
## Only trusted while it belongs to the value on the knob: the text and the number arrive as
## separate messages, and mid-turn the knob is ahead of both. A "-12.0 dB" left over from
## before the turn would be exact-looking and wrong, which is worse than an honest "41%".
##
## Asked for here, and only here: the card reads this while a knob is under a hand, so the one
## parameter anyone is looking at is the one fetched. Throttled, because the card asks every
## frame and a turn changes the value on most of them.
func _param_reading(slot: int, v: float) -> String:
	var f := DAW.state.fx(track_index, fx_index, false)
	var index := _param_for(slot)
	if f == null or index < 0:
		return "%d%%" % roundi(v * 100.0)
	var at := float(f.param_text_at.get(index, f.params.get(index, -1.0)))
	if f.param_text.has(index) and absf(at - v) < 0.002:
		var text := str(f.param_text[index]).strip_edges()
		if not text.is_empty():
			return text
	var now := Time.get_ticks_msec()
	if now - _text_asked_msec > TEXT_ASK_MSEC:
		_text_asked_msec = now
		DAW.read_fx_param_text(track_index, fx_index, index)
	return "%d%%" % roundi(v * 100.0)


func _param_for(slot: int) -> int:
	var f := DAW.state.fx(track_index, fx_index, false)
	if f == null:
		return -1
	var params: Array = f.params.keys()
	params.sort()
	var at := page_offset + slot
	return int(params[at]) if at < params.size() else -1


func refresh() -> void:
	var f := DAW.state.fx(track_index, fx_index, false)
	if f == null:
		return
	var track := DAW.state.track(track_index)
	_name_label.text = "%s   %s" % [track.display_name().to_upper(), f.name]
	# Measured from the tab's own left edge, matching where the grip starts rather than the
	# label's -- the label sits 12mm further in to clear the tab's own icon, and that 12mm has
	# to come off the span or a name just inside this fit would still touch the page readout.
	Lettering.fit(_name_label, NAME_SPAN - 0.012, NAME_SIZE, NAME_SIZE_MIN)
	_bypass.lit = f.enabled

	var params: Array = f.params.keys()
	params.sort()
	# A plugin can lose parameters -- a different preset, a reload -- and a page left past the
	# end would show a faceplate of nothing with no clue that paging back would fix it.
	if page_offset >= params.size():
		page_offset = maxi((int((params.size() - 1) / MAX_KNOBS)) * MAX_KNOBS, 0)
	var on_this_page: int = clampi(params.size() - page_offset, 0, MAX_KNOBS)

	# Knobs are created once and then only re-pointed. Rebuilding them on every FX update would
	# drop a knob that is being turned, and FX updates arrive while you turn it. A page change
	# is the same thing for the same reason, which is why a knob asks `_param_for` at the
	# moment of the turn rather than carrying the index it was built with.
	for i in _knobs.size():
		if i < on_this_page:
			var param_index: int = params[page_offset + i]
			_knobs[i].visible = true
			_knobs[i].apply_remote(f.params[param_index])
			var caption := get_node_or_null("Caption%d" % i)
			if caption:
				caption.visible = true
				caption.text = str(f.param_names.get(param_index, "P%d" % param_index)).to_upper()
				# Wrap width is in font pixels and has to be restated whenever fitting changes
				# the font size, or a smaller size wraps as if it were the larger one.
				Lettering.fit(caption, KNOB_PITCH - 0.006, CAPTION_SIZE)
				caption.width = (KNOB_PITCH - 0.006) / caption.pixel_size
		else:
			_knobs[i].visible = false
			var spare := get_node_or_null("Caption%d" % i)
			if spare:
				spare.visible = false

	_refresh_page_control(params.size(), on_this_page)


## One knob and its caption, in the next slot along.
func _add_knob() -> void:
	var k := Knob.new()
	k.body_bank = knob_bank
	var slot := _knobs.size()
	k.position = Vector3(-RACK_WIDTH * 0.5 + 0.055 + slot * KNOB_PITCH, KNOB_ROW_Y, 0.005)
	# Named for the same reason the caption is: a failure that says "knob @StaticBody3D@4327"
	# names nothing, in a test whose job is to say WHICH control went off the plate.
	k.name = "Knob%d" % slot
	k.turned.connect(func(v: float):
		var param_index := _param_for(slot)
		if param_index >= 0:
			DAW.set_fx_param(track_index, fx_index, param_index, v))
	k.describe_title = func() -> String: return "%s  %s" % [_unit_caption(), _param_name(slot)]
	k.describe_value = func(v: float) -> String: return _param_reading(slot, v)
	add_child(k)
	# Hidden until a parameter is pointed at it; after it is in the tree, so a banked knob's
	# slot goes with it.
	k.visible = false
	_knobs.append(k)

	var caption := Label3D.new()
	caption.font_size = CAPTION_SIZE
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	caption.line_spacing = CAPTION_LEADING
	caption.pixel_size = 0.00018
	caption.position = k.position + Vector3(0, -CAPTION_DROP, 0)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.modulate = Color(0.66, 0.68, 0.7)
	caption.name = "Caption%d" % slot
	Lettering.range_to_legibility(caption)
	caption.visible = false
	add_child(caption)


## The readout and its two buttons, shown only when the plugin does not fit on the faceplate.
##
## "9-16 OF 18" is the whole point of this control: without it a unit showing eight knobs and a
## unit showing eight OF THIRTY-TWO look identical, and the second one is lying about the
## plugin. The buttons are what you do about it.
func _refresh_page_control(total: int, on_this_page: int) -> void:
	if _page_label == null:
		return
	var overflows := total > MAX_KNOBS
	_page_label.visible = overflows
	_page_prev.visible = overflows
	_page_next.visible = overflows
	if not overflows:
		return
	_page_label.text = "%d-%d OF %d" % [page_offset + 1, page_offset + on_this_page, total]
	# Lit means "there is something that way", as on the console. An unlit page button at the
	# end of a plugin is the only thing that says you have reached the end rather than that the
	# button has stopped working.
	_page_prev.lit = page_offset > 0
	_page_next.lit = page_offset + MAX_KNOBS < total


func _on_fx_changed(t: int, fx: int) -> void:
	if t == track_index and fx == fx_index:
		refresh()
