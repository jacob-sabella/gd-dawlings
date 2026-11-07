extends RefCounted

## The layout file: parser, problem codes, merge, `extends` fragments, variants, and the schema file
## (docs/layouts.md sections 5 and 11 step 1), called from the `_test_*` wrappers in tests/run_tests.gd.
## The fixtures are under tests/fixtures/layouts/: `set/` is a small working set (the control-room and
## live-room fragments, the studio, the rooftop, the roulette room and a made room) and `bad/` is one
## file for each way to be broken.

const ROOT := "res://tests/fixtures/layouts"

var t: Node


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


func _fixture_set() -> LayoutSet:
	var s := LayoutSet.new()
	s.scan([ROOT + "/set"])
	return s


func _bad(file: String) -> LayoutData:
	return LayoutData.load_file("%s/bad/%s.layout.json" % [ROOT, file])


func _codes(l: LayoutData) -> Array:
	return l.problems.map(func(p: LayoutProblem) -> StringName: return p.code)


## A minimal good layout with `extra` merged over it, parsed.
func _with(extra: Dictionary) -> LayoutData:
	var d := {"format": "dawlings.layout", "version": 1, "id": "t", "title": "T"}
	d.merge(extra, true)
	return LayoutData.parse(d)


func _pieces_of(l: LayoutData) -> Array:
	return l.pieces().map(func(p: Dictionary) -> String: return p["id"])


func parsing() -> void:
	var rooftop := LayoutData.load_file(ROOT + "/set/venues/rooftop.layout.json")
	check("a good file is ok with no problems", rooftop.status == LayoutData.STATUS_OK and rooftop.problems.is_empty())
	check("it keeps its id, title, order and fragments", rooftop.id == "rooftop" and rooftop.title == "Rooftop"
			and rooftop.order == 1 and rooftop.extends_ids == ["common.control_room", "common.live_room"])
	check("it keeps its zones, pieces and variants", rooftop.zones().size() == 5 and _pieces_of(rooftop) == ["modular_annex"]
			and rooftop.variant_titles() == ["Dusk", "Golden hour", "Night"])
	check("the shell and mood are kept as written", rooftop.body["shell"]["builder"] == "RooftopVenue" and rooftop.body["mood"]["glow"] == 0.75)
	check("a dotted fragment id is an id", LayoutData.load_file(ROOT + "/set/common/live_room.layout.json").id == "common.live_room")
	check("to_dict reads back as the same layout", LayoutData.parse(rooftop.to_dict()).to_dict() == rooftop.to_dict())
	var warns := _bad("warns")
	check("unknown keys are warnings and the layout still works", warns.status == LayoutData.STATUS_OK
			and _codes(warns) == [&"unknown_key", &"unknown_key"] and warns.errors().is_empty())
	check("a layout with no variants has its own title as its one arrangement", LayoutData.load_file(
			ROOT + "/set/rooms/my-roof.layout.json").variant_titles() == ["My roof"])

	var expect := {"not_json": &"bad_json", "top_array": &"bad_json", "wrong_format": &"bad_schema",
			"future_version": &"version_unsupported", "dup_piece": &"duplicate_id", "unknown_anchor": &"unknown_anchor",
			"at_both": &"bad_schema"}
	for file: String in expect:
		var l := _bad(file)
		check("%s: %s, unusable, nothing kept, and it says what" % [file, expect[file]], l.status == LayoutData.STATUS_INVALID
				and expect[file] in _codes(l) and l.body.is_empty() and not l.problems[0].message.is_empty())
	check("a missing file is no_file", LayoutData.load_file(ROOT + "/nope.layout.json").problems[0].code == &"no_file")
	check("a problem says where", _bad("dup_piece").problems[0].where == "pieces[1]" and "pieces[1]" in str(_bad("dup_piece").problems[0]))
	check("an unknown anchor names the axis", _bad("unknown_anchor").problems[0].where == "pieces[0].at.anchor.x")

	# Field by field.
	var cases := {
		"an uppercase id": {"id": "Roof"}, "a long title": {"title": "x".repeat(61)}, "an empty title": {"title": ""},
		"a negative order": {"order": -1}, "a fractional order": {"order": 1.5}, "extends that is a string": {"extends": "a"},
		"extends of a bad id": {"extends": ["Bad Id"]}, "zones as a list": {"zones": []},
		"a zone with no room to stand in": {"zones": {"a": {"size": [0, 1, 1]}}}, "a zone with a pair for a box": {"zones": {"a": {"min": [0, 0]}}},
		"a zone that grows sideways": {"zones": {"a": {"grow": "up"}}}, "a piece of no id": {"pieces": [{"piece": "x"}]},
		"a piece that is a number": {"pieces": [3]}, "a piece in orbit": {"pieces": [{"id": "a", "at": {"pos": [1e9, 0]}}]},
		"a bad mobility": {"pieces": [{"id": "a", "mobility": "flying"}]}, "enabled as text": {"pieces": [{"id": "a", "enabled": "no"}]},
		"a frame with a pos": {"pieces": [{"id": "a", "at": {"frame": "authored:b", "pos": [0, 0]}}]},
		"a local without a frame": {"pieces": [{"id": "a", "at": {"local": [0, 0]}}]},
		"a frame of the wrong shape": {"pieces": [{"id": "a", "at": {"frame": "b", "local": [0, 0]}}]},
		"a yaw as text": {"pieces": [{"id": "a", "at": {"yaw": "left"}}]}, "an anchor as a list": {"pieces": [{"id": "a", "at": {"anchor": ["mix"]}}]},
		"a bad colour": {"mood": {"base": "blue"}}, "a glow of a hundred": {"mood": {"glow": 100}}, "a shell with a path in it": {"shell": {"builder": "../x"}},
		"a group of no members list": {"groups": [{"id": "g", "members": "a"}]}, "a wire of an unknown kind": {"wiring": [{"kind": "wishes", "from": "a", "to": "b"}]},
		"a wire with no end": {"wiring": [{"kind": "feeds", "from": "a"}]}, "an empty variants list": {"variants": []},
		"a variant with no title": {"variants": [{}]}, "a variant that is a string": {"variants": ["a"]},
		"a bad piece in a variant": {"variants": [{"title": "a", "pieces": [{"id": "A"}]}]},
	}
	for what: String in cases:
		var l := _with(cases[what])
		check("%s is refused with a problem naming it" % what, l.status == LayoutData.STATUS_INVALID and not l.errors().is_empty()
				and not l.errors()[0].message.is_empty())
	check("a variant carrying a shell is only warned about", _with({"variants": [{"title": "a", "shell": {}}]}).has_problem(&"unknown_key"))
	# Junk of every kind comes back as a problem and never throws.
	for junk: Variant in [{}, {"format": "dawlings.layout"}, {"format": "dawlings.layout", "version": "1"},
			{"format": "dawlings.layout", "version": 1, "id": 5, "title": [], "pieces": "x", "zones": 3, "wiring": {}, "groups": [1, [2]], "variants": 1},
			{"format": "dawlings.layout", "version": 0}, {"format": 7}]:
		var l := LayoutData.parse(junk)
		check("junk %s is invalid with a problem" % str(junk).left(30), l.status == LayoutData.STATUS_INVALID and not l.problems.is_empty())
	check("an optional null order is allowed and means not cycled", _with({"order": null}).status == LayoutData.STATUS_OK and _with({"order": null}).order == -1)
	check("the codes the parser raises are all listed", LayoutProblem.CODES.has(&"bad_variant") and LayoutProblem.CODES.size() == 14)


func merging() -> void:
	var base := {"shell": {"builder": "A", "kit": "box"}, "zones": {"a": {"min": [0, 0, 0], "size": [1, 1, 1]}, "b": {"min": [5, 0, 0], "size": [2, 2, 2]}},
			"pieces": [{"id": "p", "piece": "x", "mobility": "wheeled", "at": {"anchor": {"x": "mix"}, "pos": [1, 2], "yaw": 1.0}}, {"id": "q", "piece": "y"}],
			"groups": [{"id": "g", "title": "G", "members": ["p", "q"]}], "wiring": [{"kind": "feeds", "from": "p", "to": "q"}]}
	var before := base.duplicate(true)
	var over := {"shell": {"kit": null, "size": "std"}, "zones": {"a": {"min": [9, 0, 0]}, "b": null},
			"pieces": [{"id": "q", "enabled": false}, {"id": "p", "at": {"frame": "authored:q", "local": [0, 0]}}, {"id": "r", "piece": "z"}],
			"groups": [{"id": "g", "members": ["p"]}], "wiring": [{"kind": "feeds", "from": "p", "to": "q"}, {"kind": "rides", "from": "r", "to": "p"}]}
	var m := LayoutMerge.merge(base, over)
	check("neither side is changed", base == before and over.has("shell"))
	check("objects merge key by key and a null removes a key", m["shell"] == {"builder": "A", "size": "std"})
	check("a zone merges field by field and a null zone is removed", m["zones"].keys() == ["a"] and m["zones"]["a"] == {"min": [9, 0, 0], "size": [1, 1, 1]})
	check("pieces merge by id, in order, and a new one is appended", m["pieces"].map(func(p: Dictionary) -> String: return p["id"]) == ["p", "q", "r"])
	check("a merged piece keeps what the override left alone", m["pieces"][0]["mobility"] == "wheeled" and m["pieces"][0]["piece"] == "x")
	check("a placement replaces whole: no anchor left beside the frame", m["pieces"][0]["at"] == {"frame": "authored:q", "local": [0, 0]})
	check("other lists replace", m["groups"][0]["members"] == ["p"] and m["groups"][0]["title"] == "G")
	check("wires merge by kind, from and to", m["wiring"].size() == 2)
	check("a disabled piece survives the merge, so a later fragment can enable it", m["pieces"][1]["enabled"] == false)
	var again := LayoutMerge.merge(m, {"pieces": [{"id": "q", "enabled": true}]})
	check("and enabling it again leaves it in", again["pieces"][1]["enabled"] == true and again["pieces"].size() == 3)
	var gone := LayoutMerge.settle(m)
	check("settle takes out the disabled piece and says which", gone == ["q"] and m["pieces"].size() == 2)
	check("and the wires that touched it, and its place in groups", m["wiring"] == [{"kind": "rides", "from": "r", "to": "p"}])
	var grouped := LayoutMerge.settle({"pieces": [{"id": "a", "enabled": false}], "groups": [{"id": "g", "members": ["a", "b"]}]})
	check("settle on a body without wires is fine", grouped == ["a"])
	check("an array override on a missing key is a copy", LayoutMerge.merge({}, {"pieces": [{"id": "z"}]})["pieces"][0]["id"] == "z")
	check("merging nothing changes nothing", LayoutMerge.merge(base, {}) == base)
	check("null in a fresh object is dropped too", LayoutMerge.merge({}, {"zones": {"a": null, "b": {"grow": "none"}}})["zones"] == {"b": {"grow": "none"}})


func resolving() -> void:
	var s := _fixture_set()
	check("the working set has no problems of its own", s.problems.is_empty() and s.layouts.size() == 6
			and s.layouts.values().all(func(l: LayoutData) -> bool: return l.status == LayoutData.STATUS_OK))
	check("the cycled rooms come in their order, the roulette room and made rooms not at all", s.venue_ids() == [&"studio", &"rooftop"])
	var parsed_before := (s.layouts["rooftop"] as LayoutData).to_dict()
	var r := s.resolve("rooftop")
	check("the rooftop resolves", r.status == LayoutData.STATUS_OK and r.problems.is_empty() and r.id == "rooftop" and r.variant == 0)
	check("fragments come first, in order, then the file", r.chain == ["common.control_room", "common.live_room", "rooftop"])
	check("its pieces are the control room's, the live room's and its own", _pieces_of(r) == ["console", "rack_trolley", "prop_shelf",
			"cassette_rack", "hoop", "tour_case", "sampler", "wheel", "sections", "drums", "looper", "lyrics", "modular_annex"])
	check("a placement from a fragment arrives as written", r.piece(&"prop_shelf")["at"]["pos"] == [0.29, 1.0]
			and r.piece(&"prop_shelf")["at"]["anchor"] == {"x": "wall.left", "z": "control_rear"})
	check("it has the six groups and both wires", r.body["groups"].size() == 6 and r.body["wiring"].size() == 2)
	check("the mixing group is the control room's", r.body["groups"][0]["id"] == "mixing" and r.body["groups"][0]["members"] == ["console", "rack_trolley"])
	check("zones and mood are the venue's own", r.zones().size() == 5 and r.zones()["drums"]["min"] == [-3.4, 0.0, 4.8] and r.body["mood"]["base"] == "#7399FF")
	check("resolving does not change what was parsed", (s.layouts["rooftop"] as LayoutData).to_dict() == parsed_before)
	check("the arrangements keep their names", r.variant_titles() == ["Dusk", "Golden hour", "Night"])

	var base := s.resolve("studio", 0)
	var beside := s.resolve("studio", 1)
	check("arrangement 0 changes nothing", base.status == LayoutData.STATUS_OK and base.piece(&"prop_shelf")["at"]["anchor"]["x"] == "wall.left")
	check("beside: the shelf is placed against the control room's wall", beside.status == LayoutData.STATUS_OK
			and beside.piece(&"prop_shelf")["at"] == {"anchor": {"x": "control_wall.left", "z": "control_rear"}, "pos": [0.34, 2.4], "yaw": 1.5708}
			and beside.variant == 1)
	check("it is still the wheeled shelf the fragment made", beside.piece(&"prop_shelf")["mobility"] == "wheeled" and beside.piece(&"prop_shelf")["piece"] == "prop_shelf")
	check("beside: only the zones it names moved, and only the fields it names", beside.zones()["drums"]["min"] == [-9.6, 0.0, -3.4]
			and beside.zones()["drums"]["size"] == [2.6, 2.8, 2.6] and beside.zones()["drums"]["grow"] == "none"
			and beside.zones()["matrix"]["grow"] == "inward" and beside.zones()["vocals"] == base.zones()["vocals"])
	var glass := s.resolve("studio", 2)
	check("through the glass: the hoop is gone from the room, its group and the pieces", not _pieces_of(glass).has("hoop")
			and glass.body["groups"].filter(func(g: Dictionary) -> bool: return g["id"] == "tape")[0]["members"] == ["cassette_rack", "prop_shelf", "tour_case"])
	check("the other arrangements have the hoop", _pieces_of(base).has("hoop") and _pieces_of(beside).has("hoop"))
	check("an arrangement that does not exist is bad_variant", s.resolve("studio", 3).has_problem(&"bad_variant") and s.resolve("studio", -1).status == LayoutData.STATUS_INVALID
			and s.resolve("rooftop", 1).status == LayoutData.STATUS_OK and s.resolve("my-roof", 1).has_problem(&"bad_variant"))

	var roulette := s.resolve("roulette")
	check("the roulette room has no zones, no sampler and its own wall", roulette.status == LayoutData.STATUS_OK and roulette.zones().is_empty()
			and not _pieces_of(roulette).has("sampler") and roulette.piece(&"rig_roulette")["at"]["pos"] == [-2.2, -1.5])
	check("a wire or group member that named the sampler goes with it", roulette.body["wiring"].is_empty()
			and roulette.body["groups"].filter(func(g: Dictionary) -> bool: return g["id"] == "synth")[0]["members"] == [] and roulette.problems.is_empty())
	var mine := s.resolve("my-roof")
	check("a made room extends a venue, which extends fragments", mine.status == LayoutData.STATUS_OK
			and mine.chain == ["common.control_room", "common.live_room", "rooftop", "my-roof"])
	check("it dropped a zone and a piece and added one", mine.zones().size() == 4 and not mine.zones().has("synth")
			and not _pieces_of(mine).has("hoop") and _pieces_of(mine).has("duck") and _pieces_of(mine).has("modular_annex"))
	check("the venue's arrangements are not inherited", mine.variant_titles() == ["My roof"])
	check("a layout nobody wrote is no_file", s.resolve("ghost").problems[0].code == &"no_file")

	var again := LayoutSet.new()
	again.scan([ROOT + "/set", ROOT + "/set/venues"])
	check("a second file with an id already seen is an id_collision and is ignored", again.problems.size() == 3
			and again.problems.all(func(p: LayoutProblem) -> bool: return p.code == &"id_collision") and again.layouts.size() == 6)


func failing() -> void:
	var s := LayoutSet.new()
	s.scan([ROOT + "/set", ROOT + "/bad"])
	check("the bad files that parse are in the set, the others are there as invalid", s.layouts.has("cyc-a") and s.layouts.has("dup")
			and (s.layouts["dup"] as LayoutData).status == LayoutData.STATUS_INVALID)
	var cyc := s.resolve("cyc-a")
	check("two fragments that extend each other are extends_cycle", cyc.status == LayoutData.STATUS_INVALID and cyc.has_problem(&"extends_cycle"))
	check("it names the way round", "cyc-a > cyc-b" in cyc.problems[0].message)
	check("a fragment that is not there is extends_missing", s.resolve("lost").has_problem(&"extends_missing") and s.resolve("lost").status == LayoutData.STATUS_INVALID)
	var on_bad := s.resolve("onbad")
	check("a fragment that cannot be used is extends_missing and says why", on_bad.has_problem(&"extends_missing")
			and "listed twice" in on_bad.problems[0].message)
	check("an invalid file resolves to an invalid layout with its own problems", s.resolve("dup").status == LayoutData.STATUS_INVALID and s.resolve("dup").has_problem(&"duplicate_id"))
	var loop := s.resolve("loop")
	check("frames that point at each other are a cycle, reported once", loop.problems.filter(func(p: LayoutProblem) -> bool: return p.code == &"cycle").size() == 1)
	check("a frame on a piece that is not there is unknown_piece", loop.problems.any(func(p: LayoutProblem) -> bool: return p.code == &"unknown_piece" and p.where == "pieces[2].at.frame"))
	var nokind := s.resolve("nokind")
	check("a piece that never says what it is, and a zone with no min, are bad_schema", nokind.problems.filter(func(p: LayoutProblem) -> bool: return p.code == &"bad_schema").size() == 2)
	check("a group member or wire end that is not there is only a warning", nokind.problems.filter(func(p: LayoutProblem) -> bool: return p.code == &"unknown_piece" and not p.is_error()).size() == 2)
	check("and the group and wire are kept as written", nokind.body["groups"][0]["members"] == ["a", "b"])
	# The limit: 64 pieces, counted after the merge.
	for count in [64, 65]:
		var pieces: Array = []
		for i in count:
			pieces.append({"id": "p%d" % i, "piece": "x"})
		var big := LayoutSet.new()
		big.add(LayoutData.parse({"format": "dawlings.layout", "version": 1, "id": "big", "title": "Big", "pieces": pieces}))
		var r := big.resolve("big")
		check("%d pieces: %s" % [count, "ok" if count == 64 else "over_limit"], (r.status == LayoutData.STATUS_OK) == (count == 64)
				and r.has_problem(&"over_limit") == (count == 65))
	var halves := LayoutSet.new()
	halves.add(LayoutData.parse({"format": "dawlings.layout", "version": 1, "id": "half.a", "title": "A", "pieces": range(40).map(func(i: int) -> Dictionary: return {"id": "a%d" % i, "piece": "x"})}))
	halves.add(LayoutData.parse({"format": "dawlings.layout", "version": 1, "id": "half.b", "title": "B", "extends": ["half.a"], "pieces": range(40).map(func(i: int) -> Dictionary: return {"id": "b%d" % i, "piece": "x"})}))
	check("the limit counts the merged room, not each file", halves.resolve("half.b").has_problem(&"over_limit") and halves.resolve("half.a").status == LayoutData.STATUS_OK)
	var deep := LayoutSet.new()
	for i in 12:
		deep.add(LayoutData.parse({"format": "dawlings.layout", "version": 1, "id": "d%d" % i, "title": "D", "extends": ["d%d" % (i + 1)] if i < 11 else []}))
	check("fragments nest only so deep", deep.resolve("d0").has_problem(&"extends_cycle") and deep.resolve("d6").status == LayoutData.STATUS_OK)


func schema() -> void:
	var schema: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://layouts/layout.schema.json"))
	check("the schema file parses", schema is Dictionary)
	var props: Dictionary = schema["properties"]
	var defs: Dictionary = schema["$defs"]
	check("it requires what the parser requires", schema["required"] == ["format", "version", "id", "title"])
	check("it names the top-level keys the parser knows", props.keys().size() == LayoutData.TOP_KEYS.size()
			and LayoutData.TOP_KEYS.all(func(k: String) -> bool: return props.has(k)))
	check("format and version are the parser's", props["format"]["const"] == LayoutData.FORMAT and props["version"]["const"] == LayoutData.VERSION)
	check("the piece limit is the parser's", props["pieces"]["maxItems"] == LayoutData.MAX_PIECES)
	check("each entry kind has the keys the checker knows", defs["placement"]["properties"].keys() == LayoutCheck.PIECE_KEYS
			and defs["at"]["properties"].keys() == LayoutCheck.AT_KEYS and defs["group"]["properties"].keys() == LayoutCheck.GROUP_KEYS
			and defs["zones"]["additionalProperties"]["properties"].keys() == LayoutCheck.ZONE_KEYS and defs["wire"]["properties"].keys() == LayoutCheck.WIRE_KEYS
			and defs["shell"]["properties"].keys() == LayoutCheck.SHELL_KEYS and defs["mood"]["properties"].keys() == LayoutCheck.MOOD_KEYS)
	check("the enums are the checker's", defs["placement"]["properties"]["mobility"]["enum"] == LayoutCheck.MOBILITIES
			and defs["zones"]["additionalProperties"]["properties"]["grow"]["enum"] == LayoutCheck.GROW and defs["wire"]["properties"]["kind"]["enum"] == LayoutCheck.WIRE_KINDS)
	check("the variants carry what the parser lets them", props["variants"]["items"]["properties"].keys().size() == LayoutData.VARIANT_KEYS.size()
			and LayoutData.VARIANT_KEYS.all(func(k: String) -> bool: return props["variants"]["items"]["properties"].has(k)))
	check("the anchor pattern is the shell's", defs["anchor_name"]["pattern"] == ShellFacts.ANCHOR_RE)
	check("the id pattern accepts what the parser accepts", RegEx.create_from_string(props["id"]["pattern"]).search("common.live_room") != null
			and RegEx.create_from_string(props["id"]["pattern"]).search("Roof") == null)
