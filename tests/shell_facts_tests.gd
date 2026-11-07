extends RefCounted

## ShellFacts (docs/layouts.md section 3 and 11 step 2), called from the `_test_*` wrappers in
## tests/run_tests.gd: the facts read from a venue that was never readied equal the ones read from the
## built venue, for every venue and arrangement, the roulette room and a widened room; the anchors
## have the values the placement code uses today.

const WIDTHS: Array[float] = [Studio.ROOM_WIDTH, Studio.ROOM_WIDTH + 3.2]

var t: Node


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


## Every venue id with its arrangements, the roulette room last: 14 x 3 + 1.
func combinations() -> Array:
	var out: Array = []
	for id in Venue.IDS:
		for v in Venue.variant_titles(id).size():
			out.append([id, v])
	out.append([Venue.ROULETTE_ID, 0])
	return out


## The facts of a venue made and measured at once, never put in a tree, then thrown away.
func unreadied(id: StringName, variant: int, width: float) -> ShellFacts:
	var venue := Venue.make(id, variant)
	venue.room_width = width
	var facts := ShellFacts.of(venue)
	var bare := venue.get_child_count() == 0 and not venue.is_inside_tree()
	venue.free()
	check("%s/%d: measuring a venue builds nothing" % [id, variant], bare)
	return facts


func equivalence() -> void:
	var combos := combinations()
	check("there are 42 venue/arrangement combinations and the roulette room", combos.size() == 43)
	var with_solids := 0
	for width in WIDTHS:
		for combo: Array in combos:
			var id: StringName = combo[0]
			var tag := "%s/%d at %.1f m" % [id, combo[1], width]
			var bare := unreadied(id, combo[1], width)
			var venue := Venue.make(id, combo[1])
			venue.room_width = width
			t.add_child(venue)
			var built := ShellFacts.of(venue)
			var diff := ShellFacts.differences(bare, built)
			check("%s: the unreadied facts equal the built ones (differ on %s)" % [tag, diff], diff.is_empty())
			check("%s: and say something" % tag, bare.rooms.size() >= 1 and bare.live_room_half > 5.0 and bare.footprint.size.x > 10.0
					and bare.zones.size() == (0 if id == Venue.ROULETTE_ID else Venue.ZONE_IDS.size()))
			with_solids += 1 if not bare.solids.is_empty() else 0
			venue.queue_free()
	check("nearly every shell has solids to compare, so equal is not empty (%d of 86)" % with_solids, with_solids >= 80)
	var a := unreadied(&"rooftop", 0, Studio.ROOM_WIDTH)
	var b := unreadied(&"rooftop", 0, Studio.ROOM_WIDTH)
	check("facts are repeatable", ShellFacts.differences(a, b).is_empty() and a.to_dict() == b.to_dict())
	check("a wider room is a different set of facts", ShellFacts.differences(a, unreadied(&"rooftop", 0, WIDTHS[1])).has("live_room_half"))
	check("another arrangement is a different set of facts", ShellFacts.differences(
			unreadied(&"studio", 0, Studio.ROOM_WIDTH), unreadied(&"studio", 1, Studio.ROOM_WIDTH)).has("rooms"))
	var moved := unreadied(&"rooftop", 0, Studio.ROOM_WIDTH)
	moved.zones[&"synth"] = AABB(Vector3(7.9, 0, 10.1), Vector3(0.8, 2.0, 2.0))
	moved.solids.append({"c": Vector2.ZERO, "h": Vector2.ONE, "a": 0.0, "top": 1.0})
	check("differences names what changed, within a tolerance", ShellFacts.differences(a, moved) == ["solids", "zones"]
			and ShellFacts.differences(a, a) == [])


## The facts of the venue a real Studio built (it has trolleys, a parent and its own width).
func in_a_studio() -> void:
	DAW.use(OfflineBackend.new())
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	t.add_child(studio)
	for combo: Array in combinations():
		var id: StringName = combo[0]
		studio.set_venue(id, false, combo[1])
		var built := ShellFacts.of(studio.venue)
		var bare := unreadied(id, combo[1], studio.venue.room_width)
		var diff := ShellFacts.differences(bare, built)
		check("%s/%d: a venue standing in a studio has the unreadied facts (differ on %s)" % [id, combo[1], diff], diff.is_empty())
	studio.queue_free()


func anchors() -> void:
	var roof := unreadied(&"rooftop", 0, Studio.ROOM_WIDTH)
	check("the side walls are the live room's half-width", is_equal_approx(roof.anchor(&"wall.left"), -8.8) and is_equal_approx(roof.anchor(&"wall.right"), 8.8))
	check("the control room's walls, its rear, the live room's back and the mix position", is_equal_approx(roof.anchor(&"control_wall.left"), -5.6)
			and is_equal_approx(roof.anchor(&"control_wall.right"), 5.6) and roof.anchor(&"control_rear") == Studio.ROOM_BACK
			and roof.anchor(&"live_back") == Venue.LIVE_ROOM_BACK and roof.anchor(&"mix") == Studio.MIX_POSITION_Z)
	check("a zone is a point, a centre line or a corner", roof.anchor(&"zone.synth").is_equal_approx(Vector2(8.3, 11.0))
			and is_equal_approx(roof.anchor(&"zone.synth.cx"), 8.3) and is_equal_approx(roof.anchor(&"zone.synth.cz"), 11.0)
			and roof.anchor(&"zone.synth.min").is_equal_approx(Vector2(7.9, 10.0)) and roof.anchor(&"zone.synth.max").is_equal_approx(Vector2(8.7, 12.0)))
	check("an axis of an anchor is the float itself or a point's x or z", is_equal_approx(roof.anchor_axis(&"zone.synth", "x"), 8.3)
			and is_equal_approx(roof.anchor_axis(&"zone.synth", "z"), 11.0) and is_equal_approx(roof.anchor_axis(&"wall.left", "x"), -8.8))
	check("a venue with its walls further out says so: annex_edge", is_equal_approx(roof.anchor(&"annex_edge"), 8.8)
			and unreadied(&"greenhouse", 0, Studio.ROOM_WIDTH).anchor(&"annex_edge") > 8.8 + 0.5)
	var wide := unreadied(&"rooftop", 0, WIDTHS[1])
	check("the walls and the zones step out with the desk", is_equal_approx(wide.anchor(&"wall.left"), -10.4)
			and is_equal_approx(wide.anchor(&"control_wall.right"), 7.2) and wide.anchor(&"zone.synth.cx") > 8.3 + 1.0)
	var roulette := unreadied(Venue.ROULETTE_ID, 0, Studio.ROOM_WIDTH)
	check("a shell with no such zone has no such anchor", roulette.anchor(&"zone.synth") == null and roulette.anchor(&"zone.synth.cx") == null
			and roof.anchor(&"zone.choir") == null and roulette.anchor_axis(&"zone.synth", "x") == null)
	check("and the roulette room's walls are its own", is_equal_approx(roulette.anchor(&"wall.right"), Studio.ROOM_WIDTH * 0.5))
	for good in ["wall.left", "control_wall.right", "control_rear", "live_back", "mix", "annex_edge", "zone.synth", "zone.synth.cx", "zone.a1.max"]:
		check("'%s' is an anchor name" % good, ShellFacts.is_anchor_name(good))
	for bad in ["", "wall", "wall.middle", "Wall.left", "zone.", "zone.synth.cy", "zone.Synth", "control_front", "wall.left ", "mix.x"]:
		check("'%s' is not an anchor name, and has no value" % bad, not ShellFacts.is_anchor_name(bad) and roof.anchor(StringName(bad)) == null)
	# The names layouts are written with are the names the shell has.
	var s := LayoutSet.new()
	s.scan(["res://tests/fixtures/layouts/set"])
	var named := 0
	for id in ["rooftop", "studio"]:
		var r := s.resolve(id)
		for p: Dictionary in r.pieces():
			for axis: String in p.get("at", {}).get("anchor", {}):
				named += 1
				check("%s's %s is placed against %s, which the shell has" % [id, p["id"], p["at"]["anchor"][axis]],
						roof.anchor_axis(StringName(p["at"]["anchor"][axis]), axis) != null)
	check("some placements were looked at", named >= 10)
