class_name LayoutChecks
extends RefCounted

## The placement rules of docs/layouts.md section 6, one function each, over pieces already stood on
## the floor (`LayoutValidator` does that): on the floor, clear of solids and zones, apart from each
## other, a seat to stand at, reachable from the mixing position, and the claims of a room-scale piece.
## A placed piece is `{id, kind, spot, fp (footprint), quad, at (Vector2)}`.

## No two pieces stand closer than this (m): tests/run_tests.gd ROOM_CLEAR.
const ROOM_CLEAR := 0.6
## The walkway kept to every seat and every zone (m): tests/run_tests.gd WALKWAY.
const WALKWAY := 0.9


## A piece's name in a sentence.
static func name_of(id: Variant) -> String:
	return String(id).replace("_", " ")


## `off_floor`: every corner of the footprint on a walkable rectangle.
static func off_floor(p: Dictionary, floor: Array[Rect2]) -> LayoutIssue:
	for corner: Vector2 in p["quad"]:
		if not LayoutGeometry.on_floor(floor, corner):
			return LayoutIssue.make(&"off_floor", LayoutIssue.ERROR, p["id"], &"", corner,
					"The %s is not all on the floor." % name_of(p["id"]))
	return null


## `hits_solid`: the footprint overlaps a shell solid, a zone's ground or the control room.
static func hits_solid(p: Dictionary, facts: ShellFacts) -> LayoutIssue:
	var quad: PackedVector2Array = p["quad"]
	for s: Dictionary in facts.solids:
		if LayoutGeometry.gap(quad, LayoutGeometry.corners(s)) < 0.0:
			return LayoutIssue.make(&"hits_solid", LayoutIssue.ERROR, p["id"], &"solid", s["c"],
					"The %s is standing in something solid." % name_of(p["id"]))
	for zone_id: StringName in facts.zones:
		var box: AABB = facts.zones[zone_id]
		var plan := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
		if LayoutGeometry.gap(quad, LayoutGeometry.rect_corners(plan)) < 0.0:
			return LayoutIssue.make(&"hits_solid", LayoutIssue.ERROR, p["id"], StringName("zone." + zone_id), plan.get_center(),
					"The %s is standing in the %s space." % [name_of(p["id"]), zone_id])
	if LayoutGeometry.gap(quad, LayoutGeometry.rect_corners(facts.footprint)) < 0.0:
		return LayoutIssue.make(&"hits_solid", LayoutIssue.ERROR, p["id"], &"control_room", p["at"],
				"The %s is standing in the control room." % name_of(p["id"]))
	return null


## `too_close` between two placed pieces.
static func too_close(a: Dictionary, b: Dictionary) -> LayoutIssue:
	var g := LayoutGeometry.gap(a["quad"], b["quad"])
	if g >= ROOM_CLEAR:
		return null
	return LayoutIssue.make(&"too_close", LayoutIssue.ERROR, a["id"], b["id"], (a["at"] + b["at"]) * 0.5,
			"The %s is %.1f m from the %s; they need %.1f m." % [name_of(a["id"]), maxf(g, 0.0), name_of(b["id"]), ROOM_CLEAR])


## `too_close` between a placed piece and a shell solid, but for what is stood on (a riser) and what
## stands in the same zone as the piece (one activity's own furniture).
static func too_close_solid(p: Dictionary, s: Dictionary, facts: ShellFacts) -> LayoutIssue:
	var top: float = s.get("top", Walker.SOLID_HEIGHT)
	if top >= 0.0 and top <= Walker.STEP_HEIGHT:
		return null
	var zone := zone_of(facts, p["at"])
	if zone != &"" and zone == zone_of(facts, s["c"]):
		return null
	var g := LayoutGeometry.gap(p["quad"], LayoutGeometry.corners(s))
	if g >= ROOM_CLEAR:
		return null
	return LayoutIssue.make(&"too_close", LayoutIssue.ERROR, p["id"], &"solid", s["c"],
			"The %s is %.1f m from something solid; it needs %.1f m." % [name_of(p["id"]), maxf(g, 0.0), ROOM_CLEAR])


## The id of the zone whose ground holds `c`, or empty.
static func zone_of(facts: ShellFacts, c: Vector2) -> StringName:
	for zone_id: StringName in facts.zones:
		var b: AABB = facts.zones[zone_id]
		if Rect2(b.position.x, b.position.z, b.size.x, b.size.z).has_point(c):
			return zone_id
	return &""


## The seat of a station piece: Stations.seat's search (the far point first, then nearer, then
## either side) for a spot a person fits at, facing the piece; null if none, or if there is no
## room to stand at its front. `station` is PieceFeet.station.
static func seat_for(p: Dictionary, station: Dictionary, floor: Array[Rect2], solids: Array) -> Variant:
	var spot: Transform3D = p["spot"]
	var foot: Vector2 = station["foot"]
	var front := spot * Vector3(0, 0, station["foot_z"] + foot.y + Walker.RADIUS + 0.12)
	if not LayoutGeometry.fits(Vector2(front.x, front.z), floor, solids):
		return null
	for side in [0.0, 0.15, -0.15, 0.3, -0.3, 0.45, -0.45]:
		var d: float = station["seat"]
		while d >= Stations.NEAREST - 0.001:
			var at := spot * Vector3(side, 0, d)
			if LayoutGeometry.fits(Vector2(at.x, at.z), floor, solids):
				return Vector2(at.x, at.z)
			d -= 0.05
	return null


## Every `unreachable` among `seats` (id -> Vector2) and the zones of `facts`, from the mixing
## position over `floor` less `solids`, down a WALKWAY walkway.
static func unreachable(seats: Dictionary, facts: ShellFacts, floor: Array[Rect2], solids: Array) -> Array[LayoutIssue]:
	var out: Array[LayoutIssue] = []
	var grid := LayoutReach.build(floor, solids, WALKWAY * 0.5)
	grid.flood(Vector2(0.0, Studio.MIX_POSITION_Z))
	for id: StringName in seats:
		if not grid.reached(seats[id], 0.5):
			out.append(LayoutIssue.make(&"unreachable", LayoutIssue.ERROR, id, &"", seats[id],
					"There is no %.1f m walkway from the desk to the %s." % [WALKWAY, name_of(id)]))
	for zone_id: StringName in facts.zones:
		var b: AABB = facts.zones[zone_id]
		var plan := Rect2(b.position.x, b.position.z, b.size.x, b.size.z)
		if not grid.reached_box(plan, WALKWAY):
			out.append(LayoutIssue.make(&"unreachable", LayoutIssue.ERROR, StringName("zone." + zone_id), &"",
					plan.get_center(), "There is no %.1f m walkway from the desk to the %s space." % [WALKWAY, zone_id]))
	return out


## The claims of room-scale pieces (`rooms`: the placed ones, `{id, kind, edge}`), against each other, the shell
## and what stands in front of the doorway (`placed`, and the shell's solids).
static func claims(rooms: Array, placed: Array, facts: ShellFacts) -> Array[LayoutIssue]:
	var out: Array[LayoutIssue] = []
	for i in rooms.size():
		var r: Dictionary = rooms[i]
		var c := PieceFeet.claims(r["kind"], r["edge"])
		var site: Rect2 = c["site"]
		for j in i:
			if site.intersects(PieceFeet.claims(rooms[j]["kind"], rooms[j]["edge"])["site"]):
				out.append(LayoutIssue.make(&"site_taken", LayoutIssue.ERROR, r["id"], rooms[j]["id"], site.get_center(),
						"The %s would stand where the %s already does." % [name_of(r["id"]), name_of(rooms[j]["id"])]))
		var doorway := Vector2(r["edge"], c["door_z"])
		if not facts.can_cut(&"wall.right", c["door_z"], c["door_width"]):
			out.append(LayoutIssue.make(&"wall_uncuttable", LayoutIssue.ERROR, r["id"], &"", doorway,
					"A doorway cannot be cut in the wall for the %s here." % name_of(r["id"])))
		var walk: Rect2 = c["door_walk"]
		for p: Dictionary in placed:
			if LayoutGeometry.gap(p["quad"], LayoutGeometry.rect_corners(walk)) < 0.0:
				out.append(LayoutIssue.make(&"door_blocked", LayoutIssue.ERROR, r["id"], p["id"], p["at"],
						"The %s stands in the way of the %s's doorway." % [name_of(p["id"]), name_of(r["id"])]))
		for s: Dictionary in facts.solids:
			if s.get("top", Walker.SOLID_HEIGHT) > Walker.STEP_HEIGHT and LayoutGeometry.gap(LayoutGeometry.corners(s), LayoutGeometry.rect_corners(walk)) < 0.0:
				out.append(LayoutIssue.make(&"door_blocked", LayoutIssue.ERROR, r["id"], &"solid", s["c"],
						"Something solid stands in the way of the %s's doorway." % name_of(r["id"])))
	return out
