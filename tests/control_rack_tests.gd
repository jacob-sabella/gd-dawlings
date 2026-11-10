extends RefCounted

## The control API's rack tools (docs/mcp_assistant.md), called from tests/run_tests.gd's `_test_control_rack`.
## With no studio the tools act on ToolsRack.test_patch.

const ToolsRack := preload("res://core/control/tools_rack.gd")

var t: Node


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


func _call(api: ControlApi, tool: String, args := {}) -> Dictionary:
	return api.invoke(tool, args, 0, true)


func run() -> void:
	ToolsRack.test_patch = RackPatch.empty()
	var api := ControlTools.make_api()
	for n in ["rack_list", "rack_get", "rack_add", "rack_remove", "rack_move", "rack_set_knob", "rack_cables_list", "rack_cable_add",
			"rack_cable_remove", "rack_tidy", "rack_clear", "rack_patch_get", "rack_patch_set", "rack_presets_list", "rack_preset_load",
			"rack_patch_save", "rack_patch_load", "rack_modules_find", "rack_module_types", "rack_module_help", "rack_render"]:
		check("rack tool %s is registered" % n, api.has(n))
	check("the destructive rack tools ask first", not api.invoke("rack_clear", {}).get("ok", true) and not api.invoke("rack_patch_set", {"patch": {}}).get("ok", true))

	# add, list, knobs
	var vco := _call(api, "rack_add", {"type": "builtin.vco"})
	check("rack_add gives the new id", vco["ok"] and vco["data"]["id"] == "vco")
	var vco2 := _call(api, "rack_add", {"type": "builtin.vco"})
	check("a second one is vco2", vco2["ok"] and vco2["data"]["id"] == "vco2")
	var out := _call(api, "rack_add", {"type": "builtin.out"})
	check("the OUT goes in", out["ok"])
	check("a second OUT is refused in the game's words", not _call(api, "rack_add", {"type": "builtin.out"})["ok"])
	var nope := _call(api, "rack_add", {"type": "builtin.nonesuch"})
	check("an unknown type is refused", not nope["ok"] and str(nope["error"]).contains("no module called"))
	var at := _call(api, "rack_add", {"type": "builtin.lfo", "col": 30, "row": 2})
	check("a place can be given", at["ok"] and at["data"]["col"] == 30 and at["data"]["row"] == 2)
	var listed := _call(api, "rack_list")
	check("rack_list shows the modules", listed["ok"] and listed["data"]["total"] == 4 and listed["data"]["modules"][0].has("knobs"))
	check("the knobs are by label", listed["data"]["modules"].any(func(m: Dictionary) -> bool: return m["id"] == "vco" and m["knobs"].has("TUNE")))
	var k := _call(api, "rack_set_knob", {"module": "vco", "knob": "tune", "value": 0.75})
	check("a knob by label takes 0..1", k["ok"] and absf(RackPatch.knob_of(ToolsRack.test_patch, "vco", "tune") - 0.75) < 0.001)
	var kr := _call(api, "rack_set_knob", {"module": "vco", "knob": "TUNE", "real": 0.0})
	check("a knob takes its own unit", kr["ok"] and absf(RackPatch.knob_of(ToolsRack.test_patch, "vco", "tune") - 0.5) < 0.001)
	check("a knob needs one of value or real", not _call(api, "rack_set_knob", {"module": "vco", "knob": "tune"})["ok"])
	var badk := _call(api, "rack_set_knob", {"module": "vco", "knob": "zzz", "value": 0.1})
	check("an unknown knob lists the real ones", not badk["ok"] and str(badk["error"]).contains("TUNE"))
	check("an unknown module lists the ids", str(_call(api, "rack_get", {"module": "nothing"})["error"]).contains("vco2"))
	var got := _call(api, "rack_get", {"module": "vco"})
	check("rack_get has the help card summary", got["ok"] and got["data"]["help"]["blurb"] != "" and got["data"]["outs"].has("out"))

	# cables
	var c1 := _call(api, "rack_cable_add", {"from": "vco.out", "to": "out.l"})
	check("a cable goes in", c1["ok"])
	check("the same cable twice is refused", not _call(api, "rack_cable_add", {"from": "vco.out", "to": "out.l"})["ok"])
	var c2 := _call(api, "rack_cable_add", {"from": "vco2.out", "to": "out.l"})
	check("a fed input says so", c2["ok"] and c2["data"].has("note"))
	var bad_jack := _call(api, "rack_cable_add", {"from": "vco.nothing", "to": "out.l"})
	check("an unknown jack lists the real ones", not bad_jack["ok"] and str(bad_jack["error"]).contains("sub"))
	var wrong_way := _call(api, "rack_cable_add", {"from": "out.l", "to": "vco.out"})
	check("input to output is refused", not wrong_way["ok"])
	var selfie := _call(api, "rack_cable_add", {"from": "vco.out", "to": "vco.fm"})
	check("a module into itself is refused", not selfie["ok"] and str(selfie["error"]).contains("itself"))
	check("rack_cables_list", _call(api, "rack_cables_list")["data"]["total"] == 2)
	check("a cable comes out", _call(api, "rack_cable_remove", {"from": "vco2.out", "to": "out.l"})["ok"])
	check("pulling what is not there is refused", not _call(api, "rack_cable_remove", {"from": "vco2.out", "to": "out.l"})["ok"])

	# the cable limit
	var many := RackPatch.empty()
	RackPatch.add(many, "builtin.vco", Vector2i(0, 0))
	RackPatch.add(many, "builtin.out", Vector2i(10, 0))
	for i in RackPatch.MAX_CABLES:
		(many["cables"] as Array).append(["vco.out", "out.l"])
	var saved := ToolsRack.test_patch
	ToolsRack.test_patch = many
	var over := _call(api, "rack_cable_add", {"from": "vco.sub", "to": "out.r"})
	check("past MAX_CABLES is refused in words", not over["ok"] and str(over["error"]).contains("cables"))
	ToolsRack.test_patch = saved

	# move, tidy, remove
	check("a move", _call(api, "rack_move", {"module": "lfo", "col": 20, "row": 1})["ok"] and ToolsRack.test_patch["modules"]["lfo"]["at"] == [20, 1])
	check("a move onto another is refused", not _call(api, "rack_move", {"module": "lfo", "col": int(ToolsRack.test_patch["modules"]["vco"]["at"][0]), "row": int(ToolsRack.test_patch["modules"]["vco"]["at"][1])})["ok"])
	check("tidy", _call(api, "rack_tidy")["ok"])
	check("the OUT cannot be removed", not _call(api, "rack_remove", {"module": "out"})["ok"])
	check("a module comes out with its cables", _call(api, "rack_remove", {"module": "vco2"})["ok"] and not ToolsRack.test_patch["modules"].has("vco2"))

	# the whole patch, round trip
	var before := _call(api, "rack_patch_get")
	check("rack_patch_get is the file shape", before["ok"] and before["data"]["format"] == RackPatch.FORMAT and before["data"]["modules"].has("vco"))
	var snapshot: Dictionary = before["data"].duplicate(true)
	ToolsRack.test_patch = RackPatch.empty()
	var set := _call(api, "rack_patch_set", {"patch": snapshot})
	check("rack_patch_set takes it back", set["ok"])
	var after := _call(api, "rack_patch_get")
	check("the round trip is the same patch", after["data"]["modules"] == snapshot["modules"] and after["data"]["cables"] == snapshot["cables"])
	var built := _call(api, "rack_patch_set", {"patch": {"modules": {"a": {"type": "builtin.vco", "at": [0, 0], "knobs": {"tune": 0.9}},
			"o": {"type": "builtin.out", "at": [8, 0]}}, "cables": [["a.out", "o.l"], ["a.out", "o.r"]]}})
	var now := ToolsRack.test_patch
	check("a patch built in one call", built["ok"] and (now["cables"] as Array).size() == 2 and absf(RackPatch.knob_of(now, "vco", "tune") - 0.9) < 0.001 and now["modules"].size() == 2)
	var rejected := _call(api, "rack_patch_set", {"patch": {"modules": {"a": {"type": "builtin.nonesuch", "at": [0, 0]}}, "cables": []}})
	check("a patch with an unknown type is refused and changes nothing", not rejected["ok"] and ToolsRack.test_patch["modules"].size() == 2)
	var bad_cable := _call(api, "rack_patch_set", {"patch": {"modules": {"a": {"type": "builtin.vco", "at": [0, 0]}}, "cables": [["a.nothing", "a.fm"]]}})
	check("a patch with a bad cable is refused", not bad_cable["ok"] and ToolsRack.test_patch["modules"].size() == 2)
	check("not a patch is refused", not _call(api, "rack_patch_set", {"patch": {"hello": 1}})["ok"])

	# clear
	var cleared := _call(api, "rack_clear")
	check("rack_clear leaves only the OUT", cleared["ok"] and ToolsRack.test_patch["modules"].size() == 1 and (ToolsRack.test_patch["cables"] as Array).is_empty())

	# find, types, help
	var found := _call(api, "rack_modules_find", {"query": "reverb", "limit": 5})
	check("find 'reverb'", found["ok"] and found["data"]["total"] > 0 and found["data"]["modules"].size() <= 5 and found["data"]["modules"][0].has("type"))
	var kinded := _call(api, "rack_modules_find", {"query": "", "kind": "reverb", "limit": 3})
	check("find by kind", kinded["ok"] and kinded["data"]["total"] > 0)
	var types := _call(api, "rack_module_types")
	check("types by group", types["ok"] and types["data"]["groups"].size() > 3)
	var group: String = types["data"]["groups"][0]["group"]
	check("one group in full", _call(api, "rack_module_types", {"group": group})["data"]["count"] > 0)
	check("an unknown group is refused", not _call(api, "rack_module_types", {"group": "Nonesuch"})["ok"])
	var help := _call(api, "rack_module_help", {"type": "builtin.vco"})
	check("a help card", help["ok"] and help["data"]["title"] != "" and help["data"]["knobs"].size() > 0)
	check("no help for an unknown type", not _call(api, "rack_module_help", {"type": "builtin.nonesuch"})["ok"])

	# presets and saved patches
	var presets := _call(api, "rack_presets_list")
	check("presets are listed", presets["ok"] and presets["data"]["presets"].size() > 0)
	var preset_name: String = presets["data"]["presets"][0]["name"]
	check("a preset loads", _call(api, "rack_preset_load", {"name": preset_name})["ok"] and ToolsRack.test_patch["modules"].size() > 1)
	check("an unknown preset is refused", not _call(api, "rack_preset_load", {"name": "nonesuch"})["ok"])
	var saved_as := "zz control rack test"
	check("a bad name is refused", not _call(api, "rack_patch_save", {"name": "../evil"})["ok"] and not _call(api, "rack_patch_save", {"name": "_current"})["ok"])
	var wrote := _call(api, "rack_patch_save", {"name": saved_as, "overwrite": true})
	check("a patch saves by name", wrote["ok"])
	var count: int = ToolsRack.test_patch["modules"].size()
	_call(api, "rack_clear")
	var loaded := _call(api, "rack_patch_load", {"name": saved_as})
	check("a saved patch loads", loaded["ok"] and ToolsRack.test_patch["modules"].size() == count)
	check("it is listed", saved_as in _call(api, "rack_presets_list")["data"]["saved"])
	check("a missing one is refused", not _call(api, "rack_patch_load", {"name": "no such patch here"})["ok"])
	if wrote["ok"]:
		DirAccess.remove_absolute(wrote["data"]["path"])
		DirAccess.remove_absolute(wrote["data"]["path"] + ".bak")

	# undo through a batch
	ToolsRack.test_patch = RackPatch.empty()
	_call(api, "rack_add", {"type": "builtin.out"})
	var start: Dictionary = ToolsRack.test_patch.duplicate(true)
	var ran: Dictionary = await api.batch([
			{"tool": "rack_add", "args": {"type": "builtin.vco"}},
			{"tool": "rack_add", "args": {"type": "builtin.lfo"}},
			{"tool": "rack_set_knob", "args": {"module": "vco", "knob": "tune", "value": 0.9}},
			{"tool": "rack_cable_add", "args": {"from": "vco.out", "to": "out.l"}}])
	check("the batch ran", ran["ok"] and ran["data"]["failed"] == 0 and ToolsRack.test_patch["modules"].size() == 3)
	var undone := api.undo()
	check("undo says it did", undone["ok"])
	check("undo puts the rack back", ToolsRack.test_patch["modules"].keys() == start["modules"].keys() and (ToolsRack.test_patch["cables"] as Array).is_empty())
	# undo of a removal brings the module, its knob and cables back
	_call(api, "rack_patch_set", {"patch": {"modules": {"a": {"type": "builtin.vco", "at": [0, 0], "knobs": {"tune": 0.8}}, "out": {"type": "builtin.out", "at": [6, 0]}}, "cables": [["a.out", "out.l"]]}})
	var shot: Dictionary = ToolsRack.test_patch.duplicate(true)
	_call(api, "rack_remove", {"module": "a"})
	api.undo()
	check("undo of a removal restores module, knob and cable", ToolsRack.test_patch["modules"] == shot["modules"] and ToolsRack.test_patch["cables"] == shot["cables"])

	# render: stats when the engine is built, a plain refusal when it is not
	var render := _call(api, "rack_render", {"seconds": 0.3})
	check("rack_render answers, with stats or a plain refusal", (render["ok"] and render["data"].has("peak")) or (not render["ok"] and str(render["error"]) != ""))
	ToolsRack.test_patch = {}
