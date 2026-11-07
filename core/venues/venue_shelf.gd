class_name VenueShelf
extends RefCounted

## Where the things that live on and about the prop shelf are, in studio space: the item spots, the
## headphones, glasses, tablet, chips, cards, cradle, yo-yo, dartboard and darts, and the hoop's
## neighbours (the toy, the radio plane). Every one is the shelf's (or the hoop's) spot with a fixed
## offset from it. Moved out of `core/venues/venue.gd` without change of behaviour; the venue keeps a
## one-line delegate for each name that other files reach (the stations by string, the tests, the
## subclasses).

## Where dart `n` lives: left in the board, along the top of it (the board's x and y).
const DART_HOMES := [Vector2(-0.11, 0.1), Vector2(0.0, 0.135), Vector2(0.11, 0.1)]

var venue: Venue


func _init(of: Venue) -> void:
	venue = of


## Where the items live, one per item (ItemRoom.KINDS) and a few spare: in a row along the shelf's
## top, facing out into the room.
func item_spots() -> Array[Transform3D]:
	var shelf := venue.prop_shelf_spot()
	var out: Array[Transform3D] = []
	# From the middle out, so one item is not left at the end of an empty shelf; the lamp is at
	# the +X end, so that side fills last.
	for i in [1, 0, 2, 3].slice(0, ZoneKit.SHELF_SPOTS):
		var along := (float(i) - (ZoneKit.SHELF_SPOTS - 1) * 0.5) * ZoneKit.SHELF.x / ZoneKit.SHELF_SPOTS
		var at := shelf * Vector3(along, ZoneKit.SHELF.y, 0.04)
		# Facing out of the shelf's front, as an item faces -Z.
		out.append(Transform3D(shelf.basis * Basis(Vector3.UP, PI), at))
	return out


## The shelf's frame turned to face out, moved by `at` (its own x, y up, z toward the room): the
## spot of everything that lies on it.
func _on_shelf(at: Vector3, turn := PI) -> Transform3D:
	return venue.prop_shelf_spot() * Transform3D(Basis(Vector3.UP, turn), at)


## Where the headphones hang: on the hook under the front of the prop shelf (ZoneKit.HEADPHONE_HOOK),
## band over the peg, facing out.
func headphones_spot() -> Transform3D:
	return _on_shelf(ZoneKit.HEADPHONE_HOOK + Vector3(0, -HeadphonesItem.HANG, ZoneKit.HOOK_REACH * 0.55))


## Where the signal glasses lie: folded flat on the prop shelf's top at its front edge, between the
## middle two of its spots, lenses out.
func glasses_spot() -> Transform3D:
	return _on_shelf(Vector3(0.0, ZoneKit.SHELF.y + SignalGlassesItem.RIM_RADIUS, ZoneKit.SHELF.z * 0.5 - 0.07))


## Where the tablet lies: face up on the prop shelf's lower tier, toward the lamp's end and out of
## the headphones' way, its tray toward the back.
func tablet_spot() -> Transform3D:
	return _on_shelf(Vector3(0.17, ZoneKit.SHELF_LOWER_TOP, 0.03), 0.0)


## Where the chips lie: along the front edge of the shelf's top at the ball's end, as they would be
## left on a table. Not in front of a toy: from the seat a toy behind one would be a click on them.
func chips_spot() -> Transform3D:
	return _on_shelf(Vector3(-0.4, ZoneKit.SHELF.y, 0.15))


## Where the cards lie: a little askew at the lamp's end of the shelf's front edge.
func cards_spot() -> Transform3D:
	return _on_shelf(Vector3(0.38, ZoneKit.SHELF.y, 0.13), PI - 0.25)


## Where the Newton's cradle stands: at the back of the shelf's top, in the middle, its row of balls
## along the shelf -- behind the duck and the plane and taller than them, under the shelf lamp.
func cradle_spot() -> Transform3D:
	return _on_shelf(Vector3(-0.04, ZoneKit.SHELF.y, -0.135))


## Where the yo-yo lies: on its side at the front of the shelf's top, between the plane and the cards.
func yoyo_spot() -> Transform3D:
	return _on_shelf(Vector3(0.2, ZoneKit.SHELF.y, 0.15))


## Where the dartboard's face is: its middle, facing out into the room (+Z).
func dartboard_spot() -> Transform3D:
	return _on_shelf(Vector3(0, ZoneKit.DARTBOARD_Y, ZoneKit.DARTBOARD_FACE_Z), 0.0)


## What a dart sticks in (Flight.fly's `boards`): the board, and the cork panel round it.
func dart_boards() -> Array:
	var panel := _on_shelf(Vector3(0, ZoneKit.DARTBOARD_Y, ZoneKit.DART_PANEL_BACK + ZoneKit.DART_PANEL_THICK), 0.0)
	return [{"at": dartboard_spot(), "radius": ZoneKit.DARTBOARD_RADIUS},
			{"at": panel, "half": ZoneKit.DART_PANEL * 0.5}]


## Where dart `n` lives: left in the board, point in and its tail a little down, as darts hang in a
## board between games.
func dart_spot(n: int) -> Transform3D:
	var on: Vector2 = DART_HOMES[n % DART_HOMES.size()]
	return dartboard_spot() * Transform3D(Basis(Vector3.RIGHT, 0.15), Vector3(on.x, on.y, -DartItem.POINT_IN))


## Where the venue's own toy (ToyItem) lies: on the floor a little in front of the hoop and to its
## right, where you would leave a ball after shooting -- room enough round it for the rooftop's beach
## ball, clear of the hoop's base.
func toy_spot() -> Transform3D:
	return venue.hoop_spot() * Transform3D(Basis(Vector3.UP, 0.6), Vector3(0.42, 0, 0.5))


## Where the radio plane (RcPlaneItem) waits: on the floor further out from the hoop than the toy,
## its nose (-Z) pointed back along the open floor away from the control room, so a take-off runs
## down the open floor between the shelf's wall and the hoop's side, not into either.
func rcplane_spot() -> Transform3D:
	var at := venue.hoop_spot() * Vector3(0.55, 0, 1.25)
	return Transform3D(Basis(Vector3.UP, PI if at.z >= Studio.MIX_POSITION_Z else 0.0), at)
