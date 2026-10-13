class_name TrackColours
extends RefCounted

## The colour a track is SHOWN in: its own colour, read in the venue's palette.
##
## A track's colour is project data -- set in Reaper, or stepped with the timeline's COLR key
## through `STANDARD` -- and is never rewritten here. What changes with the venue is how it is
## drawn: every venue has twelve colours of its own in STANDARD's order (red, orange, yellow,
## lime, green, teal, sky, blue, violet, magenta, pink, neutral), and a track is shown in the
## venue's counterpart of the STANDARD colour nearest its own. So the kick that is red stays the
## red one everywhere -- the cabin's brick, the grid's laser red, the dome's coral -- and two
## tracks that differ keep differing. A track nobody has coloured is not left grey: it is given
## a colour by its number, so every track is told apart at a glance on every piece of gear.
##
## The studio's palette is STANDARD itself, and there a coloured track is shown exactly as it is.

## Twelve colours round the wheel, readable on the dark desk: the COLR key's steps.
const STANDARD: Array[Color] = [
	Color(0.86, 0.32, 0.30), Color(0.92, 0.52, 0.25), Color(0.93, 0.76, 0.28), Color(0.70, 0.82, 0.30),
	Color(0.38, 0.75, 0.40), Color(0.28, 0.72, 0.62), Color(0.30, 0.68, 0.86), Color(0.36, 0.50, 0.90),
	Color(0.58, 0.44, 0.88), Color(0.80, 0.42, 0.80), Color(0.90, 0.42, 0.60), Color(0.62, 0.64, 0.66),
]
## The order uncoloured tracks are given colours in: round the wheel in big steps, so neighbours
## differ, and never the neutral.
const FOR_UNCOLOURED: Array[int] = [0, 6, 2, 8, 4, 10, 1, 7, 3, 9, 5]
## What a track is before anyone colours it (MixState.TrackState.colour's default).
const UNSET := Color(0.55, 0.57, 0.6)

## The venue's twelve, in STANDARD's order; empty for STANDARD itself.
static var _palette: Array = []


## Read every track in `palette` from now on (empty: the studio's own). Whoever calls this
## rebuilds what shows tracks, since what is built has the old colours in it.
static func use(palette: Array) -> void:
	_palette = palette if palette.size() == STANDARD.size() else []


static func palette() -> Array:
	return _palette if not _palette.is_empty() else STANDARD


## How a track whose colour is `colour` and whose number is `index` is shown.
static func shown(colour: Color, index: int) -> Color:
	if colour.is_equal_approx(UNSET):
		return palette()[FOR_UNCOLOURED[posmod(index - 1, FOR_UNCOLOURED.size())]]
	if _palette.is_empty():
		return colour
	return _palette[nearest(colour)]


## Which of STANDARD `colour` is nearest.
static func nearest(colour: Color) -> int:
	var best := 0
	var best_d := INF
	for i in STANDARD.size():
		var s := STANDARD[i]
		var d := Vector3(colour.r - s.r, colour.g - s.g, colour.b - s.b).length_squared()
		if d < best_d:
			best_d = d
			best = i
	return best
