class_name TimelineTrackStrip
extends Node3D

## Tracks added, removed and named, under the timeline's right-hand end: ADD puts a new track
## after the picked one (or at the end), DEL removes the picked one, NAME renames it. A track is
## picked by pressing its name. Removing is one undo away, like every edit. AUTO steps the picked
## track through read, touch and latch: in touch a control moved while the song plays writes its
## lane until it is let go, in latch until the transport stops. LANE shows the picked track's
## automation over its lane, one control after another (see TimelineSurface.lane_targets), and
## then none. IN steps the picked track through what it records from (`MixState.inputs`, then
## none chosen); saved with the project. COLOUR steps the picked track through PALETTE, its lamp
## the track's colour.

const PITCH := 0.028
const CAPTION := Color(0.62, 0.64, 0.68)

## The TimelineSurface. Typed loosely so the files load in any order.
var surface: Node

var add: PanelButton
var remove: PanelButton
var rename: PanelButton
var auto: PanelButton
var lane: PanelButton
var input: PanelButton
var colour: PanelButton

## Twelve colours a track can be, round the wheel and readable on the dark desk.
const PALETTE := [
	Color(0.86, 0.32, 0.30), Color(0.92, 0.52, 0.25), Color(0.93, 0.76, 0.28), Color(0.70, 0.82, 0.30),
	Color(0.38, 0.75, 0.40), Color(0.28, 0.72, 0.62), Color(0.30, 0.68, 0.86), Color(0.36, 0.50, 0.90),
	Color(0.58, 0.44, 0.88), Color(0.80, 0.42, 0.80), Color(0.90, 0.42, 0.60), Color(0.62, 0.64, 0.66),
]

const MODE_NAMES := {0: "READ", 2: "TOUCH", 4: "LATCH"}


func _ready() -> void:
	var plate := MeshInstance3D.new()
	plate.name = "Plate"
	var box := BoxMesh.new()
	box.size = Vector3(7 * PITCH + 0.008, 0.036, 0.004)
	plate.mesh = box
	plate.material_override = Materials.chassis()
	plate.position = Vector3(3.0 * PITCH, -0.004, -0.002)
	add_child(plate)
	add = _key("TrackAdd", "ADD", 0, Color(0.55, 0.85, 0.55), "TRACKS  ADD", _add,
			func() -> String:
				var picked: int = surface.picked_track
				return "a new track after %s" % _name_of(picked) if picked > 0 else "a new track at the end")
	remove = _key("TrackRemove", "DEL", 1, Color(0.95, 0.38, 0.34), "TRACKS  REMOVE",
			_remove,
			func() -> String:
				var picked: int = surface.picked_track
				return "%s, its items and the sends to it" % _name_of(picked) if picked > 0 else "press a track's name first")
	rename = _key("TrackName", "NAME", 2, Color(0.45, 0.78, 0.95), "TRACKS  NAME",
			_rename,
			func() -> String:
				var picked: int = surface.picked_track
				if picked <= 0:
					return "press a track's name first"
				return "type a name for %s" % _name_of(picked) if surface.types_on_screen() \
						else "type a name for %s on the keypad" % _name_of(picked))
	auto = _key("TrackAuto", "AUTO", 3, Color(0.95, 0.6, 0.25), "TRACKS  AUTOMATION", _auto,
			func() -> String:
				var picked: int = surface.picked_track
				# With no track picked, the master's fader and pan.
				var who := _name_of(picked) if picked > 0 else "the master"
				var mode := _mode_of(picked)
				return "%s reads its lanes: %s next" % [who, MODE_NAMES[_next(mode)]] if mode == 0 \
						else "%s writes in %s: %s next" % [who, MODE_NAMES[mode], MODE_NAMES[_next(mode)]])
	lane = _key("TrackLane", "LANE", 4, TimelineSurface.AUTOMATION_COLOUR, "TRACKS  AUTOMATION LANE", _lane,
			func() -> String:
				var picked: int = surface.picked_track
				# With no track picked, the master's lanes.
				var whose := "the master's " if picked <= 0 else ""
				var next := _next_lane()
				return "show %s%s" % [whose, TimelineSurface.lane_name(next).to_lower()] if next != "" else "hide the lane")
	input = _key("TrackInput", "IN", 5, Color(0.95, 0.42, 0.38), "TRACKS  INPUT", _step_input,
			func() -> String:
				var picked: int = surface.picked_track
				if picked <= 0 or not DAW.state.tracks.has(picked):
					return "press a track's name first"
				return "%s records from %s: %s next" % [_name_of(picked),
						DAW.state.input_name(DAW.state.input_of(picked)), DAW.state.input_name(_next_input())])
	colour = _key("TrackColour", "COLR", 6, PALETTE[0], "TRACKS  COLOUR", _step_colour,
			func() -> String:
				var picked: int = surface.picked_track
				if picked <= 0 or not DAW.state.tracks.has(picked):
					return "press a track's name first"
				return "a new colour for %s" % _name_of(picked))
	DAW.track_changed.connect(_on_track_changed)
	DAW.master_changed.connect(_on_master_changed)
	refresh()


## The target after the one shown, or "" after the last.
func _next_lane() -> String:
	var targets := TimelineSurface.lane_targets(surface.picked_track)
	var at := targets.find(surface.shown_lane)
	if surface.shown_lane == "":
		return targets[0] if not targets.is_empty() else ""
	return targets[at + 1] if at >= 0 and at + 1 < targets.size() else ""


func _lane() -> void:
	if surface.picked_track == 0 or DAW.state.tracks.has(surface.picked_track):
		surface.show_lane(_next_lane())
		refresh()


func _on_master_changed(field: StringName) -> void:
	if field == &"automation_mode" and surface.picked_track == 0:
		refresh()


func _on_track_changed(index: int, field: StringName) -> void:
	if field in [&"automation_mode", &"input", &"colour"] and index == surface.picked_track:
		refresh()


func _next(mode: int) -> int:
	return DAW.AUTOMATION_TOUCH if mode == DAW.AUTOMATION_READ \
			else DAW.AUTOMATION_LATCH if mode == DAW.AUTOMATION_TOUCH else DAW.AUTOMATION_READ


## The automation mode of a track, or of the master for 0.
func _mode_of(index: int) -> int:
	if index <= 0:
		return DAW.state.master.automation_mode
	return DAW.state.track(index).automation_mode if DAW.state.tracks.has(index) else 0


func _auto() -> void:
	var picked: int = surface.picked_track
	if picked == 0 or DAW.state.tracks.has(picked):
		DAW.set_track_automation_mode(picked, _next(_mode_of(picked)))


func refresh() -> void:
	add.lit = true
	var picked: bool = surface.picked_track > 0 and DAW.state.tracks.has(surface.picked_track)
	remove.lit = picked
	rename.lit = picked
	lane.lit = surface.shown_lane != ""
	auto.lit = _mode_of(surface.picked_track) != DAW.AUTOMATION_READ
	input.lit = picked and DAW.state.input_of(surface.picked_track) != ""
	if picked:
		colour.led_colour = DAW.state.track(surface.picked_track).colour
	# After the colour: setting lit repaints the lamp.
	colour.lit = picked


## The palette's colour after the nearest one to `c`.
static func next_colour(c: Color) -> Color:
	var nearest := 0
	var best := INF
	for i in PALETTE.size():
		var p: Color = PALETTE[i]
		var d := Vector3(p.r - c.r, p.g - c.g, p.b - c.b).length_squared()
		if d < best:
			best = d
			nearest = i
	return PALETTE[(nearest + 1) % PALETTE.size()]


func _step_colour() -> void:
	var picked: int = surface.picked_track
	if picked > 0 and DAW.state.tracks.has(picked):
		DAW.set_track_colour(picked, next_colour(DAW.state.track(picked).colour))


## The input after the picked track's, round through none chosen.
func _next_input() -> String:
	var ids: Array = DAW.state.inputs.map(func(p): return p[0])
	ids.append("")
	var at := ids.find(DAW.state.input_of(surface.picked_track))
	return ids[(at + 1) % ids.size()]


func _step_input() -> void:
	var picked: int = surface.picked_track
	if picked > 0 and DAW.state.tracks.has(picked):
		DAW.set_track_input(picked, _next_input())


func _add() -> void:
	var picked: int = surface.picked_track
	var at: int = picked + 1 if picked > 0 else DAW.state.track_indices().size() + 1
	DAW.add_track(at, "")
	surface.pick_track(at)


func _remove() -> void:
	var picked: int = surface.picked_track
	if picked > 0 and DAW.state.tracks.has(picked):
		DAW.remove_track(picked)
		surface.pick_track(0)


func _rename() -> void:
	if surface.picked_track > 0:
		surface.ask_track_name(surface.picked_track)


func _name_of(index: int) -> String:
	return DAW.state.track(index).display_name() if DAW.state.tracks.has(index) else "track %d" % index


func _key(key_name: String, caption: String, slot: int, colour: Color, title: String,
		act: Callable, what: Callable) -> PanelButton:
	var key := PanelButton.new()
	key.name = key_name
	key.led_colour = colour
	key.lamp_scale = Vector2(0.8, 0.5)
	key.scale = Vector3(1.4, 1.4, 1.4)
	key.position = Vector3(slot * PITCH, 0.0, 0.003)
	key.pressed.connect(act)
	key.describe_title = func() -> String: return title
	key.describe_value = func(_v: float) -> String: return what.call()
	add_child(key)
	var l: Label3D = surface._text(caption, 22, CAPTION)
	l.position = Vector3(slot * PITCH, -0.015, 0.0016)
	add_child(l)
	return key
