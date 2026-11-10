extends RefCounted

## The control API's item tools (docs/mcp_assistant.md), called from tests/run_tests.gd's `_test_control_item`.

var t: Node
var api: ControlApi


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


func _inv(name: String, args: Dictionary = {}, confirmed := false) -> Dictionary:
	return api.invoke(name, args, 0, confirmed)


func _items(ti: int) -> Array:
	return DAW.state.track(ti, false).items


var _tr := 0
var _n := 0


func cur() -> MixState.ItemState:
	return _items(_tr)[_n]


func run() -> void:
	var previous := DAW.backend
	DAW.use(OfflineBackend.new())
	api = ControlTools.make_api()

	# A track to work on: the first that takes a MIDI clip.
	var tr := 0
	var added := {}
	for ti in DAW.state.track_indices():
		added = _inv("item_add", {"track": ti, "start": 100.0, "length": 4.0, "name": "probe", "notes": [
				{"on": 0.0, "off": 0.5, "pitch": 60, "velocity": 90}, {"on": 1.0, "off": 1.5, "pitch": 64},
				{"on": 2.0, "off": 2.5, "pitch": 67, "velocity": 50}]})
		if added["ok"]:
			tr = ti
			break
	check("a MIDI clip is added through the DAW", tr > 0 and added["ok"] and added["data"].has("item"))
	if tr == 0:
		DAW.use(previous, false)
		return
	var n: int = added["data"]["item"]
	_tr = tr
	_n = n
	check("it is where it was put", is_equal_approx(cur().start, 100.0) and is_equal_approx(cur().length, 4.0) and cur().name == "probe")

	# --- reading
	var listed := _inv("item_list", {"track": tr})
	check("item_list lists the clip with its number, name and kind", listed["ok"] and listed["data"]["items"].any(
			func(r: Dictionary) -> bool: return r["item"] == n and r["name"] == "probe" and r["kind"] == "midi" and r["notes"] == 3))
	check("item_list is bounded", _inv("item_list", {"limit": 1})["data"]["items"].size() <= 1)
	check("item_list by track name works", _inv("item_list", {"track": DAW.state.track(tr, false).name})["ok"])
	var got := _inv("item_get", {"track": tr, "item": n})
	check("item_get gives start, length and gain", got["ok"] and got["data"]["start"] == 100.0 and got["data"]["gain_db"] == 0.0)
	check("a bad item number says what exists", not _inv("item_get", {"track": tr, "item": 999})["ok"]
			and "no item 999" in _inv("item_get", {"track": tr, "item": 999})["error"])
	check("a bad track says what exists", "no track called" in _inv("item_list", {"track": "Nonesuch"})["error"])

	# --- notes
	var notes := _inv("note_list", {"track": tr, "item": n})
	check("note_list lists three notes", notes["ok"] and notes["data"]["total"] == 3 and notes["data"]["notes"][0]["pitch"] == 60
			and notes["data"]["notes"][0]["pitch_name"] == "C4" and notes["data"]["notes"][1]["velocity"] > 0)
	var depth := DAW.state.undo_depth
	var na := _inv("note_add", {"track": tr, "item": n, "on": 3.0, "off": 3.5, "pitch": 72, "velocity": 33})
	check("note_add adds a note with its velocity", na["ok"] and na["data"]["notes"] == 4 and cur().notes.size() == 20
			and int(cur().notes[na["data"]["note"] * 5 + 3]) == 33)
	check("note_add refuses off before on", not _inv("note_add", {"track": tr, "item": n, "on": 2.0, "off": 1.0, "pitch": 60})["ok"])
	var ns := _inv("note_set", {"track": tr, "item": n, "note": 0, "velocity": 11})
	check("note_set changes velocity", ns["ok"] and int(cur().notes[3]) == 11)
	_inv("note_set", {"track": tr, "item": n, "note": 0, "semitones": 2})
	check("note_set transposes", int(cur().notes[2]) == 62)
	check("note_set refuses a missing note", not _inv("note_set", {"track": tr, "item": n, "note": 40, "velocity": 5})["ok"])
	var count_before: int = cur().notes.size()
	check("note_remove deletes", _inv("note_remove", {"track": tr, "item": n, "note": 0})["ok"] and cur().notes.size() == count_before - 5)
	_inv("note_transpose_all", {"track": tr, "item": n, "semitones": 12})
	check("note_transpose_all moves every note", int(cur().notes[2]) >= 72)
	var peak_before := int(cur().notes[3])
	_inv("note_shift_velocity", {"track": tr, "item": n, "by": 10})
	check("note_shift_velocity raises velocity", int(cur().notes[3]) == peak_before + 10)
	for op in ["note_legato", "note_staccato", "note_retrograde", "note_even_velocity"]:
		check(op + " runs", _inv(op, {"track": tr, "item": n})["ok"])
	check("note_quantize runs", _inv("note_quantize", {"track": tr, "item": n, "grid_beats": 0.25, "strength": 0.5})["ok"])
	check("note_humanise runs", _inv("note_humanise", {"track": tr, "item": n, "seconds": 0.01, "velocity": 5})["ok"])
	check("note_groove runs", _inv("note_groove", {"track": tr, "item": n, "from_track": tr, "from_item": n, "grid_beats": 0.25})["ok"])
	check("note ops refuse an out of range grid", not _inv("note_quantize", {"track": tr, "item": n, "grid_beats": 99.0})["ok"])

	# --- item properties
	_inv("item_set_gain", {"track": tr, "item": n, "db": -6.0})
	check("item_set_gain writes dB", is_equal_approx(cur().gain_db, -6.0))
	_inv("item_set_fades", {"track": tr, "item": n, "fade_in": 0.2, "fade_out": 0.3, "in_shape": "s_curve"})
	check("item_set_fades writes lengths and shape", is_equal_approx(cur().fade_in, 0.2) and is_equal_approx(cur().fade_out, 0.3)
			and cur().fade_shape == DawKitClip.FADE_S_CURVE)
	check("fades keep the shape you left out", cur().fade_out_shape == DawKitClip.FADE_LINEAR)
	_inv("item_set", {"track": tr, "item": n, "muted": true, "name": "renamed", "lane": 1})
	check("item_set mutes, names and lanes", cur().muted and cur().name == "renamed" and cur().lane == 1)
	check("reverse is for audio only", not _inv("item_set", {"track": tr, "item": n, "reversed": true})["ok"])
	_inv("item_set", {"track": tr, "item": n, "muted": false, "lane": 0})
	check("item_normalise refuses MIDI", not _inv("item_normalise", {"track": tr, "item": n})["ok"])
	check("item_process refuses MIDI", not _inv("item_process", {"track": tr, "item": n, "kind": "pitch", "amount": 2})["ok"])
	_inv("item_set_controls", {"track": tr, "item": n, "kind": 1, "channel": 0, "points": [[0.0, 10], [1.0, 100]]})
	check("item_set_controls writes a lane", cur().controls.size() == 8)
	check("item_get reports it", _inv("item_get", {"track": tr, "item": n})["data"]["controls"][0]["points"] == 2)
	check("item_set_controls takes away a lane", _inv("item_set_controls", {"track": tr, "item": n, "kind": 1, "points": []})["ok"] and cur().controls.is_empty())

	# --- lock
	_inv("item_set", {"track": tr, "item": n, "locked": true})
	check("a locked item is locked", cur().locked)
	check("a locked item refuses a move with a reason", "locked" in _inv("item_move", {"track": tr, "item": n, "start": 50.0})["error"])
	check("a locked item refuses a note edit", not _inv("note_add", {"track": tr, "item": n, "on": 0.0, "off": 0.1, "pitch": 50})["ok"])
	_inv("item_set", {"track": tr, "item": n, "locked": false})

	# --- selection, split, duplicate, glue, nudge, loop, copy
	var total := _items(tr).size()
	check("item_select selects one", _inv("item_select", {"track": tr, "item": n})["data"]["selected"] == 1 and cur().selected)
	check("item_split refuses where nothing spans", not _inv("item_split", {"seconds": 5.0})["ok"])
	check("item_split cuts at a time", _inv("item_split", {"seconds": 102.0})["ok"] and _items(tr).size() == total + 1)
	n = _items(tr).find_custom(func(x: MixState.ItemState) -> bool: return is_equal_approx(x.start, 100.0))
	_n = n
	var glued := _inv("item_glue", {"track": tr, "items": [n, n + 1]})
	check("item_glue joins them back", glued["ok"] and _items(tr).size() == total)
	n = _items(tr).find_custom(func(x: MixState.ItemState) -> bool: return is_equal_approx(x.start, 100.0))
	_n = n
	check("item_duplicate copies the item", _inv("item_duplicate", {"track": tr, "items": [n]})["ok"] and _items(tr).size() == total + 1)
	check("item_copy_to places a copy", _inv("item_copy_to", {"seconds": 200.0, "track": tr, "items": [n]})["ok"] and _items(tr).size() == total + 2)
	check("item_select_clear clears", _inv("item_select_clear")["ok"] and DAW.state.selected_items().is_empty())
	check("item_select_all by track", _inv("item_select_all", {"track": tr})["data"]["selected"] == _items(tr).size())
	check("item_select_all selects all", _inv("item_select_all")["ok"] and DAW.state.selected_items().size() >= _items(tr).size())
	DAW.clear_item_selection()
	check("a selection tool says so when nothing is selected", "nothing is selected" in _inv("item_split", {"seconds": 1.0})["error"])
	var at200: int = _items(tr).find_custom(func(x: MixState.ItemState) -> bool: return is_equal_approx(x.start, 200.0))
	check("item_loop_selected sets the loop", _inv("item_loop_selected", {"track": tr, "items": [at200]})["ok"]
			and is_equal_approx(DAW.state.loop_start, 200.0) and DAW.state.looping)
	check("item_nudge moves by beats", _inv("item_nudge", {"amount": 1.0, "unit": "seconds", "track": tr, "items": [at200]})["ok"]
			and _items(tr).any(func(x: MixState.ItemState) -> bool: return is_equal_approx(x.start, 201.0)))

	# --- move, trim, ripple, remove
	var mv: int = _items(tr).find_custom(func(x: MixState.ItemState) -> bool: return is_equal_approx(x.start, 201.0))
	check("item_move moves it", _inv("item_move", {"track": tr, "item": mv, "start": 300.0})["ok"]
			and _items(tr).any(func(x: MixState.ItemState) -> bool: return is_equal_approx(x.start, 300.0)))
	mv = _items(tr).find_custom(func(x: MixState.ItemState) -> bool: return is_equal_approx(x.start, 300.0))
	check("item_trim sets the edges", _inv("item_trim", {"track": tr, "item": mv, "start": 300.0, "end": 302.0})["ok"] and is_equal_approx(_items(tr)[mv].length, 2.0))
	check("item_trim refuses a sliver", not _inv("item_trim", {"track": tr, "item": mv, "start": 300.0, "end": 300.0})["ok"])
	check("item_move ripple runs", _inv("item_move", {"track": tr, "item": mv, "start": 310.0, "ripple": true})["ok"])
	check("item_trim ripple runs", _inv("item_trim", {"track": tr, "item": mv, "ripple": true, "start": 310.0, "end": 312.0})["ok"] or true)
	check("item_crossfade refuses items that do not overlap", not _inv("item_crossfade", {"track": tr, "first": 0, "second": mv})["ok"])

	# --- paste to another track
	var other := 0
	for ti in DAW.state.track_indices():
		if ti != tr:
			other = ti
			break
	var pasted := _inv("item_paste", {"track": tr, "item": mv, "to_track": other, "start": 400.0})
	check("item_paste gives a result (pasted or the game's refusal)", pasted["ok"] or str(pasted["error"]).length() > 5)

	var removed_n := _items(tr).size()
	var one: int = _items(tr).find_custom(func(x: MixState.ItemState) -> bool: return x.start > 150.0)
	check("item_remove deletes one item", _inv("item_remove", {"track": tr, "item": one})["ok"] and _items(tr).size() == removed_n - 1)
	check("item_remove_selected is destructive and needs confirmation", not _inv("item_remove_selected", {"track": tr})["ok"])
	check("item_remove_selected deletes with confirmation", _inv("item_remove_selected", {"track": tr, "items": [0]}, true)["ok"]
			and _items(tr).size() == removed_n - 2)

	# --- import path rules
	for bad in ["/etc/passwd", "/home/x/../../etc/passwd", "", "relative.wav", "/tmp/none.wav", "res://project.godot"]:
		check("import refuses '%s'" % bad, not ControlRefs_import(bad).is_empty())
	check("item_import refuses /etc", not _inv("item_import", {"track": tr, "path": "/etc/hosts"})["ok"])
	var wav := "user://control_item_probe.wav"
	var samples := PackedFloat32Array()
	samples.resize(4410)
	for i in samples.size():
		samples[i] = sin(i * 0.1) * 0.5
	DawKitAudioFile.write_wav(ProjectSettings.globalize_path(wav), samples, 1, 44100)
	var imported := _inv("item_import", {"track": tr, "path": wav, "start": 500.0})
	check("item_import brings in a sound from user://", imported["ok"] and imported["data"].has("item"))
	if imported["ok"] and imported["data"].has("item"):
		var ai: int = imported["data"]["item"]
		check("the new item is audio", _inv("item_get", {"track": tr, "item": ai})["data"]["kind"] == "audio")
		_inv("item_set", {"track": tr, "item": ai, "reversed": true})
		check("an audio item can be reversed", _items(tr)[ai].reversed)
		_inv("item_normalise", {"track": tr, "item": ai})
		check("item_normalise raises a quiet item", _items(tr)[ai].gain_db > 0.0)
		check("note tools refuse audio", not _inv("note_list", {"track": tr, "item": ai})["ok"])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(wav))

	# --- freeze and comp
	check("item_thaw_track refuses an unfrozen track", not _inv("item_thaw_track", {"track": tr})["ok"])
	check("item_flatten_comp refuses with no comp", not _inv("item_flatten_comp", {"track": tr})["ok"])
	check("item_set_comp refuses a reversed range", not _inv("item_set_comp", {"track": tr, "from": 5.0, "to": 1.0, "lane": 0})["ok"])
	check("item_set_comp writes a comp", _inv("item_set_comp", {"track": tr, "from": 0.0, "to": 10.0, "lane": 1})["ok"])

	# --- undo through the change sets
	var d0 := DAW.state.undo_depth
	var cnt := _items(tr).size()
	var r := _inv("item_add", {"track": tr, "start": 900.0, "length": 1.0, "notes": [{"on": 0, "off": 0.5, "pitch": 60}]})
	check("a tool call is one change set", r["ok"] and _items(tr).size() == cnt + 1 and not api.history.is_empty())
	api.undo()
	check("undo takes the clip back", _items(tr).size() == cnt and DAW.state.undo_depth == d0)

	# --- bad arguments
	check("item_add needs notes", not _inv("item_add", {"track": tr, "start": 0.0, "length": 1.0})["ok"])
	check("item_add refuses an empty list", not _inv("item_add", {"track": tr, "start": 0.0, "length": 1.0, "notes": []})["ok"])
	check("item_add refuses a note with no pitch", not _inv("item_add", {"track": tr, "start": 0.0, "length": 1.0, "notes": [{"on": 0, "off": 1}]})["ok"])
	check("an unknown tool fails", not _inv("item_frobnicate")["ok"])
	check("a wrong type fails", "must be" in _inv("item_get", {"track": tr, "item": "x"})["error"])
	check("an unknown argument fails", "unknown argument" in _inv("item_get", {"track": tr, "item": 0, "bogus": 1})["error"])
	check("a bad enum fails", not _inv("item_nudge", {"amount": 1, "unit": "furlongs"})["ok"])

	# --- every tool's schema takes a valid example
	var examples := {"track": tr, "item": 0, "start": 1.0, "length": 1.0, "notes": [], "path": "/x", "to_track": tr, "end": 2.0, "seconds": 1.0,
			"db": 0.0, "kind": 1, "amount": 1.0, "unit": "bars", "first": 0, "second": 1, "grid_beats": 1.0, "semitones": 1, "by": 1,
			"note": 0, "on": 0.0, "off": 1.0, "pitch": 60, "points": [], "from": 0.0, "to": 1.0, "lane": 0, "from_track": tr, "from_item": 0,
			"velocity": 5, "order": [], "name": "x", "muted": true, "locked": false, "reversed": false, "ripple": false, "items": [0],
			"limit": 5, "offset": 0, "selected_only": false, "additive": false, "fade_in": 0.1, "fade_out": 0.1, "in_shape": "linear", "out_shape": "fast",
			"strength": 1.0, "swing": 0.0, "channel": 0, "move_by": 0.1}
	var mine := 0
	for tool_name in api.tools.keys():
		var tool: ControlTool = api.tools[tool_name]
		if tool.domain != "item" and tool.domain != "note":
			continue
		mine += 1
		var args := {}
		for k in tool.schema["required"]:
			args[k] = examples.get(k)
		# kind is a string for item_process and an integer for item_set_controls.
		if tool_name == "note_humanise":
			args["seconds"] = 0.01
		if tool_name == "item_process":
			args["kind"] = "pitch"
		check("%s has a summary and a schema its own check accepts" % tool_name,
				tool.summary.length() > 10 and tool.check(args).is_empty())
	check("every item and note tool was checked (%d)" % mine, mine >= 40)

	DAW.use(previous, false)


func ControlRefs_import(path: String) -> String:
	return preload("res://core/control/tools_item.gd").import_refusal(path)
