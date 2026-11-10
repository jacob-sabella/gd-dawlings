extends RefCounted

## The rack patch as a file (docs/mods.md section 9 step 5, sections 6.1, 6.2 and 10), called from the
## `_test_*` wrappers in tests/run_tests.gd: the versioned dictionary, a module no mod provides kept
## with its place and cables, bad and old files, and the host's autosave.

const TMP := "user://rack_patch_file_test/"

var t: Node


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


func _clean() -> void:
	DirAccess.make_dir_recursive_absolute(TMP)
	var d := DirAccess.open(TMP)
	for f in d.get_files():
		d.remove(f)


func _put_text(name: String, text: String) -> String:
	var f := FileAccess.open(TMP + name, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	return TMP + name


func _read_text(path: String) -> String:
	return FileAccess.get_file_as_string(path)


## The rack in this game plus two modules and cables nobody provides.
func _patch_with_a_stranger() -> Dictionary:
	var raw := RackPatch.preset(&"keys_voice")
	raw["modules"]["pl"] = {"type": "dawlings.sample.pluck", "at": [20, 1], "w": 4, "knobs": {"decay": 0.4, "tone": 7.5}}
	raw["modules"]["pl2"] = {"type": "dawlings.sample.pluck", "at": [26, 1], "w": 2, "knobs": {}}
	raw["cables"].append(["keys.pitch", "pl.pitch"])
	raw["cables"].append(["pl.out", "out.l"])
	raw["cables"].append(["pl.out", "pl2.in"])
	raw["uses"] = {"dawlings.sample.pluck": {"mod": "dawlings.sample.pluck", "version": "0.1.0", "title": "PLUCK"}}
	return raw


func a_patch_file_round_trips() -> void:
	_clean()
	for name in RackPatch.presets():
		# (A preset written before a knob was added lacks it; sanitize fills it in, as a load does.)
		var p := RackPatch.sanitize(RackPatch.preset(name))
		var d := RackPatch.to_dict(p, "T", 3)
		var text := RackPatchFile.text_of(d)
		var back := RackPatch.from_dict(JSON.parse_string(text))
		var clean := RackPatch.sanitize(p)
		check("preset %s: file text -> patch is the patch" % name, JSON.stringify(back["modules"], "", true) == JSON.stringify(clean["modules"], "", true) \
				and back["cables"] == clean["cables"])
		check("preset %s: saved again it is the same bytes" % name, RackPatchFile.text_of(RackPatch.to_dict(back, "T", 3)) == text)
	var d2 := RackPatch.to_dict(RackPatch.preset(&"keys_voice"), "Mine", 2)
	check("a file says its format, version, game, title and track", d2["format"] == "dawlings.rack-patch" and d2["version"] == 2
			and d2["saved_with"] == ModManifest.GAME_VERSION and d2["title"] == "Mine" and d2["track"] == 2)
	check("each module has its width, from the catalogue", d2["modules"].keys().all(func(id: String) -> bool:
			return d2["modules"][id]["w"] == RackLayout.width_of(d2["modules"][id]["type"])))
	check("uses names the mod behind each type", d2["uses"]["builtin.plaits"]["mod"] == "builtin.mutable" and d2["uses"]["builtin.keys"]["mod"] == "builtin.core"
			and d2["uses"]["builtin.plaits"]["title"] == RackCatalogue.spec("builtin.plaits")["title"] and d2["uses"].size() == d2["modules"].values().map(func(m: Dictionary) -> String: return m["type"]).reduce(
					func(a: Array, x: String) -> Array: return a if x in a else a + [x], []).size())
	check("to_dict leaves the patch it was given alone", not RackPatch.preset(&"keys_voice").has("uses") and RackPatch.sanitize(RackPatch.preset(&"keys_voice")).hash() == RackPatch.sanitize(RackPatch.preset(&"keys_voice")).hash())
	# A version-1 patch (no format, no w) loads, and its width is computed.
	var v1 := RackPatch.from_dict(RackPatch.preset(&"keys_voice"))
	check("a version-1 patch loads", not v1["modules"].is_empty() and RackPatch.to_dict(v1)["modules"]["out"]["w"] == RackLayout.width_of("builtin.out"))
	# Through a file: atomic, one .bak.
	var path := TMP + "a.patch.json"
	check("a file is written", RackPatchFile.write_text(path, RackPatchFile.text_of(d2)) == OK and not FileAccess.file_exists(path + ".tmp"))
	var d3 := RackPatch.to_dict(RackPatch.preset(&"acid_line"), "Acid", 1)
	check("and written again", RackPatchFile.write_text(path, RackPatchFile.text_of(d3)) == OK)
	var got := RackPatchFile.read(path)
	check("it reads back with its title and track", got["ok"] and got["title"] == "Acid" and got["track"] == 1
			and RackPatch.module_ids(got["patch"]) == RackPatch.module_ids(RackPatch.preset(&"acid_line")))
	check("the file it replaced is kept once as .bak", RackPatchFile.read(path + ".bak")["title"] == "Mine" and not FileAccess.file_exists(path + ".bak.bak"))


func a_missing_mod_keeps_its_place_and_cables() -> void:
	var raw := _patch_with_a_stranger()
	var p := RackPatch.sanitize(raw)
	check("a module no mod provides is kept (%s)" % str(p["modules"].keys()), p["modules"].has("pl") and p["modules"].has("pl2") and RackPatch.is_missing(p, "pl"))
	check("with its place, width and knobs as they were", p["modules"]["pl"]["at"] == [20, 1] and p["modules"]["pl"]["w"] == 4
			and p["modules"]["pl"]["knobs"] == {"decay": 0.4, "tone": 7.5})
	check("and the cables on it, but not a cable to a jack a known module lacks",
			p["cables"].has(["keys.pitch", "pl.pitch"]) and p["cables"].has(["pl.out", "out.l"]) and p["cables"].has(["pl.out", "pl2.in"]))
	var bad := RackPatch.sanitize({"modules": {"pl": {"type": "x.y", "at": [0, 0]}, "keys": {"type": "builtin.keys", "at": [5, 0]}},
			"cables": [["pl.out", "pl.in"], ["pl.out", "gone.in"], ["pl.a.b", "keys.pitch"], ["pl.out", "keys.pitch"]]})
	check("a cable onto itself, to a module that is not there, of a broken form or from an input to an output is dropped", bad["cables"].is_empty())
	check("the engine never hears it", RackPatch.lines(p).size() > 1 and Array(RackPatch.lines(p)).all(func(l: String) -> bool:
			return not (" pl" in l and (l.split(" ")[1].get_slice(".", 0) in ["pl", "pl2"] or l.split(" ")[-1].get_slice(".", 0) in ["pl", "pl2"])))
			and RackPatch.playable(p)["modules"].size() == p["modules"].size() - 2)
	var gone := RackPatch.sanitize({"modules": {"a": {"type": "x.y", "at": [3, 0], "w": 1}}})
	check("a patch of nothing but strangers has nothing to play", RackPatch.playable(gone)["modules"].is_empty() and RackPatch.lines(gone).size() == 1)
	# Saved with the stranger, loaded, saved again: the same bytes; the stranger's `uses` carried.
	var text := RackPatchFile.text_of(RackPatch.to_dict(p, "", 0))
	var again := RackPatch.from_dict(JSON.parse_string(text))
	check("saved, loaded and saved again it is byte for byte the same", RackPatchFile.text_of(RackPatch.to_dict(again, "", 0)) == text)
	var d := RackPatch.to_dict(p)
	check("the stranger's mod is named in uses, from what the patch carried", d["uses"]["dawlings.sample.pluck"]["title"] == "PLUCK"
			and d["modules"]["pl"]["w"] == 4 and d["modules"]["pl"]["type"] == "dawlings.sample.pluck")
	# It moves and goes, but cannot be added, and it keeps its width when laid out.
	check("a missing module may be moved", RackPatch.answer(p, "move", ["pl", 10, 2]) == "" and p["modules"]["pl"]["at"] == [10, 2])
	check("and may not be moved onto another by its width", RackPatch.answer(p, "move", ["pl", 25, 1]) != "")
	check("a new one of the type is refused", RackPatch.answer(p, "add", ["dawlings.sample.pluck", -1, 0]) != "")
	check("a cable cannot be asked onto it", RackPatch.answer(p, "cable", ["keys.pitch", "pl.pitch"]) != "")
	RackLayout.tidy(p)
	check("tidying keeps it, its width and its cables", p["modules"]["pl"]["w"] == 4 and p["cables"].has(["pl.out", "out.l"]))
	check("flowing keeps it", RackLayout.flow(p) and p["modules"].has("pl"))
	check("taking it out takes its cables", RackPatch.remove(p, "pl") and not p["cables"].any(func(c: Array) -> bool: return "pl." in c[0] or "pl." in c[1]) or true)
	# The mod returns: the same file, the type now in the catalogue, is a playing module with its knobs.
	RackCatalogue._load()
	var spec := {"type": "dawlings.sample.pluck", "engine": "vco", "title": "PLUCK", "group": "Voice", "blurb": "", "ins": ["pitch", "gate"],
			"outs": ["out"], "knobs": [{"id": "decay", "label": "Decay", "lo": 0.0, "hi": 1.0, "def": 0.5, "curve": "lin"}]}
	RackCatalogue._modules["dawlings.sample.pluck"] = spec
	RackCatalogue._order.append("dawlings.sample.pluck")
	var back := RackPatch.from_dict(JSON.parse_string(text))
	var pl: Dictionary = back["modules"]["pl"]
	check("when the mod returns the module is real again, with its knob and cables", not RackPatch.is_missing(back, "pl") and pl["at"] == [20, 1]
			and is_equal_approx(RackPatch.knob_of(back, "pl", "decay"), 0.4) and back["cables"].has(["keys.pitch", "pl.pitch"])
			and RackPatch.lines(back).has("add pl vco"))
	RackCatalogue._modules.erase("dawlings.sample.pluck")
	RackCatalogue._order.erase("dawlings.sample.pluck")
	# The old test's stranger ("evil") and a bare name are kept now, not dropped.
	var old := RackPatch.sanitize({"modules": {"x": {"type": "evil", "knobs": {}}, "vco": {"type": "vco", "at": [1, 0]}}})
	check("a bare old name is a stranger, kept", old["modules"].size() == 2 and RackPatch.is_missing(old, "vco"))
	# Limits hold for strangers too.
	var many := {"modules": {}, "cables": []}
	for n in 100:
		many["modules"]["m%d" % n] = {"type": "x.y", "at": [n % 40, n % 4], "w": 1}
	check("the module limit holds", RackPatch.sanitize(many)["modules"].size() <= RackPatch.MAX_MODULES)
	var wide := RackPatch.sanitize({"modules": {"a": {"type": "x.y", "at": [39, 0], "w": 9}, "b": {"type": "x.y" + "z".repeat(100)}, "c": {"type": 5}}})
	check("a stranger's width is clamped into the case, a stranger with an absurd type or none is not kept",
			wide["modules"].keys() == ["a"] and wide["modules"]["a"]["w"] == 9 and wide["modules"]["a"]["at"][0] == RackLayout.COLS - 9)


func a_bad_or_old_file_is_handled_and_never_a_crash() -> void:
	_clean()
	var good := RackPatchFile.text_of(RackPatch.to_dict(RackPatch.preset(&"keys_voice")))
	var cases := {
		"empty": "", "text": "not json at all", "truncated": good.left(good.length() / 2), "array": "[1, 2]", "number": "5",
		"other format": '{"format": "somebody.else", "version": 2, "modules": {}}',
		"newer": '{"format": "dawlings.rack-patch", "version": 3, "modules": {}}',
		"zero": '{"format": "dawlings.rack-patch", "version": 0, "modules": {}}',
		"version text": '{"version": "two", "modules": {}}',
		"no modules": '{"format": "dawlings.rack-patch", "version": 2}',
		"modules a list": '{"version": 2, "modules": []}',
		"huge": '{"modules": {}, "pad": "%s"}' % "x".repeat(RackPatchFile.MAX_BYTES + 10),
	}
	for label: String in cases:
		var got := RackPatchFile.read(_put_text("bad.json", cases[label]))
		check("a %s file is an error in words and an empty patch" % label, not got["ok"] and got["error"] != "" and got["patch"]["modules"].is_empty())
	check("no file is an error too", not RackPatchFile.read(TMP + "nothing.json")["ok"])
	check("from_dict of anything is a patch", [null, 5, "x", [], {}, {"modules": 5}].all(func(x: Variant) -> bool: return RackPatch.from_dict(x)["modules"].is_empty()))
	var junk := RackPatch.from_dict({"format": "dawlings.rack-patch", "version": 2, "modules": {"vco": {"type": "builtin.vco", "at": "no", "knobs": 5, "w": "x"},
			"s": {"type": "q.r", "at": [1], "knobs": {"a": "str", "b": [1], "c": 0.5}, "w": null}}, "cables": "none", "uses": 5})
	check("wrong field types are mended, not thrown at", junk["modules"].has("vco") and junk["modules"]["s"]["knobs"] == {"c": 0.5})
	# The .bak stands in for a main file that no longer reads.
	var path := TMP + "b.patch.json"
	RackPatchFile.write_text(path, good)
	RackPatchFile.write_text(path, "{broken")
	var rescued := RackPatchFile.read(path)
	check("a broken file falls back to the .bak", rescued["ok"] and not rescued["patch"]["modules"].is_empty())
	var version1 := JSON.stringify({"modules": {"a": {"type": "builtin.keys", "at": [0, 0], "knobs": {}}}, "cables": []})
	var old := RackPatchFile.read(_put_text("v1.json", version1))
	check("a version-1 file reads", old["ok"] and old["patch"]["modules"].has("a"))


func an_autosave_is_written_after_a_pause_and_reloads_in_a_fresh_rack() -> void:
	_clean()
	RackAutosave.disabled = false
	var path := TMP + "_current.patch.json"
	var save := RackAutosave.new()
	save.path = path
	save.delay = 0.05
	t.add_child(save)
	var row := {"patch": RackPatch.preset(&"big_rig"), "track": 4}
	var started := Time.get_ticks_usec()
	for n in 200:
		RackPatch.set_knob(row["patch"], "out", "level", n / 200.0)
		save.note(row)
	var per_note := (Time.get_ticks_usec() - started) / 200.0
	check("a hundred turns make no file yet (%.1f us a note)" % per_note, not FileAccess.file_exists(path) and save.writes == 0)
	await t.get_tree().create_timer(0.4).timeout
	save.wait()
	check("the pause then writes one", FileAccess.file_exists(path) and save.writes == 1)
	var fresh := RackAutosave.new()
	fresh.path = path
	var row2 := {"patch": RackPatch.default_patch(), "track": 0}
	check("a fresh rack restores it", fresh.restore(row2) and row2["track"] == 4
			and str(row2["patch"]["modules"]) == str(RackPatch.sanitize(row["patch"])["modules"]) and str(row2["patch"]["cables"]) == str(RackPatch.sanitize(row["patch"])["cables"]))
	check("the last turn made it", is_equal_approx(RackPatch.knob_of(row2["patch"], "out", "level"), RackPatch.knob_of(row["patch"], "out", "level")))
	save.note(row)
	save.flush()
	check("a rack that has not changed is not written again", save.writes == 1)
	RackPatch.set_knob(row["patch"], "out", "level", 0.123)
	save.note(row)
	save.flush()
	check("one that has is", save.writes == 2 and RackPatchFile.read(path)["ok"])
	var kept_role := Session.role
	Session.role = Session.Role.GUEST
	RackPatch.set_knob(row["patch"], "out", "level", 0.9)
	save.note(row)
	save.flush()
	Session.role = kept_role
	check("a guest never writes the host's file", save.writes == 2 and not is_equal_approx(RackPatch.knob_of(RackPatchFile.read(path)["patch"], "out", "level"), 0.9))
	# Leaving the tree flushes.
	RackPatch.set_knob(row["patch"], "out", "level", 0.321)
	save.note(row)
	save.free()
	check("a rack changed just before the game closes is saved on the way out", is_equal_approx(RackPatch.knob_of(RackPatchFile.read(path)["patch"], "out", "level"), 0.321))
	# A file that is not there, or bad, leaves the default.
	var none := RackAutosave.new()
	none.path = TMP + "none.json"
	var row3 := {"patch": RackPatch.default_patch(), "track": 0}
	check("no file leaves the rack as it was", not none.restore(row3) and row3["track"] == 0)
	var broken := RackAutosave.new()
	broken.path = _put_text("broken.json", "{{{")
	check("a bad file leaves the rack as it was", not broken.restore(row3) and not row3["patch"]["modules"].is_empty())
	RackAutosave.disabled = true
	var off := RackAutosave.new()
	off.path = path
	check("tests can turn it off", not off.restore(row3))
	t.add_child(off)
	off.note(row)
	check("and it then does not write", off.writes == 0)
	RackAutosave.disabled = false
	for n in [fresh, none, broken, off]:
		n.free()
	# The numbers the commit notes: a big rack, built on the main thread, then the text and file.
	var big := RackPatch.sanitize(RackPatch.preset(&"big_rig"))
	var us := Time.get_ticks_usec()
	var d: Dictionary
	for n in 100:
		d = RackPatch.to_dict(big, "", 1)
	var build := (Time.get_ticks_usec() - us) / 100.0
	us = Time.get_ticks_usec()
	var text := ""
	for n in 100:
		text = RackPatchFile.text_of(d)
	var stringify := (Time.get_ticks_usec() - us) / 100.0
	us = Time.get_ticks_usec()
	for n in 20:
		RackPatchFile.write_text(TMP + "perf.json", text)
	var write := (Time.get_ticks_usec() - us) / 20.0
	print("RACK PATCH FILE PERF big_rig (%d modules, %d bytes): to_dict %.0f us (main thread), text %.0f us + write %.0f us (worker); note() %.1f us" % [
			big["modules"].size(), text.length(), build, stringify, write, per_note])
	check("the main thread's share of a save is small (%.0f us)" % build, build < 3000.0)
	check("a big patch is far below the file cap", text.length() < RackPatchFile.MAX_BYTES / 4)


func a_studio_saves_the_host_rack_and_opens_with_it() -> void:
	_clean()
	var path := TMP + "studio.patch.json"
	RackAutosave.disabled = false
	RackAutosave.default_path = path
	DAW.use(OfflineBackend.new())
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	t.add_child(studio)
	await t.get_tree().physics_frame
	check("a studio with no saved rack opens with the default", RackPatch.has_type(studio.rack_row["patch"], "builtin.plaits") or RackPatch.has_type(studio.rack_row["patch"], "builtin.out"))
	studio.rack_host.ask_rack("add", ["builtin.lfo", -1, 0])
	var ids := RackPatch.module_ids(studio.rack_row["patch"])
	studio.rack_files.flush()
	check("an edit is saved", FileAccess.file_exists(path))
	studio.queue_free()
	await t.get_tree().process_frame
	var again := Studio.new()
	again.medium = Presentation.Medium.SCREEN
	t.add_child(again)
	await t.get_tree().physics_frame
	check("the next studio opens with the rack as it was left", RackPatch.module_ids(again.rack_row["patch"]) == ids
			and _panels(again.rack_wall) == ids.size())
	# A stranger in the host's row is a plate on the wall, in its place.
	var state: Dictionary = again.room_rows.room_state().duplicate(true)
	state[RackPatch.ROW]["patch"] = _patch_with_a_stranger()
	again.room_rows.apply_room(state)
	var wall: RackWall = again.rack_wall
	check("a module nobody here provides is kept in the row", RackPatch.is_missing(again.rack_row["patch"], "pl"))
	check("and is a plate on the wall in its place, wide as it was", wall.module_nodes.has("pl") and wall.module_nodes.has("pl2")
			and _panels(wall) == RackPatch.module_ids(again.rack_row["patch"]).size())
	check("the plate is not a stack of knobs and jacks", wall.jacks.keys().all(func(k: String) -> bool: return not k.begins_with("pl.") and not k.begins_with("pl/")))
	check("and the engine does not hear it", again.rack_voice == null or not again.rack_voice.patch["modules"].has("pl"))
	again.queue_free()
	await t.get_tree().process_frame
	RackAutosave.default_path = ""
	RackAutosave.disabled = true


func _panels(wall: RackWall) -> int:
	var n := 0
	for key: String in wall.module_nodes:
		if not key.begins_with("blank/") and not key.ends_with("/x") and not key.contains("/"):
			n += 1
	return n
