class_name RoomFloor
extends RefCounted

## The studio's trolleys and the room's delta (docs/layouts.md 7): what `Studio` asks to say where the
## room's furniture stands for the `layout` row of the room state, to follow a row the host sent, and
## whether a settled piece is at its default. Kept out of studio.gd; it reads the studio's floor plan,
## authored spots and live pieces.


## The trolleys that belong to the room: not a player's own stand or rack, not a niche built into the wall.
static func room_pieces(studio: Studio) -> Array[Trolley]:
	var out: Array[Trolley] = []
	if studio.floor_plan == null:
		return out
	for piece in studio.floor_plan.pieces:
		var t := piece as Trolley
		if t != null and is_instance_valid(t) and not t.built_in and not RoomDelta.owned_by_player(t.piece_id):
			out.append(t)
	return out


## Where the room stands piece `id` before anyone moves it, in the set's frame; null where it has no
## room for it (the sampler in a room without a synth zone) or no default (a piece built into the wall).
static func default_of(studio: Studio, id: StringName) -> Variant:
	if studio.live_pieces.has(id):
		return studio.furniture_host._live_default(id)
	return studio._authored_floor.get(id)


## Whether `piece` stands where the room stands it, as near as the floor plan lets it be (the default may
## be a wall the plan moves it off).
static func at_default(studio: Studio, piece: Trolley) -> bool:
	var spot: Variant = default_of(studio, piece.piece_id)
	if spot == null:
		return false
	var at := Vector2((spot as Transform3D).origin.x, (spot as Transform3D).origin.z)
	var heading := ControlRoom.heading(spot)
	if absf(wrapf(piece.rotation.y - heading, -PI, PI)) > 0.002:
		return false
	var here := Vector2(piece.position.x, piece.position.z)
	if here.distance_to(at) < 0.005:
		return true
	return studio.floor_plan != null and here.distance_to(studio.floor_plan.resolve(piece, at, heading)["at"]) < 0.005


## The `layout` row of the room state: the host's delta, with every trolley now standing off its default
## as `moved` too (a piece the floor plan settled elsewhere is the room's as it stands, whoever pushed it).
static func row(studio: Studio) -> Dictionary:
	var delta := studio.room_deltas.delta
	var out := delta.to_dict(false)
	var moved: Dictionary = out["moved"]
	for t in room_pieces(studio):
		if delta.is_removed(t.piece_id):
			continue
		var copy := delta.added_index(t.piece_id)
		if copy >= 0:
			# A copy the room added carries its own spot.
			out["added"][copy]["at"] = {"pos": [t.position.x, t.position.z], "yaw": t.rotation.y}
		elif not at_default(studio, t):
			moved[String(t.piece_id)] = [t.position.x, t.position.z, t.rotation.y]
		elif default_of(studio, t.piece_id) != null:
			moved.erase(String(t.piece_id))
	return out


## Put every trolley of the room where the (adopted) delta has it, or where the room stands it, unless
## a hand here has hold of it or its own push has not been answered yet (`pending`, a set of ids).
static func follow(studio: Studio, pending: Dictionary, glide: bool) -> void:
	RoomSync.sync(studio)
	for t in room_pieces(studio):
		if pending.has(t.piece_id):
			continue
		var spot: Variant = studio.room_deltas.saved(t.piece_id, null)
		if spot == null:
			spot = default_of(studio, t.piece_id)
		if spot != null:
			studio.room_rows._follow_room(t, (spot as Transform3D).origin.x, (spot as Transform3D).origin.z, ControlRoom.heading(spot), glide)
