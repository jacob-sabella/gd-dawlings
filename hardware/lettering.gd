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


## Stop drawing this label once nobody could read it anyway.
##
## Idempotent and safe to call on a label of any size: a bigger label simply gets a longer
## range. Call it after font_size and pixel_size are set, because it reads both.
static func range_to_legibility(label: Label3D) -> void:
	var readable := legible_to(label)
	# `end` is where it has finished fading, so it sits beyond `readable` by the margin -- the
	# label is fully opaque for the entire distance it was legible at.
	label.visibility_range_end = readable * (1.0 + FADE_MARGIN)
	label.visibility_range_end_margin = readable * FADE_MARGIN
	label.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
