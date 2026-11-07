extends RefCounted

## The rack's unavailable plate, dangling cables, `uses` on the room row and a guest without the mod
## (docs/mods.md section 9 step 6, sections 6.2, 6.3 and 10), called from the `_test_*` wrappers in
## tests/run_tests.gd.

var t: Node


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


const USES := {"dawlings.sample.pluck": {"mod": "dawlings.sample.pluck", "version": "0.1.0", "title": "PLUCK"}}


## The keys voice plus a stranger in the open, and a cable to a port keys does not have.
func _patch(uses := true) -> Dictionary:
	var raw := RackPatch.preset(&"keys_voice")
	raw["modules"]["pl"] = {"type": "dawlings.sample.pluck", "at": [20, 1], "w": 4, "knobs": {"decay": 0.4}}
	raw["cables"].append(["pl.out", "out.l"])
	raw["cables"].append(["keys.nope", "out.r"])
	if uses:
		raw["uses"] = USES.duplicate(true)
	return raw


func _panels(wall: RackWall) -> int:
	return wall.module_nodes.keys().filter(func(k: String) -> bool: return not k.begins_with("blank/") and not k.contains("/")).size()


func _stubs(wall: RackWall) -> Array:
	return wall._stubs.get_children().filter(func(n: Node) -> bool: return n is PatchCable and not n.is_queued_for_deletion())


func a_plate_names_its_mod() -> void:
	var p := RackPatch.sanitize(_patch())
	check("the plate says the module's name and that it is not installed", RackGaps.plate_title(p, "pl") == "PLUCK not installed")
	check("the small line names the mod and its version", RackGaps.plate_note(p, "pl") == "dawlings.sample.pluck 0.1.0")
	check("the whole sentence is the one of the design", RackGaps.plate_text(p, "pl") == "PLUCK (dawlings.sample.pluck 0.1.0): not installed")
	var blind := RackPatch.sanitize(_patch(false))
	check("a patch that did not say falls back on the type", RackGaps.plate_title(blind, "pl") == "dawlings.sample.pluck not installed"
			and RackGaps.plate_note(blind, "pl") == "" and RackGaps.plate_text(blind, "pl") == "dawlings.sample.pluck: not installed")
	check("the problem list names the mod once and the dangling cable", RackGaps.problems(p).size() == 2 and RackGaps.problems(p)[0] == RackGaps.plate_text(p, "pl"))
	var wall := RackWall.new()
	t.add_child(wall)
	wall.show_patch(p)
	var holder: Node3D = wall.module_nodes["pl"]
	var words: Array = []
	for l in holder.find_children("*", "Label3D", true, false):
		words.append((l as Label3D).text)
	check("the wall prints both on the plate (%s)" % str(words), "PLUCK not installed" in words and "dawlings.sample.pluck 0.1.0" in words)
	check("the plate stands in its place, wide as it was", is_equal_approx(holder.position.x, wall._x_of(20 + 2.0)))
	check("a known module's plate is as it was", _panels(wall) == p["modules"].size())
	wall.queue_free()


func a_dangling_cable_is_kept_stubbed_and_not_sounded() -> void:
	var p := RackPatch.sanitize(_patch())
	check("a cable to a port a known module lacks is kept", p["cables"].has(["keys.nope", "out.r"]))
	check("and is dangling, as the cable to the absent module is not", RackGaps.dangling(p, ["keys.nope", "out.r"]) and not RackGaps.dangling(p, ["pl.out", "out.l"]))
	check("the engine never hears either", not "cable keys.nope out.r" in RackPatch.lines(p) and RackPatch.playable(p)["cables"].size() == p["cables"].size() - 2)
	var again := RackPatch.from_dict(JSON.parse_string(RackPatchFile.text_of(RackPatch.to_dict(p))))
	check("saved and loaded it is still there, byte for byte", again["cables"].has(["keys.nope", "out.r"])
			and RackPatchFile.text_of(RackPatch.to_dict(again)) == RackPatchFile.text_of(RackPatch.to_dict(p)))
	check("a stub is not a mistake: the wrong way round, a loop and a repeat are dropped", RackPatch.sanitize({"modules": {"keys": {"type": "builtin.keys", "at": [0, 0]},
			"out": {"type": "builtin.out", "at": [4, 0]}}, "cables": [["out.l", "keys.pitch"], ["keys.nope", "keys.nope2"], ["keys.pitch", "out.l"], ["keys.pitch", "out.l"]]})["cables"] == [["keys.pitch", "out.l"]])
	var wall := RackWall.new()
	t.add_child(wall)
	var asked: Array = []
	wall.edit_asked.connect(func(op: String, args: Array) -> void: asked.append([op, args]))
	wall.show_patch(p)
	var stubs := _stubs(wall)
	check("the wall stands a stub for each: out of the plug there is (%d)" % stubs.size(), stubs.size() == 2)
	check("red for the dangling one", stubs.any(func(c: PatchCable) -> bool: return c.colour == RackStubs.DANGLING))
	check("and dull for the one to the absent module", stubs.any(func(c: PatchCable) -> bool: return c.colour == RackStubs.ABSENT))
	check("none is a real cable", wall.cables.size() == p["cables"].size() - 2)
	wall._stubs.pull_asked.emit("keys.nope", "out.r")
	check("a stub's key asks to take the cable out", asked == [["pull_one", ["keys.nope", "out.r"]]])
	var gone := p.duplicate(true)
	check("which the patch does", RackPatch.answer(gone, "pull_one", ["keys.nope", "out.r"]) == "")
	wall.show_patch(gone)
	check("and the stub goes", _stubs(wall).size() == 1)
	wall.queue_free()


func the_room_row_says_which_mod_each_type_needs() -> void:
	DAW.use(OfflineBackend.new())
	RackAutosave.disabled = true
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	t.add_child(studio)
	await t.get_tree().physics_frame
	var row: Dictionary = studio.room_state()[RackPatch.ROW]
	var uses: Dictionary = row["patch"].get("uses", {})
	var types := {}
	for id in row["patch"]["modules"]:
		types[row["patch"]["modules"][id]["type"]] = true
	check("every type in the published row has its mod and version", uses.size() == types.size() and types.keys().all(func(ty: String) -> bool:
			return uses.get(ty, {}).get("mod", "") != "" and uses[ty].get("version", "") != "" and uses[ty].get("title", "") != ""))
	check("the host's own row is left alone", not studio.rack_row["patch"].has("uses"))
	var blank: Dictionary = RackGaps.published({"patch": RackPatch.empty(), "track": 3})
	check("an empty rack publishes no uses, and the track is kept", blank["patch"]["uses"].is_empty() and blank["track"] == 3)
	check("a row with no patch is not touched", RackGaps.published({"track": 1}) == {"track": 1})
	check("the Session still takes the row's shape", Session.room_ask_is_valid(&"rack", [&"add", ["builtin.lfo", -1, 0]]))
	studio.queue_free()
	await t.get_tree().process_frame


## The design's test of 6.3: the host runs the engine and feeds the track, so a guest who lacks the mod
## gets the plate and the host's sound and nothing else.
func a_guest_without_the_mod_sees_a_named_plate_and_hears_the_host() -> void:
	DAW.use(OfflineBackend.new())
	RackAutosave.disabled = true
	var role := Session.role
	var host := Studio.new()
	host.medium = Presentation.Medium.SCREEN
	t.add_child(host)
	await t.get_tree().physics_frame
	var state: Dictionary = host.room_state().duplicate(true)
	state[RackPatch.ROW]["patch"] = _patch(false)
	host.apply_room(state)
	var sent: Dictionary = host.room_state()[RackPatch.ROW]
	check("the host keeps the stranger and publishes the mod behind it (here only its type: the host never knew it)", RackPatch.is_missing(host.rack_row["patch"], "pl")
			and sent["patch"]["modules"].has("pl"))
	# The host's engine plays the rack without the stranger; that is the sound a guest is sent.
	var heard := PackedVector2Array()
	if RackEngine.available():
		heard = RackEngine.render(host.rack_voice.patch, PackedStringArray(["note_on 60 100", "run 0.5"]))
		var loud := 0.0
		for f in heard:
			loud = maxf(loud, absf(f.x))
		check("the host's engine sounds the keys voice with the stranger in the case", heard.size() > 0 and loud > 0.02)
		check("and was never told about the stranger", not host.rack_voice.patch["modules"].has("pl"))
	else:
		print("  (no engine here: no sound to check)")
	# The guest: the host's row, as the room sends it, with the mod named.
	sent["patch"]["uses"] = USES.duplicate(true)
	var other := host.room_state().duplicate(true)
	other[RackPatch.ROW] = sent
	Session.start_solo()
	Session.role = Session.Role.GUEST
	Session.local_peer_id = 5
	var guest := Studio.new()
	guest.medium = Presentation.Medium.SCREEN
	t.add_child(guest)
	await t.get_tree().physics_frame
	guest.apply_room(other)
	var wall: RackWall = guest.rack_wall
	var words: Array = []
	for l in (wall.module_nodes["pl"] as Node3D).find_children("*", "Label3D", true, false):
		words.append((l as Label3D).text)
	check("the guest's wall has the plate, named from the row (%s)" % str(words), "PLUCK not installed" in words and "dawlings.sample.pluck 0.1.0" in words)
	check("in the host's place, and the host's cable to it is a stub", wall.module_nodes.has("pl") and _stubs(wall).size() == 2)
	check("the rest of the case is the host's, module for module", RackPatch.module_ids(guest.rack_row["patch"]) == RackPatch.module_ids(host.rack_row["patch"]))
	check("the guest runs no engine: the sound is the host's", not guest.rack_voice.running() and not guest.rack_voice.patch["modules"].is_empty())
	# A guest may take the stranger out by the usual verb, which the host would validate.
	var row: Dictionary = guest.rack_row.duplicate(true)
	check("the guest's own prediction keeps what the host kept", RackPatch.is_missing(RackPatch.sanitize(row["patch"]), "pl"))
	guest.queue_free()
	host.queue_free()
	Session.role = role
	await t.get_tree().process_frame
