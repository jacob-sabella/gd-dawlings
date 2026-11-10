extends RefCounted

## The control API's fx tools (docs/mcp_assistant.md), called from tests/run_tests.gd's `_test_control_fx`.

var t: Node


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


func run() -> void:
	var previous := DAW.backend
	DAW.use(OfflineBackend.new())
	var api := ControlTools.make_api()

	# Every tool of the three domains has a schema.
	var mine := 0
	for n in api.tools:
		var tool: ControlTool = api.tools[n]
		if tool.domain in ["fx", "automation", "look"]:
			mine += 1
			check("%s has a schema and a summary" % n, tool.schema.get("type") == "object" and tool.summary.length() > 20)
	check("the fx, automation and look tools are registered", mine == 24)
	check("a valid example passes its own check (fx_set_param)",
			api.tools["fx_set_param"].check({"track": "Kick", "fx": 0, "param": "Gain", "value": 0.5}).is_empty())
	check("a bad example fails its check (fx_set_param value 2)",
			not api.tools["fx_set_param"].check({"track": "Kick", "fx": 0, "param": "Gain", "value": 2.0}).is_empty())
	check("a missing argument fails its check", not api.tools["fx_add"].check({"track": 1}).is_empty())

	var st := DAW.state
	var kick := 0
	for i in st.track_indices():
		if st.track(i, false).name == "Kick":
			kick = i
	check("the stand-in has a Kick", kick > 0)

	# --- fx ---
	var plugins := api.invoke("fx_plugins", {"query": "gate"})
	check("fx_plugins finds ReaGate", plugins["ok"] and plugins["data"]["plugins"].any(func(p: Dictionary) -> bool: return p["id"] == "ReaGate"))
	check("fx_plugins pages", api.invoke("fx_plugins", {"limit": 2})["data"]["plugins"].size() == 2)

	var before: int = st.track(kick, false).plugins().size()
	var added := api.invoke("fx_add", {"track": "Kick", "plugin": "reagate"})
	check("fx_add puts a plugin on the chain", added["ok"] and st.track(kick, false).plugins().size() == before + 1)
	var comp_no: int = int(added["data"]["added"]) if added["ok"] else -1
	check("fx_add says the new plugin's number", added["ok"] and st.track(kick, false).plugins().has(comp_no))
	var eq_added := api.invoke("fx_add", {"track": kick, "plugin": "ReaEQ", "before": comp_no})
	check("fx_add before another says the new number and returns the chain", eq_added["ok"] and eq_added["data"]["added"] == comp_no
			and eq_added["data"]["fx"].size() == before + 2)
	comp_no += 1  # numbers are places: the comp moved back one
	var listed := api.invoke("fx_list", {"track": "#%d" % kick})
	check("fx_list names the chain in order, EQ before gate",
			listed["ok"] and listed["data"]["fx"].map(func(r: Dictionary) -> String: return r["name"]).slice(-2) == ["ReaEQ", "ReaGate"])
	check("fx_list rows carry number, slot, enabled and wet", listed["data"]["fx"][0].has_all(["number", "slot", "enabled", "wet"]))

	check("an unknown plugin fails and says how to look", not api.invoke("fx_add", {"track": kick, "plugin": "NoSuchThing"})["ok"]
			and "fx_plugins" in api.invoke("fx_add", {"track": kick, "plugin": "NoSuchThing"})["error"])
	check("an unknown track fails and lists tracks", "the tracks are" in api.invoke("fx_list", {"track": "Nobody"})["error"])
	var bad_fx := api.invoke("fx_get", {"track": kick, "fx": "Flanger"})
	check("an unknown plugin on a track fails and shows the chain", not bad_fx["ok"] and "ReaGate" in bad_fx["error"])

	var got := api.invoke("fx_get", {"track": kick, "fx": "ReaGate"})
	check("fx_get finds a plugin by name", got["ok"] and got["data"]["number"] == comp_no and got["data"]["name"] == "ReaGate")

	# enabled / wet
	check("fx_set_enabled bypasses", api.invoke("fx_set_enabled", {"track": kick, "fx": comp_no, "enabled": false})["ok"]
			and not st.fx(kick, comp_no, false).enabled)
	check("fx_set_wet sets the mix", api.invoke("fx_set_wet", {"track": kick, "fx": "ReaGate", "wet": 0.25})["ok"]
			and is_equal_approx(st.fx(kick, comp_no, false).wet, 0.25))
	check("wet out of range is refused by the schema", not api.invoke("fx_set_wet", {"track": kick, "fx": comp_no, "wet": 1.5})["ok"])

	# params: the stand-in's plugins have none named, so by number; then name some and set by name
	var by_number := api.invoke("fx_set_param", {"track": kick, "fx": comp_no, "param": 0, "value": 0.3})
	check("fx_set_param by number", by_number["ok"] and is_equal_approx(st.fx(kick, comp_no, false).params.get(0, -1.0), 0.3))
	var f := st.fx(kick, comp_no, false)
	f.param_names[0] = "Threshold"
	f.param_names[1] = "Ratio"
	f.param_names[2] = "Release"
	f.param_text[0] = "-18.0 dB"
	var by_name := api.invoke("fx_set_param", {"track": kick, "fx": comp_no, "param": "threshold", "value": 0.8})
	check("fx_set_param by name", by_name["ok"] and is_equal_approx(f.params[0], 0.8))
	check("fx_set_param by part of a name", api.invoke("fx_set_param", {"track": kick, "fx": comp_no, "param": "ratio", "value": 0.6})["ok"]
			and is_equal_approx(f.params[1], 0.6))
	var no_param := api.invoke("fx_set_param", {"track": kick, "fx": comp_no, "param": "Wobble", "value": 0.5})
	check("an unknown param fails and lists the names", not no_param["ok"] and "Threshold" in no_param["error"])
	var many := api.invoke("fx_set_params", {"track": kick, "fx": comp_no, "params": {"Threshold": 0.1, "Release": 0.9}})
	check("fx_set_params sets several", many["ok"] and is_equal_approx(f.params[0], 0.1) and is_equal_approx(f.params[2], 0.9))
	var half := api.invoke("fx_set_params", {"track": kick, "fx": comp_no, "params": {"Threshold": 0.7, "Nope": 0.9}})
	check("fx_set_params sets nothing if one name is unknown", not half["ok"] and is_equal_approx(f.params[0], 0.1))
	check("fx_set_params refuses a value outside 0..1", not api.invoke("fx_set_params", {"track": kick, "fx": comp_no, "params": {"Threshold": 5}})["ok"])
	var shown := api.invoke("fx_get", {"track": kick, "fx": comp_no, "limit": 2})
	var ps: Array = shown["data"]["params"]
	check("fx_get lists params by name with value and text, paged",
			ps.size() == 2 and ps[0]["name"] == "Threshold" and ps[0]["text"] == "-18.0 dB" and shown["data"]["param_count"] == 3)
	check("fx_get offset skips", api.invoke("fx_get", {"track": kick, "fx": comp_no, "offset": 2})["data"]["params"][0]["name"] == "Release")

	# presets
	var pre := api.invoke("fx_step_preset", {"track": kick, "fx": comp_no, "direction": 1})
	check("fx_step_preset moves to the next preset", pre["ok"] and pre["data"]["preset"] == "Gentle" and st.fx(kick, comp_no, false).preset == "Gentle")
	check("fx_step_preset refuses direction 0", not api.invoke("fx_step_preset", {"track": kick, "fx": comp_no, "direction": 0})["ok"])

	# undo of a change set
	var undo_before: float = st.fx(kick, comp_no, false).wet
	api.invoke("fx_set_wet", {"track": kick, "fx": comp_no, "wet": 0.9})
	check("a change set takes fx_set_wet back", api.undo()["ok"] and is_equal_approx(st.fx(kick, comp_no, false).wet, undo_before))

	# move / copy
	var snare := 0
	for i in st.track_indices():
		if st.track(i, false).name == "Snare":
			snare = i
	var snare_before: int = st.track(snare, false).plugins().size()
	var copied := api.invoke("fx_copy", {"track": kick, "fx": comp_no, "to_track": "Snare"})
	check("fx_copy puts a copy on the other track and keeps the original",
			copied["ok"] and st.track(snare, false).plugins().size() == snare_before + 1 and st.track(kick, false).plugins().has(comp_no))
	var moved := api.invoke("fx_move", {"track": "Snare", "fx": "ReaGate", "to_track": kick})
	check("fx_move takes it off the source track", moved["ok"] and st.track(snare, false).plugins().size() == snare_before)
	var kept := false
	for i in st.track(kick, false).plugins():
		var c := st.fx(kick, i, false)
		if i != comp_no and c.name == "ReaGate" and c.params == st.fx(kick, comp_no, false).params and c.preset == "Gentle":
			kept = true
	check("a copy kept its settings and its preset", kept)
	check("fx_move to a track that does not exist fails", not api.invoke("fx_move", {"track": kick, "fx": comp_no, "to_track": "Ghost"})["ok"])

	# remove is destructive
	var count: int = st.track(kick, false).plugins().size()
	check("fx_remove needs confirmation", not api.invoke("fx_remove", {"track": kick, "fx": comp_no})["ok"]
			and st.track(kick, false).plugins().size() == count)
	check("fx_remove removes once confirmed", api.invoke("fx_remove", {"track": kick, "fx": comp_no}, 0, true)["ok"]
			and st.track(kick, false).plugins().size() == count - 1)
	check("fx_remove can be undone", api.undo()["ok"] and st.track(kick, false).plugins().size() == count)

	# --- automation ---
	var empty := api.invoke("automation_list", {"track": kick})
	check("automation_list has a mode and lanes", empty["ok"] and empty["data"].has("lanes") and empty["data"].has("mode"))
	var set_r := api.invoke("automation_set", {"track": kick, "target": "volume",
			"points": [[2.0, -6.0, "linear"], [0.0, 0.0, "hold"], {"seconds": 4.0, "value": -60.0}]})
	var lane: Array = st.track(kick, false).automation.get("volume", [])
	check("automation_set writes a lane, sorted", set_r["ok"] and lane.size() == 3 and is_equal_approx(lane[0][0], 0.0) and int(lane[0][2]) == 0 and is_equal_approx(lane[2][0], 4.0))
	var got_lane := api.invoke("automation_get", {"track": "Kick", "target": "volume", "limit": 2})
	check("automation_get pages and names shapes", got_lane["ok"] and got_lane["data"]["total"] == 3 and got_lane["data"]["points"].size() == 2
			and got_lane["data"]["points"][0]["shape"] == "hold" and is_equal_approx(got_lane["data"]["points"][1]["value"], -6.0))
	check("automation_list shows the lane", api.invoke("automation_list", {"track": kick})["data"]["lanes"][0]["points"] == 3)
	api.invoke("automation_add", {"track": kick, "target": "volume", "points": [[2.0, -3.0], [8.0, 0.0]]})
	lane = st.track(kick, false).automation["volume"]
	check("automation_add merges: replaces at the same time, adds new", lane.size() == 4 and is_equal_approx(lane[1][1], -3.0) and is_equal_approx(lane[3][0], 8.0))
	api.invoke("automation_remove_points", {"track": kick, "target": "volume", "from_seconds": 7.0, "to_seconds": 9.0})
	check("automation_remove_points drops the span", st.track(kick, false).automation["volume"].size() == 3)
	check("removing every point is refused", not api.invoke("automation_remove_points", {"track": kick, "target": "volume", "from_seconds": 0.0, "to_seconds": 99.0})["ok"])
	check("an empty automation_set will not delete a lane", not api.invoke("automation_set", {"track": kick, "target": "volume", "points": []})["ok"])
	check("a value is clamped to the lane's range", api.invoke("automation_set", {"track": kick, "target": "pan", "points": [[0.0, 5.0]]})["ok"]
			and is_equal_approx(st.track(kick, false).automation["pan"][0][1], 1.0))
	check("an fx lane for a plugin that is not there fails", not api.invoke("automation_set", {"track": kick, "target": "fx:99:0", "points": [[0.0, 0.5]]})["ok"])
	check("a nonsense target fails and says the targets", "fx:<plugin number>" in api.invoke("automation_get", {"track": kick, "target": "banana"})["error"])
	check("a negative time fails", not api.invoke("automation_set", {"track": kick, "target": "pan", "points": [[-1.0, 0.0]]})["ok"])
	check("a bad point shape fails", not api.invoke("automation_set", {"track": kick, "target": "pan", "points": ["x"]})["ok"])
	var a_fx := api.invoke("automation_set", {"track": kick, "target": "fx:%d:0" % comp_no, "points": [[0.0, 0.2], [1.0, 0.9]]})
	check("an fx param lane is written", a_fx["ok"] and st.track(kick, false).automation.has("fx:%d:0" % comp_no))
	check("the master can be automated", api.invoke("automation_set", {"track": "master", "target": "volume", "points": [[0.0, -3.0]]})["ok"]
			and st.master.automation.has("volume"))
	check("the master has no mute lane", not api.invoke("automation_set", {"track": 0, "target": "mute", "points": [[0.0, 1.0]]})["ok"])
	check("automation_clear needs confirmation", not api.invoke("automation_clear", {"track": kick, "target": "pan"})["ok"])
	check("automation_clear removes the lane", api.invoke("automation_clear", {"track": kick, "target": "pan"}, 0, true)["ok"]
			and not st.track(kick, false).automation.has("pan"))
	var lane_depth: Array = st.track(kick, false).automation["volume"].duplicate(true)
	api.invoke("automation_add", {"track": kick, "target": "volume", "points": [[20.0, 0.0]]})
	check("undo puts a lane back", api.undo()["ok"] and st.track(kick, false).automation["volume"] == lane_depth)
	# a batch is one undo
	var bat: Dictionary = await api.batch([{"tool": "automation_add", "args": {"track": kick, "target": "volume", "points": [[30.0, 0.0]]}},
			{"tool": "fx_set_wet", "args": {"track": kick, "fx": comp_no, "wet": 0.1}}])
	check("a batch of fx and automation runs", bat["ok"] and bat["data"]["failed"] == 0)
	api.undo()
	check("one undo takes the whole batch back", st.track(kick, false).automation["volume"] == lane_depth and not is_equal_approx(st.fx(kick, comp_no, false).wet, 0.1))

	# --- look ---
	st.master.vu_l = 0.5
	st.track(kick, false).vu_l = 0.25
	var lv := api.invoke("look_levels", {"limit": 3, "signal": true})
	check("look_levels gives the master and a page of tracks", lv["ok"] and lv["data"]["tracks"].size() == 3 and is_equal_approx(lv["data"]["master"]["vu_l"], 0.5)
			and lv["data"]["total_tracks"] == st.track_indices().size())
	var one := api.invoke("look_levels", {"track": "Kick", "signal": true})
	check("look_levels for one track shows its vu and that signal is not measured", one["ok"] and is_equal_approx(one["data"]["tracks"][0]["vu_l"], 0.25)
			and one["data"]["tracks"][0]["signal"] == null)
	var k := st.track(kick, false)
	var chain: Array = k.plugins()
	var peaks: Array = [-12.0]
	var rmss: Array = [-20.0]
	var grs: Array = []
	for _i in chain.size():
		peaks.append(-10.0)
		rmss.append(-18.0)
		grs.append(NAN)
	k.meter_peak = PackedFloat32Array(peaks)
	k.meter_rms = PackedFloat32Array(rmss)
	k.meter_gr = PackedFloat32Array(grs)
	var sg: Dictionary = api.invoke("look_levels", {"track": "Kick", "signal": true})["data"]["tracks"][0]["signal"]
	check("look_levels shows signal-graph stages with an input and one per plugin", sg["stages"].size() == chain.size() + 1
			and is_equal_approx(sg["stages"][0]["peak_db"], -12.0) and sg["stages"][1]["gain_reduction_db"] == null)
	check("look_levels on an unknown track fails", not api.invoke("look_levels", {"track": "Zed"})["ok"])
	st.master.loudness_measured = false
	check("look_loudness says when nothing measures it", api.invoke("look_loudness")["data"]["measured"] == false)
	st.master.loudness_measured = true
	st.master.lufs_i = -14.2
	st.master.lufs_m = -INF
	var ld: Dictionary = api.invoke("look_loudness")["data"]
	check("look_loudness gives LUFS, null for silence", ld["measured"] and is_equal_approx(ld["lufs_integrated"], -14.2) and ld["lufs_momentary"] == null)
	st.tempo = 98.0
	var tr: Dictionary = api.invoke("look_transport")["data"]
	check("look_transport gives playhead, tempo and signature", is_equal_approx(tr["tempo_bpm"], 98.0) and tr.has("position_seconds") and tr["time_signature"] == "%d/%d" % [st.beats_per_bar, st.beat_unit])
	var wh := api.invoke("look_where")
	check("look_where answers without a studio", wh["ok"] and wh["data"]["studio"] == false)
	var shot := api.invoke("look_screenshot")
	check("look_screenshot fails clearly with no window", not shot["ok"] and "window" in shot["error"])
	check("an unknown tool name fails", not api.invoke("fx_nonsense")["ok"])

	DAW.use(previous, false)
