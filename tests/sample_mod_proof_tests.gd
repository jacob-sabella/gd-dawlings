extends RefCounted

## The proof of the mod system (docs/mods.md section 9 step 9 and section 10): the sample mod
## `mods_examples/dawlings.sample.pluck/` is copied, as a folder and nothing else, into a temporary
## user mods root, and must (a) appear in the registry, the rack catalogue, the ADD list and the presets,
## (b) play through the engine like the same modules patched by hand, (c) save to a patch file and reload
## in a fresh rack, and (d) replicate: a guest with the mod sees the real plate, a guest without it sees
## the named unavailable plate and the host's sound is still the one heard. Nothing in the game's code
## names the mod. Called from the `_test_*` wrapper in tests/run_tests.gd.

const SAMPLE := "res://mods_examples/dawlings.sample.pluck"
const ID := "dawlings.sample.pluck"
const TMP := "user://sample_mod_proof/"

var t: Node


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


## Copies a folder tree (files only need be small text).
func _copy(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	for f in DirAccess.get_files_at(from):
		var src := FileAccess.open(from.path_join(f), FileAccess.READ)
		var dst := FileAccess.open(to.path_join(f), FileAccess.WRITE)
		dst.store_buffer(src.get_buffer(src.get_length()))
	for d in DirAccess.get_directories_at(from):
		_copy(from.path_join(d), to.path_join(d))


func _remove(path: String) -> void:
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	for d in DirAccess.get_directories_at(path):
		_remove(path.path_join(d))
	DirAccess.remove_absolute(path)


## Makes the game's registry the one scanning the shipped mods plus (when given) the user root named
## through the same list `$DAWLINGS_MODS` takes, and forgets what the rack caches of the old one.
func _use(root: String) -> ModRegistry:
	var reg := ModRegistry.new()
	reg.scan(ModRegistry.default_roots(ProjectSettings.globalize_path(root) if root != "" else ""))
	ModRegistry.current = reg
	RackCatalogue._forget()
	RackSkin._forget()
	return reg


func _labels(holder: Node) -> Array:
	var words: Array = []
	for l in holder.find_children("*", "Label3D", true, false):
		words.append((l as Label3D).text)
	return words


func _peak(frames: PackedVector2Array, from: int, to: int) -> float:
	var p := 0.0
	for i in range(from, mini(to, frames.size())):
		p = maxf(p, maxf(absf(frames[i].x), absf(frames[i].y)))
	return p


func _same(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not a[i].is_equal_approx(b[i]):
			return false
	return true


## The preset's patch with the plate's timbre set, so the by-hand patch can name the same value.
func _demo_patch(reg: ModRegistry) -> Dictionary:
	var p := RackPatch.preset(&"pluck_demo")
	p["modules"]["pl"]["knobs"]["timbre"] = 0.5
	return p


func the_proof() -> void:
	var kept := ModRegistry.current
	var home := TMP.path_join("mods")
	if DirAccess.dir_exists_absolute(TMP):
		_remove(TMP)
	DirAccess.make_dir_recursive_absolute(home)
	check("the sample is a folder in the repo with a manifest and a README", FileAccess.file_exists(SAMPLE + "/mod.json") and FileAccess.file_exists(SAMPLE + "/README.md"))

	# Without the folder dropped in, the game has never heard of it.
	var bare := _use(home)
	check("before the drop the mod is not in the registry, the catalogue or the ADD list", bare.mod(ID) == null and not RackCatalogue.has(ID)
			and not RackCatalogue.in_group("Voice").has(ID) and not RackPatch.presets().has(&"pluck_demo"))

	# (a) It appears.
	_copy(SAMPLE, home.path_join(ID))
	var reg := _use(home)
	var mine := reg.problems().filter(func(p: ModProblem) -> bool: return p.mod == ID)
	check("(a) the dropped folder is a mod of the registry, available, with no problem (%s)" % str(mine), reg.is_available(ID) and mine.is_empty()
			and reg.mod(ID).version == "0.1.0")
	check("(a) its module is in the rack catalogue as a composite with the plate's own jacks and knobs", RackCatalogue.has(ID) and reg.is_composite(ID)
			and RackCatalogue.spec(ID)["ins"] == ["pitch", "gate"] and RackCatalogue.spec(ID)["outs"] == ["out"]
			and RackCatalogue.knob_ids(ID) == ["timbre", "decay"])
	check("(a) it is in the ADD list, in the group it names, after the engine's own", RackCatalogue.in_group("Voice").has(ID) and RackCatalogue.types().has(ID)
			and RackCatalogue.types().find(ID) > RackCatalogue.types().find("builtin.hand") and RackCatalogue.spec(ID)["title"] == "PLUCK")
	check("(a) and its preset is among the presets", RackPatch.presets().has(&"pluck_demo") and RackPatch.preset_title(&"pluck_demo") == "Pluck demo")
	check("(a) the skin is the mod's", RackSkin.tagline(ID) == "PLUCK IT" and RackSkin.accent(ID).to_html(false).to_upper() == "E6FF6A")
	var added := RackPatch.empty()
	check("(a) the ADD verb puts one in the case", RackPatch.add(added, ID) == "pluck" and RackPatch.type_of(added, "pluck") == ID)
	var demo := _demo_patch(reg)
	check("(a) the preset patch keeps the plate (not an unavailable one)", demo["modules"].has("pl") and not RackPatch.is_missing(demo, "pl") and demo["cables"].size() == 4)

	# (b) It plays.
	if RackEngine.available():
		var play := PackedStringArray(["note_on 60 100", "run 0.4", "note_off 60", "run 0.3"])
		var frames := RackEngine.render(demo, play)
		var n := int(RackEngine.RATE * 0.15)
		var attack := _peak(frames, 0, n)
		var tail := _peak(frames, frames.size() - n, frames.size())
		check("(b) it sounds: %d frames, attack peak %.3f" % [frames.size(), attack], frames.size() > 0 and attack > 0.001)
		check("(b) and is plucked: the end is quieter than the start (tail %.4f)" % tail, tail < attack * 0.5)
		var hand := {"modules": {"keys": {"type": "builtin.keys", "at": [0, 0], "knobs": {}},
				"osc": {"type": "builtin.plaits", "at": [1, 0], "knobs": {"engine": 0.35, "harm": 0.4, "timbre": 0.5}},
				"env": {"type": "builtin.env", "at": [2, 0], "knobs": {"a": 0.0, "d": 0.4, "s": 0.0, "r": 0.2}},
				"amp": {"type": "builtin.vca", "at": [3, 0], "knobs": {}}, "out": {"type": "builtin.out", "at": [4, 0], "knobs": {}}},
				"cables": [["keys.pitch", "osc.pitch"], ["keys.gate", "env.gate"], ["keys.gate", "osc.trig"], ["env.out", "amp.cv"],
				["osc.out", "amp.in"], ["amp.out", "out.l"], ["amp.out", "out.r"]]}
		check("(b) and is the same sound as Plaits, an envelope and a VCA patched by hand", _same(frames, RackEngine.render(hand, play)))
		var idle := RackEngine.render(demo, PackedStringArray(["run 0.3"]))
		check("(b) with no note it is silent, so the keys drive it", idle.size() > 0 and _peak(idle, 0, idle.size()) < 0.001)
	else:
		print("  (no engine binary here: (b) is checked as far as the expansion, not as audio)")
		var lines := "\n".join(RackPatch.lines(demo))
		check("(b, expansion only) the engine is told Plaits, an envelope and a VCA", lines.contains("add pl~osc plaits") and lines.contains("add pl~env env")
				and lines.contains("add pl~amp vca"))

	# (c) It saves and reloads.
	var file := TMP.path_join("pluck.patch.json")
	var d := RackPatch.to_dict(RackPatch.sanitize(demo), "Pluck", 1)
	check("(c) the file names the mod and its version", d["uses"][ID]["mod"] == ID and d["uses"][ID]["version"] == "0.1.0" and d["modules"]["pl"]["type"] == ID)
	check("(c) it is written", RackPatchFile.write_text(file, RackPatchFile.text_of(d)) == OK)
	var read := RackPatchFile.read(file)
	check("(c) read back it is the patch, and saved again the same bytes", read["ok"] and read["patch"]["modules"] == RackPatch.sanitize(demo)["modules"]
			and read["patch"]["cables"] == RackPatch.sanitize(demo)["cables"] and RackPatchFile.text_of(RackPatch.to_dict(read["patch"], "Pluck", 1)) == RackPatchFile.text_of(d))
	DAW.use(OfflineBackend.new())
	var autosave := TMP.path_join("studio.patch.json")
	RackAutosave.disabled = false
	RackAutosave.default_path = autosave
	var host := Studio.new()
	host.medium = Presentation.Medium.SCREEN
	t.add_child(host)
	await t.get_tree().physics_frame
	var state: Dictionary = host.room_rows.room_state().duplicate(true)
	state[RackPatch.ROW]["patch"] = demo.duplicate(true)
	host.room_rows.apply_room(state)
	host.rack_host.ask_rack("add", ["builtin.lfo", -1, 0])
	var ids := RackPatch.module_ids(host.rack_row["patch"])
	host.rack_files.flush()
	var saved := RackPatchFile.text_of(RackPatch.to_dict(host.rack_row["patch"]))
	host.queue_free()
	await t.get_tree().process_frame
	var fresh := Studio.new()
	fresh.medium = Presentation.Medium.SCREEN
	t.add_child(fresh)
	await t.get_tree().physics_frame
	check("(c) a fresh rack opens with the plate in its place and its knobs", RackPatch.module_ids(fresh.rack_row["patch"]) == ids and fresh.rack_row["patch"]["modules"]["pl"]["knobs"]["decay"] == 0.4
			and fresh.rack_row["patch"]["modules"]["pl"]["at"] == demo["modules"]["pl"]["at"])
	check("(c) the file it saves is the file it was", RackPatchFile.text_of(RackPatch.to_dict(fresh.rack_row["patch"])) == saved)
	check("(c) and the plate on the wall is the real one", fresh.rack_wall.module_nodes.has("pl") and not _labels(fresh.rack_wall.module_nodes["pl"]).has("PLUCK not installed"))
	# Take the folder away: the same file loads with the plate unavailable and the place and cables kept, and the mod
	# coming back restores the patch exactly.
	fresh.queue_free()
	await t.get_tree().process_frame
	_remove(home.path_join(ID))
	_use(home)
	var gone: Dictionary = RackPatchFile.read(file)["patch"]
	check("(c) without the folder the plate is kept, unavailable, in its place with its cables", RackPatch.is_missing(gone, "pl")
			and gone["modules"]["pl"]["at"] == demo["modules"]["pl"]["at"] and gone["cables"].has(["keys.pitch", "pl.pitch"]) and gone["cables"].has(["pl.out", "out.l"]))
	check("(c) and saved again the file is the same", RackPatchFile.text_of(RackPatch.to_dict(gone, "Pluck", 1)) == RackPatchFile.text_of(d))
	_copy(SAMPLE, home.path_join(ID))
	_use(home)
	var back: Dictionary = RackPatchFile.read(file)["patch"]
	check("(c) with the folder back it is the playing plate again", not RackPatch.is_missing(back, "pl") and back["modules"] == RackPatch.sanitize(demo)["modules"])
	RackAutosave.default_path = ""
	RackAutosave.disabled = true

	# (d) It replicates. The host has the mod; a guest with it and a guest without it are given the host's row.
	var role := Session.role
	RackAutosave.disabled = true
	_use(home)
	var h := Studio.new()
	h.medium = Presentation.Medium.SCREEN
	t.add_child(h)
	await t.get_tree().physics_frame
	var hs: Dictionary = h.room_rows.room_state().duplicate(true)
	hs[RackPatch.ROW]["patch"] = demo.duplicate(true)
	h.room_rows.apply_room(hs)
	var row: Dictionary = h.room_rows.room_state()[RackPatch.ROW]
	check("(d) the host's row says which mod the plate needs", row["patch"]["uses"][ID]["mod"] == ID and row["patch"]["uses"][ID]["version"] == "0.1.0" and row["patch"]["uses"][ID]["title"] == "PLUCK")
	var heard := PackedVector2Array()
	if RackEngine.available():
		heard = RackEngine.render(h.rack_voice.patch, PackedStringArray(["note_on 60 100", "run 0.3"]))
		check("(d) the host's engine plays the plate (peak %.3f)" % _peak(heard, 0, heard.size()), _peak(heard, 0, heard.size()) > 0.001)
	var other := h.room_rows.room_state().duplicate(true)
	other[RackPatch.ROW] = row
	Session.start_solo()
	Session.role = Session.Role.GUEST
	Session.local_peer_id = 5
	var with_mod := Studio.new()
	with_mod.medium = Presentation.Medium.SCREEN
	t.add_child(with_mod)
	await t.get_tree().physics_frame
	with_mod.room_rows.apply_room(other)
	check("(d) a guest with the mod sees the real plate, in the host's place", with_mod.rack_wall.module_nodes.has("pl") and not RackPatch.is_missing(with_mod.rack_row["patch"], "pl")
			and not _labels(with_mod.rack_wall.module_nodes["pl"]).has("PLUCK not installed"))
	with_mod.queue_free()
	await t.get_tree().process_frame
	_use("")
	check("(d) the guest's game no longer has the mod", not RackCatalogue.has(ID))
	var without := Studio.new()
	without.medium = Presentation.Medium.SCREEN
	t.add_child(without)
	await t.get_tree().physics_frame
	without.room_rows.apply_room(other)
	var words := _labels(without.rack_wall.module_nodes["pl"]) if without.rack_wall.module_nodes.has("pl") else []
	check("(d) a guest without it sees the plate naming the mod (%s)" % str(words), "PLUCK not installed" in words and ("%s 0.1.0" % ID) in words)
	check("(d) in the host's place with the rest of the case the host's", RackPatch.module_ids(without.rack_row["patch"]) == RackPatch.module_ids(h.rack_row["patch"])
			and without.rack_row["patch"]["modules"]["pl"]["at"] == demo["modules"]["pl"]["at"])
	check("(d) the guest runs no engine: the sound is the host's", not without.rack_voice.running())
	if RackEngine.available():
		check("(d) and the host's sound, rendered by the host with the mod, is the sound that is heard (not the guest's)", _peak(heard, 0, heard.size()) > 0.001)
	without.queue_free()
	h.queue_free()
	Session.role = role
	await t.get_tree().process_frame
	_remove(TMP)
	ModRegistry.current = kept
	RackCatalogue._forget()
	RackSkin._forget()
