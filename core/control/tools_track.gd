extends RefCounted

## Control tools: track and mix. See core/control/control_tools.gd and docs/mcp_assistant.md.
##
## `track_*` is the track as a thing (add, remove, move, name, colour, arm, input, monitor, automation mode,
## bank); `mix_*` is how it sounds and where it goes (volume, pan, width, mute, solo, groups, VCA, main send,
## master, sends, sidechain, latency). Every write goes through the DAW method the desk's controls call.
## Tracks renumber when one is added, removed or moved, so each tool says the numbers as they are afterwards.

const T = preload("res://core/control/control_tool.gd")
const LIST_MAX := 200
const MONITOR := ["off", "on", "auto"]
const AUTOMATION := {"read": 0, "touch": 2, "latch": 4}
const SAMPLE_RATE := 48000.0


static func register(api: ControlApi) -> void:
	_register_track(api)
	_register_mix(api)
	_register_sends(api)


# --- helpers ------------------------------------------------------------------------------------

static func _state() -> MixState:
	return DAW.state


## {ok, index} or a fail dict, for argument `key`.
static func _track(a: Dictionary, key := "track") -> Dictionary:
	if not a.has(key):
		return T.fail("missing '%s'" % key)
	return ControlRefs.track(DAW.state, a[key])


static func _db_of(taper: float) -> Variant:
	var db := DAW.taper_to_db(taper)
	return db if is_finite(db) else null   # null is silence (-inf), which JSON cannot carry


static func _taper(db: float) -> float:
	return clampf(DAW.db_to_taper(db), 0.0, 1.0)


static func _pan_out(p: float) -> float:
	return snappedf(p * 2.0 - 1.0, 0.001)


static func _pan_in(p: float) -> float:
	return clampf((p + 1.0) * 0.5, 0.0, 1.0)


static func _brief(i: int) -> Dictionary:
	return {"track": i, "name": _state().track(i, false).display_name()}


static func _row(s: MixState, i: int) -> Dictionary:
	var t := s.track(i, false)
	var parent := s.folder_parent(i)
	return {
		"track": i, "name": t.display_name(), "level_db": _db_of(t.volume),
		"pan": _pan_out(t.pan), "width": snappedf(t.width, 0.001),
		"mute": t.mute, "solo": t.solo, "arm": t.rec_arm, "group": t.group,
		"is_folder": t.folder_depth > 0, "parent": parent,
		"parent_name": s.track(parent, false).display_name() if parent > 0 else "",
		"colour": "#" + t.colour.to_html(false), "input": t.input, "input_off": t.input_off,
		"monitor": MONITOR[clampi(t.monitor, 0, 2)],
		"automation_mode": _auto_name(t.automation_mode),
		"main_send": t.main_send, "fx": t.plugins().size(), "items": t.items.size(),
		"sends": t.sends.size(), "frozen": t.is_frozen(), "selected": t.selected,
	}


static func _auto_name(mode: int) -> String:
	for k in AUTOMATION:
		if AUTOMATION[k] == mode:
			return k
	return "trim" if mode == 1 else ("write" if mode == 3 else str(mode))


static func _is_destructive_remove(s: MixState, i: int) -> String:
	var t := s.track(i, false)
	var why := PackedStringArray()
	if not t.items.is_empty():
		why.append("%d items" % t.items.size())
	if not t.plugins().is_empty():
		why.append("%d effects" % t.plugins().size())
	if t.folder_depth > 0:
		why.append("a folder")
	return ", ".join(why)


## The track number a name now has (tracks renumber), or 0.
static func _find_named(s: MixState, track_name: String, near: int) -> int:
	if near > 0 and s.tracks.has(near) and s.tracks[near].name == track_name:
		return near
	for i in s.track_indices():
		if s.track(i, false).name == track_name:
			return i
	return 0


static func _need(cap: StringName, what: String) -> Dictionary:
	if DAW.can(cap):
		return {}
	return T.fail("this DAW cannot %s (%s is not supported by %s)" % [what, cap, DAW.backend.summary() if DAW.backend != null else "no backend"])


# --- track --------------------------------------------------------------------------------------

static func _register_track(api: ControlApi) -> void:
	api.add(T.make("track_list",
			"List the tracks, in order. Each row: track (the number to address it by), name, level_db (null = silent), pan (-1 left .. 1 right), width (0 mono .. 1), mute, solo, arm, group (0 none, 1-4), is_folder, parent (folder track number, 0 = master), colour (#rrggbb), input, input_off, monitor (off/on/auto), automation_mode (read/touch/latch), main_send, fx (effect count), items, sends, frozen. Tracks renumber when one is added, removed or moved.",
			{"limit": T.int_p("rows to return (default 100)", 1, LIST_MAX), "offset": T.int_p("rows to skip", 0)}, [], T.READ,
			func(a: Dictionary) -> Dictionary:
				var s := _state()
				if s == null:
					return T.fail("there is no project")
				var all := s.track_indices()
				var off := int(a.get("offset", 0))
				var lim := int(a.get("limit", 100))
				var rows: Array = []
				for i in all.slice(off, off + lim):
					rows.append(_row(s, i))
				return T.ok({"tracks": rows, "total": all.size(), "offset": off, "bank_offset": s.bank_offset, "bank_size": s.bank_size})))

	api.add(T.make("track_get",
			"One track in full: everything track_list says plus its effects (number, name, enabled, wet) and its sends (number, destination, level_db, pan, pre_fader, sidechain).",
			{"track": T.ref_p("track name or number")}, ["track"], T.READ,
			func(a: Dictionary) -> Dictionary:
				var r := _track(a)
				if not r["ok"]:
					return r
				var s := _state()
				var row := _row(s, r["index"])
				var t := s.track(r["index"], false)
				var fx: Array = []
				for k in t.plugins():
					var f: MixState.FXState = t.fx[k]
					fx.append({"fx": k, "name": f.name, "enabled": f.enabled, "wet": snappedf(f.wet, 0.001)})
				row["effects"] = fx
				row["send_list"] = _sends_of(s, r["index"])
				return T.ok(row)))

	api.add(T.make("track_add",
			"Add an empty track. `at` is the number it should have (1 = first; default the end), later tracks move up one. Returns its number and name.",
			{"name": T.str_p("the track's name"), "at": T.int_p("position, 1-based; default last", 1)}, [], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				var s := _state()
				var at := int(a.get("at", s.track_indices().size() + 1))
				var n := str(a.get("name", ""))
				var before := s.track_indices().size()
				DAW.add_track(at, n)
				if s.track_indices().size() == before:
					return T.fail("the track was not added")
				var i := clampi(at, 1, before + 1)
				return T.ok(_brief(i))))

	api.add(T.make("track_remove",
			"Remove an EMPTY track (no items, no effects, not a folder). A track with content is refused: use track_delete, which a person confirms. Tracks after it move down one.",
			{"track": T.ref_p("track name or number")}, ["track"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				var r := _track(a)
				if not r["ok"]:
					return r
				var holds := _is_destructive_remove(_state(), r["index"])
				if holds != "":
					return T.fail("track '%s' holds %s; use track_delete (a person confirms) to remove it" % [_state().track(r["index"], false).display_name(), holds])
				return _remove(r["index"])))

	api.add(T.make("track_delete",
			"Remove a track WITH its items, effects and sends (a person is asked to confirm). Tracks after it move down one, so re-resolve by name in a batch. One undo step.",
			{"track": T.ref_p("track name or number")}, ["track"], T.DESTRUCTIVE,
			func(a: Dictionary) -> Dictionary:
				var r := _track(a)
				if not r["ok"]:
					return r
				return _remove(r["index"])))

	api.add(T.make("track_rename",
			"Rename a track (up to 64 characters).",
			{"track": T.ref_p("track name or number"), "name": T.str_p("the new name")}, ["track", "name"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				var r := _track(a)
				if not r["ok"]:
					return r
				DAW.rename_track(r["index"], str(a["name"]))
				return T.ok(_brief(r["index"]))))

	api.add(T.make("track_move",
			"Move a track to be number `to` (1-based, in the order after the move), optionally inside a folder track `parent` (name or number; 0 or omitted = top level). Other tracks renumber. Needs a DAW that can reorder tracks.",
			{"track": T.ref_p("track name or number"), "to": T.int_p("the number it should have afterwards", 1),
			"parent": T.ref_p("the folder track to put it in; 0 for none")}, ["track", "to"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				var r := _track(a)
				if not r["ok"]:
					return r
				var need := _need(&"track_order", "reorder tracks")
				if not need.is_empty():
					return need
				var parent := 0
				if a.has("parent") and not (typeof(a["parent"]) in [TYPE_INT, TYPE_FLOAT] and int(a["parent"]) == 0):
					var p := _track(a, "parent")
					if not p["ok"]:
						return p
					parent = p["index"]
				if parent == r["index"]:
					return T.fail("a track cannot be its own folder")
				var nm := _state().track(r["index"], false).name
				var to := clampi(int(a["to"]), 1, _state().track_indices().size())
				DAW.move_track(r["index"], to, parent)
				var now := _find_named(_state(), nm, to)
				return T.ok(_brief(now) if now > 0 else {"track": to, "name": nm})))

	api.add(T.make("track_duplicate",
			"Copy a track with its items, effects and settings; the copy comes right after it. Returns the copy's number and name.",
			{"track": T.ref_p("track name or number")}, ["track"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				var r := _track(a)
				if not r["ok"]:
					return r
				var s := _state()
				var before := s.track_indices().size()
				DAW.duplicate_track(r["index"])
				if s.track_indices().size() == before:
					return T.fail("the track was not duplicated")
				return T.ok(_brief(r["index"] + 1))))

	api.add(T.make("track_set_colour",
			"Set a track's colour as a hex string, '#rrggbb'.",
			{"track": T.ref_p("track name or number"), "colour": T.str_p("'#rrggbb'")}, ["track", "colour"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				var r := _track(a)
				if not r["ok"]:
					return r
				var c := str(a["colour"])
				if not Color.html_is_valid(c):
					return T.fail("'%s' is not a colour; say '#rrggbb'" % c)
				DAW.set_track_colour(r["index"], Color.html(c))
				return T.ok({"track": r["index"], "colour": "#" + _state().track(r["index"], false).colour.to_html(false)})))

	api.add(T.make("track_set_arm",
			"Arm or disarm a track for recording.",
			{"track": T.ref_p("track name or number"), "armed": T.bool_p("true to arm")}, ["track", "armed"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				var r := _track(a)
				if not r["ok"]:
					return r
				var need := _need(&"record_arm", "arm tracks")
				if not need.is_empty():
					return need
				DAW.set_track_rec_arm(r["index"], bool(a["armed"]))
				return T.ok({"track": r["index"], "arm": _state().track(r["index"], false).rec_arm})))

	api.add(T.make("track_set_input",
			"Choose what a track records from: an input id as track_inputs_list gives, or '' for whatever the recorder is set to. Optionally set the input aside (off=true: neither heard nor recorded, the choice kept) or take it back.",
			{"track": T.ref_p("track name or number"), "input": T.str_p("input id, or ''"), "off": T.bool_p("set the input aside / take it back")},
			["track"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				var r := _track(a)
				if not r["ok"]:
					return r
				if not a.has("input") and not a.has("off"):
					return T.fail("say `input` and/or `off`")
				if a.has("input"):
					var id := str(a["input"])
					var known := id == ""
					for pair in _state().inputs:
						known = known or pair[0] == id
					if not known:
						return T.fail("no input '%s'; see track_inputs_list" % id)
					DAW.set_track_input(r["index"], id)
				if a.has("off"):
					DAW.set_track_input_off(r["index"], bool(a["off"]))
				var t := _state().track(r["index"], false)
				return T.ok({"track": r["index"], "input": t.input, "input_off": t.input_off})))

	api.add(T.make("track_inputs_list",
			"The inputs a track can record from: id and name each (audio interface channels, the keys, MIDI).",
			{}, [], T.READ,
			func(_a: Dictionary) -> Dictionary:
				var out: Array = []
				for pair in _state().inputs:
					out.append({"id": pair[0], "name": pair[1]})
				return T.ok(out)))

	api.add(T.make("track_set_monitor",
			"Input monitoring for a track: off, on, or auto (monitor while armed and not playing back).",
			{"track": T.ref_p("track name or number"), "mode": T.str_p("off, on or auto", MONITOR)}, ["track", "mode"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				var r := _track(a)
				if not r["ok"]:
					return r
				DAW.set_track_monitor(r["index"], MONITOR.find(str(a["mode"])))
				return T.ok({"track": r["index"], "monitor": MONITOR[clampi(_state().track(r["index"], false).monitor, 0, 2)]})))

	api.add(T.make("track_set_automation_mode",
			"How a track's controls meet their automation: read (lanes move the controls), touch (a moved control writes its lane until let go), latch (until the transport stops). Use track 'master' for the master's fader and pan.",
			{"track": T.ref_p("track name or number, or 'master'"), "mode": T.str_p("read, touch or latch", AUTOMATION.keys())},
			["track", "mode"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				var idx := 0
				if str(a["track"]).to_lower() != "master":
					var r := _track(a)
					if not r["ok"]:
						return r
					idx = r["index"]
				DAW.set_track_automation_mode(idx, AUTOMATION[str(a["mode"])])
				var got := _state().master.automation_mode if idx == 0 else _state().track(idx, false).automation_mode
				return T.ok({"track": idx, "automation_mode": _auto_name(got)})))

	api.add(T.make("track_set_bank",
			"Move which slice of the project the desk shows, for a DAW with a bank (Reaper: 64 tracks wide). `offset` is the first track's offset (0 = tracks 1..). Only a DAW that can page banks does it.",
			{"offset": T.int_p("first track of the bank, 0-based", 0)}, ["offset"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				var need := _need(&"track_banking", "page track banks")
				if not need.is_empty():
					return need
				DAW.set_track_bank(int(a["offset"]))
				return T.ok({"bank_offset": _state().bank_offset, "bank_size": _state().bank_size})))

	api.add(T.make("track_select",
			"Select every item on a track (the timeline's track-header click), replacing the item selection. Selection is what the item tools' 'selected' operations act on.",
			{"track": T.ref_p("track name or number")}, ["track"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				var r := _track(a)
				if not r["ok"]:
					return r
				DAW.select_track_items(r["index"])
				return T.ok(_brief(r["index"]))))

	api.add(T.make("track_freeze",
			"Freeze a track to a file of its sound (it plays the file, its effects off); it takes the song's length. track_thaw puts it back. Needs a DAW that can render.",
			{"track": T.ref_p("track name or number")}, ["track"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				var r := _track(a)
				if not r["ok"]:
					return r
				var need := _need(&"render", "freeze tracks")
				if not need.is_empty():
					return need
				DAW.freeze_track(r["index"])
				return T.ok({"track": r["index"], "frozen": _state().track(r["index"], false).is_frozen()})))

	api.add(T.make("track_thaw",
			"Put a frozen track back as it was.",
			{"track": T.ref_p("track name or number")}, ["track"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				var r := _track(a)
				if not r["ok"]:
					return r
				DAW.thaw_track(r["index"])
				return T.ok({"track": r["index"], "frozen": _state().track(r["index"], false).is_frozen()})))


static func _remove(index: int) -> Dictionary:
	var s := _state()
	var nm := s.track(index, false).display_name()
	var before := s.track_indices().size()
	DAW.remove_track(index)
	if s.track_indices().size() == before:
		return T.fail("the track was not removed")
	return T.ok({"removed": nm, "tracks": s.track_indices().size()})


# --- mix ----------------------------------------------------------------------------------------

static func _register_mix(api: ControlApi) -> void:
	api.add(T.make("mix_set_volume",
			"Set a track's fader in dB (0 = unity, 6 = about the top of travel, -60 or lower = nearly silent; the fader law is the desk's). A track in a group drags its group by the same dB unless free_of_group. Returns the level now.",
			{"track": T.ref_p("track name or number"), "db": T.num_p("fader level in dB", -150, 12),
			"free_of_group": T.bool_p("move only this track, not its group")}, ["track", "db"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				var r := _track(a)
				if not r["ok"]:
					return r
				if bool(a.get("free_of_group", false)):
					DAW.set_group_free(true)
				DAW.set_track_volume(r["index"], _taper(float(a["db"])))
				DAW.set_group_free(false)
				return T.ok({"track": r["index"], "level_db": _db_of(_state().track(r["index"], false).volume)})))

	api.add(T.make("mix_set_pan",
			"Pan a track: -1 hard left, 0 centre, 1 hard right.",
			{"track": T.ref_p("track name or number"), "pan": T.num_p("-1 .. 1", -1, 1)}, ["track", "pan"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				var r := _track(a)
				if not r["ok"]:
					return r
				DAW.set_track_pan(r["index"], _pan_in(float(a["pan"])))
				return T.ok({"track": r["index"], "pan": _pan_out(_state().track(r["index"], false).pan)})))

	api.add(T.make("mix_set_width",
			"How wide a track's stereo image is: 0 folded to mono, 1 as recorded. Needs a DAW that can set width.",
			{"track": T.ref_p("track name or number"), "width": T.num_p("0 .. 1", 0, 1)}, ["track", "width"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				var r := _track(a)
				if not r["ok"]:
					return r
				var need := _need(&"width", "set stereo width")
				if not need.is_empty():
					return need
				DAW.set_track_width(r["index"], float(a["width"]))
				return T.ok({"track": r["index"], "width": snappedf(_state().track(r["index"], false).width, 0.001)})))

	api.add(T.make("mix_set_mute",
			"Mute or unmute a track. A grouped track's mute is its whole group's, unless free_of_group.",
			{"track": T.ref_p("track name or number"), "mute": T.bool_p("true to mute"), "free_of_group": T.bool_p("only this track")},
			["track", "mute"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				var r := _track(a)
				if not r["ok"]:
					return r
				if bool(a.get("free_of_group", false)):
					DAW.set_group_free(true)
				DAW.set_track_mute(r["index"], bool(a["mute"]))
				return T.ok({"track": r["index"], "mute": _state().track(r["index"], false).mute})))

	api.add(T.make("mix_set_solo",
			"Solo or unsolo a track. A grouped track's solo is its whole group's, unless free_of_group.",
			{"track": T.ref_p("track name or number"), "solo": T.bool_p("true to solo"), "free_of_group": T.bool_p("only this track")},
			["track", "solo"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				var r := _track(a)
				if not r["ok"]:
					return r
				if bool(a.get("free_of_group", false)):
					DAW.set_group_free(true)
				DAW.set_track_solo(r["index"], bool(a["solo"]))
				return T.ok({"track": r["index"], "solo": _state().track(r["index"], false).solo})))

	api.add(T.make("mix_clear_solos", "Let go every soloed track.", {}, [], T.EDIT,
			func(_a: Dictionary) -> Dictionary:
				DAW.clear_solos()
				return T.ok({"soloed": _state().track_indices().filter(func(i: int) -> bool: return _state().track(i, false).solo).size()})))

	api.add(T.make("mix_clear_mutes", "Unmute every muted track.", {}, [], T.EDIT,
			func(_a: Dictionary) -> Dictionary:
				DAW.clear_mutes()
				return T.ok({"muted": _state().track_indices().filter(func(i: int) -> bool: return _state().track(i, false).mute).size()})))

	api.add(T.make("mix_set_group",
			"Put a track in one of the %d track groups (1-%d), or out of any (0). Tracks of a group move together: faders by the same dB, mute and solo as one." % [DAW.GROUPS, DAW.GROUPS],
			{"track": T.ref_p("track name or number"), "group": T.int_p("0 for none, else 1-%d" % DAW.GROUPS, 0, DAW.GROUPS)},
			["track", "group"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				var r := _track(a)
				if not r["ok"]:
					return r
				DAW.set_track_group(r["index"], int(a["group"]))
				return T.ok({"track": r["index"], "group": _state().track(r["index"], false).group})))

	api.add(T.make("mix_set_group_free",
			"Arm 'FREE': the next fader move, mute or solo affects only its own track though it is in a group (the desk's group override). Local to the desk, not saved.",
			{"on": T.bool_p("true to arm, false to put the group back")}, ["on"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				DAW.set_group_free(bool(a["on"]))
				return T.ok({"group_free": DAW.group_free})))

	api.add(T.make("mix_set_vca",
			"A group's VCA trim in dB (-60..12): all its tracks follow, their faders staying where they are. 0 is no trim.",
			{"group": T.int_p("group 1-%d" % DAW.GROUPS, 1, DAW.GROUPS), "db": T.num_p("trim in dB", -60, 12)}, ["group", "db"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				DAW.set_vca(int(a["group"]), float(a["db"]))
				return T.ok({"group": int(a["group"]), "vca_db": _state().vca_db(int(a["group"]))})))

	api.add(T.make("mix_get_vca",
			"Every group's VCA trim in dB and which tracks are in it.",
			{}, [], T.READ,
			func(_a: Dictionary) -> Dictionary:
				var out: Array = []
				for g in range(1, DAW.GROUPS + 1):
					var members: Array = []
					for i in _state().track_indices():
						if _state().track(i, false).group == g:
							members.append(_brief(i))
					out.append({"group": g, "vca_db": _state().vca_db(g), "tracks": members})
				return T.ok(out)))

	api.add(T.make("mix_set_main_send",
			"Whether a track plays into its folder / the master at all. Off, it is heard only through its sends.",
			{"track": T.ref_p("track name or number"), "on": T.bool_p("true to play into the master or folder")}, ["track", "on"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				var r := _track(a)
				if not r["ok"]:
					return r
				DAW.set_track_main_send(r["index"], bool(a["on"]))
				return T.ok({"track": r["index"], "main_send": _state().track(r["index"], false).main_send})))

	api.add(T.make("mix_get_master",
			"The master bus: level_db, pan (-1..1), automation_mode, and its loudness if this DAW measures it (lufs_momentary, lufs_short, lufs_integrated, true_peak_db, listened_seconds).",
			{}, [], T.READ,
			func(_a: Dictionary) -> Dictionary:
				var m := _state().master
				var out := {"level_db": _db_of(m.volume), "pan": _pan_out(m.pan), "automation_mode": _auto_name(m.automation_mode),
						"loudness_measured": m.loudness_measured}
				if m.loudness_measured:
					out["lufs_momentary"] = _fin(m.lufs_m)
					out["lufs_short"] = _fin(m.lufs_s)
					out["lufs_integrated"] = _fin(m.lufs_i)
					out["true_peak_db"] = _fin(m.true_peak_db)
					out["listened_seconds"] = snappedf(m.loudness_seconds, 0.1)
				return T.ok(out)))

	api.add(T.make("mix_set_master",
			"Set the master's fader (dB) and/or pan (-1..1). Say at least one.",
			{"db": T.num_p("master level in dB", -150, 12), "pan": T.num_p("-1 .. 1", -1, 1)}, [], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				if not a.has("db") and not a.has("pan"):
					return T.fail("say `db` and/or `pan`")
				if a.has("db"):
					DAW.set_master_volume(_taper(float(a["db"])))
				if a.has("pan"):
					DAW.set_master_pan(_pan_in(float(a["pan"])))
				return T.ok({"level_db": _db_of(_state().master.volume), "pan": _pan_out(_state().master.pan)})))

	api.add(T.make("mix_reset_loudness",
			"Start the master's integrated loudness measurement (LUFS, true peak) over.",
			{}, [], T.EDIT,
			func(_a: Dictionary) -> Dictionary:
				DAW.reset_loudness()
				return T.ok({"reset": true})))

	api.add(T.make("mix_latency_report",
			"What plugin latency adds to each track's path out, and how much later than the slowest path a track would need holding to line up. Rows: track, name, own_ms, path_ms, comp_ms (and the same in samples at 48 kHz), plus the slowest path.",
			{}, [], T.READ,
			func(_a: Dictionary) -> Dictionary:
				var rows := DAW.latency_report()
				var out: Array = []
				for r: Dictionary in rows:
					out.append({"track": r["track"], "name": _state().track(r["track"], false).display_name(),
							"own_samples": r["own"], "path_samples": r["path"], "comp_samples": r["comp"],
							"own_ms": snappedf(LatencyReport.milliseconds(int(r["own"]), SAMPLE_RATE), 0.01),
							"path_ms": snappedf(LatencyReport.milliseconds(int(r["path"]), SAMPLE_RATE), 0.01),
							"comp_ms": snappedf(LatencyReport.milliseconds(int(r["comp"]), SAMPLE_RATE), 0.01)})
				return T.ok({"tracks": out, "slowest_samples": LatencyReport.longest(rows),
						"slowest_ms": snappedf(LatencyReport.milliseconds(LatencyReport.longest(rows), SAMPLE_RATE), 0.01)})))


static func _fin(v: float) -> Variant:
	return snappedf(v, 0.01) if is_finite(v) else null


# --- sends --------------------------------------------------------------------------------------

static func _sends_of(s: MixState, i: int) -> Array:
	var t := s.track(i, false)
	var out: Array = []
	var slots: Array = t.sends.keys()
	slots.sort()
	for k in slots:
		var sd: MixState.SendState = t.sends[k]
		var dest := sd.resolve(s)
		out.append({"send": k, "to": dest, "to_name": s.track(dest, false).display_name() if dest > 0 and s.tracks.has(dest) else sd.dest_name,
				"level_db": _db_of(sd.volume), "pan": _pan_out(sd.pan), "pre_fader": sd.pre_fader, "sidechain": sd.key})
	return out


## {ok, slot} for `a["send"]`: a number is the send's slot (as mix_sends_list gives), a name is its destination track.
static func _send_slot(s: MixState, track_index: int, ref: Variant) -> Dictionary:
	var t := s.track(track_index, false)
	if typeof(ref) in [TYPE_INT, TYPE_FLOAT] or (typeof(ref) == TYPE_STRING and str(ref).is_valid_int()):
		if t.sends.has(int(ref)):
			return {"ok": true, "slot": int(ref)}
		return T.fail("track '%s' has no send number %s; its sends are %s" % [t.display_name(), str(ref), JSON.stringify(_sends_of(s, track_index).map(func(x: Dictionary) -> String: return "%d to %s" % [x["send"], x["to_name"]]))])
	var d := ControlRefs.track(s, ref)
	if not d["ok"]:
		return d
	var hits: Array = []
	for k in t.sends:
		if (t.sends[k] as MixState.SendState).resolve(s) == d["index"]:
			hits.append(k)
	if hits.size() == 1:
		return {"ok": true, "slot": hits[0]}
	if hits.is_empty():
		return T.fail("track '%s' has no send to '%s'" % [t.display_name(), s.track(d["index"], false).display_name()])
	return T.fail("track '%s' has several sends to '%s' (numbers %s); give the send number" % [t.display_name(), s.track(d["index"], false).display_name(), str(hits)])


static func _register_sends(api: ControlApi) -> void:
	api.add(T.make("mix_sends_list",
			"The sends (routing to other tracks) of one track, or of every track if none is named. Each: track, send (its number on that track, what the other send tools take), to (destination number), to_name, level_db, pan, pre_fader, sidechain (feeds the destination's key input).",
			{"track": T.ref_p("only this track's sends")}, [], T.READ,
			func(a: Dictionary) -> Dictionary:
				var s := _state()
				var out: Array = []
				var which := s.track_indices()
				if a.has("track"):
					var r := _track(a)
					if not r["ok"]:
						return r
					which = [r["index"]]
				for i in which:
					for row: Dictionary in _sends_of(s, i):
						row["track"] = i
						row["track_name"] = s.track(i, false).display_name()
						out.append(row)
				return T.ok(out)))

	api.add(T.make("mix_send_add",
			"Create a send (a cable) from one track to another. Refused, with the reason, for a track into itself or a loop. Then set its level with mix_send_set. Needs a DAW that can route.",
			{"from": T.ref_p("source track"), "to": T.ref_p("destination track")}, ["from", "to"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				return _make_send(a, false)))

	api.add(T.make("mix_sidechain_add",
			"Create a sidechain send: the source feeds the destination's key input (what a compressor there listens to) and is not heard in its mix. Same refusals as mix_send_add.",
			{"from": T.ref_p("the track that keys (e.g. the kick)"), "to": T.ref_p("the track whose plugin listens (e.g. the bass)")}, ["from", "to"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				return _make_send(a, true)))

	api.add(T.make("mix_send_set",
			"Change a send: level_db (the send's fader), pan (-1..1) and/or pre_fader (taken before the track's own fader and pan). `send` is the send's number from mix_sends_list, or the destination track's name. Say at least one of level_db, pan, pre_fader.",
			{"track": T.ref_p("the sending track"), "send": T.ref_p("send number, or destination track name"),
			"level_db": T.num_p("send level in dB", -150, 12), "pan": T.num_p("-1 .. 1", -1, 1), "pre_fader": T.bool_p("before the fader")},
			["track", "send"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				var r := _track(a)
				if not r["ok"]:
					return r
				if not (a.has("level_db") or a.has("pan") or a.has("pre_fader")):
					return T.fail("say at least one of level_db, pan, pre_fader")
				var s := _state()
				var sl := _send_slot(s, r["index"], a["send"])
				if not sl["ok"]:
					return sl
				var k: int = sl["slot"]
				if a.has("level_db"):
					DAW.set_send_volume(r["index"], k, _taper(float(a["level_db"])))
				if a.has("pan"):
					DAW.set_send_pan(r["index"], k, _pan_in(float(a["pan"])))
				if a.has("pre_fader"):
					DAW.set_send_pre_fader(r["index"], k, bool(a["pre_fader"]))
				var sd: MixState.SendState = s.track(r["index"], false).sends[k]
				return T.ok({"track": r["index"], "send": k, "level_db": _db_of(sd.volume), "pan": _pan_out(sd.pan), "pre_fader": sd.pre_fader})))

	api.add(T.make("mix_send_remove",
			"Remove a send. `send` is its number from mix_sends_list, or the destination track's name. Other sends of the track renumber.",
			{"track": T.ref_p("the sending track"), "send": T.ref_p("send number, or destination track name")}, ["track", "send"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				var r := _track(a)
				if not r["ok"]:
					return r
				var need := _need(&"routing", "change routing")
				if not need.is_empty():
					return need
				var s := _state()
				var sl := _send_slot(s, r["index"], a["send"])
				if not sl["ok"]:
					return sl
				var before := s.track(r["index"], false).sends.size()
				DAW.remove_send(r["index"], sl["slot"])
				if s.track(r["index"], false).sends.size() >= before:
					return T.fail("the send was not removed")
				return T.ok({"track": r["index"], "sends": s.track(r["index"], false).sends.size()})))


static func _make_send(a: Dictionary, key: bool) -> Dictionary:
	var f := _track(a, "from")
	if not f["ok"]:
		return f
	var d := _track(a, "to")
	if not d["ok"]:
		return d
	var need := _need(&"routing", "make sends")
	if not need.is_empty():
		return need
	var why := DAW.send_refusal(f["index"], d["index"])
	if why != "":
		return T.fail(why)
	var s := _state()
	var had := s.track(f["index"], false).sends.keys()
	var made: bool
	if key:
		made = DAW.create_sidechain(f["index"], d["index"])
	else:
		made = DAW.create_send(f["index"], d["index"])
	if not made:
		return T.fail("the send was not made (one of that kind may already exist between them, or this machine is a guest: the host decides)")
	for k in s.track(f["index"], false).sends:
		if not had.has(k):
			var row := _sends_of(s, f["index"]).filter(func(x: Dictionary) -> bool: return x["send"] == k)
			return T.ok(row[0] if not row.is_empty() else {"send": k})
	return T.ok({"from": f["index"], "to": d["index"]})
