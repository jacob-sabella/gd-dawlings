class_name Venue
extends Node3D

## The world the studio stands in.
##
## Everything a person WORKS with -- the gear, the stands it rides on, the lamps, the looms, where
## each of them has been pushed -- belongs to the studio and is the same in every venue. A venue
## is everything else: the floor, what is past the edge of the floor, the sky if there is one,
## the air, and how all of it is lit. Swapping one is a change of scenery, never of setup, which
## is why it is safe to do mid-session and why it is one key.
##
## Saved in the layout on your own; in a session, the HOST'S, like everything else about the room
## (see Session.room). A guest is shown the host's venue and keeps its own for later.
##
## Every venue keeps the same working footprint (room_width x Studio.ROOM_DEPTH) because the
## furniture's floor plan is that rectangle. A venue with no walls marks it instead -- a lit
## border on the grid, a chalk outline in the chalk zone -- so the edge you will bump a rack
## into is never invisible.

## Registry, in cycling order; the first is the default. Read from the venue layout files' `order`
## (`VenueCatalogue`), so adding a venue is adding a file.
static var IDS: Array[StringName] = VenueCatalogue.ids()

## The Rig Roulette room's id. A place the band is taken to, not one of the venues (`IDS`).
const ROULETTE_ID := &"roulette"

## A venue can come in more than one arrangement -- the same place with its structure moved
## about: walls or none, a city close in or far off. A variant keeps the venue's footprint and
## its zones' contract; only what stands round them changes. Variant 0 is the venue as first
## built. Chosen by whoever's room it is, and carried with the venue (see Session.room). Their
## names are the layout file's `variants` (`variant_titles`).

## What people will do here besides mix, each with room of its own. Built later; every venue
## leaves the space for all of them now, so an activity made for one lands in every one.
const ZONE_IDS: Array[StringName] = [&"bricks", &"matrix", &"drums", &"vocals", &"synth"]

## Where they go, at the base room width: back of house, behind the mix position, so the gear's
## floor plan never moves for them. The live room is laid out in neighbourhoods (Neighbourhoods,
## docs/architecture.md "Room layout"), three columns either side of two walkways, each a cluster
## round a middle of its own: turn round from the desk and the rhythm section is straight ahead
## (the riser on the left of the middle, the lattice behind on the right, the venue's own
## instrument on the back wall between), tape and toys on the left with the vocal booth behind
## them, harmony round the bricks table on the right with synth and sound design
## behind. Each box is the activity's whole space -- clearance to walk round it included -- from
## the floor up to the height it needs.
##
## Spread out on 2026-10-28 ("EVERYTHING is way too cramped"): the room's pieces stood nose to
## tail along the back wall, 3 to 12 cm apart, and the modular and the
## lyric board could not be reached down a 0.9 m walkway.
const ZONES := {
	# A booth 3.4 x 3.1 m: a singer, a stand, the lyric board, room for a talk box, and a door
	# wide enough to walk through without turning sideways.
	&"vocals": AABB(Vector3(-8.7, 0.0, 9.2), Vector3(3.4, 2.6, 3.1)),
	# A riser for a full kit and the drummer's stool, 2.6 m square, at the front of the middle.
	&"drums": AABB(Vector3(-3.4, 0.0, 4.8), Vector3(2.6, 2.8, 2.6)),
	# The lattice, 3.4 m on every side: a 3 m cube of cells and room to reach in from any face.
	&"matrix": AABB(Vector3(0.0, 0.0, 8.6), Vector3(3.4, 3.4, 3.4)),
	# A 1 x 2 m table at waist height, long way back, with walking room all round.
	&"bricks": AABB(Vector3(6.8, 0.0, 4.6), Vector3(1.9, 1.3, 2.9)),
	# A keyboard stand 1.5 m wide against the right-hand wall, modules racked above it.
	&"synth": AABB(Vector3(7.9, 0.0, 10.0), Vector3(0.8, 2.0, 2.0)),
}
## The back-of-house space the zones stand in: from the control room's open rear (the
## footprint's far edge) back to here, and this far either side of centre at the base width.
## 8.4 x 17.6 m: a little over twice the floor it had (4.5 x 14.2).
const LIVE_ROOM_BACK := 12.4
const LIVE_ROOM_HALF := 8.8
## Tall enough for the lattice, a hand raised above it, and the neighbourhoods' banners over that.
const LIVE_ROOM_HEIGHT := 5.0
## The live room as every venue's dressing was first drawn round it, before the spread (half its
## width at the old base room, and its back wall). A venue whose scenery is placed by number scales
## it by the room's size over these, so it fills the bigger room rather than huddling in the old one.
const DRAWN_HALF := 7.1
const DRAWN_BACK := 7.3

## How wide the working footprint is. Set by the studio before the venue enters the tree; the
## room grows with the desk (see SessionLayout), and a venue drawn for the old width would put
## its walls through the rack.
var room_width := Studio.ROOM_WIDTH

## Which arrangement of this venue to build (`variant_titles`). Set by make(), before the venue enters
## the tree.
var variant := 0

## Set by the studio before the venue enters the tree: whether the full desktop renderer is
## running. A venue must look right without it -- a headset runs the mobile renderer.
var rich := false

## The helpers that carry the bodies moved out of this file; each reads the venue it was made for.
var reacting := VenueReact.new(self)
var shelf_spots := VenueShelf.new(self)
var station_spots := VenueStations.new(self)
var zone_spots := VenueZoneSpots.new(self)
var shell_floor := VenueShell.new(self)


## A new venue of `id` in arrangement `which`: the shell class its layout file names
## (`ShellBuilders`), the studio's for an id nobody ships.
static func make(id: StringName, which := 0) -> Venue:
	var out := ShellBuilders.make(id)
	out.variant = known_variant(id, which)
	return out


## The names of a venue's arrangements, in order, without building it. A venue with one has
## nothing to choose between, and the stage manager shows no picker for it.
static func variant_titles(id: StringName) -> PackedStringArray:
	return VenueCatalogue.variant_titles(id)


## `which` if the venue has that arrangement, else its first.
static func known_variant(id: StringName, which: int) -> int:
	return which if which >= 0 and which < variant_titles(id).size() else 0


## A venue's name without building one: building the chalk zone to read its title would draw
## sixty-four doodles for a button caption.
static func make_title(id: StringName) -> String:
	return VenueCatalogue.title_of(id)


## The venue id after `id` in `IDS`, wrapping round.
static func next_after(id: StringName) -> StringName:
	var at := IDS.find(id)
	return IDS[(at + 1) % IDS.size()]


static func is_known(id: StringName) -> bool:
	return IDS.has(id) or id == ROULETTE_ID or MadeRooms.has(id)


func venue_id() -> StringName:
	return &"studio"


## What a person is told when they arrive.
func title() -> String:
	if variant_titles(venue_id()).size() < 2:
		return make_title(venue_id())
	return "%s, %s" % [make_title(venue_id()), variant_titles(venue_id())[variant]]


## Set up the sky, the air, the exposure and the key light. `env` arrives fresh, with the
## studio's house defaults (glow on, SSAO on) already in it, so a venue only states what is
## different about it.
func dress(_env: Environment, _key: DirectionalLight3D) -> void:
	pass


## The lamps are furniture and go wherever the venue goes, but what they shine is the venue's
## call: a warm tungsten floor lamp on a neon grid is a lamp from another room.
func lamp_colour(_index: int, authored: Color) -> Color:
	return authored


func lamp_energy(_index: int, authored: float) -> float:
	return authored


## The house lights go, for a venue with fittings of its own to kill -- `power_flicker`'s strike,
## the one bar a chaos event takes the room dark. Nothing by default: a venue with no fittings
## of its own (anything but the studio today) has nothing here to turn off; its own practicals
## (scenes/studio.gd's `_lamps`) still dip and die, which is the whole room going dark anywhere.
func blackout(_on: bool) -> void:
	pass


## How loud the mix is right now, 0..1, every frame. For venues that move to the music.
func pulse(_level: float) -> void:
	pass


## Whether the room moves to the music. Off, `hear` takes everything for silence and a venue sits
## at its authored look: for anyone who would rather the room held still.
var reactive := true
## The mix's level through a meter's ballistics (fast up, slow down), 0..1.
var heard := 0.0
## A flash on each rise in the level -- a kick or a snare -- that dies away in a few frames, 0..1.
var heard_hit := 0.0
var _heard_slow := 0.0


## What a venue's `pulse` calls first: smooths the level into `heard` and its hits into `heard_hit`.
func hear(level: float) -> void: reacting.hear(level)


## The room hears a clip (docs/spatial_loop.md part two, slice 21, idea #5): the master or any
## track over 0 dBFS lifts the practicals by LIFT, falling to nothing over LIFT_SECONDS -- the shape
## of `heard_hit`, a jump and a fall -- and at most once every FLASH_GAP however often it clips. A
## mix clipping on every beat is told once in two seconds, not strobed at.
const LIFT := 0.3
const LIFT_SECONDS := 0.15
const FLASH_GAP := 2.0
## Whether a clip lifts the room at all (COMFORT's "Lift on clip"). Only while `reactive` too.
var lift_on_clip := true
## How far the practicals are lifted now, 0..LIFT, as a share of their own energy.
var lift := 0.0
## How many lifts there have been, for the suite and a shot's log.
var lifts := 0
var _lift_left := 0.0
var _since_lift := INF


## One frame of the room hearing whether anything is over: a clip starts a lift (`VenueReact.hear_clip`).
func hear_clip(over: bool, delta: float) -> void: reacting.hear_clip(over, delta)


## A box of soft additive sparks, off until `drive_sparks` turns them on (`VenueReact.make_sparks`).
func make_sparks(label: String, at: Vector3, extents: Vector3, seen: AABB, colours: Gradient,
		amount: int, rise := false) -> GPUParticles3D:
	return reacting.make_sparks(label, at, extents, seen, colours, amount, rise)


## How many of `p`'s sparks are out, from what the mix is doing.
func drive_sparks(p: GPUParticles3D, gain := 1.0) -> void: reacting.drive_sparks(p, gain)


## The activity zones, id -> AABB in studio space. The room widens with the desk, and the zones
## step out with it on their own side, so they never close in on the footprint or on each other.
func zones() -> Dictionary:
	var out := {}
	for id in ZONE_IDS:
		var box: AABB = ZONES[id]
		var shift := _grow() * signf(box.get_center().x)
		out[id] = AABB(box.position + Vector3(shift, 0, 0), box.size)
	return out


## What in the zones stops a person walking, as walker footprints ({c, h, a, top}) in studio
## space. Nothing by default: a zone that is only drawn (the chalk zone's sketches) is walked
## through, the way everything drawn in the air there is.
func zone_solids() -> Array:
	return []


## Where the prop shelf stands, in studio space: its floor centre, turned so its front faces
## into the room. On its trolley (WHEELED), wherever that has been pushed; else where the venue
## stands it.
func prop_shelf_spot() -> Transform3D:
	return station_spots.spot_of(&"prop_shelf")


## Where the venue stands the prop shelf until it is pushed somewhere else: the layout's
## (`common.live_room`, or the venue's own file; see LiveRoom): the tape and toys neighbourhood
## (Neighbourhoods), against the left wall at the front of the live room, facing across the
## neighbourhood's middle to the hoop and the Tour case.
func default_prop_shelf_spot() -> Transform3D:
	var spot: Transform3D = default_spot(&"prop_shelf")
	return spot


## How far across the tape and toys neighbourhood from the left wall the hoop and the Tour case
## stand (the layout's numbers); the pendants over it hang by the same measure.
const TOYS_ACROSS := 3.5


## Where the items live along the prop shelf's top (`VenueShelf.item_spots`).
func item_spots() -> Array[Transform3D]: return shelf_spots.item_spots()


## Where the headphones hang, under the prop shelf (`VenueShelf`).
func headphones_spot() -> Transform3D: return shelf_spots.headphones_spot()


## Where the signal glasses lie on the prop shelf (`VenueShelf`).
func glasses_spot() -> Transform3D: return shelf_spots.glasses_spot()


## Where the tablet lies on the prop shelf's lower tier (`VenueShelf`).
func tablet_spot() -> Transform3D: return shelf_spots.tablet_spot()


## Where the dartboard's face is (`VenueShelf`).
func dartboard_spot() -> Transform3D: return shelf_spots.dartboard_spot()


## What a dart sticks in: the board and its cork panel (`VenueShelf`).
func dart_boards() -> Array: return shelf_spots.dart_boards()


## Where dart `n` lives, left in the board (`VenueShelf`).
func dart_spot(n: int) -> Transform3D: return shelf_spots.dart_spot(n)


## Where the mini hoop stands, in studio space: its foot, its board facing into the room. On its
## trolley (WHEELED), wherever that has been pushed; else where the venue stands it.
func hoop_spot() -> Transform3D:
	return station_spots.spot_or_home(&"hoop")


## Where the venue stands the hoop until it is pushed somewhere else: the layout's, across the
## neighbourhood from the shelf the ball lives on, its board facing back at it.
func default_hoop_spot() -> Transform3D:
	var spot: Transform3D = default_spot(&"hoop")
	return spot


## Where the venue's own toy lies, in front of the hoop (`VenueShelf`).
func toy_spot() -> Transform3D: return shelf_spots.toy_spot()


## Where the radio plane waits, out from the hoop (`VenueShelf`).
func rcplane_spot() -> Transform3D: return shelf_spots.rcplane_spot()


## Where the Tour case stands, in studio space. On its trolley (WHEELED), wherever that has been
## pushed; else where the venue stands it.
func tour_case_spot() -> Transform3D:
	return station_spots.spot_or_home(&"tour_case")


## Where the venue stands the Tour case until it is pushed somewhere else: the layout's, beside
## the hoop, across the middle from the cassette rack, its stencilled front facing back at the
## shelf and the rack -- the run's opening move, where everyone walks past.
func default_tour_case_spot() -> Transform3D:
	var spot: Transform3D = default_spot(&"tour_case")
	return spot


## The harmony neighbourhood (Neighbourhoods): HARMONY_AISLE is the aisle the venues keep out from
## the bricks table's long side toward the middle of the room.
const HARMONY_AISLE := 1.75


## The synth and sound design neighbourhood (Neighbourhoods) round the synth zone's keyboard stand
## and the modular wall over it: its middle SYNTH_MIDDLE out from the zone's middle into the room;
## the sampler (the layout's) on the side away from the control room, facing it.
const SYNTH_MIDDLE := 1.7


## The synth neighbourhood's middle and which side the stand is on; null without a synth zone (`VenueZoneSpots`).
func synth_middle() -> Variant: return zone_spots.synth_middle()


## How high the modular room's rack foot is, over the synth zone's keyboard stand's upper deck, so its
## touch keys lie on the deck under it (RackWall).
const MODULAR_BOTTOM := 1.26


## Whether the modular room can be built onto this venue's live room: every venue but the Rig Roulette
## room, and a made room that was made without it.
func has_annex() -> bool:
	return venue_id() != ROULETTE_ID


## Where the modular room's wall hangs, over the synth zone's keyboard stand; null without an annex (`VenueZoneSpots`).
func modular_spot() -> Variant: return zone_spots.modular_spot()


## Everywhere on foot: the venue's rooms and the modular room built onto the live room.
func walk_rooms() -> Array[Rect2]: return zone_spots.walk_rooms()


## Where the lyric board stands in the vocal booth; null without a booth (`VenueZoneSpots`).
func lyrics_spot() -> Variant: return zone_spots.lyrics_spot()


## Where the cassette rack stands (CassetteRack, docs/spatial_loop.md part two, slice 23), in
## studio space: on its trolley (WHEELED) wherever that has been pushed, else on the floor beside the
## prop shelf, clear of it on the side away from the control room, its back in line with the
## shelf's against the same wall and facing into the room the same way. So the clips the band pulls
## out of the timeline stand beside the toys, where everyone walks past.
func cassette_rack_spot() -> Transform3D:
	return station_spots.spot_or_home(&"cassette_rack")


## Where the venue stands the cassette rack until it is pushed somewhere else: the layout's,
## beside where it stands the prop shelf (placed in the shelf's own frame).
func default_cassette_rack_spot() -> Transform3D:
	var spot: Transform3D = default_spot(&"cassette_rack")
	return spot


## Where the sampler stands (Sampler, docs/spatial_loop.md part two, slice 26), in studio space: on
## its trolley (WHEELED) wherever that has been pushed, else in the synth neighbourhood on its
## middle's side away from the control room, facing the middle: the pads and
## the modular one turn apart. Null where there is no synth zone (the Rig Roulette
## room has no zones).
func sampler_spot() -> Variant:
	return station_spots.spot_of(&"sampler")


## Where the fifths wheel stands (FifthsWheel.on_stand), in studio space: on the bricks table,
## the bottom edge of its board WHEEL_IN in from the table's end nearest the control room, facing
## back toward it. So whoever walks back from the desk meets it at the end of the table, where
## both hands reach it and the table's length is behind it. Null where there is no bricks table
## (the Rig Roulette room has no zones). The layout's (`wheel` of `common.live_room`, whose offset is
## this WHEEL_IN in from the table's end); the constant stays for the wheel's own plaque
## (`FifthsWheel`), which hangs off the same edge.
const WHEEL_IN := 0.06

func wheel_spot() -> Variant:
	return default_spot(&"wheel")


## The bricks table in three bands (docs/spatial_loop.md part two, slice 30), each a rectangle on
## its top that one zone-mounted station has to itself, in the table's own frame (`bricks_table`):
## x across it, + toward the long edge far from the middle of the room, and z along it, + away
## from the control room. The fifths wheel's board and its strut at the end nearest the control
## room (where `wheel_spot` stands it, WHEEL_IN in from that end); the section blocks along the
## far long edge, past the wheel. Clear of each other by BAND_GAP or more.
const TABLE_BANDS := {
	&"wheel": Rect2(-0.47, -1.0, 0.94, 0.56),
	&"sections": Rect2(0.12, -0.4, 0.36, 1.38),
}
const BAND_GAP := 0.04


## The bricks table's top, square to the room; null without one (`VenueZoneSpots`).
func bricks_table() -> Variant: return zone_spots.bricks_table()


## Where the section blocks stand (SectionBlocks, slice 30), in studio space: their band's middle
## (TABLE_BANDS) on the bricks table, along its far long edge, its front (+Z) toward the near long
## edge where a player stands, so its +X runs along the table away from the wheel, left to right for
## them. The layout's (`sections` of `common.live_room`). Null where there is no bricks table.
func sections_spot() -> Variant:
	return default_spot(&"sections")


## The circle of hand drums on the drum riser (HandDrum, docs/spatial_loop.md part two, slice 40):
## how far each drum's middle is from the ring's, and the most a drum stands out from its own middle
## on the floor (the low conga's belly, the cajón's corners on their stand), for the walker's solids.
const DRUM_RING := 0.72
const DRUM_FOOT := 0.19


## Where the ring of hand drums stands in a drums zone `box` (`VenueZoneSpots.drum_ring`).
static func drum_ring(box: AABB, n := -1, floor := ZoneKit.RISER_HEIGHT) -> Transform3D:
	return VenueZoneSpots.drum_ring(box, n, floor)


## Where the ring of hand drums stands (`n` -1) or drum `n`'s place; null without a riser.
func drum_circle_spot(n := -1) -> Variant: return zone_spots.drum_circle_spot(n)


## How high the ring of hand drums stands: the riser's top, or the floor where it is only drawn.
func drum_floor() -> float: return zone_spots.drum_floor()


## The looper (Looper, docs/spatial_loop.md part two, slice 45) on its stand at the drum riser's front
## corner: how far out along both of the ring's axes its feet's middle is, inside the riser's edge.
const LOOPER_CORNER := 0.98


## Where the looper stands in a drums zone `box` (`VenueZoneSpots.looper_at`).
static func looper_at(box: AABB, floor := ZoneKit.RISER_HEIGHT) -> Transform3D: return VenueZoneSpots.looper_at(box, floor)


## Where the looper stands here (`looper_at`), in studio space: the station `looper`. Null where the
## venue has no drum riser.
func looper_spot() -> Variant:
	return default_spot(&"looper")


## The venue's own instrument (VenueInstrument, docs/spatial_loop.md part two, slices 42 and 43, idea
## #19): {"kind" (one of VenueInstrument.KINDS), "spot" (the set's frame in studio space, its front,
## +Z, toward whoever plays it, on the floor under the row's middle), and optionally "count" (bars,
## up to VenueInstrument.MOST), "low" (the note its first bar's tonic is nearest), "title" and
## whatever of its kind it changes (how high it hangs, `at`)}. Every venue of Venue.IDS has one; empty
## for none, the Rig Roulette room, which says nothing of one.
func instrument() -> Dictionary:
	return {}


## Where the venue's instrument stands (the station `venue`), or null.
func instrument_spot() -> Variant: return zone_spots.instrument_spot()


## How far the instruments set against a wall stand off it, bars to its face (m).
const INSTRUMENT_OFF_WALL := 0.12


## A spot for an instrument against the live room's back wall, `depth` deep (`VenueZoneSpots`).
func back_wall_instrument(depth: float) -> Transform3D: return zone_spots.back_wall_instrument(depth)


## A spot for an instrument against a side wall of the floor beside the desk (`VenueZoneSpots`).
func side_wall_instrument(side: float, along: float, depth: float) -> Transform3D:
	return zone_spots.side_wall_instrument(side, along, depth)


## The venue's instrument as a walker solid, where it is solid.
func instrument_solids() -> Array: return zone_spots.instrument_solids()


## The venue's weather (Weather, docs/spatial_loop.md part two, slice 44, idea #20), in an arrangement
## that has some: {"kind" (one of Weather.KINDS), "spot" (the switch's frame in studio space, on the
## floor under it, its front +Z into the room), "sill" (the switch's height), "glass" (the pane the
## drops land on, a frame at its middle, X across, Y up, +Z into the room) and "size" (the pane's
## width and height), or "pools" (points on the water the cave's drips fall into), and optionally
## "post" (it stands on a post of its own, at the floor's edge), "switch_z" and "plaque_z" (how far
## out of the spot's front the switch and the plaque are) and "low" (the note its lowest drop's tonic
## is nearest)}. Empty for none: every arrangement but the loft's Thunderstorm, the greenhouse's Rain,
## the cabin's Snowy night and the cave's grotto and glowworm lake.
func weather() -> Dictionary:
	return {}


## Where the venue's weather switch stands (the station `weather`), or null.
func weather_spot() -> Variant: return zone_spots.weather_spot()


## The weather switch's post as a walker solid, where it stands on one.
func weather_solids() -> Array: return zone_spots.weather_solids()


## The floor's height at `p` (studio space): the top of whatever the venue stands there that a person
## steps up onto (the drum riser), or 0, as the walker finds it (Walker.ground_of, `solids`). Where a
## station's seat is put down (Stations.seat), and so a headset's play space on a travel there.
func floor_at(p: Vector2) -> float:
	return Walker.ground_of(solids(), p)


## The stations and the furniture of the back of house that stand on the floor by themselves, and
## so are pushed about it like the gear in the control room: each is a trolley of the studio's
## (Studio.live_pieces), and its `*_spot` is wherever that trolley has been wheeled. Which they are
## is the layout's (the pieces of `common.live_room` that are `mobility: wheeled`, LiveRoom), and so
## is where each stands until somebody moves it (`default_spot`): null where the venue has no room
## for it at all. The fifths wheel is not here: it is mounted on the bricks table, which is the
## venue's and does not move.
static var WHEELED: Array[StringName] = LiveRoom.wheeled_ids()

## Where the venue stands wheeled piece `id` until it is pushed (`VenueStations.default_spot`); null without room.
func default_spot(id: StringName) -> Variant: return station_spots.default_spot(id)


## Where wheeled piece `id` stands now: its trolley's place while out here, else `default_spot`.
func _spot_of(id: StringName) -> Variant: return station_spots.spot_of(id)


## Where the stage table stands, read off the studio; null in no studio (`VenueStations`).
func stage_table_spot() -> Variant: return station_spots.stage_table_spot()


## Where the EQ wall stands, read off the studio; null in no studio (`VenueStations`).
func eq_wall_spot() -> Variant: return station_spots.eq_wall_spot()


## Where the LEVELS wall stands in its niche; null in no studio (`VenueStations`).
func levels_spot() -> Variant: return station_spots.levels_spot()


## Where the DJ platter stands on the deck's cart; null in no studio (`VenueStations`).
func platter_spot() -> Variant: return station_spots.platter_spot()


## Where the session in miniature lies at home, on the side table; null in no studio.
func miniature_spot() -> Variant: return station_spots.miniature_spot()


## Where the Rig Roulette station hangs on the control room's back wall (`VenueStations`).
func rig_roulette_spot() -> Transform3D: return station_spots.rig_roulette_spot()


## Where the door to the Rig Roulette room stands (`VenueStations`).
func rig_roulette_door() -> Transform3D: return station_spots.rig_roulette_door()


## The Rig Roulette door as the walker's footprint, solid to its lintel.
func door_solid() -> Dictionary: return station_spots.door_solid()


## Where the board that writes up a Rig Roulette roll hangs (`VenueStations`).
func roll_board_spot() -> Transform3D: return station_spots.roll_board_spot()


## Where the LEVELS niche is, in the front wall left of the timeline (`VenueStations`).
func levels_niche_spot() -> Transform3D: return station_spots.levels_niche_spot()


## Where the sampling station's TV is, read off the studio; null in no studio.
func tv_spot() -> Variant: return station_spots.tv_spot()


## Where the TV hangs on the front wall right of the timeline (`VenueStations`).
func tv_mount_spot() -> Transform3D: return station_spots.tv_mount_spot()


## The TV's middle this far in from the right-hand wall; its face this far out from the front
## wall's line (the wall's face is 5cm in, its bracket between), or a stand's.
const TV_FROM_RIGHT := 2.6
const TV_IN := 0.17
const TV_STANDS_IN := 0.4


## The niche's middle this far in from the left-hand wall (its left edge just clear of a bass trap
## up the corner, its right as near the timeline's shoulder from the seat as that leaves it); its
## board this far out from the front wall's line (the wall's face is 5cm in, the board's back a little off it); a standing cabinet's
## this far, shallow (`Studio.NICHE_STANDING_OUT`), its front 0.6 m short of the patch wall's legs.
const LEVELS_NICHE_FROM_LEFT := 2.25
const LEVELS_NICHE_IN := 0.14
const LEVELS_NICHE_STANDS_IN := 0.33


## Where the Workshop's panel hangs; null unless the Workshop is on (`VenueStations`).
func workshop_spot() -> Variant: return station_spots.workshop_spot()


## The twelve colours tracks are shown in here, in TrackColours.STANDARD's order (red, orange,
## yellow, lime, green, teal, sky, blue, violet, magenta, pink, neutral); empty for STANDARD's
## own, which is the studio's.
func track_palette() -> Array:
	return []


## What the gear is made of here (see GearStyle). The studio's own: no change from the defaults but a
## steel edge.
func gear_style() -> GearStyle:
	return GearStyle.new()


## Whether what hangs on the control room's back wall elsewhere (the roll board, the Rig Roulette
## panel) stands on posts of its own here, for a venue with no wall to hang it on.
func back_wall_gear_stands() -> bool:
	return false


## Whether the board is drawn as chalk on a slate rather than as a lit screen.
func roll_board_chalky() -> bool:
	return false


## The baskets a ball meets in flight, in studio space (Flight.fly's `hoops`), each with the Hoop
## that sounds it as its "node" when the venue has stood one.
func hoops() -> Array:
	var shape := Hoop.shape(hoop_spot())
	shape["node"] = get_node_or_null("Hoop")
	return [shape]


## Where the mic lives, in the clip of the booth's mic stand; null where there is no stand.
func mic_spot() -> Variant: return zone_spots.mic_spot()


## How high the room's ceiling is, for the walker: no one flies out through the roof.
func ceiling_height() -> float:
	return LIVE_ROOM_HEIGHT


## Everything the venue puts on the floor that stops a person, as the walker is given it: the zones'
## dressing, the instrument and weather posts, the door, and -- outside a studio, where there are no
## trolleys -- the prop shelf and the free-standing pieces with it (the hoop, the Tour case, the
## cassette rack, the sampler). In a studio those (WHEELED) are left out: the walker already stops at
## every trolley in the floor plan, wherever it has been pushed.
func solids() -> Array:
	var out := zone_solids()
	out.append_array(instrument_solids())
	out.append_array(weather_solids())
	if prop_shelf_solid():
		# The door is as solid as the shelf: a venue that only draws its furniture (the chalk
		# zone) is walked through, door and all.
		out.append(door_solid())
		if station_spots.trolley_of(&"prop_shelf") == null:
			out.append_array(wheeled_solids())
	return out


## The free-standing pieces where they stand now, as walker footprints with their heights.
func wheeled_solids() -> Array: return shell_floor.wheeled_solids()


## Whether the shelf is a thing you bump into. A venue that only draws it (the chalk zone) says
## no, the way its sketched zones are walked through.
func prop_shelf_solid() -> bool:
	return true


## Build the prop shelf and its hoop in the venue's own materials; each venue calls it as it dresses its zones.
func _dress_prop_shelf(top: Material, frame: Material, lamp := Color(1.0, 0.76, 0.48)) -> Node3D:
	return shell_floor.dress_prop_shelf(top, frame, lamp)


## The floor behind the working footprint that a person can walk on to reach the zones.
func back_of_house() -> Rect2: return shell_floor.back_of_house()


## Whether the venue's floor ends at walls: false for one in the open (a plaza, a roof, a stage),
## where a sign has nothing to hang on. Text goes on walls or nowhere, never in the air, so the
## neighbourhoods' banners are not hung where this is false.
func has_walls() -> bool:
	return true


## Every room past the working footprint that a person can walk in, in studio space, each
## meeting the footprint or another along a shared line (see Walker.outline). By default the
## one back_of_house; an arrangement with a room off to the side has more.
func rooms() -> Array[Rect2]:
	return [back_of_house()]


## The floor either side of the working footprint, out to the live room's width.
func beside_the_desk() -> Array[Rect2]: return shell_floor.beside_the_desk()


## One floor round everything, `margin` past it on every side, for a venue in the open.
func open_floor(margin: float) -> Rect2: return shell_floor.open_floor(margin)


## Where the modular room's near wall begins, along x: the live room's wall, or a house's outer wall
## beyond it. Overridden by venues whose walls stand past the live room.
func annex_edge() -> float:
	return live_room_half()


## Half the live room's width, grown with the desk the way the zones are.
func live_room_half() -> float:
	return LIVE_ROOM_HALF + _grow()


## How much each side of the room has grown past its base width, so the back of house and the
## strips beside the control room keep their room as it widens with the desk.
const DRAWN_WIDTH := Studio.ROOM_WIDTH


func _grow() -> float:
	return (room_width - DRAWN_WIDTH) * 0.5


## How high the neighbourhoods' banners hang here (Neighbourhoods.sign_spot): under whatever is
## overhead. A venue with something lower over the live room (a gallery, eaves) says so.
func sign_height() -> float:
	return Neighbourhoods.SIGN_HEIGHT


## A lit or drawn outline of the working footprint, at floor level, as corners.
func footprint_corners() -> PackedVector2Array: return shell_floor.footprint_corners()


## The board's materials and ink, in the venue's own style. Left plain by default.
func _dress_wardrobe(_board: Wardrobe) -> void:
	pass


## Where the glass's centre stands, facing into the room. By default on the left wall behind
## the treatment, facing across the room: a step back and a turn left from the mix position,
## clear of every piece of gear in the floor plan.
func mirror_spot(glass: Vector2) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, PI * 0.5),
			Vector3(-room_width * 0.5 + 0.16, 0.14 + glass.y * 0.5, 2.2))


## Build the frame round `mirror`'s glass, as its children. The glass faces +Z and is centred
## on the mirror; a frame stands proud of it, never in front of the glass's face.
func _frame_mirror(_mirror: Mirror) -> void:
	pass


## Four bars round the glass, shared by the venues whose frames are solid (`VenueShell.frame_bars`).
static func frame_bars(mirror: Mirror, bar: float, depth: float, proud: float,
		material: Material, inset := 0.0) -> void:
	VenueShell.frame_bars(mirror, bar, depth, proud, material, inset)

