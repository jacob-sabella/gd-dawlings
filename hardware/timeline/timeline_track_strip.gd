class_name TimelineTrackStrip
extends Node3D

## Tracks added, removed and named, under the timeline's right-hand end: ADD puts a new track
## after the picked one (or at the end), DEL removes the picked one, NAME renames it. A track is
## picked by pressing its name. Removing is one undo away, like every edit.

const PITCH := 0.028
const CAPTION := Color(0.62, 0.64, 0.68)

## The TimelineSurface. Typed loosely so the files load in any order.
var surface: Node

var add: PanelButton
var remove: PanelButton
var rename: PanelButton


func _ready() -> void:
	var plate := MeshInstance3D.new()
	plate.name = "Plate"
	var box := BoxMesh.new()
	box.size = Vector3(3 * PITCH + 0.008, 0.036, 0.004)
	plate.mesh = box
	plate.material_override = Materials.chassis()
	plate.position = Vector3(PITCH, -0.004, -0.002)
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
				return "type a name for %s" % _name_of(picked) if surface.can_type() else "rename it on the screen")
	refresh()


func refresh() -> void:
	add.lit = true
	var picked: bool = surface.picked_track > 0 and DAW.state.tracks.has(surface.picked_track)
	remove.lit = picked
	rename.lit = picked and surface.can_type()


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
	if surface.picked_track > 0 and surface.can_type():
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
