class_name SessionLayout
extends RefCounted

## Where the room's furniture stands, worked out from how big the session is.
##
## The default room was laid out round a thirteen-track desk: 92cm of console with the rack just
## off its left end and the tape trolley just off its right. The desk is not that size. It is as
## wide as the bank it shows, so a forty-track session builds 2.5 metres of console straight
## through the rack and the deck, and a sixty-four-track one builds four metres of it in a room
## that was six wide. Furniture that does not move out of the way of the desk is not furniture,
## and a room that does not get bigger when the desk does is a cupboard.
##
## So the desk is the measurement and everything else follows from it: the rack and the deck
## stand a walkway's width off its ends, the walls stand back from THEM, and the lamps keep their
## place relative to the walls. The rule is one function of one number, which keeps it testable
## and makes it the same answer for every participant without anything having to be sent.

## The room as it was authored, and the smallest it gets.
const BASE_WIDTH := Studio.ROOM_WIDTH
## Rooms grow in whole steps, so one more track does not move every wall by a centimetre and
## rebuild the venue on each.
const WIDTH_STEP := 0.8
## From the end of the desk to the middle of the piece beside it, as authored round the small
## desk: the rack a walkway off the left end, the deck tucked in close on the right where the
## transport is reached from the chair.
## Spread with the room (2026-10-28): the rack is played from the seat but stands well clear of
## the desk's end, and the deck's cart, whose transport is reached from the chair, stands its 0.6 m
## of clearance off it.
const RACK_GAP := 0.95
const DECK_GAP := 0.51
## Between that gear and the wall behind it.
const WALL_CLEARANCE := 1.2

## Half the width of the rack's and the deck's footprint, for the clearance from the wall.
const RACK_HALF := 0.30
const DECK_HALF := 0.28
## The patch stand, along the right-hand wall behind the deck: a walkway clear of it.
const PATCH_GAP := 1.3


## `desk_half`: half the console's width on the floor, in metres. Returns room_width, and for each
## piece that has to make room for the desk, where it stands: {"rack": [Vector2, degrees], ...}.
## The spots for a thirteen-track desk, which this must reproduce, are the control-room fragment's
## (`ControlRoom.fit_of`: the `fit` of the rack and the deck, the authored place of the patch stand);
## the rule here is the gaps, the halves and the clearance only.
static func fit(desk_half: float) -> Dictionary:
	var rack: Dictionary = ControlRoom.fit_of(&"rack")
	var deck: Dictionary = ControlRoom.fit_of(&"deck_trolley")
	var patch: Dictionary = ControlRoom.fit_of(&"patch_stand")
	# Never closer in than authored: a desk smaller than the default leaves the room as it was.
	var rack_x := minf(rack["at"].x, -(desk_half + RACK_GAP))
	var deck_x := maxf(deck["at"].x, desk_half + DECK_GAP)
	var patch_x := maxf(patch["at"].x, deck_x + PATCH_GAP)
	var reach := maxf(-rack_x + RACK_HALF, maxf(deck_x + DECK_HALF, patch_x + 0.2)) + WALL_CLEARANCE
	var width := BASE_WIDTH
	if reach * 2.0 > BASE_WIDTH:
		width = BASE_WIDTH + ceilf((reach * 2.0 - BASE_WIDTH) / WIDTH_STEP) * WIDTH_STEP
	return {
		"room_width": width,
		"rack": [Vector2(rack_x, rack["at"].y), rad_to_deg(rack["yaw"])],
		"deck_trolley": [Vector2(deck_x, deck["at"].y), rad_to_deg(deck["yaw"])],
		"patch_stand": [Vector2(patch_x, patch["at"].y), rad_to_deg(patch["yaw"])],
	}


## A point authored for the base room, kept the same distance from the nearest side wall in a
## room `width` wide. Lamps in the corners stay in the corners; something in the middle stays put.
static func widen(at: Vector2, width: float) -> Vector2:
	var grow := (width - BASE_WIDTH) * 0.5
	if absf(at.x) < 1.0:
		return at
	return Vector2(at.x + signf(at.x) * grow, at.y)
