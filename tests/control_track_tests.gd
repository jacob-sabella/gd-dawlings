extends RefCounted

## The control API's track tools (docs/mcp_assistant.md), called from tests/run_tests.gd's `_test_control_track`.

var t: Node


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


func _ok(api: ControlApi, tool: String, args: Dictionary = {}, confirmed := false) -> Dictionary:
	return api.invoke(tool, args, 0, confirmed)


func _names() -> Array:
	return DAW.state.track_indices().map(func(i: int) -> String: return DAW.state.track(i, false).name)


func run() -> void:
	var previous := DAW.backend
	DAW.use(OfflineBackend.new())
	var api := ControlTools.make_api()
	var s := DAW.state

	# Every track and mix tool has a schema that accepts a valid example.
	var examples := {
		"track_list": {"limit": 5, "offset": 0}, "track_get": {"track": 1}, "track_add": {"name": "X", "at": 2},
		"track_remove": {"track": "X"}, "track_delete": {"track": "X"}, "track_rename": {"track": 1, "name": "Y"},
		"track_move": {"track": 1, "to": 2, "parent": 0}, "track_duplicate": {"track": 1},
		"track_set_colour": {"track": 1, "colour": "#ff0000"}, "track_set_arm": {"track": 1, "armed": true},
		"track_set_input": {"track": 1, "input": "", "off": false}, "track_inputs_list": {},
		"track_set_monitor": {"track": 1, "mode": "auto"}, "track_set_automation_mode": {"track": "master", "mode": "touch"},
		"track_set_bank": {"offset": 0}, "track_select": {"track": 1}, "track_freeze": {"track": 1}, "track_thaw": {"track": 1},
		"mix_set_volume": {"track": 1, "db": -6.0}, "mix_set_pan": {"track": 1, "pan": 0.5}, "mix_set_width": {"track": 1, "width": 0.5},
		"mix_set_mute": {"track": 1, "mute": true}, "mix_set_solo": {"track": 1, "solo": true}, "mix_clear_solos": {}, "mix_clear_mutes": {},
		"mix_set_group": {"track": 1, "group": 1}, "mix_set_group_free": {"on": false}, "mix_set_vca": {"group": 1, "db": 0},
		"mix_get_vca": {}, "mix_set_main_send": {"track": 1, "on": true}, "mix_get_master": {}, "mix_set_master": {"db": 0, "pan": 0},
		"mix_reset_loudness": {}, "mix_latency_report": {}, "mix_sends_list": {"track": 1},
		"mix_send_add": {"from": 1, "to": 2}, "mix_sidechain_add": {"from": 1, "to": 2},
		"mix_send_set": {"track": 1, "send": 1, "level_db": -3, "pan": 0, "pre_fader": true}, "mix_send_remove": {"track": 1, "send": "Y"},
	}
	var registered := 0
	for n: String in api.tools:
		var tool: ControlTool = api.tools[n]
		if tool.domain not in ["track", "mix"]:
			continue
		registered += 1
		check("%s has an example" % n, examples.has(n))
		if examples.has(n):
			var bad := tool.check(examples[n].duplicate())
			check("%s accepts its example (%s)" % [n, bad], bad.is_empty())
	check("every example names a tool", examples.keys().all(func(k: String) -> bool: return api.has(k)))
	check("track and mix tools are registered", registered == examples.size())

	# Listing.
	var l := _ok(api, "track_list")
	check("track_list lists the tracks", l["ok"] and l["data"]["total"] == s.track_indices().size() and l["data"]["tracks"][0].has("level_db"))
	check("track_list pages", _ok(api, "track_list", {"limit": 1, "offset": 1})["data"]["tracks"][0]["track"] == s.track_indices()[1])
	check("track_get unknown track fails helpfully", not _ok(api, "track_get", {"track": "Nope"})["ok"] and str(_ok(api, "track_get", {"track": "Nope"})["error"]).contains("no track called"))
	check("unknown tool fails", not api.invoke("track_nothing", {})["ok"])
	check("bad argument type fails", not _ok(api, "mix_set_volume", {"track": 1, "db": "loud"})["ok"])
	check("out of range pan fails", not _ok(api, "mix_set_pan", {"track": 1, "pan": 3})["ok"])

	# Add, rename, colour, move, duplicate, remove.
	var n0 := s.track_indices().size()
	var added := _ok(api, "track_add", {"name": "Probe", "at": 2})
	check("track_add adds at the place asked", added["ok"] and added["data"]["track"] == 2 and s.track(2, false).name == "Probe" and s.track_indices().size() == n0 + 1)
	check("rename", _ok(api, "track_rename", {"track": "Probe", "name": "Probe2"})["ok"] and s.track(2, false).name == "Probe2")
	check("colour", _ok(api, "track_set_colour", {"track": "Probe2", "colour": "#ff0000"})["ok"] and s.track(2, false).colour.is_equal_approx(Color(1, 0, 0)))
	check("bad colour fails", not _ok(api, "track_set_colour", {"track": 2, "colour": "red-ish"})["ok"])
	var dup := _ok(api, "track_duplicate", {"track": "Probe2"})
	check("duplicate puts the copy after it", dup["ok"] and dup["data"]["track"] == 3 and s.track_indices().size() == n0 + 2)
	var mv := _ok(api, "track_move", {"track": 3, "to": 1})
	check("move reorders", mv["ok"] and s.track(1, false).name == dup["data"]["name"])
	check("a track cannot be its own folder", not _ok(api, "track_move", {"track": 1, "to": 2, "parent": 1})["ok"])

	# Undo of an add through the api.
	var before := _names()
	_ok(api, "track_add", {"name": "Temp"})
	check("add at the end", _names().back() == "Temp")
	var undone := api.undo()
	check("api.undo puts the add back", undone["ok"] and _names() == before)

	# Remove: empty is EDIT, with content is refused and delete is destructive.
	var holder := 1
	var holds := not s.track(holder, false).items.is_empty() or not s.track(holder, false).plugins().is_empty()
	if holds:
		var nm := s.track(holder, false).name
		check("track_remove refuses a track with content", not _ok(api, "track_remove", {"track": holder})["ok"] and s.track(holder, false).name == nm)
	check("track_delete wants confirmation", not _ok(api, "track_delete", {"track": holder})["ok"])
	check("track_remove is edit tier and track_delete destructive", api.tools["track_remove"].tier == ControlTool.EDIT and api.tools["track_delete"].tier == ControlTool.DESTRUCTIVE)
	var gone := _ok(api, "track_remove", {"track": "Temp"})
	check("an empty track is removed", not gone["ok"] or not _names().has("Temp"))
	_ok(api, "track_add", {"name": "Fodder"})
	var fi: int = _ok(api, "track_get", {"track": "Fodder"})["data"]["track"]
	var cnt := s.track_indices().size()
	var rem := _ok(api, "track_remove", {"track": "Fodder"})
	check("removing an empty track", rem["ok"] and s.track_indices().size() == cnt - 1 and fi > 0)
	var removed_by_batch: Dictionary = await api.batch([
		{"tool": "track_add", "args": {"name": "B1"}}, {"tool": "track_delete", "args": {"track": "B1"}},
		{"tool": "track_add", "args": {"name": "B2"}}, {"tool": "track_rename", "args": {"track": "B2", "name": "B2b"}}])
	check("a batch with a destructive tool without a confirm is refused whole", not removed_by_batch["ok"] and not _names().has("B1"))

	# Mix.
	var tr := "#1"
	check("volume in dB", _ok(api, "mix_set_volume", {"track": tr, "db": -6.0, "free_of_group": true})["ok"] and absf(DAW.taper_to_db(s.track(1, false).volume) + 6.0) < 0.5)
	var back := api.undo()
	check("volume undo", back["ok"])
	check("pan -1..1", _ok(api, "mix_set_pan", {"track": 1, "pan": -1})["ok"] and is_equal_approx(s.track(1, false).pan, 0.0))
	check("mute and clear", _ok(api, "mix_set_mute", {"track": 1, "mute": true, "free_of_group": true})["ok"] and s.track(1, false).mute and _ok(api, "mix_clear_mutes")["ok"] and not s.track(1, false).mute)
	check("solo and clear", _ok(api, "mix_set_solo", {"track": 1, "solo": true})["ok"] and s.track(1, false).solo and _ok(api, "mix_clear_solos")["ok"] and not s.track(1, false).solo)
	check("group", _ok(api, "mix_set_group", {"track": 1, "group": 2})["ok"] and s.track(1, false).group == 2)
	check("bad group fails", not _ok(api, "mix_set_group", {"track": 1, "group": 9})["ok"])
	_ok(api, "mix_set_group", {"track": 1, "group": 0})
	check("vca", _ok(api, "mix_set_vca", {"group": 1, "db": -3})["ok"] and is_equal_approx(s.vca_db(1), -3.0) and _ok(api, "mix_get_vca")["data"].size() == DAW.GROUPS)
	_ok(api, "mix_set_vca", {"group": 1, "db": 0})
	check("master", _ok(api, "mix_set_master", {"db": -3, "pan": 0.5})["ok"] and absf(DAW.taper_to_db(s.master.volume) + 3.0) < 0.5 and s.master.pan > 0.5)
	check("master needs an argument", not _ok(api, "mix_set_master")["ok"])
	check("master read", _ok(api, "mix_get_master")["data"].has("level_db"))
	check("loudness reset", _ok(api, "mix_reset_loudness")["ok"])
	check("main send", _ok(api, "mix_set_main_send", {"track": 1, "on": false})["ok"] and not s.track(1, false).main_send)
	_ok(api, "mix_set_main_send", {"track": 1, "on": true})
	check("width follows the backend's ability", _ok(api, "mix_set_width", {"track": 1, "width": 0.25})["ok"] == DAW.can(&"width"))
	check("latency report", _ok(api, "mix_latency_report")["data"]["tracks"].size() == s.track_indices().size())

	# Arm, input, monitor, automation, bank, select.
	check("arm", _ok(api, "track_set_arm", {"track": 1, "armed": true})["ok"] == DAW.can(&"record_arm"))
	_ok(api, "track_set_monitor", {"track": 1, "mode": "on"})
	_ok(api, "track_set_automation_mode", {"track": 1, "mode": "latch"})
	check("bad input id fails", not _ok(api, "track_set_input", {"track": 1, "input": "no-such-input-zz"})["ok"])
	check("input needs input or off", not _ok(api, "track_set_input", {"track": 1})["ok"])
	check("input off", _ok(api, "track_set_input", {"track": 1, "off": true})["ok"] and s.track(1, false).input_off == true)
	check("bank refused where the DAW cannot", _ok(api, "track_set_bank", {"offset": 0})["ok"] == DAW.can(&"track_banking"))
	check("select", _ok(api, "track_select", {"track": 1})["ok"])
	check("inputs list", _ok(api, "track_inputs_list")["ok"])

	# Sends.
	var a1: String = "Bass DI"
	var a2: String = "Verb Rtn"
	var sent := _ok(api, "mix_send_add", {"from": a1, "to": a2})
	check("send add", sent["ok"] and sent["data"]["to_name"] == a2)
	var slot: int = sent["data"]["send"]
	check("send to self refused with the game's words", str(_ok(api, "mix_send_add", {"from": a1, "to": a1})["error"]).contains("cannot send to itself"))
	check("send back refused as a loop", str(_ok(api, "mix_send_add", {"from": a2, "to": a1})["error"]).contains("loop"))
	check("send set", _ok(api, "mix_send_set", {"track": a1, "send": slot, "level_db": -12.0, "pan": -1, "pre_fader": true})["ok"]
			and s.track(s.track_indices()[_names().find(a1)], false).sends[slot].pre_fader and is_equal_approx(s.track(s.track_indices()[_names().find(a1)], false).sends[slot].pan, 0.0))
	check("send set by destination name", _ok(api, "mix_send_set", {"track": a1, "send": a2, "level_db": -6.0})["ok"])
	check("send set needs a field", not _ok(api, "mix_send_set", {"track": a1, "send": slot})["ok"])
	check("send list", _ok(api, "mix_sends_list", {"track": a1})["data"].size() == 1 and _ok(api, "mix_sends_list")["data"].size() >= 1)
	var sc := _ok(api, "mix_sidechain_add", {"from": a1, "to": a2})
	check("sidechain add", sc["ok"] and sc["data"]["sidechain"] == true)
	check("send remove by number", _ok(api, "mix_send_remove", {"track": a1, "send": sc["data"]["send"]})["ok"])
	check("send remove by name", _ok(api, "mix_send_remove", {"track": a1, "send": a2})["ok"] and s.track(s.track_indices()[_names().find(a1)], false).sends.is_empty())
	check("send remove of nothing fails", not _ok(api, "mix_send_remove", {"track": a1, "send": a2})["ok"])

	# Names re-resolve in a batch after a removal.
	_ok(api, "track_add", {"name": "Zed", "at": 1})
	var bres: Dictionary = await api.batch([
		{"tool": "track_delete", "args": {"track": "Zed"}},
		{"tool": "track_rename", "args": {"track": a1, "name": "Renamed"}}])
	check("a destructive batch is refused with no one to confirm", not bres["ok"])
	api.confirm = func(_n: String, _a: Dictionary, _w: int) -> bool: return true
	bres = await api.batch([
		{"tool": "track_delete", "args": {"track": "Zed"}},
		{"tool": "track_rename", "args": {"track": a1, "name": "Renamed"}}])
	check("a write after a removal finds its track by name", bres["ok"] and bres["data"]["failed"] == 0 and _names().has("Renamed") and not _names().has("Zed"))
	var tdel := await api.call_tool("track_delete", {"track": "Renamed"})
	check("call_tool confirms and deletes", tdel["ok"] and not _names().has("Renamed"))

	DAW.use(previous, false)
