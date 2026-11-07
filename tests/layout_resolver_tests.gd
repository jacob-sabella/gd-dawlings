extends RefCounted

## LayoutResolver (docs/layouts.md section 11 step 3), called from the `_test_*` wrappers in
## tests/run_tests.gd: the shipped `common.live_room` fragment resolves, from ShellFacts alone, to the
## transforms Venue.default_spot gives for the five wheeled pieces, in every venue and arrangement
## (and the roulette room) at two widths; and the rules of a placement hold on their own.

const WIDTHS: Array[float] = [Studio.ROOM_WIDTH, Studio.ROOM_WIDTH + 3.2]
const TOLERANCE := 1e-4
const FRAGMENTS: Array[String] = ["res://layouts/common"]
## `studio` arrangement 1 ("Live room beside") moves the shelf: studio_venue.gd default_prop_shelf_spot,
## written as the variant entry docs/layouts.md 5.2 gives.
const STUDIO_BESIDE := {"id": "prop_shelf", "at": {"anchor": {"x": "control_wall.left", "z": "control_rear"},
		"pos": [0.34, 2.4], "yaw": 1.5707963267948966}}

## The modular room, as the rooftop example of docs/layouts.md 5.2 places it.
const ANNEX := {"id": "modular_annex", "piece": "modular_annex", "at": {"anchor": {"x": "annex_edge"}, "pos": [0.0, 0.0], "yaw": 0.0}}

var t: Node


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


## The room `id` in arrangement `variant` as a resolved layout: the venue's file as it will be (step 7)
## for what this step needs, i.e. it extends the shipped live-room fragment, and the studio's second
## arrangement moves the shelf; `with_annex` adds the modular room. `set` is a LayoutSet that has scanned FRAGMENTS.
static func room(set: LayoutSet, id: StringName, variant: int, with_annex := false) -> LayoutData:
	var variants: Array = []
	for i in maxi(1, Venue.variant_titles(id).size()):
		variants.append({"title": "arrangement %d" % i})
	if id == &"studio":
		variants[1]["pieces"] = [STUDIO_BESIDE]
	var file := "room_%s%s" % [id, "_annex" if with_annex else ""]
	if not set.layouts.has(file):
		var data := {"format": "dawlings.layout", "version": 1, "id": file, "title": str(id),
				"extends": ["common.live_room"], "variants": variants}
		if with_annex:
			data["pieces"] = [ANNEX]
		set.add(LayoutData.parse(data))
	return set.resolve(file, variant)


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
	check("and places exactly the five wheeled pieces, the venue's own list (%s)" % [placed], placed == wheeled_ids and placed.size() == 5)
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


func placement_rules() -> void:
	var set := fragments()
	var venue := Venue.make(&"rooftop", 0)
	var facts := ShellFacts.of(venue)
	venue.free()
	var layout := set.resolve("common.live_room")
	var all := LayoutResolver.all(layout, facts)
	check("all gives each of the five a transform, keyed by id", all.size() == 5 and all.has(&"hoop")
			and LayoutResolver.transform(layout, &"hoop", facts) == all[&"hoop"])
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
