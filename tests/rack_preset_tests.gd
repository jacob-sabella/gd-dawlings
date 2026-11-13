extends RefCounted

## The rack's presets pop-up (RackPresetScreen) and the player's own presets (RackUserPresets), called from
## tests/run_tests.gd's `_test_rack_preset_*`. Every test keeps its presets in a folder of its own.

var t: Node

const DIR := "user://rack_preset_tests"


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


func _fresh_dir() -> void:
	RackUserPresets.dir_override = DIR
	var d := DirAccess.open(DIR)
	if d != null:
		for f in d.get_files():
			DirAccess.remove_absolute(DIR.path_join(f))


func _done() -> void:
	_fresh_dir()
	DirAccess.remove_absolute(DIR)
	RackUserPresets.dir_override = ""


## Saved, listed, read back, loaded onto a rack through the `load` ask and deleted.
func own_presets_save_and_load() -> void:
	_fresh_dir()
	var rack := RackPatch.preset(&"acid_line")
	check("a name with nothing in it is refused", RackUserPresets.save("  !! ", rack) != "")
	check("an empty rack is refused", RackUserPresets.save("Nothing", RackPatch.empty()) != "")
	check("a rack is kept under its name", RackUserPresets.save("My Acid  Line!", rack) == "")
	check("its file name is plain", RackUserPresets.name_of("My Acid  Line!") == "my_acid_line"
			and FileAccess.file_exists(DIR.path_join("my_acid_line.patch.json")))
	var all := RackUserPresets.all()
	check("it is listed with the title typed", all.size() == 1 and all[0]["title"] == "My Acid  Line!")
	check("and is known by that title", RackUserPresets.has("my acid line"))
	var d := RackUserPresets.patch_dict("my_acid_line")
	var p := RackPatch.preset(&"keys_voice")
	check("the load ask puts it on a rack", RackPatch.answer(p, "load", [d]) == "")
	check("module for module and cable for cable", RackPatch.module_ids(p) == RackPatch.module_ids(rack)
			and p["cables"].size() == rack["cables"].size())
	check("a load of something that is not a patch is refused in words", RackPatch.answer(p, "load", ["junk"]) != ""
			and RackPatch.answer(p, "load", [{"format": "nope", "modules": {}}]) != "")
	check("and leaves the rack alone", RackPatch.module_ids(p) == RackPatch.module_ids(rack))
	check("deleted, it is gone", RackUserPresets.remove("my_acid_line") and RackUserPresets.all().is_empty())
	_done()


## The pop-up: the ready-made presets and the player's own, found by name or module; LOAD asks the host,
## SAVE keeps the rack (twice to replace), DELETE forgets one (twice).
func popup_finds_loads_saves_and_deletes() -> void:
	_fresh_dir()
	var screen := RackPresetScreen.new()
	t.add_child(screen)
	var rack := [RackPatch.preset(&"drum_machine")]
	screen.on_rack = func() -> Dictionary: return rack[0]
	var asked: Array = []
	screen.load_asked.connect(func(op: String, args: Array) -> void: asked.append([op, args]))
	screen.open_presets()
	check("it opens", screen.is_open())
	check("every ready-made preset is listed", RackPresetScreen.search("").size() == RackPatch.presets().size())
	check("found by a word of the name", RackPresetScreen.search("acid").any(func(it: Dictionary) -> bool: return it["name"] == "acid_line"))
	check("nothing for nonsense", RackPresetScreen.search("zzqqx").is_empty())
	var titles := RackPresetScreen.module_titles(RackPatch.preset(&"acid_line"))
	check("a preset says what modules it holds (%s)" % ", ".join(titles), titles.size() > 1)
	check("found by a module in it", RackPresetScreen.search(titles[0].get_slice(" x", 0).to_lower()).any(
			func(it: Dictionary) -> bool: return it["name"] == "acid_line"))
	screen._search.text = "acid"
	screen.refresh()
	screen._load_chosen()
	check("LOAD of a ready-made one asks for the preset", asked == [["preset", ["acid_line"]]])
	screen._name.text = "Drums Mine"
	check("SAVE keeps the rack as it is", screen.save_current() == "" and RackUserPresets.has("Drums Mine"))
	check("and the list shows it, chosen", screen.chosen().get("name") == "drums_mine" and screen.chosen().get("kind") == "own")
	asked.clear()
	screen._load_chosen()
	check("LOAD of one of your own sends the patch itself", asked.size() == 1 and asked[0][0] == "load"
			and RackPatch.from_dict(asked[0][1][0])["modules"].size() == rack[0]["modules"].size())
	rack[0] = RackPatch.preset(&"keys_voice")
	screen._name.text = "Drums Mine"
	screen.save_current()
	var kept := RackPatch.from_dict(RackUserPresets.patch_dict("drums_mine"))
	check("a name used already is not replaced at the first SAVE", kept["modules"].size() == RackPatch.preset(&"drum_machine")["modules"].size()
			and screen._save.text != "SAVE")
	screen.save_current()
	kept = RackPatch.from_dict(RackUserPresets.patch_dict("drums_mine"))
	check("but at the second", kept["modules"].size() == RackPatch.preset(&"keys_voice")["modules"].size())
	check("DELETE shows for your own", screen._delete.visible)
	screen._delete_chosen()
	check("one press of DELETE only asks", RackUserPresets.has("Drums Mine"))
	screen._delete_chosen()
	check("the second deletes it", not RackUserPresets.has("Drums Mine"))
	screen._search.text = ""
	screen.refresh()
	screen._list.select(0)
	screen._describe()
	check("DELETE does not show for a ready-made one", not screen._delete.visible)
	screen.close_presets()
	check("CLOSE shuts it", not screen.is_open())
	screen.queue_free()
	_done()


## The PRESETS key of the palette opens the pop-up rather than laying presets out as keys.
func presets_key_asks_for_the_popup() -> void:
	var wall := RackWall.new()
	t.add_child(wall)
	wall.show_patch(RackPatch.preset(&"keys_voice"))
	var asked := [0]
	wall.presets_asked.connect(func() -> void: asked[0] += 1)
	var key: EqWall.WallKey = null
	for n in wall._palette_nodes:
		if n is EqWall.WallKey and (n as EqWall.WallKey).legend == RackWall.GROUP_PRESETS:
			key = n
	check("the palette has a PRESETS key", key != null)
	if key != null:
		key.pressed.emit()
	check("which asks for the pop-up", asked[0] == 1)
	check("and lays no presets out as keys", wall.group != RackWall.GROUP_PRESETS)
	wall.queue_free()


## The pop-ups stay on a 1280x720 screen however long what they show.
func popups_stay_on_screen() -> void:
	_fresh_dir()
	var box := SubViewport.new()
	box.size = Vector2i(1280, 720)
	t.add_child(box)
	var vp := Rect2(Vector2.ZERO, Vector2(box.size))
	var screen := RackPresetScreen.new()
	box.add_child(screen)
	screen.open_presets()
	await t.get_tree().process_frame
	var r: Rect2 = screen._panel.get_global_rect()
	check("the presets pop-up is on the screen (%s in %s)" % [r, vp], vp.encloses(r))
	var finder := MilkFinderScreen.new()
	box.add_child(finder)
	finder._panel.visible = true
	finder._detail.text = "a long blurb\n".repeat(80)
	finder._pack_status.text = "a status that goes on ".repeat(30)
	finder._fit()
	await t.get_tree().process_frame
	await t.get_tree().process_frame
	r = finder._panel.get_global_rect()
	check("the picture finder is on the screen with a long blurb (%s in %s)" % [r, vp], vp.encloses(r))
	box.queue_free()
	_done()
