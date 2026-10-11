class_name ChannelStrip
extends Node3D

## One channel of the console: name, pan, rec/solo/mute/monitor, a send socket, fader, meter.
##
## Built for a track index and bound to it for life. A rebuild of the console replaces strips
## wholesale rather than re-pointing them, because a strip that changes which track it means
## while someone is holding its fader writes the new track's volume from the old track's hand
## position -- a bug that only appears when a bank scrolls, which is exactly when nobody is
## watching the fader they just let go of.

const WIDTH := 0.055
const HEIGHT := 0.30

var track_index: int = 0
## Whose sends the fader and pan are showing: 0 for this track's own level and pan, or the index
## of a return, when the desk has been flipped to put the sends to it on the faders. Set by the
## console through `show_sends_to`, never while a hand is on the strip.
var send_dest: int = 0

var _fader: Fader
var _pan: Knob
var _mute: PanelButton
var _solo: PanelButton
var _rec: PanelButton
var _monitor: PanelButton
var _name_label: Label3D
var _db_label: Label3D
var _name_tab: NameTab

## Where this strip's repeated geometry gets drawn, if the console gave it somewhere. See
## hardware/mesh_bank.gd -- ninety strips of three buttons is 540 objects otherwise. All seven
## are optional and a strip with none of them builds everything itself, which is what keeps a
## strip usable outside a console surface.
##
## The last two hold the only MOVING geometry on the desk: a knob turns and a cap slides, so
## their slots are rewritten on every value change rather than claimed once. That is the whole
## difference between them and the other five.
var body_bank: MeshBank
var lamp_bank: MeshBank
var plate_bank: MeshBank
var chip_bank: MeshBank
var slot_bank: MeshBank
var knob_bank: MeshBank
var cap_bank: MeshBank
## And the send socket's nut and bore.
var socket_bank: MeshBank

## The track's send socket, beside the buttons: a personal mix's plug goes in here to hear this
## track by itself (PersonalMix). What its plugs and clicks mean is the studio's.
var send: SendSocket

const PLATE_SIZE := Vector3(WIDTH - 0.002, HEIGHT, 0.008)
const PLATE_OFFSET := Vector3(0, HEIGHT * 0.5, -0.005)
## Font sizes for the two things a strip says. Set from a measurement at 1600x900 with the desk
## focused: the old 56 and 44 came out at about 9 and 8 pixels, under the twelve where reading
## stops being an effort. 80 and 60 reach it, and `Lettering.fit` brings any name that would run
## off the strip back down, so a long one costs itself and not every other strip.
const NAME_SIZE := 80
const DB_SIZE := 60
## How much of the strip's width lettering may use: the panel less a few millimetres a side.
const LETTER_SPAN := WIDTH - 0.006
## The level readout's ink: the desk's ordinary lettering, and amber while the strip is showing
## a send rather than the track.
const LEVEL_INK := Color(0.86, 0.87, 0.89)
const SEND_INK := Color(0.95, 0.72, 0.36)
## And grey where a flipped strip has no send to show: it is the answer, but not a reading, and a
## row of amber NO SENDs shouted louder than the two sends that were there.
const ABSENT_INK := Color(0.42, 0.43, 0.46)
## Input monitoring's lamp blinks while it is on auto: lit is on, dark is off, and auto -- on only
## when Reaper would let the input through -- is neither, and says so without a new colour.
const AUTO_BLINK_HZ := 1.2
const CHIP_SIZE := Vector3(WIDTH - 0.008, 0.004, 0.001)
const CHIP_OFFSET := Vector3(0, HEIGHT - 0.022, 0.0005)

## Slot in `chip_bank`, or -1 when the chip is a mesh of its own. The plate needs no slot kept:
## nothing ever changes it after it is placed.
var _chip_slot := -1


static func create(index: int) -> ChannelStrip:
	var s := ChannelStrip.new()
	s.track_index = index
	s.name = "Strip%d" % index
	return s


func _ready() -> void:
	_claim_or_build(plate_bank, PLATE_SIZE, PLATE_OFFSET, Materials.chassis(), Color.WHITE, "")

	_name_label = _make_label(NAME_SIZE / 4, Vector3(0, HEIGHT - 0.011, 0.001))
	add_child(_name_label)

	# Over the name, not beside it: the strip has no spare millimetre, and the name is the one
	# thing already on it that says "this track" -- so that is where adding a plugin starts.
	_name_tab = NameTab.new()
	_name_tab.position = Vector3(0, HEIGHT - 0.016, 0.003)
	_name_tab.describe_title = func() -> String: return _caption_for("FIND A PLUGIN")
	_name_tab.describe_value = func(_v: float) -> String: return "search by name"
	_name_tab.pressed.connect(_open_plugin_search)
	add_child(_name_tab)

	# A colour chip carrying Reaper's own track colour. It is how you find the kick on a desk of
	# 32 identical strips, and it is the one piece of the DAW's visual language worth keeping.
	_chip_slot = _claim_or_build(
		chip_bank, CHIP_SIZE, CHIP_OFFSET, null, Color.WHITE, "ColourChip")

	_pan = Knob.new()
	_pan.body_bank = knob_bank
	_pan.position = Vector3(0, HEIGHT - 0.048, 0.004)
	_pan.turned.connect(_on_pan_turned)
	_pan.describe_title = func() -> String:
		return _caption_for("PAN") if send_dest <= 0 else _caption_for("SEND PAN TO " + _dest_name())
	_pan.describe_value = Knob.pan_text
	add_child(_pan)

	_rec = PanelButton.new()
	_rec.body_bank = body_bank
	_rec.lamp_bank = lamp_bank
	_rec.led_colour = Ergonomics.current.signal_colour(&"record")
	_rec.lamp_scale = Vector2(1.0, 1.0)
	_rec.position = Vector3(0, HEIGHT - 0.077, 0.004)
	_rec.describe_title = func() -> String: return _caption_for("RECORD ARM")
	_rec.pressed.connect(func(): DAW.set_track_rec_arm(track_index, not _state().rec_arm))
	add_child(_rec)

	_solo = PanelButton.new()
	_solo.body_bank = body_bank
	_solo.lamp_bank = lamp_bank
	_solo.led_colour = Ergonomics.current.signal_colour(&"solo")
	_solo.lamp_scale = Vector2(0.38, 1.0)
	_solo.position = Vector3(0, HEIGHT - 0.095, 0.004)
	_solo.describe_title = func() -> String: return _caption_for("SOLO")
	_solo.pressed.connect(func(): DAW.set_track_solo(track_index, not _state().solo))
	add_child(_solo)

	_mute = PanelButton.new()
	_mute.body_bank = body_bank
	_mute.lamp_bank = lamp_bank
	_mute.led_colour = Ergonomics.current.signal_colour(&"mute")
	_mute.lamp_scale = Vector2(1.0, 0.40)
	_mute.position = Vector3(0, HEIGHT - 0.113, 0.004)
	_mute.describe_title = func() -> String: return _caption_for("MUTE")
	_mute.pressed.connect(func(): DAW.set_track_mute(track_index, not _state().mute))
	add_child(_mute)

	# Input monitoring, under the three. Its lamp is a dot: the fourth silhouette, after the bar,
	# the stub and the line, so it is not told from the others by its green alone. A press steps
	# off -> on -> auto -> off, the order Reaper's own monitor button goes round in.
	_monitor = PanelButton.new()
	_monitor.body_bank = body_bank
	_monitor.lamp_bank = lamp_bank
	_monitor.led_colour = Ergonomics.current.signal_colour(&"ok")
	_monitor.lamp_scale = Vector2(0.38, 0.40)
	_monitor.position = Vector3(0, HEIGHT - 0.131, 0.004)
	_monitor.describe_title = func() -> String: return _caption_for("INPUT MONITOR")
	_monitor.describe_value = func(_v: float) -> String:
		return monitor_text(_state().monitor)
	_monitor.pressed.connect(func(): DAW.set_track_monitor(track_index, next_monitor(_state().monitor)))
	add_child(_monitor)

	# Beside mute and monitor, in the column the meter rises in below: the one place on the strip
	# with room for a plug to stand out of.
	send = SendSocket.new()
	send.source = PersonalMix.track_socket(track_index)
	send.hit = SendSocket.STRIP_HIT
	send.face_bank = socket_bank
	send.position = Vector3(0.0175, HEIGHT - 0.122, -0.001)
	add_child(send)

	_fader = Fader.new()
	_fader.track_index = track_index
	_fader.slot_bank = slot_bank
	_fader.cap_bank = cap_bank
	_fader.position = Vector3(-0.011, 0.040, 0.004)
	_fader.write_value = _on_fader_moved
	_fader.describe_title = func() -> String:
		return _caption_for("LEVEL") if send_dest <= 0 else _caption_for("SEND TO " + _dest_name())
	add_child(_fader)

	var meter := VUMeter.new()
	meter.track_index = track_index
	meter.position = Vector3(0.016, 0.042, 0.002)
	add_child(meter)

	_db_label = _make_label(DB_SIZE / 4, Vector3(0, 0.022, 0.001))
	add_child(_db_label)

	DAW.track_changed.connect(_on_track_changed)
	refresh()


func _make_label(font_size: int, pos: Vector3) -> Label3D:
	var l := Label3D.new()
	l.font_size = font_size * 4
	# pixel_size x font_size is the cap height in metres. At 0.00018 a 56px font is ~10mm, which
	# is legible across a room in AR and still sharp with a face against the panel.
	l.pixel_size = 0.00018
	l.position = pos
	l.modulate = Color(0.86, 0.87, 0.89)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.no_depth_test = false
	Lettering.range_to_legibility(l)
	return l


## The hover-card name of one of this strip's controls. Asked at hover time rather than baked
## at build, because a strip is re-pointed when the bank moves and a track can be renamed.
static func next_monitor(mode: int) -> int:
	return (mode + 1) % 3


static func monitor_text(mode: int) -> String:
	match mode:
		DAW.MONITOR_ON: return "ON"
		DAW.MONITOR_AUTO: return "AUTO (when armed and stopped, or recording)"
	return "OFF"


func _process(_delta: float) -> void:
	_monitor.lit = fmod(Time.get_ticks_msec() / 1000.0 * AUTO_BLINK_HZ, 1.0) < 0.5


func _caption_for(what: String) -> String:
	return "%s  %s" % [_state().display_name().to_upper(), what]


func _state() -> MixState.TrackState:
	return DAW.state.track(track_index)


## Put the sends to track `dest` on this strip's fader and pan, or the track's own back with 0.
func show_sends_to(dest: int) -> void:
	send_dest = maxi(dest, 0)
	refresh()
	# Past any echo wait: what the controls were waiting to hear about is the other number.
	var t := _state()
	var slot := send_slot()
	if send_dest <= 0:
		_fader.snap_to(t.volume)
		_pan.snap_to(t.pan)
	else:
		_fader.snap_to((t.sends[slot] as MixState.SendState).volume if slot > 0 else 0.0)
		_pan.snap_to((t.sends[slot] as MixState.SendState).pan if slot > 0 else 0.5)


## This track's send to `send_dest`, as its 1-based slot, or 0 when it has none. The lowest slot
## wins when a track sends to the same return twice, which Reaper allows and nobody means.
func send_slot() -> int:
	if send_dest <= 0:
		return 0
	var t := _state()
	var order: Array = t.sends.keys()
	order.sort()
	for i in order:
		if int(i) >= 1 and (t.sends[i] as MixState.SendState).resolve(DAW.state) == send_dest:
			return int(i)
	return 0


func _dest_name() -> String:
	return DAW.state.track(send_dest).display_name().to_upper()


func _on_fader_moved(v: float) -> void:
	if send_dest <= 0:
		DAW.set_track_volume(track_index, v)
		return
	var slot := send_slot()
	if slot > 0:
		DAW.set_send_volume(track_index, slot, v)


func _on_pan_turned(v: float) -> void:
	if send_dest <= 0:
		DAW.set_track_pan(track_index, v)
		return
	var slot := send_slot()
	if slot > 0:
		DAW.set_send_pan(track_index, slot, v)


## Opens the same searchable picker the rack's own FIND button does (hardware/rack/rack_surface.
## gd), for this strip's track directly -- so finding a plugin never requires finding the rack
## first. Desktop-only, same as the rack's: PluginPicker is a 2D overlay, and XR still has the
## rack's wheel.
func _open_plugin_search() -> void:
	if (is_inside_tree() and get_viewport().use_xr) or not DAW.state.tracks.has(track_index):
		return
	if DAW.state.fx_choices.size() <= 1:
		return
	var picker := PluginPicker.ask(self, "Add a plugin to %s" % _state().display_name(),
			DAW.state.fx_choices)
	picker.chosen.connect(_add_plugin_by_id)


func _add_plugin_by_id(id: String) -> void:
	if DAW.state.tracks.has(track_index):
		DAW.add_fx(track_index, id)


func _on_track_changed(index: int, _field: StringName) -> void:
	if index == track_index:
		refresh()


## Pull every displayed value from the cache. Cheap enough to do wholesale rather than per field,
## and a single path means a strip cannot end up showing a mix of two different moments.
func refresh() -> void:
	var t := _state()
	_name_label.text = t.display_name().to_upper()
	send.label = t.display_name().to_upper()
	var level := t.volume
	var pan := t.pan
	var db := t.volume_db
	# Flipped: the fader is a send. Lettered in the send colour so a desk of send levels is
	# never read as a desk of track levels -- the two look identical otherwise, and a fader
	# pulled down "to fix the vocal" would be the reverb on it.
	_db_label.modulate = SEND_INK if send_dest > 0 else LEVEL_INK
	var slot := send_slot()
	var live := send_dest <= 0 or slot > 0
	if send_dest > 0:
		if slot > 0:
			var sd: MixState.SendState = t.sends[slot]
			level = sd.volume
			pan = sd.pan
			db = DAW.taper_to_db(sd.volume)
		else:
			level = 0.0
			pan = 0.5
	if live:
		_db_label.text = "%+.1f" % db if db > -150.0 else "-inf"
	else:
		_db_label.text = "NO SEND"
		_db_label.modulate = ABSENT_INK
	# A strip with no send to the return has nothing for the fader to move. Taken off the
	# collision layer rather than left grabbable: a cap that slides and changes nothing is a
	# control lying about what it does.
	_fader.collision_layer = 2 if live else 0
	_pan.collision_layer = 2 if live else 0
	Lettering.fit(_name_label, LETTER_SPAN, NAME_SIZE, ConsoleSurface.SMALLEST_FONT)
	Lettering.fit(_db_label, LETTER_SPAN, DB_SIZE, ConsoleSurface.SMALLEST_FONT)
	_fader.apply_remote(level)
	_pan.apply_remote(pan)
	_mute.lit = t.mute
	_solo.lit = t.solo
	_rec.lit = t.rec_arm
	_monitor.lit = t.monitor == DAW.MONITOR_ON
	set_process(t.monitor == DAW.MONITOR_AUTO)
	if chip_bank != null:
		# Banked chips are unshaded, so the emission `led()` would have carried has to be
		# expressed as a colour above 1 instead -- gently, because a chip is an identifier and
		# a clipped identifier is no identifier. See Materials.chip_colour.
		chip_bank.set_colour(_chip_slot, Materials.chip_colour(t.colour))
	else:
		var chip := get_node_or_null("ColourChip")
		if chip:
			chip.material_override = Materials.led(t.colour, true)


## Put one box either into a bank or into the strip, depending on whether there is a bank.
##
## Same shape as PanelButton's two branches and worth factoring out here because the strip has
## three of them. A marker node rather than arithmetic for the bank case: the offset is stated
## once, and the bank is handed a transform instead of a position plus an assumption about which
## way the strip is facing.
func _claim_or_build(bank: MeshBank, size: Vector3, offset: Vector3, material: Material,
		tint: Color, mesh_name: String) -> int:
	if bank != null:
		var at := Node3D.new()
		add_child(at)
		at.position = offset
		var slot := bank.place(at, tint)
		at.queue_free()
		return slot
	var box := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	box.mesh = box_mesh
	box.position = offset
	if material != null:
		box.material_override = material
	if mesh_name != "":
		box.name = mesh_name
	add_child(box)
	return -1
