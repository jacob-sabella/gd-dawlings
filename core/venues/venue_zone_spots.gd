class_name VenueZoneSpots
extends RefCounted

## Where the stations that are mounted in a zone stand, in studio space: the synth neighbourhood's
## middle, the modular room's wall, the lyric board, the bricks table, the ring of hand drums and the
## looper, the venue's own instrument and its weather, and the mic. All of them are read off the
## venue's zones (`Venue.zones`), so they follow the room as it widens. Moved out of
## `core/venues/venue.gd` without change of behaviour; the venue keeps a one-line delegate for each
## name other files reach (the stations by string, the tests, the subclasses).

var venue: Venue


func _init(of: Venue) -> void:
	venue = of


## The venue's zone `id` as a box in studio space, or null where the venue has none (the Rig Roulette
## room has no zones).
func _zone(id: StringName) -> Variant:
	var at := venue.zones()
	return at.get(id)


## The synth neighbourhood's middle, on the floor, and which way across the room the stand is from
## it (+1 the stand on the right); null where there is no synth zone. Its middle is
## `Venue.SYNTH_MIDDLE` out from the zone's middle into the room.
func synth_middle() -> Variant:
	var box: Variant = _zone(&"synth")
	if box == null:
		return null
	var c := (box as AABB).get_center()
	var side := 1.0 if c.x >= 0.0 else -1.0
	return [Vector3(c.x - side * Venue.SYNTH_MIDDLE, 0, c.z), side]


## Where the modular room's wall hangs (RackWall, docs/spatial_loop.md part two, slice 51): the synth
## zone's module rack over the keyboard stand (ZoneKit.keyboard_stand). Null where the venue cannot
## have the modular room built onto it (`Venue.has_annex`).
func modular_spot() -> Variant:
	if not venue.has_annex():
		return null
	return ModularAnnex.rack_spot(venue.annex_edge())


## Everywhere on foot: the venue's rooms, and the modular room built onto the live room's side with
## its doorway.
func walk_rooms() -> Array[Rect2]:
	var out := venue.rooms()
	if venue.has_annex():
		out.append_array(ModularAnnex.floors(venue.annex_edge(), venue.live_room_half()))
	return out


## Where the lyric board stands (LyricBoard, docs/spatial_loop.md part two, slice 56): in the vocal
## booth, LyricBoard.IN_BOOTH from its floor's middle, across the mic stand's foot from where the
## singer stands and in line with it, its face (+Z) back toward the singer. Mounted in the zone, not
## a trolley: the booth is the venue's. Null where there is no booth. It stands on what the mic stand
## stands on (the studio's felt, a millimetre over the floor elsewhere), so its foot is not in the
## floor's plane.
func lyrics_spot() -> Variant:
	var box: Variant = _zone(&"vocals")
	if box == null:
		return null
	var c := (box as AABB).get_center()
	var floor_y := 0.001
	var stand := venue.find_child("MicStand", true, false) as Node3D
	if stand != null:
		var y := stand.position.y
		var up := stand.get_parent()
		while up != null and up != venue:
			if up is Node3D:
				y += (up as Node3D).position.y
			up = up.get_parent()
		floor_y = y
	return Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(c.x, floor_y, c.z) + LyricBoard.IN_BOOTH)


## The bricks table's top: the middle of its top, square to the room (x across it, z along it, as
## `Venue.TABLE_BANDS` has them). Null where there is no bricks table.
func bricks_table() -> Variant:
	var box: Variant = _zone(&"bricks")
	if box == null:
		return null
	var c := (box as AABB).get_center()
	return Transform3D(Basis.IDENTITY, Vector3(c.x, ZoneKit.TABLE_HEIGHT, c.z))


## Where the ring of hand drums stands in a drums zone `box` (HandDrum, docs/spatial_loop.md part two,
## slice 40): `n` -1 is the ring's middle `floor` up (the riser's top, or the floor where the riser is
## only drawn: `drum_floor`), its front (+Z) toward the mix position (square to the room, the nearest
## of the four ways), where the station's seat is; `n` 0 to 3 is HandDrum.KINDS[n]'s place round it,
## each `Venue.DRUM_RING` out on a diagonal, the djembe and the cajon in front, the two congas, the
## tallest, behind, every drum's front (an item's -Z) toward the ring's front, so its jack and the
## cajon's face are seen from the seat.
static func drum_ring(box: AABB, n := -1, floor := ZoneKit.RISER_HEIGHT) -> Transform3D:
	var c := box.get_center()
	var toward := Vector2(0.0, Studio.MIX_POSITION_Z) - Vector2(c.x, c.z)
	var yaw := snappedf(atan2(toward.x, toward.y), PI * 0.5)
	var middle := Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, floor, c.z))
	if n < 0 or n >= 4:
		return middle
	var corner: Vector2 = [Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1)][n]
	var along := corner.normalized() * Venue.DRUM_RING
	return middle * Transform3D(Basis(Vector3.UP, PI), Vector3(along.x, 0, along.y))


## Where the ring of hand drums stands here (`drum_ring`): its middle (`n` -1, the station `drums`)
## or drum `n`'s place. Null where the venue has no drum riser.
func drum_circle_spot(n := -1) -> Variant:
	if n < 0:
		return venue.default_spot(&"drums")
	var box: Variant = _zone(&"drums")
	if box == null:
		return null
	return drum_ring(box, n, drum_floor())


## How high the ring of hand drums stands: the riser's top where the riser is a step the walker
## climbs (`Venue.zone_solids`), and the floor where it is only drawn (the chalk zone), so a drum
## stands on what a person stands on beside it. 0 where there is no drums zone.
func drum_floor() -> float:
	var box: Variant = _zone(&"drums")
	if box == null:
		return 0.0
	var c: Vector3 = (box as AABB).get_center()
	return Walker.ground_of(venue.zone_solids(), Vector2(c.x, c.z))


## Where the looper (Looper, docs/spatial_loop.md part two, slice 45) stands in a drums zone `box`, on
## `floor` (`drum_ring`'s): at the riser's front corner on the ring's left as you face its front,
## `Venue.LOOPER_CORNER` out along both of the ring's axes, its front (+Z) the ring's, so it is played
## from the floor in front of the riser.
static func looper_at(box: AABB, floor := ZoneKit.RISER_HEIGHT) -> Transform3D:
	return drum_ring(box, -1, floor) * Transform3D(Basis.IDENTITY, Vector3(-Venue.LOOPER_CORNER, 0, Venue.LOOPER_CORNER))


## Where the venue's instrument stands (the station `venue`): its `spot`, or null where it has none.
func instrument_spot() -> Variant:
	var spec := venue.instrument()
	return spec["spot"] if spec.get("spot") is Transform3D else null


## A spot for an instrument against the live room's back wall, behind the drum riser beside the
## lattice (the rhythm neighbourhood's back wall), its front toward the desk, its bars `depth` deep:
## where the studio's tubular bells, the cave's crystals, the grid's neon bars, the chalk zone's
## xylophone, the station's hull panels, the greenhouse's pots, the stage's cymbals and gong and the
## desert's ringing stones stand. Clear of both zones' boxes and of the walk between.
func back_wall_instrument(depth: float) -> Transform3D:
	var drums: Variant = _zone(&"drums")
	var box: AABB = drums if drums != null else Venue.ZONES[&"drums"]
	return Transform3D(Basis(Vector3.UP, PI),
			Vector3(box.get_center().x, 0, Venue.LIVE_ROOM_BACK - 0.05 - Venue.INSTRUMENT_OFF_WALL - depth))


## A spot for an instrument against a side wall of the floor beside the desk (`side` -1 the left, 1
## the right), `along` its middle's z, its bars `depth` deep, its front into the room: where the
## garden's chimes, the cabin's icicles and the loft's steam pipes hang and the dome's glass stands.
func side_wall_instrument(side: float, along: float, depth: float) -> Transform3D:
	var x := signf(side) * (venue.live_room_half() - 0.05 - Venue.INSTRUMENT_OFF_WALL - depth)
	return Transform3D(Basis(Vector3.UP, -signf(side) * PI * 0.5), Vector3(x, 0, along))


## The venue's instrument as a walker solid, where it is solid (`Venue.prop_shelf_solid`): a person
## walks up to it rather than through it, and a throw bounces off it.
func instrument_solids() -> Array:
	var spec := VenueInstrument.spec_of(venue)
	if spec.is_empty() or not venue.prop_shelf_solid() or &"venue" in venue.without:
		return []
	return [VenueInstrument.solid(spec)]


## Where the venue's weather's switch stands (the station `weather`): its `spot`, or null where it
## has none.
func weather_spot() -> Variant:
	var spec := venue.weather()
	return spec["spot"] if spec.get("spot") is Transform3D else null


## The weather's switch's post as a walker solid, where it stands on one and the room is solid.
func weather_solids() -> Array:
	var post := Weather.solid(Weather.spec_of(venue))
	if post.is_empty() or not venue.prop_shelf_solid() or &"weather" in venue.without:
		return []
	return [post]


## Where the mic lives: in the clip at the end of the booth's mic stand's boom, along it, grille out.
## Null where there is no stand (the chalk zone only draws one), and the mic takes a place on the
## shelf instead.
func mic_spot() -> Variant:
	var stand := venue.find_child("MicStand", true, false) as Node3D
	if stand == null:
		return null
	var at := stand.transform
	var up := stand.get_parent()
	while up != null and up != venue:
		if up is Node3D:
			at = (up as Node3D).transform * at
		up = up.get_parent()
	# Along the boom: out along the stand's -Z and up by its tilt, and the mic's axis (which is
	# its own centre height above its origin) through the clip.
	var along := Basis(Vector3.RIGHT, ZoneKit.MIC_TILT)
	return at * Transform3D(along, ZoneKit.mic_clip() - along * Vector3(0, MicItem.AXIS_HEIGHT, 0))
