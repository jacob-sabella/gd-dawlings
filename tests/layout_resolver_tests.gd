extends RefCounted

## LayoutResolver (docs/layouts.md section 11 step 3), called from the `_test_*` wrappers in
## tests/run_tests.gd: the shipped `common.live_room` fragment resolves, from ShellFacts alone, to the
## transforms Venue.default_spot gives for the five wheeled pieces, in every venue and arrangement
## (and the roulette room) at two widths; and the rules of a placement hold on their own.

const WIDTHS: Array[float] = [Studio.ROOM_WIDTH, Studio.ROOM_WIDTH + 3.2]
const TOLERANCE := 1e-4
const FRAGMENTS: Array[String] = ["res://layouts"]
## The modular room, as the rooftop example of docs/layouts.md 5.2 places it.
const ANNEX := {"id": "modular_annex", "piece": "modular_annex", "at": {"anchor": {"x": "annex_edge"}, "pos": [0.0, 0.0], "yaw": 0.0}}

var t: Node


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


## The room `id` in arrangement `variant` as a resolved layout: the venue's own shipped file
## (`layouts/venues/<id>.layout.json`, which extends the control-room and live-room fragments and
## carries the studio's second arrangement); `with_annex` adds the modular room, which no venue file
## lists yet (it is the studio's for every venue, step 11). `set` is a LayoutSet that has scanned FRAGMENTS.
static func room(set: LayoutSet, id: StringName, variant: int, with_annex := false) -> LayoutData:
	var out := set.resolve(String(id), variant)
	if with_annex:
		out.body["pieces"].append(ANNEX.duplicate(true))
	return out


static func fragments() -> LayoutSet:
	var set := LayoutSet.new()
	set.scan(FRAGMENTS)
	return set


## True when two transforms agree to TOLERANCE in origin and in all three axes.
static func same(a: Transform3D, b: Transform3D) -> bool:
	return a.origin.distance_to(b.origin) <= TOLERANCE and a.basis.x.distance_to(b.basis.x) <= TOLERANCE \
			and a.basis.y.distance_to(b.basis.y) <= TOLERANCE and a.basis.z.distance_to(b.basis.z) <= TOLERANCE


## Every venue id with its arrangements, the roulette room last: 14 x 3 + 1.
static func combinations() -> Array:
	var out: Array = []
	for id in Venue.IDS:
		for v in Venue.variant_titles(id).size():
			out.append([id, v])
	out.append([Venue.ROULETTE_ID, 0])
	return out


## The old transforms, frozen before docs/layouts.md step 5 deleted the code that computed them
## (`Venue.default_*_spot`): for each venue, arrangement and width, each wheeled piece as 12 numbers
## (basis columns, origin) or null where the venue had no room for it.
const LEGACY_SPOTS := "res://tests/fixtures/layouts/live_room_legacy_spots.json"


static func _legacy_rows() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LEGACY_SPOTS))
	return parsed["rows"] if parsed is Dictionary else []


static func _transform(n: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(n[0], n[1], n[2]), Vector3(n[3], n[4], n[5]), Vector3(n[6], n[7], n[8])), Vector3(n[9], n[10], n[11]))


## Regression check against the frozen fixture of the old transforms: what the venue gives now, which
## is the shipped layout read through `Venue.default_spot`, and what the test's own in-memory rooms
## resolve to, both equal the code that stood for the five pieces before it was deleted.
func equals_the_venue() -> void:
	var set := fragments()
	var fragment := set.layouts.get("common.live_room") as LayoutData
	check("the shipped live-room fragment parses clean (%s)" % [fragment.problems if fragment != null else "missing"],
			fragment != null and fragment.status == LayoutData.STATUS_OK and fragment.problems.is_empty())
	var placed: Array = fragment.pieces().map(func(p: Dictionary) -> String: return p["id"]) if fragment != null else []
	placed.sort()
	var wheeled_ids: Array = Venue.WHEELED.map(func(p: StringName) -> String: return String(p))
	wheeled_ids.sort()
	# The fragment also places the four zone-mounted pieces (step 6 part 2) and lists `lyrics` with no place
	# (the vocals group names it; its spot reads the booth's mic stand, so it is the venue's: part 3); the wheeled ones are the five.
	var wheeled_placed: Array = fragment.pieces().filter(func(p: Dictionary) -> bool: return p.get("mobility") == "wheeled") \
			.map(func(p: Dictionary) -> String: return p["id"])
	wheeled_placed.sort()
	check("and places exactly the five wheeled pieces, the venue's own list, and the four in zones, and lyrics unplaced (%s)" % [placed],
			wheeled_placed == wheeled_ids and wheeled_placed.size() == 5 and placed.size() == 10)
	check("in the order the studio has always built their trolleys", Venue.WHEELED == [&"cassette_rack", &"sampler",
			&"tour_case", &"prop_shelf", &"hoop"])
	var studio_file := LiveRoom.layouts().layouts.get("studio") as LayoutData
	check("the studio's own shipped layout names the arrangements the venue does",
			studio_file != null and PackedStringArray(studio_file.variant_titles()) == Venue.variant_titles(&"studio"))
	var rows := _legacy_rows()
	check("the frozen fixture holds 43 rooms at two widths (86 rows)", rows.size() == 86)
	var compared := 0
	var nulls := 0
	for row: Dictionary in rows:
		var id := StringName(row["venue"])
		var variant := int(row["variant"])
		var venue := Venue.make(id, variant)
		venue.room_width = row["room_width"]
		var layout := room(set, id, variant)
		var facts := ShellFacts.of(venue)
		var tag := "%s/%d at %.1f m" % [id, variant, venue.room_width]
		check("%s: the room resolves (%s)" % [tag, layout.problems], layout.status == LayoutData.STATUS_OK)
		for wheeled: StringName in Venue.WHEELED:
			var frozen: Variant = row["spots"].get(String(wheeled))
			var now: Variant = venue.default_spot(wheeled)
			var data: Variant = LayoutResolver.transform(layout, wheeled, facts)
			if frozen == null:
				nulls += 1
				check("%s: %s had no room here, and still has none" % [tag, wheeled], now == null and data == null)
			else:
				compared += 1
				var want := _transform(frozen)
				check("%s: %s stands where the old code stood it (%s, wanted %s)" % [tag, wheeled, now, want],
						now != null and same(now, want) and data != null and same(data, want))
		venue.free()
	check("every wheeled piece was compared: 5 x 43 x 2 = 430, the roulette room's sampler (2) being null (%d + %d)"
			% [compared, nulls], compared == 428 and nulls == 2)
	var cached := Venue.make(&"studio", 1)
	var before: Variant = cached.default_spot(&"prop_shelf")
	cached.room_width += 0.8
	var wider: Variant = cached.default_spot(&"prop_shelf")
	cached.variant = 0
	var behind: Variant = cached.default_spot(&"prop_shelf")
	check("the venue's cache follows its width and its arrangement (the shelf moves with each)",
			before != null and wider != null and behind != null and not same(before, wider) and not same(wider, behind))
	cached.free()


## The zone-mounted pieces (the wheel, the section blocks, the drums' ring, the looper): the old code's
## transforms frozen in `ZONE_SPOTS` before `wheel_spot`, `band_spot`, `drum_circle_spot` and
## `looper_spot` read the layout, held for 43 rooms at two widths through the venue and through the
## resolver alone.
const ZONE_SPOTS := "res://tests/fixtures/layouts/zone_pieces_legacy_spots.json"


func equals_the_zone_pieces() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ZONE_SPOTS))
	var rows: Array = parsed["rows"] if parsed is Dictionary else []
	check("the frozen fixture holds 43 rooms at two widths (86 rows)", rows.size() == 86)
	var set := fragments()
	var compared := 0
	var nulls := 0
	for row: Dictionary in rows:
		var id := StringName(row["venue"])
		var venue := Venue.make(id, int(row["variant"]))
		venue.room_width = row["room_width"]
		var facts := ShellFacts.of(venue)
		var layout := room(set, id, int(row["variant"]))
		var tag := "%s/%d at %.1f m" % [id, int(row["variant"]), venue.room_width]
		var now := {&"wheel": venue.wheel_spot(), &"sections": venue.sections_spot(), &"drums": venue.drum_circle_spot(),
				&"looper": venue.looper_spot()}
		for piece: StringName in now:
			var frozen: Variant = row["spots"].get(String(piece))
			var data: Variant = LayoutResolver.transform(layout, piece, facts)
			if frozen == null:
				nulls += 1
				check("%s: %s had no room here, and still has none" % [tag, piece], now[piece] == null and data == null)
			else:
				compared += 1
				var want := _transform(frozen)
				check("%s: %s stands where the old code stood it (%s, wanted %s)" % [tag, piece, now[piece], want],
						now[piece] != null and same(now[piece], want) and data != null and same(data, want))
		venue.free()
	check("the four were compared in every room that has their zone (%d + %d null)" % [compared, nulls], compared > 0 and compared + nulls == 344)
	# A drum ring's n-th drum is still the static `drum_ring`'s: only the middle and the looper are data.
	var studio_venue := Venue.make(&"studio", 0)
	check("a drum's own place is still the ring's", studio_venue.drum_circle_spot(2) != null
			and (studio_venue.drum_circle_spot(2) as Transform3D).is_equal_approx(Venue.drum_ring(studio_venue.zones()[&"drums"], 2, studio_venue.drum_floor())))
	studio_venue.free()


func placement_rules() -> void:
	var set := fragments()
	var venue := Venue.make(&"rooftop", 0)
	var facts := ShellFacts.of(venue)
	venue.free()
	var layout := set.resolve("common.live_room")
	var all := LayoutResolver.all(layout, facts)
	check("all gives each of the five wheeled, and the four zone-mounted, a transform, keyed by id", all.size() == 9 and all.has(&"hoop")
			and LayoutResolver.transform(layout, &"hoop", facts) == all[&"hoop"])
	# Height and facing: `up` is metres or an anchor read as a height; a yaw may face an anchor, rounded.
	var up := LayoutData.parse({"format": "dawlings.layout", "version": 1, "id": "up", "title": "Up", "pieces": [
			{"id": "a", "piece": "wheel", "at": {"pos": [3.0, 4.0], "up": 0.5, "yaw": {"toward": "mix"}}},
			{"id": "b", "piece": "wheel", "at": {"pos": [3.0, 4.0], "up": "height.table", "yaw": {"toward": "mix", "snap": 1.5707963267948966}}},
			{"id": "c", "piece": "wheel", "at": {"pos": [3.0, 4.0], "up": "zone.choir.floor"}}]})
	check("a placement with up and a facing parses clean (%s)" % [up.problems], up.status == LayoutData.STATUS_OK)
	var a: Variant = LayoutResolver.transform(up, &"a", facts)
	var b: Variant = LayoutResolver.transform(up, &"b", facts)
	var toward := atan2(-3.0, Studio.MIX_POSITION_Z - 4.0)
	check("up in metres lifts the piece, and a yaw toward mix turns it to (0, mix)", a != null
			and is_equal_approx((a as Transform3D).origin.y, 0.5) and same(a, Transform3D(Basis(Vector3.UP, toward), Vector3(3.0, 0.5, 4.0))))
	check("up as an anchor is its height (the table's), and snap rounds the turn to a quarter", b != null
			and is_equal_approx((b as Transform3D).origin.y, ZoneKit.TABLE_HEIGHT)
			and same(b, Transform3D(Basis(Vector3.UP, snappedf(toward, PI * 0.5)), Vector3(3.0, ZoneKit.TABLE_HEIGHT, 4.0))))
	check("a height from a zone the shell lacks leaves the piece unplaced", LayoutResolver.transform(up, &"c", facts) == null)
	var bad := LayoutData.parse({"format": "dawlings.layout", "version": 1, "id": "bad", "title": "Bad", "pieces": [
			{"id": "a", "piece": "wheel", "at": {"up": "ceiling", "yaw": {"toward": "nowhere"}}}]})
	check("an up or a facing that is no anchor is refused", bad.status != LayoutData.STATUS_OK and bad.problems.size() >= 2)
	var shelf: Transform3D = all[&"prop_shelf"]
	check("an anchor placement is the anchors' values plus pos (the shelf: -8.8 + 0.29, 4 + 1)",
			shelf.origin.is_equal_approx(Vector3(-8.51, 0, 5.0)) and is_equal_approx(shelf.basis.get_euler().y, PI * 0.5))
	var rack: Transform3D = all[&"cassette_rack"]
	check("a frame placement is in the authored frame of the piece it names",
			same(rack, shelf * Transform3D(Basis.IDENTITY, Vector3(-1.345, 0, -0.11))))
	var moved := LayoutData.parse({"format": "dawlings.layout", "version": 1, "id": "moved", "title": "Moved",
			"extends": ["common.live_room"], "pieces": [{"id": "prop_shelf", "at": {"anchor": {"x": "wall.left"}, "pos": [1.0, 9.0], "yaw": 0.0}}]})
	set.add(moved)
	var again := set.resolve("moved")
	var after := LayoutResolver.all(again, facts)
	check("a piece placed in a frame follows its frame when that is overridden (the rack, the hoop)",
			(after[&"cassette_rack"] as Transform3D).origin.distance_to((all[&"cassette_rack"] as Transform3D).origin) > 2.0
			and same(after[&"hoop"], after[&"prop_shelf"] * Transform3D(Basis(Vector3.UP, PI), Vector3(-0.4, 0, 3.31))))
	check("an axis with no anchor is measured from 0", is_equal_approx((after[&"prop_shelf"] as Transform3D).origin.z, 9.0))
	var wide_venue := Venue.make(&"rooftop", 0)
	wide_venue.room_width = WIDTHS[1]
	var wide := LayoutResolver.all(layout, ShellFacts.of(wide_venue))
	wide_venue.free()
	check("a wider room moves what is anchored to its wall (by 1.6 m) and leaves the control rear alone",
			is_equal_approx((wide[&"prop_shelf"] as Transform3D).origin.x, -10.4 + 0.29)
			and is_equal_approx((wide[&"prop_shelf"] as Transform3D).origin.z, 5.0))
	var roulette_venue := Venue.make(Venue.ROULETTE_ID, 0)
	var roulette := ShellFacts.of(roulette_venue)
	roulette_venue.free()
	check("an anchor the shell lacks leaves the piece unplaced, not an error: the sampler without a synth zone",
			LayoutResolver.transform(layout, &"sampler", roulette) == null and LayoutResolver.all(layout, roulette).size() == 4)
	check("and so does everything framed on an unplaced piece",
			LayoutResolver.transform(LayoutData.parse({"format": "dawlings.layout", "version": 1, "id": "chain", "title": "Chain",
			"pieces": [{"id": "a", "piece": "x", "at": {"anchor": {"x": "zone.synth.cx"}}},
			{"id": "b", "piece": "x", "at": {"frame": "authored:a", "local": [1, 1]}}]}), &"b", roulette) == null)
	check("a piece with no placement, or none in the room, has no transform",
			LayoutResolver.transform(LayoutData.parse({"format": "dawlings.layout", "version": 1, "id": "z", "title": "Z",
			"pieces": [{"id": "wheel", "piece": "wheel"}]}), &"wheel", roulette) == null
			and LayoutResolver.transform(layout, &"nobody", roulette) == null)
	check("a placement loop cannot hang the resolver (the guard), whatever got past the parser",
			LayoutResolver.transform(LayoutData.parse({"format": "dawlings.layout", "version": 1, "id": "loop", "title": "Loop",
			"pieces": [{"id": "a", "piece": "x", "at": {"frame": "authored:b"}}, {"id": "b", "piece": "x", "at": {"frame": "authored:a"}}]}),
			&"a", roulette) == null)
