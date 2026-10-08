class_name Lettering
extends Object

## When a piece of lettering is too small to read, and what to do about it.
##
## Measured, because this is the studio's single largest drawing cost and it was not obvious.
## An ablation -- hide every Label3D, re-read the counters -- put the 517 labels in a 90-track
## session at **735 of 2,492 draw calls and 0.70ms of a 1.82ms frame**. Roughly 30% of the
## drawing and nearly 40% of the time, for text.
##
## They are also the one thing a MultiMesh cannot help with. Every Label3D carries its own glyph
## texture, which makes it its own material, and the renderer batches by material -- so a label
## is an unbatchable draw call by construction (see docs/architecture.md for the microbenchmark
## that established this).
##
## WHAT IS ACTUALLY BEING TRADED
##
## Nothing, at the distances anyone reads at. A console strip's name is a 10mm cap, which on a
## 850px viewport at 75 degrees subtends about 5.6/d pixels: under five pixels by the time you
## are 1.2m away, and already unreadable in a screenshot taken there. The cost, meanwhile, only
## arrives when you stand BACK -- which is exactly when the text stopped saying anything. So
## the rule is to stop drawing lettering once it is reliably sub-legible, and the saving lands
## precisely in the case that was expensive.
##
## This is done with GeometryInstance3D's own visibility range, so the culling happens on the
## rendering server with no per-frame script, and it is per-camera -- which is what makes it
## correct in a headset, where two eyes and a moving head decide independently.

## Whose eyes this is being decided for.
##
## It used to be a constant -- 0.0054 radians, three pixels of capital on a 850px viewport --
## and the constant was not wrong so much as unmarked. It is a true statement about one reader.
## Treating it as a property of TEXT rather than of a PERSON is what made every label in the
## project silently assume the same eyesight, and it is the smallest, clearest instance of the
## thing wrong with the whole layout: there is no average body to build for.
##
## Static, and not injected into every call, for a boring reason that is worth stating: a
## visibility range is set once when a label is built and then enforced by the rendering
## server per camera, so there is no per-frame hook to pass a profile through. Changing the
## profile therefore needs the labels rebuilt, which `Lettering.reader_changed` asks for.
## Kept as a name because the lettering code reads better for it, but the storage is
## Ergonomics.current -- there is one reader, not one per subsystem.
static var reader: Ergonomics:
	get: return Ergonomics.current
	set(value): Ergonomics.current = value

## Kept as the default a fresh Ergonomics carries, so the old behaviour is still named.
const DEFAULT_MIN_CAP_ANGLE := 0.0054

## Fades out over the 35% beyond the legibility distance rather than popping. The label is at
## full opacity for the whole range it can be read in; the fade happens entirely inside the
## region where it could not be.
const FADE_MARGIN := 0.35


## How tall this label's capitals are, in metres. pixel_size x font_size, which is the whole of
## how Label3D sizes itself.
static func cap_height(label: Label3D) -> float:
	return label.pixel_size * float(label.font_size)


## How far away this label can still be read.
static func legible_to(label: Label3D) -> float:
	return reader.legible_to(cap_height(label))


# --- the face ----------------------------------------------------------------------------------
#
# Measured before this existed, at 1600x900 with each surface focused: rack knob captions came
# out at a median of 6.3 px from the top of an ascender to the bottom of a descender, which puts
# the capitals at about 4.5 px; strip names at 8.8; the dB under a fader at 8.4. Comfortable
# reading on a monitor starts around 12. Two causes on top of the size, and they are the reason
# making everything bigger was not the first fix:
#
# - No typeface was shipped, so every label was Godot's fallback rasterised once at its font
#   size -- 36 to 96 px -- and then shrunk on the GPU to six. Thin strokes at that ratio either
#   vanish or smear into the panel behind them. The bundled face is rendered from a
#   multichannel distance field instead, which is resolved per screen pixel: an edge is as
#   sharp at six pixels as at sixty, and an outline costs nothing.
# - Captions were tinted 0.58 to 0.66 grey on panels that are themselves dark grey under a warm
#   practical, which is a contrast ratio for decoration, not for reading.

const FACE_PATH := "res://assets/fonts/NotoSans-Bold.ttf"
## Distance range of the field, in texels. Wider means a thicker outline can be drawn from it;
## Godot wants it at least twice the widest outline used.
const FIELD_RANGE := 14
## Outline as a fraction of the font size. A hairline of dark round every glyph, which is what
## keeps light lettering readable where a lamp lifts the panel behind it to nearly its colour.
const OUTLINE_FRACTION := 0.11
const OUTLINE_COLOUR := Color(0.02, 0.02, 0.03, 0.75)
## The darkest a light caption may be. Hierarchy survives -- a secondary caption is still dimmer
## than a name -- but nothing on a panel is allowed to sit at the panel's own value.
const FLOOR_VALUE := 0.80

static var _face: FontFile


static func face() -> FontFile:
	if _face == null:
		var base := load(FACE_PATH) as FontFile
		if base == null:
			return null
		_face = base.duplicate() as FontFile
		_face.multichannel_signed_distance_field = true
		_face.msdf_pixel_range = FIELD_RANGE
		_face.msdf_size = 48
		_face.generate_mipmaps = false
	return _face


## Typeface, outline and contrast, for any label. Part of `range_to_legibility` because that is
## already the one call every label in the project makes once its size is set, so nothing can
## be built without it.
static func dress(label: Label3D) -> void:
	var f := face()
	if f != null:
		label.font = f
	label.outline_size = maxi(2, roundi(label.font_size * OUTLINE_FRACTION))
	label.outline_modulate = OUTLINE_COLOUR
	# Linear without mipmaps: a distance field is not a picture, and averaging it into mips
	# moves the edge. The field's own screen-space smoothing does the job mips were doing.
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	var c := label.modulate
	if c.v > 0.4:
		# Lifted along a curve rather than clamped, so two captions that were different greys
		# are still different greys afterwards.
		c.v = FLOOR_VALUE + (1.0 - FLOOR_VALUE) * clampf((c.v - 0.5) / 0.45, 0.0, 1.0)
		label.modulate = c


## The largest size from `largest` down at which this label's text fits `width` metres.
##
## Lettering on a panel has a slot, and text that runs past it lands on the next strip's name.
## Shrinking only the labels that would overflow keeps every short name at full size, rather
## than sizing all of them for the longest name in the session.
##
## From `largest` rather than from the current size, so a label refitted after its text changes
## grows back when a long name is replaced by a short one. Wrapped labels are measured by their
## longest WORD, because that is what a wrap cannot break.
static func fit(label: Label3D, width: float, largest: int, smallest: int = 16) -> void:
	var f := label.font if label.font != null else face()
	if f == null or width <= 0.0:
		return
	var pieces := PackedStringArray([label.text])
	if label.autowrap_mode != TextServer.AUTOWRAP_OFF:
		pieces = label.text.split(" ", false)
	var size := largest
	while size > smallest and _widest(f, pieces, size) * label.pixel_size > width:
		size -= 2
	label.font_size = size
	label.outline_size = maxi(2, roundi(size * OUTLINE_FRACTION))


static func _widest(f: Font, pieces: PackedStringArray, size: int) -> float:
	var most := 0.0
	for piece in pieces:
		most = maxf(most, f.get_string_size(piece, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	return most


## Stop drawing this label once nobody could read it anyway.
##
## Idempotent and safe to call on a label of any size: a bigger label simply gets a longer
## range. Call it after font_size and pixel_size are set, because it reads both.
static func range_to_legibility(label: Label3D) -> void:
	dress(label)
	var readable := legible_to(label)
	# `end` is where it has finished fading, so it sits beyond `readable` by the margin -- the
	# label is fully opaque for the entire distance it was legible at.
	label.visibility_range_end = readable * (1.0 + FADE_MARGIN)
	label.visibility_range_end_margin = readable * FADE_MARGIN
	label.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
