extends RefCounted

## The control-room fragment, the groups and the floor import (docs/layouts.md section 11 step 6, part
## 3), called from the `_test_*` wrappers in tests/run_tests.gd. Everything is held to
## tests/fixtures/layouts/control_room_legacy.json, dumped from the code before it was deleted:
## where `Studio._build_furniture` stood each trolley at four room widths, what `SessionLayout.fit`
## answered for five desks, the old `Neighbourhoods.ALL` rows and the MIXING banner's frame, and what
## `Studio.was_an_old_default` said for 4536 probes.

const FIXTURE := "res://tests/fixtures/layouts/control_room_legacy.json"
## The fixture carries float32 noise from the old code's `Vector3`s.
const TOLERANCE := 1e-3

var t: Node


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


func _legacy() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))


## Degrees apart, round the circle.
static func _turn_apart(a: float, b: float) -> float:
	return absf(wrapf(a - b, -180.0, 180.0))


## The fragment stands each trolley where the old code stood it, at each width the room has.
func defaults() -> void:
	var old: Dictionary = _legacy()["defaults"]
	for w: String in old:
		var bad: Array[String] = []
		for id: String in old[w]:
			if id == "timeline_stand":
				continue # Stays in code: its z is the timeline's (ControlRoom's doc comment).
			var want: Array = old[w][id]
			var got := ControlRoom.trolley_args(StringName(id), float(w))
			var at: Vector3 = got[0]
			if absf(at.x - want[0]) > TOLERANCE or absf(at.z - want[1]) > TOLERANCE or _turn_apart(got[1], want[2]) > TOLERANCE:
				bad.append("%s %s vs %s" % [id, [at.x, at.z, got[1]], want])
		check("the fragment's trolleys stand where they stood in a %s m room (%s)" % [w, bad], bad.is_empty())
	check("it places the eight trolleys of the old code", old["11.2"].size() == 9 and ControlRoom.layout().piece(&"rack").has("fit"))


## SessionLayout.fit, reading the fragment, answers what it did with its own constants.
func fits() -> void:
	var old: Dictionary = _legacy()["fits"]
	for half: String in old:
		var got := SessionLayout.fit(float(half))
		var want: Dictionary = old[half]
		var ok := is_equal_approx(got["room_width"], want["w"])
		for pair: Array in [["rack", "rack"], ["deck_trolley", "deck"], ["patch_stand", "patch"]]:
			var g: Array = got[pair[0]]
			var w: Array = want[pair[1]]
			ok = ok and absf((g[0] as Vector2).x - w[0]) < TOLERANCE and absf((g[0] as Vector2).y - w[1]) < TOLERANCE \
					and _turn_apart(g[1], w[2]) < TOLERANCE
		check("a desk half %s m wide fits the room as it did (%s m)" % [half, got["room_width"]], ok)


## The groups are the old rows, in their order, with the MIXING banner where it hung.
func groups() -> void:
	var old: Array = _legacy()["neighbourhoods"]
	check("there are as many neighbourhoods as there were", Neighbourhoods.all().size() == old.size())
	for i in old.size():
		var want: Dictionary = old[i]
		var r: Dictionary = Neighbourhoods.all()[i] if i < Neighbourhoods.all().size() else {}
		var same: bool = not r.is_empty() and String(r["id"]) == want["id"] and r["title"] == want["title"] \
				and Array(r["stations"]).map(func(s: StringName) -> String: return String(s)) == want["stations"] \
				and Array(r["pieces"]).map(func(s: StringName) -> String: return String(s)) == want["pieces"] \
				and is_equal_approx(float(r.get("lift", 0.0)), want["lift"])
		if same:
			var c: Color = r["colour"]
			var was := Color.html(want["colour"])
			# A hex colour is a byte a channel; the old rows were floats.
			same = absf(c.r - was.r) <= 1.0 / 255.0 and absf(c.g - was.g) <= 1.0 / 255.0 and absf(c.b - was.b) <= 1.0 / 255.0
		check("the %s neighbourhood is the old row" % want["id"], same)
	var frame: Array = _legacy()["mixing_banner"]
	for w in [11.2, 14.4]:
		var at := ControlRoom.banner(w) as Transform3D
		check("the MIXING banner hangs where it did in a %s m room" % w, at != null
				and absf(at.origin.x - frame[0]) < TOLERANCE and absf(at.origin.y - frame[1]) < TOLERANCE
				and absf(at.origin.z - frame[2]) < TOLERANCE and at.basis.is_equal_approx(Basis.IDENTITY))
	check("and only the mixing group has a banner of its own", Neighbourhoods.all().filter(
			func(r: Dictionary) -> bool: return r.has("banner")).size() == 1 and Neighbourhoods.row(&"mixing").has("banner"))


## The `fit` and `banner` keys are checked, and said so in words.
func seeded_violations() -> void:
	var piece := {"id": "a", "piece": "a", "at": {"pos": [0.0, 0.0]}}
	var cases := {
		"a fit that is not an object": [{"pieces": [piece.merged({"fit": 3})]}, "pieces[0].fit"],
		"a fit with no place": [{"pieces": [piece.merged({"fit": {"yaw": 1.0}})]}, "pieces[0].fit"],
		"a fit place of three numbers": [{"pieces": [piece.merged({"fit": {"at": [1.0, 2.0, 3.0]}})]}, "pieces[0].fit"],
		"a fit turn that is a word": [{"pieces": [piece.merged({"fit": {"at": [1.0, 2.0], "yaw": "left"}})]}, "pieces[0].fit"],
		"a banner that is not a placement": [{"pieces": [piece], "groups": [{"id": "g", "title": "G", "members": ["a"], "banner": 4}]}, "groups[0].banner"],
		"a banner anchored to nothing": [{"pieces": [piece], "groups": [{"id": "g", "title": "G", "members": ["a"],
				"banner": {"anchor": {"z": "nowhere"}, "pos": [0.0, 0.0]}}]}, "groups[0].banner"],
	}
	for label: String in cases:
		var l := LayoutData.parse({"format": "dawlings.layout", "version": 1, "id": "t", "title": "T"}.merged(cases[label][0]))
		check("%s is an error naming %s" % [label, cases[label][1]], l.errors().any(
				func(p: LayoutProblem) -> bool: return p.where.begins_with(cases[label][1])))
	var good := LayoutData.parse({"format": "dawlings.layout", "version": 1, "id": "t", "title": "T",
			"pieces": [piece.merged({"fit": {"at": [1.0, 2.0], "yaw": 0.5}})],
			"groups": [{"id": "g", "title": "G", "members": ["a"], "banner": {"anchor": {"z": "control_rear"},
					"pos": [0.0, 0.1], "up": "height.control_header"}}]})
	check("a fit and a banner written right are no problem", good.errors().is_empty())


## FloorImport answers what Studio.was_an_old_default did, probe for probe.
func classification() -> void:
	var probes: Array = _legacy()["old_default_probes"]
	var wrong := 0
	var first := ""
	for p: Array in probes:
		var saved := Transform3D(Basis(Vector3.UP, deg_to_rad(p[3])), Vector3(p[1], 0, p[2]))
		if FloorImport.was_old_default(StringName(p[0]), saved) != p[4]:
			wrong += 1
			first = first if first != "" else str(p)
	check("the import tells an old default from a pushed piece in all %d frozen probes (%d wrong, first %s)"
			% [probes.size(), wrong, first], wrong == 0 and probes.size() > 4000)
	check("some of the probes are old defaults and some are not", probes.any(func(p: Array) -> bool: return p[4])
			and probes.any(func(p: Array) -> bool: return not p[4]))


## The import forgets old defaults once, keeps a pushed piece, marks the profile and saves the mark.
func import_runs_once() -> void:
	var path := "user://test_floor_import.cfg"
	var at := func(x: float, z: float, deg: float) -> Transform3D:
		return Transform3D(Basis(Vector3.UP, deg_to_rad(deg)), Vector3(x, 0, z))
	var profile := LayoutProfile.new()
	profile.save_path = path
	profile.set_transform(&"floor/rack", Presentation.Mode.STUDIO, at.call(-1.75, -0.42, 45.0))
	profile.set_transform(&"floor/eq_wall", Presentation.Mode.STUDIO, at.call(3.38, -1.55, -74.0))
	profile.set_transform(&"floor/deck_trolley", Presentation.Mode.STUDIO, at.call(1.7, 0.9, 10.0))
	profile.set_transform(&"floor/rack", Presentation.Mode.ROOM, at.call(-1.75, -0.42, 45.0))
	check("a profile starts unimported", profile.floor_import == 0)
	check("the import forgot the two old defaults", FloorImport.run(profile) == 2)
	check("the old ones are gone, a pushed one and another mode's are kept",
			not profile.has_transform(&"floor/rack", Presentation.Mode.STUDIO)
			and not profile.has_transform(&"floor/eq_wall", Presentation.Mode.STUDIO)
			and profile.has_transform(&"floor/deck_trolley", Presentation.Mode.STUDIO)
			and profile.has_transform(&"floor/rack", Presentation.Mode.ROOM))
	check("and the profile is marked", profile.floor_import == FloorImport.VERSION)
	# Pushed back to an old default after the import: somebody's choice now.
	profile.set_transform(&"floor/rack", Presentation.Mode.STUDIO, at.call(-1.75, -0.42, 45.0))
	check("it does not run twice", FloorImport.run(profile) == 0 and profile.has_transform(&"floor/rack", Presentation.Mode.STUDIO))
	profile.save()
	var again := LayoutProfile.new()
	again.save_path = path
	again.load_saved()
	check("the mark is kept in the file", again.floor_import == FloorImport.VERSION and FloorImport.run(again) == 0)
	var fresh := LayoutProfile.new()
	check("a fresh profile has nothing to forget", FloorImport.run(fresh) == 0 and fresh.floor_import == FloorImport.VERSION)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
