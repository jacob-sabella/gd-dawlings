class_name VenueStations
extends RefCounted

## Where the studio's own furniture and the wheeled pieces stand as the venue sees them, and where the
## venue puts what hangs on the control room's walls. Read from the studio the venue stands in (the
## trolleys wherever they have been pushed) or from the layout (`LiveRoom`, against the venue's
## anchors); the wall spots are plain numbers off the room's width. Moved out of
## `core/venues/venue.gd` without change of behaviour; the venue keeps a one-line delegate for each
## name other files reach (the stations by string, the tests, the subclasses).

var venue: Venue

## The layout's spots for this venue (id -> Transform3D) and the arrangement and width they were
## resolved for, kept until either changes.
var _spots: Dictionary = {}
var _spots_for: Array = []


func _init(of: Venue) -> void:
	venue = of


## The studio this venue stands in, or null in none (a venue made to be measured).
func _studio() -> Studio:
	return venue.get_parent() as Studio


## `node`'s transform in the venue's frame, read through the studio's set; null where there is no
## studio or `node` is gone or not built (AR).
func _studio_piece(node_of: Callable) -> Variant:
	var studio := _studio()
	if studio == null:
		return null
	var node: Node3D = node_of.call(studio)
	if node == null or not is_instance_valid(node):
		return null
	return venue.transform.affine_inverse() * studio.studio_set.transform * node.transform


## Where wheeled piece `id` (`Venue.WHEELED`) stands until it is pushed somewhere else, in studio
## space; null where the venue has no room for it. Read from the layout against this venue's anchors;
## kept while its arrangement and width stay as they are.
func default_spot(id: StringName) -> Variant:
	var restored := _restored()
	var key := [venue.variant, venue.room_width, restored]
	if _spots_for != key:
		_spots = LiveRoom.spots(ShellFacts.anchors_of(venue), restored)
		_spots_for = key
	if id == &"tour_case" and not Tour.enabled:
		# Tour mode is off: no case, and no solid where it would stand.
		return null
	return _spots.get(id)


## The pieces the room's delta has back that its layout left out, or none in no studio.
func _restored() -> Array:
	var studio := _studio()
	if studio == null or studio.room_deltas == null:
		return []
	return studio.room_deltas.delta.restored.duplicate()


## The trolley that wheeled piece `id` stands on, in the studio this venue stands in; null in no
## studio (a venue made to be measured) or one that has not built it (AR).
func trolley_of(id: StringName) -> Trolley:
	var studio := _studio()
	if studio == null or studio.studio_set == null:
		return null
	var t: Trolley = studio.live_pieces.get(id)
	return t if t != null and is_instance_valid(t) else null


## `spot_of`, or for a made room that does without the piece (its layout switched it off) the shared
## live room's: the venue's own pieces (the hoop on the wall) that still read a spot take that.
func spot_or_home(id: StringName) -> Transform3D:
	var at: Variant = spot_of(id)
	if at != null:
		return at
	var home := LayoutResolver.all(LiveRoom.layout(&"", 0), ShellFacts.anchors_of(venue))
	return home.get(id, Transform3D.IDENTITY)


## Where wheeled piece `id` stands, in studio space: where its trolley has been wheeled while it is
## out in this venue, else the venue's own `default_spot` for it.
func spot_of(id: StringName) -> Variant:
	var t := trolley_of(id)
	if t != null and t.visible:
		return venue.transform.affine_inverse() * venue.get_parent().studio_set.transform * t.transform
	return default_spot(id)


## Where the stage table stands (StageTable): on its trolley in the control room, wherever it has
## been wheeled. Its front (+Z) faces the mix position. Null for a venue in no studio, or one with
## no table (AR).
func stage_table_spot() -> Variant:
	return _studio_piece(func(s: Studio) -> Node3D: return s.stage_trolley)


## Where the EQ wall stands (EqWall): on its trolley at the control room's side wall, its front (+Z)
## into the room. Null for a venue in no studio, or one with no wall (AR).
func eq_wall_spot() -> Variant:
	return _studio_piece(func(s: Studio) -> Node3D: return s.eq_wall_trolley)


## Where the LEVELS wall stands (LevelsWall): in its niche (`levels_niche_spot`), its front (+Z) into
## the room. Null for a venue in no studio, or one with no wall (AR).
func levels_spot() -> Variant:
	return _studio_piece(func(s: Studio) -> Node3D: return s.levels_niche)


## Where the DJ platter stands (Platter): on the leaf of the tape deck's cart, wherever the cart has
## been wheeled. Its front (+Z) is the cart's. Null for a venue in no studio, or one with no cart (AR).
func platter_spot() -> Variant:
	var studio := _studio()
	if studio == null or studio.platter == null or not is_instance_valid(studio.platter) \
			or studio.deck_trolley == null or not is_instance_valid(studio.deck_trolley):
		return null
	return venue.transform.affine_inverse() * studio.studio_set.transform * studio.deck_trolley.transform * Platter.ON_CART


## Where the session in miniature lies at home (MiniatureItem): on the side table by the seat
## (Studio.desk_wing), wherever it has been pushed to. Its reader's edge (an item's -Z) toward the
## table's front. Null for a venue in no studio, or one with no table (AR).
func miniature_spot() -> Variant:
	var at: Variant = _studio_piece(func(s: Studio) -> Node3D: return s.desk_wing)
	if at == null:
		return null
	return (at as Transform3D) * Transform3D(Basis(Vector3.UP, PI), Vector3(0, Studio.WING_TOP, 0))


## Where the sampling station's TV is (TvSurface, docs/sampling_station.md): on its bracket or its
## stand, read off the studio's.
func tv_spot() -> Variant:
	return _studio_piece(func(s: Studio) -> Node3D: return s.tv_mount)


## Where the Rig Roulette station hangs: on the control room's own back wall, within reach of the
## console rather than tucked away in the back of house -- the whole band gathers around it between
## takes. Mounted at console-knob height, facing into the room.
##
## The back wall, not a side wall: both side walls sit behind furniture that grows with every track's
## own FX (the mixing rack and the patchbay), and a long enough one stands squarely between the seat
## and anything mounted on the wall behind it. The back wall carries nothing of the kind, only the
## fixed first-reflection panels, which this clears by mounting past their x -1.95..1.95 spread.
func rig_roulette_spot() -> Transform3D:
	var x := -venue.room_width * 0.5 + 1.0
	# The wall is a box 0.1 thick centred on ROOM_FRONT, its face 5cm out; the plate stands 1cm
	# deep behind the origin, so a spot any nearer than this buries the panel in the plaster.
	var z := Studio.ROOM_FRONT + 0.07
	return Transform3D(Basis.IDENTITY, Vector3(x, 1.05, z))


## Where the door to the Rig Roulette room stands (its origin the floor in the middle of the opening,
## facing into the room, 7cm off the wall): at the right-hand end of the front wall, in the corner,
## clear of the roulette panel's end, the first-reflection panels, the roll board and the acoustic
## treatment. Where the room has no wall it is a gate on its own legs. A venue whose front wall is
## taken says where else.
func rig_roulette_door() -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(venue.room_width * 0.5 - 1.0, 0.0, Studio.ROOM_FRONT + 0.07))


## The door as the walker's footprint: solid to its lintel.
func door_solid() -> Dictionary:
	var at := venue.rig_roulette_door()
	# Its frame stands in the wall's face; what a person walks into is the part on the floor.
	var c := Vector2(at.origin.x, at.origin.z)
	if absf(at.basis.get_euler().y) < 0.01:
		c.y = maxf(c.y, Studio.ROOM_FRONT + 0.05 + RouletteDoor.HALF.y + 0.005)
	return {"c": c, "h": RouletteDoor.HALF, "a": at.basis.get_euler().y,
			"top": RouletteDoor.OPENING.y + RouletteDoor.LINTEL}


## Where the board that writes up a Rig Roulette roll hangs (its origin the middle of its bottom
## edge): high on the right-hand wall, facing in, its lower edge just above the acoustic panels (which
## stand to 2.1m) and its top just under the ceiling, so the whole room can read it with a turn of
## the head. Not on the front wall, where it was the backdrop to the whole set, and not the left wall,
## which has the mirror and, in the studio, a window into the live room. Where there is no wall and
## the board stands on its own legs, it stands in from the edge, which is where a venue puts its own
## uprights.
func roll_board_spot() -> Transform3D:
	# The wall is a box 0.1 thick centred on the room's edge, its face 5cm in.
	var inset := 0.45 if venue.back_wall_gear_stands() else 0.11
	return Transform3D(Basis(Vector3.UP, -PI * 0.5),
			Vector3(venue.room_width * 0.5 - inset, 2.14, Studio.ROOM_MID))


## Where the LEVELS niche is (its origin the floor under the board's middle, its front +Z into the
## room): in the front wall left of the timeline, the board set back in it, so it can be an entire
## wall in each of the venues. Left of the timeline as the seat sees it, so not behind it, and short
## of the left wall, where the patch wall, the mirror and the window are; its x follows the wall out
## as the room widens. Where the wall is not one to build into (`back_wall_gear_stands`) the niche is
## a cabinet of its own, stood in from the edge as the roll board is.
func levels_niche_spot() -> Transform3D:
	var inset := Venue.LEVELS_NICHE_STANDS_IN if venue.back_wall_gear_stands() else Venue.LEVELS_NICHE_IN
	return Transform3D(Basis.IDENTITY,
			Vector3(-venue.room_width * 0.5 + Venue.LEVELS_NICHE_FROM_LEFT, 0.0, Studio.ROOM_FRONT + inset))


## Where the TV hangs (its origin the floor under the screen's middle, its face +Z into the room): on
## the front wall right of the timeline, as LEVELS is left of it, short of the door in the right-hand
## corner. Where the wall is not one to hang it on (`back_wall_gear_stands`), on a stand of its own,
## in from the edge.
func tv_mount_spot() -> Transform3D:
	var inset := Venue.TV_STANDS_IN if venue.back_wall_gear_stands() else Venue.TV_IN
	return Transform3D(Basis.IDENTITY,
			Vector3(venue.room_width * 0.5 - Venue.TV_FROM_RIGHT, 0.0, Studio.ROOM_FRONT + inset))


## Where the assistant's panel hangs (AssistantPanel, docs/mcp_assistant.md): on the control room's right wall like
## the Workshop's, further toward the desk, stood off the wall the same way. In every venue but the Rig Roulette room, where a ControlHost is attached to the studio.
func assistant_spot() -> Variant:
	if not ControlHost.stands or venue.venue_id() == Venue.ROULETTE_ID:
		return null
	var inset := AssistantPanel.OFF_WALL if venue.back_wall_gear_stands() else AssistantPanel.ON_WALL + 0.05
	return Transform3D(Basis(Vector3.UP, -PI * 0.5),
			Vector3(venue.room_width * 0.5 - inset, 0.0, Studio.ROOM_BACK - AssistantPanel.FROM_LIVE_ROOM))


## Where the Workshop's panel hangs (WorkshopPanel, docs/workshop.md; its origin the floor under the
## middle of its face, its front +Z into the room): on the control room's right wall near the live
## room's end, behind the patchbay's stand and the station board, at eye height, on stand-offs in
## front of what hangs there, clear of the roll board and the door; stood WorkshopPanel.OFF_WALL in
## where the venue has no wall and it stands on a post. Null unless the Workshop is on in this
## process (Workshop.enabled: a dev flag, this machine, never a guest), and in the Rig Roulette room.
func workshop_spot() -> Variant:
	if not Workshop.enabled() or venue.venue_id() == Venue.ROULETTE_ID:
		return null
	var inset := WorkshopPanel.OFF_WALL if venue.back_wall_gear_stands() else WorkshopPanel.ON_WALL + 0.05
	return Transform3D(Basis(Vector3.UP, -PI * 0.5),
			Vector3(venue.room_width * 0.5 - inset, 0.0, Studio.ROOM_BACK - WorkshopPanel.FROM_LIVE_ROOM))
