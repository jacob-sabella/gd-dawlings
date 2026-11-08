class_name LayoutValidator
extends RefCounted

## Checks a resolved layout against a shell without building a room (docs/layouts.md section 6): the
## clear-of-each-other and reachable-from-the-middle guarantees the placement tests make with a whole
## Studio (`_test_every_venue_stands_every_station_clear`, `..._keeps_its_pieces_apart_and_every_station_in_reach`),
## from a LayoutData and ShellFacts alone. Pure: layout and facts in, LayoutIssues out, nothing mutated.
##
## What it knows is what the layout and the facts hold. The control room's furniture (the desk, the
## trolleys inside the footprint), the props with homes of their own (the toy, the mic stand) and the
## pieces that are not in a layout yet (the zone-mounted stations) are not in either, so the Studio tests
## stay beside it until they are (queue step 6). Zones stand in for the stations mounted in them:
## each must have a walkway up to it.
##
## `opts`: `unavailable` (Array of piece kinds whose mod is missing: a warning each, the piece stays),
## `fix` (true: give each placement issue the nearest clear floor point in `fix`), `reach` (false: skip
## the walkway grid, the one slow check; default true).


## Every issue of `layout` (resolved by LayoutSet.resolve) against `facts`, errors first as found.
## A layout that did not resolve gives its structural issues only.
static func validate(layout: LayoutData, facts: ShellFacts, opts: Dictionary = {}) -> Array[LayoutIssue]:
	var out := structure(layout)
	if layout.status != LayoutData.STATUS_OK:
		return out
	out.append_array(_skipped(layout, facts))
	out.append_array(LayoutChecks.zones_apart(facts))
	var placed := _placed(layout, facts, out, opts)
	var floor := walkable(layout, facts)
	for p: Dictionary in placed:
		_add(out, LayoutChecks.off_floor(p, floor))
		_add(out, LayoutChecks.hits_solid(p, facts))
	for i in placed.size():
		for j in range(i + 1, placed.size()):
			_add(out, LayoutChecks.too_close(placed[i], placed[j]))
		for s: Dictionary in facts.solids:
			_add(out, LayoutChecks.too_close_solid(placed[i], s, facts))
	out.append_array(_groups(layout, placed))
	out.append_array(LayoutChecks.claims(_room_scale(layout, facts), placed, facts))
	if opts.get("reach", true):
		out.append_array(_walkways(placed, facts, floor))
	else:
		out.append_array(_seats(placed, floor, _solids(placed, facts)).issues)
	if opts.get("fix", false):
		for issue in out:
			if issue.piece != &"" and issue.code in [&"off_floor", &"hits_solid", &"too_close"]:
				var near: Variant = nearest_clear(layout, issue.piece, issue.at, facts)
				if near != null:
					issue.fix = {"pos": [(near as Vector2).x, (near as Vector2).y]}
	return out


## The issues that involve piece `id` (as the offender or the one it clashes with): what an edit-mode
## ghost shows while it is dragged. Same inputs as `validate`; pass `reach: false` to skip the grid.
static func validate_piece(layout: LayoutData, id: StringName, facts: ShellFacts, opts: Dictionary = {}) -> Array[LayoutIssue]:
	var out: Array[LayoutIssue] = []
	for issue in validate(layout, facts, opts):
		if issue.piece == id or issue.other == id:
			out.append(issue)
	return out


## The nearest floor point to `wanted`, within 3 m, where piece `id` (turned as it is placed) would be
## on the floor, clear of the solids, the zones and the other pieces. Null if there is none, or the
## piece has no known footprint.
static func nearest_clear(layout: LayoutData, id: StringName, wanted: Vector2, facts: ShellFacts) -> Variant:
	var placed := _placed(layout, facts, [], {})
	var mine := placed.filter(func(p: Dictionary) -> bool: return p["id"] == id)
	if mine.is_empty():
		return null
	var floor := walkable(layout, facts)
	var spot: Transform3D = mine[0]["spot"]
	for ring in range(0, 31):
		var count := maxi(1, ring * 6)
		for k in count:
			var at := wanted + Vector2.from_angle(TAU * k / count) * ring * 0.1
			var moved := _stand(id, mine[0]["kind"], Transform3D(spot.basis, Vector3(at.x, 0, at.y)))
			if _clear(moved, placed.filter(func(p: Dictionary) -> bool: return p["id"] != id), facts, floor):
				return at
	return null


## The parser's own problems as issues (the codes `schema`, `duplicate_id`, `unknown_piece`,
## `unknown_anchor`, `cycle`, `over_limit`) plus `unknown_anchor` for a zone no shell has.
static func structure(layout: LayoutData) -> Array[LayoutIssue]:
	var out: Array[LayoutIssue] = []
	for prob in layout.problems:
		var code: StringName = prob.code if prob.code in [&"duplicate_id", &"unknown_piece", &"unknown_anchor", &"cycle", &"over_limit"] else &"schema"
		out.append(LayoutIssue.make(code, LayoutIssue.ERROR if prob.is_error() else LayoutIssue.WARNING, &"", &"", Vector2.ZERO,
				"%s: %s" % [prob.where, prob.message] if prob.where != "" else prob.message))
	if layout.status == LayoutData.STATUS_OK:
		for piece: Dictionary in layout.pieces():
			for axis: String in piece.get("at", {}).get("anchor", {}):
				var name: String = piece["at"]["anchor"][axis]
				if name.begins_with("zone.") and not StringName(name.split(".")[1]) in Venue.ZONE_IDS:
					out.append(LayoutIssue.make(&"unknown_anchor", LayoutIssue.ERROR, piece["id"], &"", Vector2.ZERO,
							"The %s is placed by '%s', but there is no such zone." % [LayoutChecks.name_of(piece["id"]), name]))
	return out


## The floor a person can walk: the control room's footprint, the shell's rooms and, when the
## layout has the modular room, its floor and the passage to it.
static func walkable(layout: LayoutData, facts: ShellFacts) -> Array[Rect2]:
	var out: Array[Rect2] = [facts.footprint]
	out.append_array(facts.rooms)
	for r in _room_scale(layout, facts):
		out.append_array(ModularAnnex.floors(r["edge"], facts.live_room_half))
	return out


## The pieces a layout stands, with their footprints (see LayoutChecks). Pieces whose kind has no
## known footprint get a warning in `issues`; pieces the shell cannot place (`_skipped`) are left out.
static func _placed(layout: LayoutData, facts: ShellFacts, issues: Array, opts: Dictionary) -> Array:
	var out: Array = []
	var missing: Array = opts.get("unavailable", [])
	var count := {}
	for piece: Dictionary in layout.pieces():
		var id := StringName(piece["id"])
		var kind := StringName(piece.get("piece", ""))
		var spot: Variant = LayoutResolver.transform(layout, id, facts)
		count[kind] = count.get(kind, 0) + 1
		var limit := PieceFeet.limit(kind)
		if limit > 0 and count[kind] == limit + 1:
			issues.append(LayoutIssue.make(&"over_limit", LayoutIssue.ERROR, id, &"", Vector2.ZERO,
					"A room holds only %d %s." % [limit, LayoutChecks.name_of(kind)]))
		if kind in missing:
			issues.append(LayoutIssue.make(&"unavailable_mod", LayoutIssue.WARNING, id, &"", Vector2.ZERO,
					"The %s needs a mod that is not installed; it stays where it is." % LayoutChecks.name_of(kind)))
		if spot == null or kind == PieceFeet.ANNEX:
			continue
		if PieceFeet.mounted(kind):
			continue
		if not PieceFeet.known(kind):
			if kind not in missing:
				issues.append(LayoutIssue.make(&"unknown_piece", LayoutIssue.WARNING, id, &"", Vector2.ZERO,
						"Nothing is known of the %s's size, so it is not checked." % LayoutChecks.name_of(kind)))
			continue
		out.append(_stand(id, kind, spot))
	return out


static func _stand(id: StringName, kind: StringName, spot: Transform3D) -> Dictionary:
	var fp := PieceFeet.footprint(kind, spot)
	return {"id": id, "kind": kind, "spot": spot, "fp": fp, "quad": LayoutGeometry.corners(fp),
			"at": Vector2(spot.origin.x, spot.origin.z)}


## `needs_missing`: a piece that has an `at` but no place here, because the zone its anchor names (or
## the piece whose frame it is in) is not in this shell. It is skipped, which is a warning, not an error.
static func _skipped(layout: LayoutData, facts: ShellFacts) -> Array[LayoutIssue]:
	var out: Array[LayoutIssue] = []
	for piece: Dictionary in layout.pieces():
		if not piece.get("at") is Dictionary or LayoutResolver.transform(layout, StringName(piece["id"]), facts) != null:
			continue
		var root := _root_cause(layout, piece, facts)
		if root != "":
			out.append(LayoutIssue.make(&"needs_missing", LayoutIssue.WARNING, piece["id"], StringName(root), Vector2.ZERO,
					"The %s needs the %s, which this room has not; it is left out." % [LayoutChecks.name_of(piece["id"]), root.trim_prefix("zone.")]))
	return out


## The name of the anchor (or the piece, via frames) that leaves `piece` unplaced, or "" if it is none of those.
static func _root_cause(layout: LayoutData, piece: Dictionary, facts: ShellFacts, depth := 0) -> String:
	var at: Dictionary = piece["at"]
	if at.has("frame") and depth < 16:
		var next := layout.piece(StringName((at["frame"] as String).trim_prefix("authored:")))
		return _root_cause(layout, next, facts, depth + 1) if next.get("at") is Dictionary else ""
	for axis: String in at.get("anchor", {}):
		var name: String = at["anchor"][axis]
		if facts.anchor_axis(StringName(name), axis) == null:
			return "zone." + name.split(".")[1] if name.begins_with("zone.") else name
	return ""


## The room-scale pieces: `{id, kind, edge}` where `edge` is the x of their anchor.
static func _room_scale(layout: LayoutData, facts: ShellFacts) -> Array:
	var out: Array = []
	for piece: Dictionary in layout.pieces():
		if piece.get("piece") == String(PieceFeet.ANNEX):
			var spot: Variant = LayoutResolver.transform(layout, StringName(piece["id"]), facts)
			if spot != null:
				out.append({"id": StringName(piece["id"]), "kind": PieceFeet.ANNEX, "edge": (spot as Transform3D).origin.x})
	return out


## `group_spread`: members of a group stand within Neighbourhoods.RADIUS of the middle of the box
## round them (Neighbourhoods.middle). Members with no place are not counted.
static func _groups(layout: LayoutData, placed: Array) -> Array[LayoutIssue]:
	var out: Array[LayoutIssue] = []
	for g: Dictionary in layout.body.get("groups", []):
		var mine := placed.filter(func(p: Dictionary) -> bool: return String(p["id"]) in g.get("members", []))
		if mine.is_empty():
			continue
		var box := Rect2(mine[0]["at"], Vector2.ZERO)
		for p: Dictionary in mine:
			box = box.expand(p["at"])
		for p: Dictionary in mine:
			var far: float = (p["at"] as Vector2).distance_to(box.get_center())
			if far > Neighbourhoods.RADIUS:
				out.append(LayoutIssue.make(&"group_spread", LayoutIssue.WARNING, p["id"], StringName(g["id"]), p["at"],
						"The %s is %.1f m from the middle of %s; %.1f m is the most." % [LayoutChecks.name_of(p["id"]), far,
						g.get("title", g["id"]), Neighbourhoods.RADIUS]))
	return out


## What blocks a person: the shell's solids and the pieces' footprints.
static func _solids(placed: Array, facts: ShellFacts) -> Array:
	var out: Array = facts.solids.duplicate()
	for p: Dictionary in placed:
		out.append(p["fp"])
	return out


## The seat of every station piece: `.seats` (id -> point) and `.issues` (`no_seat`).
static func _seats(placed: Array, floor: Array[Rect2], solids: Array) -> Dictionary:
	var seats := {}
	var issues: Array[LayoutIssue] = []
	for p: Dictionary in placed:
		var station := PieceFeet.station(p["kind"])
		if station.is_empty():
			continue
		var seat: Variant = LayoutChecks.seat_for(p, station, floor, solids)
		if seat == null:
			issues.append(LayoutIssue.make(&"no_seat", LayoutIssue.ERROR, p["id"], &"", p["at"],
					"There is no room to stand at the %s." % LayoutChecks.name_of(p["id"])))
		else:
			seats[p["id"]] = seat
	return {"seats": seats, "issues": issues}


static func _walkways(placed: Array, facts: ShellFacts, floor: Array[Rect2]) -> Array[LayoutIssue]:
	var solids := _solids(placed, facts)
	var found := _seats(placed, floor, solids)
	var out: Array[LayoutIssue] = found["issues"]
	out.append_array(LayoutChecks.unreachable(found["seats"], facts, floor, solids))
	return out


static func _clear(p: Dictionary, others: Array, facts: ShellFacts, floor: Array[Rect2]) -> bool:
	if LayoutChecks.off_floor(p, floor) != null or LayoutChecks.hits_solid(p, facts) != null:
		return false
	for o: Dictionary in others:
		if LayoutChecks.too_close(p, o) != null:
			return false
	for s: Dictionary in facts.solids:
		if LayoutChecks.too_close_solid(p, s, facts) != null:
			return false
	return true


static func _add(out: Array[LayoutIssue], issue: LayoutIssue) -> void:
	if issue != null:
		out.append(issue)
