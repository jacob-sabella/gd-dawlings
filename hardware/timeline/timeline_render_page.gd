class_name TimelineRenderPage
extends TimelinePage

## Writing the song out, on the deck's RENDER page: MIX renders the mix to a WAV beside the
## project, STEMS the mix and every track's own. The loop range while the song loops, else all of
## it, in real time: the song plays through once while it is written, and its effects ring out
## after (see DAWBackend.render). Dark where the DAW cannot render, and while a render runs.

const INK := Color(0.95, 0.75, 0.35)

var mix: GlyphKey
var stems: GlyphKey
## Between asking for a render and hearing it is done.
var busy := false


func _ready() -> void:
	tab_name = "RENDER"
	tab_glyph = &"render"
	mix = _key("RenderMix", &"render_mix", INK, "RENDER  MIX", _render.bind(false),
			func() -> String: return _what(false))
	stems = _key("RenderStems", &"render_stems", INK, "RENDER  STEMS", _render.bind(true),
			func() -> String: return _what(true))
	DAW.render_finished.connect(_on_rendered)
	DAW.connection_changed.connect(refresh)
	DAW.transport_changed.connect(refresh)
	refresh()


func refresh() -> void:
	var can := DAW.can(DAWBackend.Capability.RENDER) and not busy
	mix.lit = can
	stems.lit = can
	if not DAW.can(DAWBackend.Capability.RENDER):
		notice = "this DAW cannot render from here"
	elif busy:
		notice = "rendering, as the song plays"
	else:
		notice = _span()


func _span() -> String:
	var s := DAW.state
	var looped := s.looping and s.loop_end - s.loop_start > 0.01
	return "the loop, %s to %s" % [s.bar_beat(s.loop_start), s.bar_beat(s.loop_end)] if looped \
			else "the whole song, %s" % TimelineRuler._clock(s.timeline_length())


## What a render would write, for the hover card.
func _what(with_stems: bool) -> String:
	if not DAW.can(DAWBackend.Capability.RENDER):
		return "this DAW cannot render from here"
	if busy:
		return "rendering, as the song plays"
	return "%s%s, played through once and rung out" % [_span(), " and each track's stem" if with_stems else ""]


func _render(with_stems: bool) -> void:
	if not DAW.can(DAWBackend.Capability.RENDER) or busy:
		return
	busy = true
	refresh()
	DAW.render(with_stems)


func _on_rendered(_files: PackedStringArray, _problems: PackedStringArray) -> void:
	busy = false
	refresh()
