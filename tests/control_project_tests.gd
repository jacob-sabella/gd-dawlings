extends RefCounted

## The control API's project tools (docs/mcp_assistant.md), called from tests/run_tests.gd's `_test_control_project`.

var t: Node


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


func _ok(api: ControlApi, tool_name: String, args := {}, confirmed := false) -> Dictionary:
	var r := api.invoke(tool_name, args, 0, confirmed)
	check("%s %s works" % [tool_name, str(args)], r["ok"])
	if not r["ok"]:
		print("   ", r.get("error", ""))
	return r.get("data", {}) if r["ok"] else {}


func _bad(api: ControlApi, tool_name: String, args: Dictionary, label: String, confirmed := false) -> String:
	var r := api.invoke(tool_name, args, 0, confirmed)
	check("%s: %s" % [tool_name, label], not r["ok"] and not str(r.get("error", "")).is_empty())
	return str(r.get("error", ""))


func run() -> void:
	var previous := DAW.backend
	DAW.use(OfflineBackend.new())
	var api := ControlTools.make_api()
	var s := DAW.state

	# Every tool has a schema, and a valid example passes its own check.
	var names: Array = []
	for n in api.tools.keys():
		if str(n).begins_with("project_") or str(n).begins_with("transport_"):
			names.append(n)
	check("project and transport tools are registered", names.size() >= 35)
	var examples := {
		"project_list": {}, "project_save": {"as": "x", "overwrite": true}, "project_open": {"name": "x"},
		"project_new": {"tracks": 2}, "project_new_from_template": {"template": "x"}, "project_template_add": {"name": "x"},
		"project_recover": {"generation": 0}, "project_tempo_set": {"bpm": 100}, "project_tempo_map_set": {"points": [{"beat": 0, "bpm": 90}]},
		"project_time_signature_map_set": {"points": [{"beat": 0, "numerator": 3, "denominator": 4}]},
		"project_marker_list": {"limit": 5}, "project_marker_add": {"at": 1.5, "name": "a"}, "project_marker_set": {"at": 1.5, "to": 2},
		"project_marker_remove": {"name": "a"}, "project_region_list": {"offset": 0}, "project_region_add": {"start": 0, "end": 4, "name": "A"},
		"project_region_set": {"region": "A", "end": 6}, "project_region_remove": {"region": 0}, "project_lyrics_set": {"text": "hi"},
		"project_sections_arrange": {"order": [1, 0]}, "project_history_list": {"limit": 3}, "project_undo": {"steps": 2},
		"project_redo": {"steps": 1}, "project_undo_to": {"depth": 0}, "project_render": {"stems": true, "bits": 16, "rate": 44100, "normalise": false, "flac": false},
		"transport_seek": {"bar": 2}, "transport_set": {"looping": true, "loop_start": 0, "loop_end": 2, "metronome": true, "count_in_bars": 1,
				"count_in_play": false, "pre_roll": false, "punch": false},
	}
	for n in names:
		var tool: ControlTool = api.tools[n]
		check("%s has a schema and a summary" % n, tool.schema.get("type") == "object" and tool.summary.length() > 20)
		var args: Dictionary = (examples.get(n, {}) as Dictionary).duplicate(true)
		check("%s accepts a valid example" % n, tool.check(args).is_empty())
		check("%s refuses an unknown argument" % n, not tool.check({"bogus_arg": 1}).is_empty())

	# Reading.
	var got := _ok(api, "project_get")
	check("project_get says the tempo and the track count", got.get("tempo_bpm") == s.tempo and got.get("tracks") == s.track_indices().size())
	_ok(api, "project_list")
	_ok(api, "project_name_get")

	# Tempo.
	_ok(api, "project_tempo_set", {"bpm": 97.5})
	check("tempo was set through the DAW", is_equal_approx(s.tempo, 97.5))
	_bad(api, "project_tempo_set", {"bpm": 5000}, "above the maximum is refused by the schema")
	_ok(api, "project_tempo_map_set", {"points": [{"beat": 0, "bpm": 100}, {"beat": 8, "bpm": 140, "shape": "ramp_beats"}]})
	var map := _ok(api, "project_tempo_map_list")
	check("the tempo map has both points with the ramp", map.get("points", []).size() == 2 and map["points"][1]["shape"] == "ramp_beats" and is_equal_approx(map["points"][1]["bpm"], 140.0))
	_bad(api, "project_tempo_map_set", {"points": [{"beat": 2, "bpm": 100}]}, "first point not at beat 0")
	_bad(api, "project_tempo_map_set", {"points": [{"beat": 0, "bpm": 100}, {"beat": 0, "bpm": 90}]}, "beats not rising")
	_bad(api, "project_tempo_map_set", {"points": [{"beat": 0, "bpm": 100, "shape": "wobble"}]}, "unknown shape")
	_ok(api, "project_tempo_map_set", {"points": []})
	check("an empty list clears the tempo map", s.tempo_points.is_empty())
	_ok(api, "project_time_signature_map_set", {"points": [{"beat": 0, "numerator": 4, "denominator": 4}, {"beat": 8, "numerator": 3, "denominator": 4}]})
	var sig := _ok(api, "project_time_signature_map_list")
	check("the signature map has two points", sig.get("points", []).size() == 2 and sig["points"][1]["numerator"] == 3)
	_bad(api, "project_time_signature_map_set", {"points": [{"beat": 0, "numerator": 0, "denominator": 4}]}, "numerator 0")

	# Markers.
	var had := s.markers.size()
	_ok(api, "project_marker_add", {"at": 4.321, "name": "Mk Alpha"})
	_ok(api, "project_marker_add", {"at": 8.123, "name": "Mk Beta"})
	var ml := _ok(api, "project_marker_list")
	check("two markers more, listed in order of position", ml.get("total") == had + 2 and ml["markers"].size() == mini(had + 2, 100)
			and ml["markers"].map(func(m): return m["seconds"]) == ml["markers"].map(func(m): return m["seconds"]).duplicate())
	_ok(api, "project_marker_set", {"name": "Mk Alpha", "to": 5.25, "new_name": "Mk One"})
	check("the marker moved and was renamed", s.markers.has(5.25) and str(s.markers[5.25]) == "Mk One" and not s.markers.has(4.321))
	_bad(api, "project_marker_set", {"name": "Nope", "to": 1.0}, "unknown marker")
	_bad(api, "project_marker_set", {"at": 5.0}, "nothing to change")
	_bad(api, "project_marker_remove", {}, "no ref")
	_ok(api, "project_marker_remove", {"at": 8.123})
	check("the marker is gone", s.markers.size() == had + 1 and not s.markers.has(8.123))
	_ok(api, "transport_seek", {"marker": "Mk One"})
	check("seek to a marker by name", is_equal_approx(s.position_seconds, 5.25))

	# Regions and sections. Start from none, and from one time signature (a change inside a section blocks arranging).
	for r in s.regions.duplicate():
		DAW.remove_region(float(r[0]))
	_ok(api, "project_time_signature_map_set", {"points": [{"beat": 0, "numerator": 4, "denominator": 4}]})
	_ok(api, "project_region_add", {"start": 0.0, "end": 4.0, "name": "Intro"})
	_ok(api, "project_region_add", {"start": 4.0, "end": 12.0, "name": "Verse"})
	_ok(api, "project_region_add", {"start": 12.0, "end": 16.0, "name": "Outro"})
	check("three regions", s.regions.size() == 3)
	_bad(api, "project_region_add", {"start": 5.0, "end": 5.0, "name": "Zero"}, "empty span")
	_ok(api, "project_region_set", {"region": "Outro", "end": 20.0, "name": "Coda"})
	check("the region was resized and renamed", is_equal_approx(float(s.regions[2][1]), 20.0) and str(s.regions[2][2]) == "Coda")
	_bad(api, "project_region_set", {"region": 9, "end": 1.0}, "no such region number")
	_bad(api, "project_region_set", {"region": "Intro"}, "nothing to change")
	var rl := _ok(api, "project_region_list", {"limit": 2})
	check("region list is bounded and carries numbers", rl.get("total") == 3 and rl["regions"].size() == 2 and rl["regions"][1]["number"] == 1)
	_bad(api, "project_sections_arrange", {"order": [0, 0, 1]}, "not an order of all the sections")
	var depth_before := s.undo_depth
	_ok(api, "project_sections_arrange", {"order": [2, 0, 1]})
	check("sections were arranged: the first region now starts with Coda", str(s.regions[0][2]) == "Coda")
	check("arranging is one undo step", s.undo_depth == depth_before + 1)
	_ok(api, "project_region_remove", {"region": "Coda"})
	check("a region was removed", s.regions.size() == 2)

	# Lyrics.
	_ok(api, "project_lyrics_set", {"text": "[00:01.00] hello\n[00:03.00] world"})
	var ly := _ok(api, "project_lyrics_get")
	check("lyrics round-trip", ly.get("lines") == 2 and str(ly["lyrics"]).contains("hello"))

	# History.
	var hist := _ok(api, "project_history_list")
	check("history lists steps with done flags", hist.get("depth", -1) == s.undo_depth and hist.get("steps", []).size() > 0)
	var d := s.undo_depth
	_ok(api, "project_undo")
	check("undo went back one step", s.undo_depth == d - 1 and s.redo_depth == 1)
	_ok(api, "project_redo")
	check("redo came forward", s.undo_depth == d)
	_ok(api, "project_undo_to", {"depth": 0})
	check("undo_to 0 empties the history done", s.undo_depth == 0)
	_bad(api, "project_undo", {}, "nothing left to undo")
	_bad(api, "project_undo_to", {"depth": 9999}, "past the history")
	_ok(api, "project_undo_to", {"depth": d})
	check("the project is back where it was", s.lyrics.contains("hello"))

	# A tool call and its change set undo.
	var before := s.tempo
	_ok(api, "project_tempo_set", {"bpm": 150})
	check("tempo changed", is_equal_approx(s.tempo, 150.0))
	check("the change set can be undone", api.undo()["ok"] and is_equal_approx(s.tempo, before))

	# Transport.
	_ok(api, "transport_play")
	check("playing", s.playing)
	_ok(api, "transport_stop")
	check("stopped", not s.playing)
	_ok(api, "transport_seek", {"seconds": 3.0})
	check("seeked", is_equal_approx(s.position_seconds, 3.0))
	_ok(api, "transport_seek", {"bar": 2})
	check("seeked to bar 2", s.position_seconds > 0.0)
	_bad(api, "transport_seek", {}, "nothing to seek to")
	_bad(api, "transport_seek", {"seconds": 1, "bar": 2}, "two places")
	_bad(api, "transport_seek", {"marker": "Nowhere"}, "unknown marker")
	var tr := _ok(api, "transport_set", {"looping": true, "loop_start": 2.0, "loop_end": 6.0, "metronome": true, "count_in_bars": 2,
			"count_in_play": true, "pre_roll": true, "punch": true})
	check("loop on with its range", s.looping and is_equal_approx(s.loop_start, 2.0) and is_equal_approx(s.loop_end, 6.0))
	check("metronome, count-in, pre-roll and punch set", s.metronome and s.count_in_bars == 2 and s.count_in_play and s.pre_roll and s.punch)
	check("transport_set returns the transport", tr.get("looping") == true and tr.get("count_in_bars") == 2)
	_bad(api, "transport_set", {"count_in_bars": 99}, "count-in beyond the maximum")
	_bad(api, "transport_set", {}, "nothing to set")
	_ok(api, "transport_set", {"looping": false, "metronome": false, "punch": false})
	check("settings turned off", not s.looping and not s.metronome and not s.punch)
	_bad(api, "transport_loop_selected", {}, "nothing selected")
	_ok(api, "transport_record")
	check("recording", s.recording)
	_ok(api, "transport_stop")
	var tg := _ok(api, "transport_get")
	check("transport_get reports the position", tg.has("position") and tg["position"].has("bar_beat"))

	# Render: the stand-in cannot, and says so.
	var why := _bad(api, "project_render", {}, "the stand-in cannot render")
	check("the render refusal names the DAW", why.contains("cannot"))
	_bad(api, "project_render", {"bits": 20}, "odd bit depth is refused")
	var rs := _ok(api, "project_render_status")
	check("no render has finished", rs.get("finished") == false)

	# Destructive tools need confirmation, and files are names, not paths.
	_bad(api, "project_new", {}, "needs a confirmation")
	_bad(api, "project_open", {"name": "../etc/passwd"}, "a path is not a project name", true)
	_bad(api, "project_open", {"name": "no such project zzz"}, "an unknown project", true)
	_bad(api, "project_save", {"as": "a/b"}, "a path is not a name")
	_bad(api, "project_new_from_template", {"template": "no such template zzz"}, "unknown template", true)
	if DAW.recoverable_copy().is_empty():
		_bad(api, "project_recover", {}, "no autosave to recover", true)
	var tracks_now := s.track_indices().size()
	var asked: Dictionary = {}
	api.confirm = func(tool_name: String, _args: Dictionary, _who: int) -> bool:
		asked["tool"] = tool_name
		return false
	var denied: Dictionary = await api.call_tool("project_new", {})
	check("a denied confirmation leaves the project alone", not denied["ok"] and asked.get("tool") == "project_new" and s.track_indices().size() == tracks_now)
	api.confirm = func(_n: String, _a: Dictionary, _w: int) -> bool: return true
	var fresh: Dictionary = await api.call_tool("project_new", {"tracks": 2})
	check("a confirmed project_new replaces the project", fresh["ok"] and DAW.state.track_indices().size() == 2)
	check("an unknown tool fails usefully", not api.invoke("project_nope", {})["ok"])

	DAW.use(previous, false)
