class_name VenueShell
extends RefCounted

## The shared shell-building helpers and floor maths of a venue: the prop shelf and its hoop built in
## the venue's own materials, the floors round the working footprint, the walker footprints of the
## wheeled pieces, and the mirror with its frame and wardrobe board. Moved out of
## `core/venues/venue.gd` without change of behaviour; the venue keeps a one-line delegate for each
## name its subclasses, the tests or the tools reach.

var venue: Venue


func _init(of: Venue) -> void:
	venue = of


## Build the prop shelf at its spot in the venue's own materials: called by each venue as it dresses
## its zones, with the bricks table's top and legs so the two read as one set, and a lamp the colour
## of the venue's own light. The hoop across the room is the shelf's: its stand in the shelf's frame.
func dress_prop_shelf(top: Material, frame: Material, lamp := Color(1.0, 0.76, 0.48)) -> Node3D:
	var holder := Node3D.new()
	holder.name = "PropShelf"
	holder.transform = venue.prop_shelf_spot()
	venue.add_child(holder)
	ZoneKit.prop_shelf(holder, top, frame, lamp)
	var hoop := Hoop.new(frame, null, false, lamp)
	hoop.transform = venue.hoop_spot()
	venue.add_child(hoop)
	return holder


## The free-standing pieces (`Venue.WHEELED`) where they stand now, as walker footprints with how
## tall each is: what a thrown thing lands on top of or bounces off the side of (Flight.fly), which a
## trolley's footprint alone does not say. None where they are only drawn (`Venue.prop_shelf_solid`).
func wheeled_solids() -> Array:
	var out: Array = []
	if not venue.prop_shelf_solid():
		return out
	var spot := venue.prop_shelf_spot()
	out.append({"c": Vector2(spot.origin.x, spot.origin.z),
			"h": Vector2(ZoneKit.SHELF.x, ZoneKit.SHELF.z) * 0.5,
			"a": spot.basis.get_euler().y, "top": ZoneKit.SHELF.y})
	# What a made room does without (its layout switched the piece off) has no solid.
	if venue.default_spot(&"hoop") != null:
		out.append_array(Hoop.solids(venue.hoop_spot()))
	if venue.default_spot(&"tour_case") != null:
		out.append_array(TourCase.solids(venue.tour_case_spot()))
	if venue.default_spot(&"cassette_rack") != null:
		out.append(CassetteRack.solid(venue.cassette_rack_spot()))
	var sampler_at: Variant = venue.sampler_spot()
	if sampler_at != null:
		out.append(Sampler.solid(sampler_at))
	return out


## The floor behind the working footprint that a person can walk on to reach the zones: the
## footprint's far edge back to the live room's back, wall to wall. Furniture stays out of it; it is
## for people. In the studio it is the live room; in an open venue, where nothing else would stop
## you, it is where the floor ends being somewhere.
func back_of_house() -> Rect2:
	var front := Studio.ROOM_BACK
	var half := venue.live_room_half() - 0.05
	return Rect2(-half, front, half * 2.0, Venue.LIVE_ROOM_BACK - 0.05 - front)


## The floor either side of the working footprint, out to the live room's width, from the footprint's
## front edge to where the back of house begins: for a venue with nothing beside the desk but more of
## itself (a deck, a roof, a plaza), so you can walk round the gear rather than only between it.
func beside_the_desk() -> Array[Rect2]:
	var half := venue.live_room_half()
	var cr := venue.room_width * 0.5
	var z := Studio.ROOM_FRONT + 0.05
	var depth := Studio.ROOM_DEPTH - 0.05
	return [Rect2(-half + 0.05, z, half - cr, depth), Rect2(cr - 0.05, z, half - cr, depth)]


## One floor round everything -- the desk, the zones, the live room -- `margin` past them on every
## side: for a venue with nothing round the room but more open ground, so the zones can be walked
## round and the desk approached from in front. It overlaps the footprint rather than meeting it,
## which Walker.outline takes as floor on both sides.
func open_floor(margin: float) -> Rect2:
	var half := venue.live_room_half() + margin
	var front := Studio.ROOM_FRONT + 0.05 - margin
	return Rect2(-half, front, half * 2.0, Venue.LIVE_ROOM_BACK + margin - front)


## A lit or drawn outline of the working footprint, at floor level, as a set of corners.
func footprint_corners() -> PackedVector2Array:
	var hw := venue.room_width * 0.5 - 0.05
	var front := Studio.ROOM_BACK - 0.05
	var back := Studio.ROOM_FRONT + 0.05
	return PackedVector2Array([Vector2(-hw, back), Vector2(hw, back), Vector2(hw, front),
			Vector2(-hw, front)])


## A mirror in the venue's style, where the venue keeps it. See core/venues/mirror.gd.
func make_mirror(env: Environment) -> Mirror:
	var m := Mirror.new()
	m.name = "Mirror"
	m.rich = venue.rich
	m.environment_from = env
	m.transform = venue.mirror_spot(m.glass_size)
	venue._frame_mirror(m)
	var board := Wardrobe.new()
	board.name = "Wardrobe"
	venue._dress_wardrobe(board)
	board.transform = wardrobe_spot(m)
	m.add_child(board)
	m.wardrobe = board
	return m


## Where the wardrobe board hangs, in the mirror's frame: beside the glass on its +X side, at hand
## height, turned a little toward whoever is standing in front of the glass.
func wardrobe_spot(mirror: Mirror) -> Transform3D:
	var beside := mirror.glass_size.x * 0.5 + 0.34
	var hand := 1.25 - mirror.position.y
	return Transform3D(Basis(Vector3.UP, -0.4), Vector3(beside, hand, 0.06))


## Four bars round the glass, `bar` wide and `depth` deep, set back so their faces sit `proud` in
## front of the glass, and `inset` over its edge. Shared by the venues whose frames are solid.
static func frame_bars(mirror: Mirror, bar: float, depth: float, proud: float,
		material: Material, inset := 0.0) -> void:
	var w := mirror.glass_size.x - inset * 2.0
	var h := mirror.glass_size.y - inset * 2.0
	for spec in [[Vector3(0, (h + bar) * 0.5, 0), Vector3(w + bar * 2.0, bar, depth)],
			[Vector3(0, -(h + bar) * 0.5, 0), Vector3(w + bar * 2.0, bar, depth)],
			[Vector3((w + bar) * 0.5, 0, 0), Vector3(bar, h, depth)],
			[Vector3(-(w + bar) * 0.5, 0, 0), Vector3(bar, h, depth)]]:
		var piece := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = spec[1]
		piece.mesh = box
		piece.material_override = material
		piece.position = spec[0] + Vector3(0, 0, proud - depth * 0.5)
		mirror.add_child(piece)
