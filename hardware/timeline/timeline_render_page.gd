class_name TimelineRenderPage
extends TimelinePage

## Writing the song out, on the deck's RENDER page: MIX renders the mix to a WAV beside the
## project, STEMS the mix and every track's own. The loop range while the song loops, else all of
## it, in real time: the song plays through once while it is written, and its effects ring out
## after (see DAWBackend.render). Dark where the DAW cannot render, and while a render runs.

const INK := Color(0.95, 0.75, 0.35)

var mix: GlyphKey
var stems: GlyphKey
## The files' depth, stepped round DAW.RENDER_BITS: each person's own, sent with their render.
var depth: GlyphKey
var bits := DAW.RENDER_BITS_DEFAULT
## The files' sample rate, stepped round DAW.RENDER_RATES: each person's own, sent with their render.
var rate_key: GlyphKey
var rate := DAW.RENDER_RATE_DEFAULT
## Normalised to a peak (DAWBackend.RENDER_NORMALISE_DB), the stems by the mix's gain: each
## person's own, sent with their render.
var normalise_key: GlyphKey
var normalise := false
## Between asking for a render and hearing it is done.
var busy := false


func _ready() -> void:
	tab_name = "RENDER"
	tab_glyph = &"render"
	mix = _key("RenderMix", &"render_mix", INK, "RENDER  MIX", _render.bind(false),
			func() -> String: return _what(false))
	stems = _key("RenderStems", &"render_stems", INK, "RENDER  STEMS", _render.bind(true),
			func() -> String: return _what(true))
	_group()
	depth = _key("RenderDepth", depth_glyph(bits), INK, "RENDER  BIT DEPTH", step_depth,
			func() -> String: return "%s: %s next" % [depth_name(bits), depth_name(_next_depth(bits))])
	depth.lit = true
	rate_key = _key("RenderRate", rate_glyph(rate), INK, "RENDER  SAMPLE RATE", step_rate,
			func() -> String: return "%s: %s next" % [rate_name(rate), rate_name(_next_rate(rate))])
	rate_key.lit = true
	normalise_key = _key("RenderNormalise", &"normalise", INK, "RENDER  NORMALISE",
			func(): set_normalise(not normalise),
			func() -> String: return ("on: the mix peaks at %d dB, each stem moved by the mix's gain"
					% int(DAWBackend.RENDER_NORMALISE_DB)) if normalise else "off: as loud as it plays")
	normalise_key.toggle = true
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
	return "%s%s, played through once and rung out, %s" % [_span(),
			" and each track's stem" if with_stems else "", depth_name(bits) + (", %s" % rate_name(rate))] \
			+ (", normalised to %d dB" % int(DAWBackend.RENDER_NORMALISE_DB) if normalise else "")


func set_normalise(on: bool) -> void:
	normalise = on
	normalise_key.lit = on


func step_rate() -> void:
	rate = _next_rate(rate)
	rate_key.glyph = rate_glyph(rate)


static func _next_rate(r: int) -> int:
	var at := DAW.RENDER_RATES.find(r)
	return DAW.RENDER_RATES[(at + 1) % DAW.RENDER_RATES.size()]


static func rate_name(r: int) -> String:
	return "%s kHz" % String.num(r / 1000.0, 1)


static func rate_glyph(r: int) -> StringName:
	match r:
		44100: return &"rate_44"
		96000: return &"rate_96"
	return &"rate_48"


func step_depth() -> void:
	bits = _next_depth(bits)
	depth.glyph = depth_glyph(bits)


static func _next_depth(b: int) -> int:
	var at := DAW.RENDER_BITS.find(b)
	return DAW.RENDER_BITS[(at + 1) % DAW.RENDER_BITS.size()]


static func depth_name(b: int) -> String:
	return "32-bit float WAV" if b == 32 else "%d-bit WAV, dithered" % b


## A wave drawn in steps: coarse for 16, fine for 24, smooth for 32-bit float.
static func depth_glyph(b: int) -> StringName:
	match b:
		16: return &"depth_16"
		32: return &"depth_32"
	return &"depth_24"


func _render(with_stems: bool) -> void:
	if not DAW.can(DAWBackend.Capability.RENDER) or busy:
		return
	busy = true
	refresh()
	DAW.render(with_stems, bits, normalise, rate)


func _on_rendered(_files: PackedStringArray, _problems: PackedStringArray) -> void:
	busy = false
	refresh()
