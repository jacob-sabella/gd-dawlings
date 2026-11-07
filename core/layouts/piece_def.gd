class_name PieceDef
extends RefCounted

## What a piece is, apart from where a layout stands it (docs/layouts.md 4.1): its kind, its floor
## footprint, how heavy it is to push, what it is taken hold of by, what it cannot stand without, and
## what rides with it when it moves (its followers). The five wheeled pieces of the live room are
## defined here, once; the numbers are the classes' own constants (`CassetteRack.FOOT`, `Hoop.BASE_HALF`,
## ...), never copied, so a piece drawn bigger is a bigger footprint with no second edit. This is the
## code side of a piece definition; the data side (a `piece` mod entry, `PieceBuilders`) comes with
## the rest of step 6, and reads the same fields.
##
## Used by `PieceHost` (builds each piece's trolley and carries its followers), `PieceFeet` (the
## validator's footprints) and `LayoutValidator`.

## The two kinds of piece (docs/layouts.md 4.3). Only `SINGLE` is defined here; the modular room is
## `PieceFeet.ANNEX` until its definition moves in.
enum Kind { SINGLE, ROOM_SCALE }

## What may ride with a piece (`followers`), each run by `PieceHost.carry` after the piece itself has
## moved: the venue's items rehomed on the shelf and hoop (`ITEMS`), the dart boards that hang on the
## shelf's posts (`BOARDS`), the hoops' baskets (`HOOPS`), the rack's slots and the made items' homes
## (`HOLD_RACK`, only while this piece is the rack) and the same when a shelf stands with no rack
## (`HOLD_RACK_IF_GONE`: a cassette then lies on the shelf), and what the Tour case spilled (`SPILLS`).
const ITEMS := &"items"
const BOARDS := &"boards"
const HOOPS := &"hoops"
const HOLD_RACK := &"hold_rack"
const HOLD_RACK_IF_GONE := &"hold_rack_if_gone"
const SPILLS := &"spills"

## The id (`Venue.default_spot`, `Studio.live_pieces`) and what the player sees.
var id: StringName
var kind := Kind.SINGLE
## Name of the studio's trolley node.
var trolley_name := ""
## The footprint in the piece's own frame: centre and half extents (from its `Stations` row or its own
## class's solid), and the height of its highest solid.
var foot_centre := Vector2.ZERO
var foot_half := Vector2.ZERO
var top := 0.0
## How heavy it is to push (Trolley.follow).
var weight := 9.0
## Boxes `[size, centre]` of its own lowest structure -- a plinth, feet, a base, a pole -- to take it
## by, under whatever on it is played or picked up. Nothing is drawn: the piece draws its own.
var grips: Array = []
## Where a walker bumps it, when that is less than the footprint (the hoop: its base is a step
## underfoot, its pole is what a person walks into); `Vector2.ZERO` half extents mean "the footprint".
var body_centre := Vector2.ZERO
var body_half := Vector2.ZERO
## Zone ids the venue must have for the piece to stand at all (`default_spot` is null without one).
var needs: Array[StringName] = []
## Which of the studio's nodes (a variable) or the venue's children is the piece itself, and the frame
## its `Venue.<id>_spot()` is read in before it is set on it.
var studio_node := &""
var venue_child := ""
var node_in_set := false
## What rides with it (the constants above), in the order they run.
var followers: Array[StringName] = []


## The definition of wheeled piece `piece`, or null for one that is not defined.
static func of(piece: StringName) -> PieceDef:
	return _table().get(piece)


## True for a piece with a definition.
static func has(piece: StringName) -> bool:
	return _table().has(piece)


## Every defined id, in the order the studio builds their trolleys (the same order as `LiveRoom.wheeled_ids`).
static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k: StringName in _table():
		out.append(k)
	return out


static var _defs := {}


static func _table() -> Dictionary:
	if _defs.is_empty():
		_defs = _build()
	return _defs


static func _define(piece: StringName, trolley: String, half: Vector2, height: float, weight: float, grips: Array) -> PieceDef:
	var d := PieceDef.new()
	d.id = piece
	d.trolley_name = trolley
	d.foot_half = half
	d.top = height
	d.weight = weight
	d.grips = grips
	return d


static func _build() -> Dictionary:
	var out := {}
	var rack := _define(&"cassette_rack", "CassetteRackTrolley", CassetteRack.FOOT, CassetteRack.TOP, 9.0,
			[[Vector3(CassetteRack.FOOT.x * 2.0, 0.15, CassetteRack.FOOT.y * 2.0), Vector3(0, 0.075, 0)]])
	rack.studio_node = &"cassette_rack"
	rack.followers = [HOLD_RACK]
	out[rack.id] = rack

	var sampler := _define(&"sampler", "SamplerTrolley", Sampler.FOOT, Sampler.TOP, 9.0,
			[[Vector3(Sampler.FOOT.x * 2.0, 0.15, Sampler.FOOT.y * 2.0), Vector3(0, 0.075, 0)]])
	sampler.studio_node = &"sampler"
	sampler.needs = [&"synth"]
	out[sampler.id] = sampler

	# The case's bottom edge, a little proud of it: above that a click on the case knocks on it.
	var tour := _define(&"tour_case", "TourCaseTrolley", Vector2(TourCase.CASE_WIDTH, TourCase.CASE_DEPTH) * 0.5,
			TourCase.BODY_H + TourCase.LID_H, 7.5,
			[[Vector3(TourCase.CASE_WIDTH + 0.08, 0.1, TourCase.CASE_DEPTH + 0.08), Vector3(0, 0.05, 0)]])
	tour.studio_node = &"tour_case"
	tour.node_in_set = true
	tour.followers = [SPILLS]
	out[tour.id] = tour

	# Its legs, under the lower tier the tablet and the percussion lie on.
	var shelf := _define(&"prop_shelf", "PropShelfTrolley", Vector2(ZoneKit.SHELF.x, ZoneKit.SHELF.z) * 0.5,
			ZoneKit.SHELF.y, 8.0, [[Vector3(ZoneKit.SHELF.x, 0.18, ZoneKit.SHELF.z), Vector3(0, 0.09, 0)]])
	shelf.venue_child = "PropShelf"
	shelf.followers = [BOARDS, ITEMS, HOLD_RACK_IF_GONE]
	out[shelf.id] = shelf

	# The base in front of the pole: the board overhangs the rest of it, which reaches back under the
	# wall's skirting where the venue stands it, and would have the hoop shoved off the wall. The pole
	# first among the grips, up to under the board: from across the room it is what shows over whatever
	# stands between, and what a hand reaches for.
	var hoop := _define(&"hoop", "HoopTrolley",
			Vector2(Hoop.BASE_HALF.x, (Hoop.BASE_Z + Hoop.BASE_HALF.y - Hoop.POLE_Z + 0.03) * 0.5),
			maxf(Hoop.BASE_TOP, Hoop.POLE_TOP), 10.0,
			[[Vector3(0.07, 1.75, 0.07), Vector3(0, 0.975, Hoop.POLE_Z)],
			[Vector3(Hoop.BASE_HALF.x * 2.0, 0.1, Hoop.BASE_HALF.y * 2.0), Vector3(0, 0.05, Hoop.BASE_Z)]])
	hoop.foot_centre = Vector2(0, (Hoop.POLE_Z - 0.03 + Hoop.BASE_Z + Hoop.BASE_HALF.y) * 0.5)
	hoop.body_centre = Vector2(0, Hoop.POLE_Z)
	hoop.body_half = Vector2.ONE * Hoop.POLE_RADIUS
	hoop.venue_child = "Hoop"
	hoop.followers = [HOOPS, ITEMS]
	out[hoop.id] = hoop
	return out
