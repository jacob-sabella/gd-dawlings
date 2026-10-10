class_name TimelineRenderStrip
extends Node3D

## Writing the song out, under the timeline: MIX renders the mix to a WAV beside the project,
## STEMS the mix and every track's own. The loop range while the song loops, else all of it, in
## real time: the song plays through once while it is written, and its effects ring out after
## (see DAWBackend.render). Dark where the
## DAW cannot render, and while a render runs.

const PITCH := 0.028
const CAPTION := Color(0.62, 0.64, 0.68)

## The TimelineSurface. Typed loosely so the files load in any order.
var surface: Node

var mix: PanelButton
var stems: PanelButton
## Between asking for a render and hearing it is done.
var busy := false


func _ready() -> void:
	var plate := MeshInstance3D.new()
	plate.name = "Plate"
	var box := BoxMesh.new()
	box.size = Vector3(2 * PITCH + 0.008, 0.036, 0.004)
	plate.mesh = box
	plate.material_override = Materials.chassis()
	plate.position = Vector3(0.5 * PITCH, -0.004, -0.002)
	add_child(plate)
	mix = _key("RenderMix", "MIX", 0, Color(0.95, 0.75, 0.35), "RENDER  MIX", _render.bind(false))
	stems = _key("RenderStems", "STEMS", 1, Color(0.95, 0.75, 0.35), "RENDER  STEMS", _render.bind(true))
	DAW.render_finished.connect(_on_rendered)
	DAW.connection_changed.connect(refresh)
	refresh()


func refresh() -> void:
	var can := DAW.can(DAWBackend.Capability.RENDER) and not busy
	mix.lit = can
	stems.lit = can


## What a render would write, for the hover card.
func _what(with_stems: bool) -> String:
	if not DAW.can(DAWBackend.Capability.RENDER):
		return "this DAW cannot render from here"
	if busy:
		return "rendering, as the song plays"
	var s := DAW.state
	var looped := s.looping and s.loop_end - s.loop_start > 0.01
	var span := "the loop, %s to %s" % [s.bar_beat(s.loop_start), s.bar_beat(s.loop_end)] if looped \
			else "the whole song, %s" % TimelineRuler._clock(s.timeline_length())
	return "%s%s, played through once and rung out" % [span, " and each track's stem" if with_stems else ""]


func _render(with_stems: bool) -> void:
	if not DAW.can(DAWBackend.Capability.RENDER) or busy:
		return
	busy = true
	refresh()
	DAW.render(with_stems)


func _on_rendered(_files: PackedStringArray, _problems: PackedStringArray) -> void:
	busy = false
	refresh()


func _key(key_name: String, caption: String, slot: int, colour: Color, title: String,
		act: Callable) -> PanelButton:
	var key := PanelButton.new()
	key.name = key_name
	key.led_colour = colour
	key.lamp_scale = Vector2(0.8, 0.5)
	key.scale = Vector3(1.4, 1.4, 1.4)
	key.position = Vector3(slot * PITCH, 0.0, 0.003)
	key.pressed.connect(act)
	key.describe_title = func() -> String: return title
	key.describe_value = func(_v: float) -> String: return _what(slot == 1)
	add_child(key)
	var l: Label3D = surface._text(caption, 22, CAPTION)
	l.position = Vector3(slot * PITCH, -0.015, 0.0016)
	add_child(l)
	return key
