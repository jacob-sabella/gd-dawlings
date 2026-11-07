class_name ShellFacts
extends RefCounted

## What a room's shell says about itself, as plain data (docs/layouts.md section 3): the width, the
## walkable floor, the solids, the zone boxes and the named anchors a layout is written against.
## Placement checks need these and nothing else, so they can run without building a room.
##
## `of` reads them from a Venue that has been made but never put in a tree. That works because the
## geometry questions a venue answers (`rooms`, `zones`, `zone_solids`, `live_room_half`, ...) are
## computed from constants, `variant` and `room_width`, not from the nodes `_ready` builds; the
## equivalence test (tests/shell_facts_tests.gd) holds that to account for all 42 venue/arrangement
## combinations, the roulette room and a widened room. No Studio is needed either.

## The anchors a shell provides (section 3), as one pattern: the contract layout files are written to.
const ANCHOR_RE := "^(?:(?:wall|control_wall)\\.(?:left|right)|control_rear|live_back|mix|annex_edge|height\\.table|zone\\.[a-z][a-z0-9_]*(?:\\.(?:cx|cz|min|max|floor))?)$"
const _EPSILON := 1e-5

## The venue's id and arrangement the facts are for.
var venue_id: StringName = &""
var variant := 0
## Studio.room_width: 11.2 at base, growing in 0.8 m steps with the desk.
var room_width := Studio.ROOM_WIDTH
## The working footprint (the control room), as the placement tests measure it: the venue's
## `footprint_corners` bounds.
var footprint := Rect2()
## Venue.rooms(): the walkable floor.
var rooms: Array[Rect2] = []
## Solids that belong to the shell, as walker footprints {c, h, a, top}: the zone solids, the
## venue's instrument and weather, and the door to the roulette room. Not the wheeled pieces, which
## are pieces (Venue.solids() adds them when no trolley stands in for them).
var solids: Array[Dictionary] = []
## Zone id -> AABB (Venue.zones()).
var zones: Dictionary = {}
## Zone id -> the height of the floor at the zone's middle: the top of what a person steps up onto
## there (the drum riser), or 0 (`zone.<id>.floor`).
var zone_floors: Dictionary = {}
var live_room_half := Venue.LIVE_ROOM_HALF
var annex_edge := Venue.LIVE_ROOM_HALF
var has_walls := true
## Venue.ceiling_height(): where a person stops going up.
var ceiling := Venue.LIVE_ROOM_HEIGHT


## True when `name` is an anchor name (the syntax only; whether this shell has it is `anchor`).
static func is_anchor_name(name: String) -> bool:
	return RegEx.create_from_string(ANCHOR_RE).search(name) != null


## Only what the anchors read, from `venue`: its id, arrangement, width, zones, live-room half and
## annex edge. It asks for no solid, so it is safe to call from a placement question (the venue's
## own `default_spot`, which `solids()` itself reaches through the wheeled pieces); `of` is the whole.
static func anchors_of(venue: Venue) -> ShellFacts:
	var f := ShellFacts.new()
	f.venue_id = venue.venue_id()
	f.variant = venue.variant
	f.room_width = venue.room_width
	f.zones = venue.zones()
	var stepped := venue.zone_solids()
	for id: StringName in f.zones:
		var middle := (f.zones[id] as AABB).get_center()
		f.zone_floors[id] = Walker.ground_of(stepped, Vector2(middle.x, middle.z))
	f.live_room_half = venue.live_room_half()
	f.annex_edge = venue.annex_edge()
	return f


## The facts of `venue`, which need not be in a tree (and must not have been given a studio).
static func of(venue: Venue) -> ShellFacts:
	var f := anchors_of(venue)
	var bounds := Rect2()
	for i in venue.footprint_corners().size():
		var corner := venue.footprint_corners()[i]
		bounds = Rect2(corner, Vector2.ZERO) if i == 0 else bounds.expand(corner)
	f.footprint = bounds
	f.rooms = venue.rooms()
	f.solids.assign(_shell_solids(venue))
	f.has_walls = venue.has_walls()
	f.ceiling = venue.ceiling_height()
	return f


## The value of anchor `name`, or null when this shell has no such anchor: a float for a line (a
## wall's x, a back wall's z), a Vector2 for a point (`zone.<id>` is the zone's middle) and for
## `zone.<id>.min|max` its corners; `.cx`, `.cz` and `.floor` (the height of the floor at the zone's
## middle) are floats, as is `height.table` (the bricks table's top, `ZoneKit.TABLE_HEIGHT`).
func anchor(name: StringName) -> Variant:
	var s := String(name)
	if not is_anchor_name(s):
		return null
	match s:
		"wall.left":
			return -live_room_half
		"wall.right":
			return live_room_half
		"control_wall.left":
			return -room_width * 0.5
		"control_wall.right":
			return room_width * 0.5
		"control_rear":
			return Studio.ROOM_BACK
		"live_back":
			return Venue.LIVE_ROOM_BACK
		"mix":
			return Studio.MIX_POSITION_Z
		"annex_edge":
			return annex_edge
		"height.table":
			return ZoneKit.TABLE_HEIGHT
	var parts := s.split(".")
	var box: Variant = zones.get(StringName(parts[1]))
	if box == null:
		return null
	var lo := Vector2((box as AABB).position.x, (box as AABB).position.z)
	var hi := Vector2((box as AABB).end.x, (box as AABB).end.z)
	match parts[2] if parts.size() > 2 else "":
		"cx":
			return (lo.x + hi.x) * 0.5
		"cz":
			return (lo.y + hi.y) * 0.5
		"min":
			return lo
		"max":
			return hi
		"floor":
			return float(zone_floors.get(StringName(parts[1]), 0.0))
	return (lo + hi) * 0.5


## One axis of an anchor: the float itself for a line, the x or z of a point; null when the shell has
## no such anchor. `axis` is "x" or "z".
func anchor_axis(name: StringName, axis: String) -> Variant:
	var a: Variant = anchor(name)
	if a is Vector2:
		return (a as Vector2).x if axis == "x" else (a as Vector2).y
	return a


## Whether an opening `width` wide, its middle at `z`, can be cut through the live room's side wall
## `wall` (`wall.left` or `wall.right`). Every shell cuts what is boxy at the doorway and leaves open
## ground alone (ModularAnnex.cut_the_wall), so the one thing that can say no is the opening not
## lying wholly in the live room's depth, between the control room's rear and the back wall.
func can_cut(wall: StringName, z: float, width: float) -> bool:
	if wall != &"wall.left" and wall != &"wall.right":
		return false
	return z - width * 0.5 >= Studio.ROOM_BACK and z + width * 0.5 <= Venue.LIVE_ROOM_BACK


## Every fact as plain values (rects and boxes as number lists), for comparing and for tools.
func to_dict() -> Dictionary:
	var zone_rows := {}
	for id: StringName in zones:
		var b: AABB = zones[id]
		zone_rows[String(id)] = [b.position.x, b.position.y, b.position.z, b.size.x, b.size.y, b.size.z]
	return {
		"venue_id": String(venue_id), "variant": variant, "room_width": room_width,
		"footprint": _rect(footprint), "rooms": rooms.map(_rect),
		"solids": solids.map(func(s: Dictionary) -> Array:
			return [s["c"].x, s["c"].y, s["h"].x, s["h"].y, s["a"], s["top"]]),
		"zones": zone_rows, "zone_floors": zone_floors.keys().map(func(k: StringName) -> Array: return [String(k), zone_floors[k]]),
		"live_room_half": live_room_half, "annex_edge": annex_edge,
		"has_walls": has_walls, "ceiling": ceiling,
	}


## The names of the facts on which `a` and `b` differ (numbers within 1e-5); empty when equal.
static func differences(a: ShellFacts, b: ShellFacts) -> Array[String]:
	var da := a.to_dict()
	var db := b.to_dict()
	var out: Array[String] = []
	for key: String in da:
		if not _same(da[key], db[key]):
			out.append(key)
	return out


static func _rect(r: Rect2) -> Array:
	return [r.position.x, r.position.y, r.size.x, r.size.y]


## The venue's solids without the pieces: Venue.solids() minus its wheeled solids.
static func _shell_solids(venue: Venue) -> Array:
	var wheeled := venue.wheeled_solids()
	return venue.solids().filter(func(s: Dictionary) -> bool: return not wheeled.has(s))


static func _same(a: Variant, b: Variant) -> bool:
	if a is Array and b is Array:
		return (a as Array).size() == (b as Array).size() and range((a as Array).size()).all(
				func(i: int) -> bool: return _same(a[i], b[i]))
	if a is Dictionary and b is Dictionary:
		return (a as Dictionary).size() == (b as Dictionary).size() and (a as Dictionary).keys().all(
				func(k: Variant) -> bool: return (b as Dictionary).has(k) and _same(a[k], b[k]))
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a) - float(b)) <= _EPSILON
	return a == b
