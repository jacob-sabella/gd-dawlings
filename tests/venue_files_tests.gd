extends RefCounted

## The 14 venue files and the roulette room (docs/layouts.md section 11 step 7), called from the
## `_test_*` wrappers in tests/run_tests.gd. `Venue.IDS`, `Venue.variant_titles`, `Venue.make_title`,
## `Venue.make` and `RackMood.palette` are read from `layouts/venues/*.layout.json`; they are held to
## tests/fixtures/layouts/venue_tables_legacy.json, dumped from the tables in code before they were deleted.

const FIXTURE := "res://tests/fixtures/layouts/venue_tables_legacy.json"
## A mood colour is a byte a channel in the file; the old floats were typed by hand.
const COLOUR_TOLERANCE := 1.0 / 255.0

var t: Node


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


func _legacy() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))


func _close(c: Color, rgb: Array) -> bool:
	return absf(c.r - float(rgb[0])) <= COLOUR_TOLERANCE and absf(c.g - float(rgb[1])) <= COLOUR_TOLERANCE \
			and absf(c.b - float(rgb[2])) <= COLOUR_TOLERANCE


## The cycle, the names, the arrangements and the moods are what the deleted tables said.
func tables_are_the_files() -> void:
	var old := _legacy()
	var ids: Array = Array(Venue.IDS).map(func(i: StringName) -> String: return String(i))
	check("Venue.IDS is the 14 venues in the old cycling order (%s)" % [ids], ids == old["ids"])
	for id: String in old["ids"]:
		var sid := StringName(id)
		check("%s: its name is the old one" % id, Venue.make_title(sid) == old["titles"][id])
		check("%s: its arrangements are the old ones, in order" % id, Array(Venue.variant_titles(sid)) == old["variants"][id])
		var m := RackMood.palette(sid)
		var want: Dictionary = old["moods"][id]
		check("%s: its mood is the old one to a byte" % id, _close(m["base"], want["base"]) and _close(m["hit"], want["hit"])
				and absf(m["glow"] - float(want["glow"])) < 1e-6)
		check("%s: it builds its own shell" % id, _builds(sid))
	check("the roulette room is named, is not cycled, and has one arrangement", Venue.make_title(Venue.ROULETTE_ID) == old["roulette_title"]
			and not Venue.IDS.has(Venue.ROULETTE_ID) and Venue.is_known(Venue.ROULETTE_ID)
			and Array(Venue.variant_titles(Venue.ROULETTE_ID)) == old["variants"]["roulette"]
			and _builds(Venue.ROULETTE_ID))
	check("a name nobody ships is the studio's, with one arrangement and the fallback mood", Venue.make_title(&"nowhere") == old["unknown_title"]
			and Array(Venue.variant_titles(&"nowhere")) == old["variants"]["nowhere"]
			and RackMood.palette(&"nowhere") == RackMood.FALLBACK and _builds(&"nowhere", &"studio"))
	check("next_after cycles through the files' order and home again", Venue.next_after(Venue.IDS[Venue.IDS.size() - 1]) == Venue.IDS[0]
			and Venue.next_after(Venue.IDS[0]) == Venue.IDS[1])


## `Venue.make(id)` is a shell whose own id is `id` (`as_id` when the name is nobody's).
func _builds(id: StringName, as_id := id) -> bool:
	var v := Venue.make(id)
	var ok := v.venue_id() == as_id
	v.free()
	return ok


## Fifteen files, each valid on its own and resolved with its fragments; the shell builders are all in
## the one table; nothing but the files decides which venues exist.
func files_are_shipped_and_valid() -> void:
	var set := LiveRoom.layouts()
	var shell_names := {}
	for id: StringName in Venue.IDS + [Venue.ROULETTE_ID]:
		var file := set.layouts.get(String(id)) as LayoutData
		check("%s: a file ships and parses clean (%s)" % [id, file.problems if file != null else "missing"],
				file != null and file.status == LayoutData.STATUS_OK and file.problems.is_empty())
		if file == null:
			continue
		check("%s: it extends both common fragments" % id, file.extends_ids == ["common.control_room", "common.live_room"])
		var builder := VenueCatalogue.builder_of(id)
		shell_names[builder] = true
		check("%s: its shell builder (%s) is in the one table" % [id, builder], ShellBuilders.BY_NAME.has(builder))
		for v in maxi(1, file.variants.size()):
			var room := set.resolve(String(id), v)
			check("%s/%d: it resolves, with the wheeled five and the control room's furniture" % [id, v],
					room.status == LayoutData.STATUS_OK and room.piece(&"hoop") != {} and room.piece(&"eq_wall") != {}
					and room.pieces().size() == 22)
	var rooftop := Venue.make(&"rooftop")
	check("a venue stands none of the control room's furniture (the studio does, in the room's width)", rooftop.default_spot(&"mini_table") == null
			and rooftop.default_spot(&"eq_wall") == null and rooftop.default_spot(&"hoop") != null)
	rooftop.free()
	check("15 builders are named, one for each file, and the table has no others (%d)" % shell_names.size(),
			shell_names.size() == 15 and ShellBuilders.BY_NAME.size() == 15)
	check("the cycle is exactly the files with an order, and the roulette room has none", set.venue_ids() == Venue.IDS
			and (set.layouts["roulette"] as LayoutData).order == -1)
	check("only the studio's arrangements move a piece", (set.layouts["studio"] as LayoutData).variants[1].has("pieces")
			and Venue.IDS.slice(1).all(func(i: StringName) -> bool:
				return (set.layouts[String(i)] as LayoutData).variants.all(func(v: Dictionary) -> bool: return v.keys() == ["title"])))
	# A room built from a file nobody wrote in code: a new venue is a layout and a line in the table.
	var extra := LayoutSet.new()
	extra.scan(["res://layouts"])
	extra.add(LayoutData.parse({"format": "dawlings.layout", "version": 1, "id": "annexe", "title": "Annexe", "order": 14,
			"extends": ["common.live_room"], "shell": {"builder": "DesertVenue"}, "mood": {"glow": 0.5}, "variants": [{"title": "One"}, {"title": "Two"}]}))
	check("a file added to the set joins the cycle after the others", extra.venue_ids().size() == 15 and extra.venue_ids()[14] == &"annexe")
