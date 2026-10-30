class_name InputPicker
extends CanvasLayer

## Everything about one track's input, on one panel: what it records from, whether it is heard,
## and whether its input is in use at all (2026-10-30: "choosing the input device for a track
## needs a better UI and a button to silence input for tracks im done recording on").
##
## The timeline's INPUT key used to step through every input one press at a time: each device
## three times over (both sides, input 1, input 2), the keys and none, so going back one was a
## dozen presses past names like "alsa_input.usb-...analog-stereo". Here every device is a row by
## the name the sound server gives it, its sides three buttons on that row, the one in use lit.
## Under them the track's monitoring, off / on / auto, and INPUT IN USE: off, the track neither
## hears nor records its input (MixState.TrackState.input_off), so it is off the meters, the
## LEVELS wall and the EQ wall's spectra while another track plays through the same input, and
## its choice is kept for when it is wanted again. LOOK AGAIN asks the machine for its devices
## afresh, for an interface plugged in since the game started.
##
## A 2D overlay, as PluginPicker and NamePrompt are, so a desk's: in a headset the INPUT key
## still steps. Every press acts at once, through DAW, and the panel redraws from DAW.state; it
## stays open until Escape or DONE, so a choice and its monitoring are made in one visit.

signal closed()

var track := 0
var _rows: VBoxContainer
var _title: Label


static func ask(parent: Node, index: int) -> InputPicker:
	var p := InputPicker.new()
	p.layer = 100
	p.track = index
	parent.get_tree().root.add_child(p)
	p._build()
	return p


func _build() -> void:
	var box := PanelContainer.new()
	box.name = "Box"
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(560, 0)
	box.position = Vector2(-280, -220)
	# Solid: over the room's lit panels the theme's own, half see-through, could not be read.
	box.add_theme_stylebox_override("panel", _box(Color(0.075, 0.08, 0.095, 0.97), Color(0.3, 0.32, 0.36), 16))
	add_child(box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	box.add_child(column)
	_title = Label.new()
	column.add_child(_title)
	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	column.add_child(_rows)
	var foot := HBoxContainer.new()
	column.add_child(foot)
	var again := Button.new()
	again.name = "LookAgain"
	again.text = "LOOK AGAIN"
	again.tooltip_text = "ask the machine for its input devices afresh"
	again.focus_mode = Control.FOCUS_NONE
	_frame(again)
	again.pressed.connect(func() -> void:
		DAW.refresh_inputs()
		redraw())
	foot.add_child(again)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(gap)
	var done := Button.new()
	done.name = "Done"
	done.text = "DONE"
	done.focus_mode = Control.FOCUS_NONE
	_frame(done)
	done.pressed.connect(close)
	foot.add_child(done)
	var hint := Label.new()
	hint.text = "every press takes at once  ·  Escape to leave it"
	hint.modulate = Color(1, 1, 1, 0.6)
	column.add_child(hint)
	redraw()


## The devices, each [name, [[id, side label], ...]], in the order DAW.state.inputs lists them:
## "audio:<device>" both sides, "#1" and "#2" each alone, then whatever is not a device's.
static func devices(inputs: Array) -> Array:
	var out: Array = []
	var at := {}
	for pair in inputs:
		var id := str(pair[0])
		if not id.begins_with("audio:"):
			out.append([str(pair[1]), [[id, "USE"]]])
			continue
		var device := GuestAudio.device_of(id)
		var side := GuestAudio.channel_of(id)
		if not at.has(device):
			at[device] = out.size()
			var said := str(pair[1])
			if side != 0:
				said = said.get_slice(",", 0)
			out.append([said, []])
		(out[at[device]][1] as Array).append([id, "BOTH" if side == 0 else "IN %d" % side])
	return out


func redraw() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var t: MixState.TrackState = DAW.state.track(track, false) if DAW.state != null else null
	if t == null:
		_title.text = "no such track"
		return
	_title.text = "INPUT  ·  %s" % t.display_name()
	for device in devices(DAW.state.inputs):
		var row := HBoxContainer.new()
		_rows.add_child(row)
		var name_label := Label.new()
		name_label.text = device[0]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.clip_text = true
		row.add_child(name_label)
		for side in device[1]:
			row.add_child(_choice(side[1], side[0] == t.input, func() -> void: DAW.set_track_input(track, side[0])))
	var none := HBoxContainer.new()
	_rows.add_child(none)
	var none_label := Label.new()
	none_label.text = "none chosen: as the recorder is set"
	none_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	none.add_child(none_label)
	none.add_child(_choice("USE", t.input == "", func() -> void: DAW.set_track_input(track, "")))
	_rows.add_child(HSeparator.new())
	var monitoring := HBoxContainer.new()
	monitoring.name = "Monitoring"
	_rows.add_child(monitoring)
	var heard := Label.new()
	heard.text = "hear it through the track"
	heard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	monitoring.add_child(heard)
	for mode in [[DAW.MONITOR_OFF, "OFF"], [DAW.MONITOR_ON, "ON"], [DAW.MONITOR_AUTO, "AUTO"]]:
		monitoring.add_child(_choice(mode[1], t.monitor == mode[0], func() -> void: DAW.set_track_monitor(track, mode[0])))
	var in_use := HBoxContainer.new()
	in_use.name = "InUse"
	_rows.add_child(in_use)
	var use_label := Label.new()
	use_label.text = "input in use" if not t.input_off \
			else "input set aside: not heard, not recorded, off the meters"
	use_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	use_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	in_use.add_child(use_label)
	var toggle := _choice("IN USE" if not t.input_off else "SET ASIDE", not t.input_off,
			func() -> void: DAW.set_track_input_off(track, not t.input_off))
	toggle.name = "InputOff"
	toggle.tooltip_text = "set this track's input aside, or take it back"
	in_use.add_child(toggle)


func _choice(text: String, on: bool, act: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = on
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(64, 0)
	_frame(b)
	b.pressed.connect(func() -> void:
		act.call()
		redraw.call_deferred())
	return b


## The theme's buttons are flat until pressed: framed here, so what can be pressed shows, and the
## one in use is lit in the input key's own red.
const LIT := Color(0.95, 0.42, 0.38)


static func _box(fill: Color, edge: Color, pad: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	box.set_content_margin_all(pad)
	box.content_margin_top = pad * 0.4
	box.content_margin_bottom = pad * 0.4
	return box


static func _frame(b: Button) -> void:
	b.add_theme_stylebox_override("normal", _box(Color(0.15, 0.16, 0.18), Color(0.32, 0.34, 0.38), 10))
	b.add_theme_stylebox_override("hover", _box(Color(0.21, 0.22, 0.25), Color(0.5, 0.52, 0.56), 10))
	b.add_theme_stylebox_override("pressed", _box(LIT.darkened(0.35), LIT, 10))
	b.add_theme_stylebox_override("hover_pressed", _box(LIT.darkened(0.25), LIT.lightened(0.2), 10))
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)


func close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
