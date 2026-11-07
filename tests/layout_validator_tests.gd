extends RefCounted

## LayoutValidator (docs/layouts.md section 11 step 4), called from the `_test_*` wrappers in
## tests/run_tests.gd: every venue and arrangement, at two widths, stands its layout clear of the
## shell and of itself and reachable from the desk, from ShellFacts and no Studio; and a layout seeded
## with each fault the validator knows is told off by the code for it.

const LayoutResolverTests := preload("res://tests/layout_resolver_tests.gd")
const WIDTHS: Array[float] = [Studio.ROOM_WIDTH, Studio.ROOM_WIDTH + 3.2]
const BASE := {"format": "dawlings.layout", "version": 1, "title": "Seed"}

var t: Node


## A shell whose wall cannot be cut, for `wall_uncuttable`.
class StoneWall extends ShellFacts:
	func can_cut(_wall: StringName, _z: float, _width: float) -> bool:
		return false


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


static func facts_of(id: StringName, variant: int, width: float) -> ShellFacts:
	var venue := Venue.make(id, variant)
	venue.room_width = width
	var facts := ShellFacts.of(venue)
	venue.free()
	return facts


func every_layout_is_valid() -> void:
	var set := LayoutResolverTests.fragments()
	var started := Time.get_ticks_msec()
	var runs := 0
	var warnings := 0
	for width in WIDTHS:
		for combo: Array in LayoutResolverTests.combinations():
			var id: StringName = combo[0]
			var tag := "%s/%d at %.1f m" % [id, combo[1], width]
			var layout := LayoutResolverTests.room(set, id, combo[1], id != Venue.ROULETTE_ID)
			var issues := LayoutValidator.validate(layout, facts_of(id, combo[1], width))
			var errors := issues.filter(func(i: LayoutIssue) -> bool: return i.is_error())
			runs += 1
			warnings += issues.size() - errors.size()
			check("%s: the layout is valid (%s)" % [tag, errors], errors.is_empty())
	check("43 rooms at two widths were checked, in %d ms" % (Time.get_ticks_msec() - started), runs == 86)
	# The roulette room has no zones: its sampler (needs a synth zone) and the four pieces mounted in zones
	# (wheel, sections, drums, looper; step 6 part 2) are left out, at each of the two widths.
	check("the only things left out are the roulette room's sampler and zone-mounted four (%d warnings)" % warnings, warnings == 2 + 8)


## Resolves `body` (merged over the standard live room) as a room called `name`.
func seeded(set: LayoutSet, name: String, body: Dictionary) -> LayoutData:
	var data := BASE.duplicate()
	data["id"] = name
	data["extends"] = ["common.live_room"]
	data.merge(body)
	set.add(LayoutData.parse(data))
	return set.resolve(name)


func codes(issues: Array[LayoutIssue]) -> Array:
	return issues.map(func(i: LayoutIssue) -> StringName: return i.code)


func names_each_seeded_violation() -> void:
	var set := LayoutResolverTests.fragments()
	var roof := facts_of(&"rooftop", 0, Studio.ROOM_WIDTH)
	var seen := {}
	var base := seeded(set, "seed_base", {})
	check("the standard live room on the rooftop has no issue at all (%s)" % [LayoutValidator.validate(base, roof)],
			LayoutValidator.validate(base, roof).is_empty())
	var piece := func(id: String, at: Dictionary) -> Dictionary:
		return {"id": id, "at": at}
	var cases := {
		&"schema": [LayoutData.parse({"format": "dawlings.layout", "version": 1, "id": "bad", "title": "Bad", "pieces": "none"}), roof, {}],
		&"duplicate_id": [LayoutData.parse({"format": "dawlings.layout", "version": 1, "id": "dup", "title": "Dup",
				"pieces": [{"id": "a", "piece": "hoop"}, {"id": "a", "piece": "hoop"}]}), roof, {}],
		&"unknown_piece": [seeded(set, "seed_ghost", {"pieces": [piece.call("hoop", {"frame": "authored:ghost", "local": [0, 0]})]}), roof, {}],
		&"unknown_anchor": [seeded(set, "seed_choir", {"pieces": [piece.call("hoop", {"anchor": {"x": "zone.choir.cx"}})]}), roof, {}],
		&"cycle": [seeded(set, "seed_loop", {"pieces": [piece.call("rack_a", {"frame": "authored:rack_b"}),
				piece.call("rack_b", {"frame": "authored:rack_a"})]}), roof, {}],
		&"over_limit": [seeded(set, "seed_crowd", {"pieces": range(65).map(func(i: int) -> Dictionary:
				return {"id": "stool_%d" % i, "piece": "stool"})}), roof, {}],
		&"off_floor": [seeded(set, "seed_out", {"pieces": [piece.call("hoop", {"anchor": {"x": "wall.left"}, "pos": [-2.0, 9.0], "yaw": 0.0})]}), roof, {}],
		&"hits_solid": [seeded(set, "seed_in_zone", {"pieces": [piece.call("hoop", {"anchor": {"x": "zone.drums.cx", "z": "zone.drums.cz"}, "yaw": 0.0})]}), roof, {}],
		&"too_close": [seeded(set, "seed_close", {"pieces": [piece.call("tour_case", {"frame": "authored:hoop", "local": [1.0, 0.0], "yaw": 0.0})]}), roof, {}],
		&"unreachable": [base, wall_across(), {}],
		&"no_seat": [seeded(set, "seed_facing_wall", {"pieces": [piece.call("cassette_rack", {"anchor": {"x": "wall.left"}, "pos": [0.3, 7.5], "yaw": -PI * 0.5})]}), facts_of(&"studio", 0, Studio.ROOM_WIDTH), {}],
		&"group_spread": [seeded(set, "seed_far", {"groups": [{"id": "far", "title": "FAR", "members": ["hoop", "sampler"]}]}), roof, {}],
		&"needs_missing": [base, facts_of(Venue.ROULETTE_ID, 0, Studio.ROOM_WIDTH), {}],
		&"door_blocked": [seeded(set, "seed_door", {"pieces": [LayoutResolverTests.ANNEX, piece.call("tour_case",
				{"anchor": {"x": "annex_edge"}, "pos": [-1.0, 9.0], "yaw": 0.0})]}), roof, {}],
		&"site_taken": [seeded(set, "seed_two_annexes", {"pieces": [LayoutResolverTests.ANNEX, LayoutResolverTests.ANNEX.merged({"id": "annex_two"}, true)]}), roof, {}],
		&"wall_uncuttable": [seeded(set, "seed_stone", {"pieces": [LayoutResolverTests.ANNEX]}), stone(), {}],
		&"unavailable_mod": [base, roof, {"unavailable": [&"sampler"]}],
	}
	for code: StringName in cases:
		var c: Array = cases[code]
		var issues := LayoutValidator.validate(c[0], c[1], c[2])
		var hit := issues.filter(func(i: LayoutIssue) -> bool: return i.code == code)
		seen[code] = not hit.is_empty()
		check("%s is raised, in a sentence (%s)" % [code, hit[0] if not hit.is_empty() else codes(issues)],
				not hit.is_empty() and not (hit[0] as LayoutIssue).message.is_empty())
	for code in LayoutIssue.CODES:
		check("a seeded violation exists for %s" % code, seen.get(code, false))
	var severities := {}
	for code: StringName in cases:
		for i in LayoutValidator.validate(cases[code][0], cases[code][1], cases[code][2]):
			severities[i.code] = i.severity
	check("only the group, the missing zone and the missing mod are warnings", [&"group_spread", &"needs_missing", &"unavailable_mod"].all(
			func(c: StringName) -> bool: return severities[c] == LayoutIssue.WARNING) and [&"off_floor", &"hits_solid", &"too_close", &"unreachable",
			&"no_seat", &"door_blocked", &"site_taken", &"wall_uncuttable", &"schema"].all(func(c: StringName) -> bool: return severities[c] == LayoutIssue.ERROR))
	check("a piece of a kind nothing is known of is a warning, not checked", codes(LayoutValidator.validate(seeded(set, "seed_mystery",
			{"pieces": [{"id": "stool", "piece": "stool", "at": {"anchor": {"x": "wall.left"}, "pos": [1.0, 6.0]}}]}), roof)) == [&"unknown_piece"])
	fixes_and_pieces(set, roof, piece)


func fixes_and_pieces(set: LayoutSet, roof: ShellFacts, piece: Callable) -> void:
	var shelf := seeded(set, "seed_overlap", {"pieces": [piece.call("hoop", {"anchor": {"x": "zone.drums.cx", "z": "zone.drums.cz"}, "yaw": -PI * 0.5})]})
	var issues := LayoutValidator.validate(shelf, roof, {"fix": true})
	var fixed := issues.filter(func(i: LayoutIssue) -> bool: return i.piece == &"hoop" and not i.fix.is_empty())
	check("with fixes asked for, a placement issue carries the nearest clear point (%s)" % [issues], not fixed.is_empty())
	if not fixed.is_empty():
		var pos: Array = fixed[0].fix["pos"]
		var moved := seeded(set, "seed_moved", {"pieces": [piece.call("hoop", {"pos": pos, "yaw": -PI * 0.5})]})
		var left := LayoutValidator.validate(moved, roof).filter(func(i: LayoutIssue) -> bool: return i.is_error())
		check("and standing the piece there clears it (%s)" % [left], left.is_empty())
	check("without them it has none", LayoutValidator.validate(shelf, roof).all(func(i: LayoutIssue) -> bool: return i.fix.is_empty()))
	check("an edit-mode ghost sees the issues of its own piece and not of others'",
			not LayoutValidator.validate_piece(shelf, &"hoop", roof).is_empty()
			and LayoutValidator.validate_piece(shelf, &"prop_shelf", roof, {"reach": false}).all(func(i: LayoutIssue) -> bool: return i.other == &"prop_shelf"))
	check("nothing is nearest-clear for a piece that is not there", LayoutValidator.nearest_clear(shelf, &"nobody", Vector2.ZERO, roof) == null)
	var stacked := LayoutValidator.validate(shelf, roof, {"reach": false})
	check("the walkway grid can be skipped, the rest still runs", codes(stacked).has(&"hits_solid"))


## The rooftop with a wall of solid across the live room at z = 8.2, 10 m wide and 2 m high.
func wall_across() -> ShellFacts:
	var f := facts_of(&"rooftop", 0, Studio.ROOM_WIDTH)
	f.solids.append({"c": Vector2(0.0, 8.2), "h": Vector2(9.0, 0.1), "a": 0.0, "top": 2.0})
	return f


func stone() -> ShellFacts:
	var real := facts_of(&"rooftop", 0, Studio.ROOM_WIDTH)
	var f := StoneWall.new()
	for prop in ["room_width", "footprint", "rooms", "solids", "zones", "live_room_half", "annex_edge", "has_walls", "ceiling"]:
		f.set(prop, real.get(prop))
	return f
