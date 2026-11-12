class_name SingerStyle
extends RefCounted

## How the singer's words look in each venue (the booth's prompter and desk, the lyric board, the creature's perch):
## the venue's own colours (its mood, RackMood) and a character of its own: the club's and the grid's neon capitals
## spaced wide and glowing, the chalk zone's and the cabin's leaning hand, the stage's and the desert's heavy
## capitals, and so on (CHARACTER).
##
## Readability first, whatever the venue (`readable`): the words are always light on a dark panel at 7:1 or more
## (WCAG's AAA for text), the sung syllable and the dimmer lines at 4.5:1 or more; a colour that falls short is
## lifted toward white until it does not. A style never makes letters smaller, slants them past 0.15, spaces them
## past a few pixels or thins them, and the lyrics' lines and the status are never all capitals (long lines in
## capitals read slower); only keys and names take a venue's capitals. Every label keeps its dark outline.

const MIN_TEXT := 7.0
const MIN_ACCENT := 4.5
const MOST_SLANT := 0.15
const MOST_SPACING := 6
const MOST_BOLD := 0.8
const MOST_GLOW := 1.5
const MIN_LIT_SATURATION := 0.45

## Each venue's lettering beyond its colours: caps (keys and names in capitals), spacing (px between letters),
## slant (a lean, as a shear), bold (embolden), glow (how far the lit syllable and the lit keys glow, 1 none).
const CHARACTER := {
	&"studio": {"caps": false, "spacing": 0, "slant": 0.0, "bold": 0.0, "glow": 1.1},
	&"club": {"caps": true, "spacing": 4, "slant": 0.0, "bold": 0.2, "glow": 1.5},
	&"grid": {"caps": true, "spacing": 6, "slant": 0.0, "bold": 0.0, "glow": 1.5},
	&"station": {"caps": true, "spacing": 4, "slant": 0.0, "bold": 0.0, "glow": 1.3},
	&"chalk": {"caps": false, "spacing": 2, "slant": 0.12, "bold": 0.0, "glow": 1.0},
	&"cabin": {"caps": false, "spacing": 1, "slant": 0.14, "bold": 0.3, "glow": 1.0},
	&"garden": {"caps": false, "spacing": 1, "slant": 0.08, "bold": 0.0, "glow": 1.1},
	&"greenhouse": {"caps": false, "spacing": 1, "slant": 0.06, "bold": 0.0, "glow": 1.2},
	&"cave": {"caps": false, "spacing": 3, "slant": 0.0, "bold": 0.0, "glow": 1.5},
	&"dome": {"caps": true, "spacing": 5, "slant": 0.0, "bold": 0.0, "glow": 1.4},
	&"desert": {"caps": true, "spacing": 5, "slant": 0.0, "bold": 0.5, "glow": 1.1},
	&"stage": {"caps": true, "spacing": 2, "slant": 0.0, "bold": 0.6, "glow": 1.2},
	&"loft": {"caps": true, "spacing": 1, "slant": 0.0, "bold": 0.7, "glow": 1.0},
	&"rooftop": {"caps": false, "spacing": 2, "slant": 0.1, "bold": 0.0, "glow": 1.3},
}

static var _fonts := {}


## The style of venue `id`: {ink, dim, lit, panel, outline, caps, spacing, slant, bold, glow}, readable.
static func of(id: StringName) -> Dictionary:
	var mood := RackMood.palette(id)
	var base: Color = mood["base"]
	var hit: Color = mood["hit"]
	var c: Dictionary = CHARACTER.get(id, CHARACTER[&"studio"])
	var style := {
		"id": id,
		# the words: white, warmed by the venue's colour
		"ink": Color.WHITE.lerp(base, 0.22),
		# the next line and the status: the venue's colour, quieter
		"dim": base.lerp(Color(0.7, 0.7, 0.7), 0.35),
		# the syllable sung, and lit keys: the venue's flash
		"lit": hit if _hue_apart(hit, base) else base.lightened(0.25),
		# the panel behind: the venue's colour, almost black
		"panel": Color(base.r * 0.07, base.g * 0.07, base.b * 0.07, 0.86),
		"caps": c["caps"], "spacing": c["spacing"], "slant": c["slant"], "bold": c["bold"], "glow": c["glow"],
	}
	return readable(style)


## `style` made readable (see the class's rules): colours lifted until they stand off the panel, the shape held in.
static func readable(style: Dictionary) -> Dictionary:
	var s := style.duplicate()
	var panel: Color = s["panel"]
	panel.a = 1.0
	s["ink"] = lift(s["ink"], panel, MIN_TEXT)
	s["dim"] = lift(s["dim"], panel, MIN_ACCENT)
	# the sung words must stand apart from the rest by colour, not only by brightness: a pale venue colour (the
	# chalk zone's) is given its hue back (amber if it has none) before it is lifted
	var lit: Color = s["lit"]
	if lit.s < MIN_LIT_SATURATION:
		lit = Color.from_hsv(lit.h if lit.s > 0.05 else 0.09, 0.6, maxf(lit.v, 0.9))
	s["lit"] = lift(lit, panel, MIN_ACCENT)
	# small print (status, hints): between the ink and the venue's colour, held to the words' own 7:1, since thin
	# strokes at a small size lose more to their outline than a line's
	s["note"] = lift((s["ink"] as Color).lerp(s["dim"], 0.45), panel, MIN_TEXT)
	s["outline"] = Color(panel.r * 0.5, panel.g * 0.5, panel.b * 0.5, 1.0)
	s["slant"] = clampf(float(s["slant"]), 0.0, MOST_SLANT)
	s["spacing"] = clampi(int(s["spacing"]), 0, MOST_SPACING)
	s["bold"] = clampf(float(s["bold"]), 0.0, MOST_BOLD)
	s["glow"] = clampf(float(s["glow"]), 1.0, MOST_GLOW)
	return s


## `colour` lightened toward white until it stands `ratio` to 1 against `back`.
static func lift(colour: Color, back: Color, ratio: float) -> Color:
	var c := Color(colour.r, colour.g, colour.b, 1.0)
	for i in 40:
		if contrast(c, back) >= ratio:
			break
		c = c.lerp(Color.WHITE, 0.08)
	return c


## WCAG's contrast ratio of two colours (1 to 21).
static func contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _luminance(c: Color) -> float:
	var f := func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)


static func _hue_apart(a: Color, b: Color) -> bool:
	var d := absf(a.h - b.h)
	return minf(d, 1.0 - d) > 0.06 or absf(a.v - b.v) > 0.15


## A lit key's paint in `style`: the venue's lit colour, darkened until the key's legend (the ink) stands 7 to 1
## off it. The keys are drawn unshaded, so this is the colour seen.
static func key_paint(style: Dictionary) -> Color:
	var c: Color = style.get("lit", Color(1.0, 0.7, 0.3))
	# deep from the start: a venue's exposure lifts an unshaded key well past its value
	c = c.darkened(0.75)
	var ink: Color = style.get("ink", Color.WHITE)
	for i in 30:
		if contrast(ink, c) >= MIN_TEXT:
			break
		c = c.darkened(0.1)
	return Color(c.r, c.g, c.b, 1.0)


## The typeface for `style`: the shipped face (Lettering.face) leaned, spaced and weighted as the venue has it.
static func font(style: Dictionary) -> Font:
	var key := "%.2f/%d/%.2f" % [float(style["slant"]), int(style["spacing"]), float(style["bold"])]
	if _fonts.has(key):
		return _fonts[key]
	var base := Lettering.face()
	if base == null:
		return null
	var v := FontVariation.new()
	v.base_font = base
	v.variation_embolden = float(style["bold"])
	v.variation_transform = Transform2D(Vector2(1, 0), Vector2(float(style["slant"]), 1), Vector2.ZERO)
	v.spacing_glyph = int(style["spacing"])
	_fonts[key] = v
	return v


## Label `l` lettered in `style` as a `role`: "line" (a lyric line: never capitals), "lit" (the syllable sung),
## "dim" (the next line), "status", "key" (a key's legend or a name: the venue's capitals).
static func dress(l: Label3D, style: Dictionary, role: String) -> void:
	if l == null or style.is_empty():
		return
	var f := font(style)
	if f != null:
		l.font = f
	match role:
		"line":
			l.modulate = style["ink"]
		"lit":
			var c: Color = style["lit"]
			l.modulate = Color(c.r * style["glow"], c.g * style["glow"], c.b * style["glow"], 1.0)
		"dim":
			l.modulate = style["dim"]
		"status":
			l.modulate = style["note"]
		_:
			l.modulate = style["ink"]
	l.uppercase = bool(style["caps"]) and role == "key"
	l.outline_modulate = style["outline"]
	# an outline that edges the letters without eating them: thinner for small print
	l.outline_size = maxi(2, roundi(l.font_size * (0.035 if role == "status" else 0.06)))
