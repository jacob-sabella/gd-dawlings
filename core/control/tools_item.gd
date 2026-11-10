extends RefCounted

## Control tools: item and note. See core/control/control_tools.gd and docs/mcp_assistant.md.
##
## An item is addressed by `track` (a name or number, as track_list shows) and `item` (its number in item_list,
## which is its place in the track's start order). Items re-sort after a move, so list again after moving one.
## Every write goes through the DAW method the timeline's own controls call.

const ITEMS_DEFAULT := 100
const ITEMS_MAX := 500
const NOTES_DEFAULT := 200
const NOTES_MAX := 1000
const FADE_NAMES := ["linear", "equal_power", "slow", "fast", "s_curve"]
const NUDGE_UNITS := ["seconds", "beats", "bars"]
## Where an imported sound may come from, besides the project folder and user://.
const IMPORT_DIRS := [OS.SYSTEM_DIR_MUSIC, OS.SYSTEM_DIR_DOCUMENTS, OS.SYSTEM_DIR_DOWNLOADS, OS.SYSTEM_DIR_DESKTOP]


# --- reading ------------------------------------------------------------------------------------

static func _is_audio(it: MixState.ItemState) -> bool:
	return not it.source.is_empty() or not it.peaks.is_empty()


static func _kind(it: MixState.ItemState) -> String:
	if _is_audio(it):
		return "audio"
	if not it.part.is_empty():
		return "demo"
	return "midi"


static func _row(ti: int, it: MixState.ItemState) -> Dictionary:
	var kind := _kind(it)
	var row := {"track": ti, "item": it.index, "name": it.name, "kind": kind,
			"start": snappedf(it.start, 0.0001), "end": snappedf(it.end(), 0.0001), "length": snappedf(it.length, 0.0001),
			"start_beat": snappedf(DAW.state.beat_at(it.start), 0.001), "bar_beat": DAW.state.bar_beat(it.start),
			"gain_db": snappedf(it.gain_db, 0.01), "fade_in": it.fade_in, "fade_out": it.fade_out,
			"fade_in_shape": FADE_NAMES[clampi(it.fade_shape, 0, FADE_NAMES.size() - 1)],
			"fade_out_shape": FADE_NAMES[clampi(it.fade_out_shape, 0, FADE_NAMES.size() - 1)],
			"muted": it.muted, "locked": it.locked, "reversed": it.reversed, "lane": it.lane, "selected": it.selected}
	if kind == "midi":
		row["notes"] = it.notes.size() / MidiTake.NOTE_WIDTH
	if it.is_looped():
		row["loop"] = [it.loop_start, it.loop_end]
	return row


## {ok, track, item, it} for `track` + `item` of the arguments, or a fail.
static func _find(a: Dictionary) -> Dictionary:
	var r := ControlRefs.track(DAW.state, a.get("track"))
	if not r["ok"]:
		return r
	var ti: int = r["index"]
	var items: Array = DAW.state.track(ti, false).items
	var n := int(a.get("item", -1))
	if n < 0 or n >= items.size():
		return ControlTool.fail("track %d has no item %d; it has %d item(s), numbered 0 to %d (item_list shows them)" % [
				ti, n, items.size(), items.size() - 1])
	return {"ok": true, "track": ti, "item": n, "it": items[n]}


static func _find_midi(a: Dictionary, edits := true) -> Dictionary:
	var f := _find(a)
	if not f["ok"]:
		return f
	if _kind(f["it"]) != "midi":
		return ControlTool.fail("item %d on track %d is %s, not MIDI" % [f["item"], f["track"], _kind(f["it"])])
	if edits and f["it"].locked:
		return _locked(f)
	return f


static func _find_audio(a: Dictionary) -> Dictionary:
	var f := _find(a)
	if not f["ok"]:
		return f
	if _kind(f["it"]) != "audio":
		return ControlTool.fail("item %d on track %d is %s, not audio" % [f["item"], f["track"], _kind(f["it"])])
	return f


## A found item that must not be locked.
static func _find_free(a: Dictionary) -> Dictionary:
	var f := _find(a)
	if f["ok"] and f["it"].locked:
		return _locked(f)
	return f


## The item again after a write: the backend may have replaced the object, so one found before is stale.
static func _fresh(f: Dictionary) -> MixState.ItemState:
	return DAW.state.item(f["track"], f["item"])


static func _locked(f: Dictionary) -> Dictionary:
	return ControlTool.fail("item %d on track %d is locked: unlock it first (item_set locked=false)" % [f["item"], f["track"]])


static func _notes_of(it: MixState.ItemState) -> Array:
	var out: Array = []
	var w := MidiTake.NOTE_WIDTH
	for i in it.notes.size() / w:
		out.append({"note": i, "on": snappedf(it.notes[i * w], 0.0001), "off": snappedf(it.notes[i * w + 1], 0.0001),
				"pitch": int(it.notes[i * w + 2]), "velocity": int(it.notes[i * w + 3]), "channel": int(it.notes[i * w + 4])})
	return out


static func _note_at(it: MixState.ItemState, n: int) -> Variant:
	var w := MidiTake.NOTE_WIDTH
	if n < 0 or n * w + w > it.notes.size():
		return null
	return n


static func _pitch_name(p: int) -> String:
	return "%s%d" % [["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"][p % 12], p / 12 - 1]


## Make the selection what a selection verb should act on: the named items of `track` when the call names a
## track, else whatever is selected now. {ok, count} or a fail.
static func _target(a: Dictionary) -> Dictionary:
	if a.has("track"):
		var r := ControlRefs.track(DAW.state, a["track"])
		if not r["ok"]:
			return r
		var ti: int = r["index"]
		var items: Array = DAW.state.track(ti, false).items
		var which: Array = []
		if a.has("items"):
			for v in a["items"]:
				if typeof(v) not in [TYPE_INT, TYPE_FLOAT] or int(v) < 0 or int(v) >= items.size():
					return ControlTool.fail("track %d has no item %s; it has %d item(s)" % [ti, str(v), items.size()])
				which.append(int(v))
		else:
			for i in items.size():
				which.append(i)
		if which.is_empty():
			return ControlTool.fail("track %d has no items" % ti)
		DAW.clear_item_selection()
		for i in which.size():
			DAW.select_item(ti, which[i], i > 0)
		return {"ok": true, "count": which.size()}
	var n: int = DAW.state.selected_items().size()
	if n == 0:
		return ControlTool.fail("nothing is selected: pass track (and items), or call item_select first")
	return {"ok": true, "count": n}


## Whether `path` may be brought in: returns "" or why not.
static func import_refusal(path: String) -> String:
	if path.is_empty():
		return "no path given"
	if ".." in path.replace("\\", "/").split("/"):
		return "paths with '..' are not allowed"
	var real := path
	if path.begins_with("res://") or path.begins_with("user://"):
		real = ProjectSettings.globalize_path(path)
	if not real.is_absolute_path():
		return "give an absolute path, or a res:// or user:// one"
	real = real.simplify_path()
	if not FileAccess.file_exists(real):
		return "%s is not a file" % path
	if real.get_extension().to_lower() not in AudioImport.EXTENSIONS:
		return "%s is not an audio file (%s)" % [real.get_file(), ", ".join(PackedStringArray(AudioImport.EXTENSIONS))]
	var roots: Array = [ProjectSettings.globalize_path("res://"), ProjectSettings.globalize_path("user://")]
	for d in IMPORT_DIRS:
		var dir := OS.get_system_dir(d)
		if not dir.is_empty():
			roots.append(dir)
	var home := OS.get_environment("HOME")
	var allowed := false
	for root: String in roots:
		var r := root.simplify_path().trim_suffix("/")
		if not r.is_empty() and r != home and (real == r or real.begins_with(r + "/")):
			allowed = true
	if not allowed:
		return "files may come only from the project folder, user://, or the Music, Documents, Downloads and Desktop folders"
	if DirAccess.dir_exists_absolute(real.get_base_dir()) and _has_link(real):
		return "links are not followed: give the real file"
	return ""


static func _has_link(real: String) -> bool:
	var d := DirAccess.open(real.get_base_dir())
	return d != null and d.is_link(real.get_file())


# --- registering --------------------------------------------------------------------------------

static func register(api: ControlApi) -> void:
	_register_items(api)
	_register_edits(api)
	_register_selection(api)
	_register_midi(api)
	_register_notes(api)


static func _register_items(api: ControlApi) -> void:
	var T := ControlTool
	var item_p := T.int_p("the item's number in item_list (starting at 0)", 0)
	var trk := T.ref_p("the track: a name or a number (see track_list)")

	api.add(T.make("item_list", "List the clips (items) on one track, or on every track when no track is given, in start order. Each row: track, item (the number other item tools take), name, kind (audio, midi, demo), start/end/length in seconds, start_beat, bar_beat, gain_db, fade_in/fade_out in seconds and their shapes, muted, locked, reversed, lane (take lane, 0 first), selected, and for MIDI the note count. Items re-sort by start after a move, so list again after moving one.",
			{"track": trk, "selected_only": T.bool_p("only the selected items"),
			"limit": T.int_p("most rows, default %d" % ITEMS_DEFAULT, 1, ITEMS_MAX), "offset": T.int_p("rows to skip", 0)},
			[], T.READ, func(a: Dictionary) -> Dictionary:
				var tracks: Array = []
				if a.has("track"):
					var r := ControlRefs.track(DAW.state, a["track"])
					if not r["ok"]:
						return r
					tracks = [r["index"]]
				else:
					tracks = DAW.state.track_indices()
				var rows: Array = []
				for ti in tracks:
					for it: MixState.ItemState in DAW.state.track(ti, false).items:
						if not a.get("selected_only", false) or it.selected:
							rows.append(_row(ti, it))
				var off := int(a.get("offset", 0))
				var lim := int(a.get("limit", ITEMS_DEFAULT))
				return T.ok({"total": rows.size(), "offset": off, "items": rows.slice(off, off + lim)})))

	api.add(T.make("item_get", "One item in full: everything item_list gives, plus its source file name, offset into the file, loop range, the controller lanes of a MIDI item (kind: a CC number, 128 pitch bend, 129 aftertouch; channel; point count) and the track's comp.",
			{"track": trk, "item": item_p}, ["track", "item"], T.READ, func(a: Dictionary) -> Dictionary:
				var f := _find(a)
				if not f["ok"]:
					return f
				var it: MixState.ItemState = f["it"]
				var row := _row(f["track"], it)
				row["source"] = it.source
				row["source_offset"] = it.source_offset
				if not it.part.is_empty():
					row["part"] = it.part
				var lanes := {}
				var w := DawKitClip.CONTROL_WIDTH
				for o in range(0, it.controls.size() - w + 1, w):
					var key := "%d/%d" % [int(it.controls[o + 1]), int(it.controls[o + 3])]
					lanes[key] = int(lanes.get(key, 0)) + 1
				row["controls"] = lanes.keys().map(func(k: String) -> Dictionary:
						return {"kind": int(k.get_slice("/", 0)), "channel": int(k.get_slice("/", 1)), "points": lanes[k]})
				row["comp"] = DAW.state.track(f["track"], false).comp
				return T.ok(row)))

	api.add(T.make("item_add", "Put a new MIDI clip on a track (a take of notes). start and length are seconds on the song's timeline. notes are [{on, off, pitch, velocity}]: on/off in seconds from the start of the clip, pitch 0-127 (60 = middle C), velocity 1-127 (default 100), optional channel 0-15. Returns the new item's number. Refused when the track cannot take MIDI (an audio input track) or the DAW cannot. For sound files use item_import.",
			{"track": trk, "start": T.num_p("seconds", 0), "length": T.num_p("seconds, greater than 0"), "name": T.str_p("the clip's name"),
			"notes": T.arr_p("[{on, off, pitch, velocity}]", {"type": "object"})},
			["track", "start", "length", "notes"], T.EDIT, func(a: Dictionary) -> Dictionary:
				var r := ControlRefs.track(DAW.state, a["track"])
				if not r["ok"]:
					return r
				var ti: int = r["index"]
				var start := float(a["start"])
				var length := float(a["length"])
				if length <= 0.0:
					return T.fail("length must be above 0 seconds")
				var notes: Array = []
				for n in a["notes"]:
					if typeof(n) != TYPE_DICTIONARY or not n.has("on") or not n.has("off") or not n.has("pitch"):
						return T.fail("each note needs on, off and pitch: {\"on\": 0, \"off\": 0.5, \"pitch\": 60}")
					notes.append([start + float(n["on"]), start + float(n["off"]), int(n["pitch"]), int(n.get("velocity", 100)), int(n.get("channel", 0))])
				if notes.is_empty():
					return T.fail("a MIDI clip needs at least one note")
				var name := str(a.get("name", ""))
				var why := DAW.midi_take_refusal([ti, start, start + length, notes, name])
				if not why.is_empty():
					return T.fail(why)
				var before := DAW.state.track(ti, false).items.size()
				DAW.insert_midi_take(ti, start, start + length, notes, name)
				return _added(ti, start, before)))

	api.add(T.make("item_import", "Bring a sound file onto a track as a new audio clip at `start` seconds. The path must be an existing audio file (wav, aiff, flac, ogg, mp3) inside the project folder, user://, or the Music, Documents, Downloads or Desktop folder; paths with '..' are refused. Host only. Returns the clip's number and length in seconds.",
			{"track": trk, "path": T.str_p("absolute path, or res:// / user://"), "start": T.num_p("seconds, default 0", 0)},
			["track", "path"], T.EDIT, func(a: Dictionary) -> Dictionary:
				var r := ControlRefs.track(DAW.state, a["track"])
				if not r["ok"]:
					return r
				var ti: int = r["index"]
				var path := str(a["path"])
				var why := import_refusal(path)
				if not why.is_empty():
					return T.fail(why)
				if path.begins_with("res://") or path.begins_with("user://"):
					path = ProjectSettings.globalize_path(path)
				var start := float(a.get("start", 0.0))
				var before := DAW.state.track(ti, false).items.size()
				var done := DAW.import_audio(path.simplify_path(), ti, start)
				if not str(done.get("error", "")).is_empty():
					return T.fail(str(done["error"]))
				var out := _added(ti, start, before)
				if out["ok"]:
					out["data"]["seconds"] = done["seconds"]
				return out))

	api.add(T.make("item_remove", "Delete ONE item. The rest of the track stays where it is unless ripple is true, when later items move back to close the gap. To delete several at once use item_remove_selected.",
			{"track": trk, "item": item_p, "ripple": T.bool_p("close the gap")}, ["track", "item"], T.EDIT, func(a: Dictionary) -> Dictionary:
				var f := _find_free(a)
				if not f["ok"]:
					return f
				DAW.select_item(f["track"], f["item"])
				if a.get("ripple", false):
					DAW.ripple_delete_selected()
				else:
					DAW.delete_selected()
				return T.ok({"removed": 1})))

	api.add(T.make("item_remove_selected", "Delete every selected item (or the named items of one track), across tracks. Destructive: the player confirms. With ripple, later items on each track move back to close the gap.",
			{"track": trk, "items": arr_ints(), "ripple": T.bool_p("close the gaps")}, [], T.DESTRUCTIVE, func(a: Dictionary) -> Dictionary:
				var t := _target(a)
				if not t["ok"]:
					return t
				if a.get("ripple", false):
					DAW.ripple_delete_selected()
				else:
					DAW.delete_selected()
				return T.ok({"removed": t["count"]})))


static func arr_ints() -> Dictionary:
	return ControlTool.arr_p("item numbers on that track (all of them when omitted)", {"type": "integer"})


## The item just made on `ti` near `start`, for what an add tool returns.
static func _added(ti: int, start: float, before: int) -> Dictionary:
	var items: Array = DAW.state.track(ti, false).items
	if items.size() <= before:
		return ControlTool.fail("the DAW did not add the clip (or it is still being added: look with item_list)")
	var best: MixState.ItemState = null
	for it: MixState.ItemState in items:
		if absf(it.start - start) < 0.01:
			best = it
	if best == null:
		return ControlTool.ok({"track": ti, "note": "added; list the track to find it"})
	return ControlTool.ok({"track": ti, "item": best.index, "start": best.start, "end": best.end()})


static func _register_edits(api: ControlApi) -> void:
	var T := ControlTool
	var item_p := T.int_p("the item's number in item_list (starting at 0)", 0)
	var trk := T.ref_p("the track: a name or a number (see track_list)")
	var sel_args := {"track": trk, "items": arr_ints()}

	api.add(T.make("item_move", "Move an item to start at `start` seconds, and optionally onto another track (to_track). With ripple, every later unlocked item on its track is carried along by as much. Items re-sort afterwards: list again to learn its new number.",
			{"track": trk, "item": item_p, "start": T.num_p("new start, seconds", 0), "to_track": trk, "ripple": T.bool_p("carry later items along (same track only)")},
			["track", "item", "start"], T.EDIT, func(a: Dictionary) -> Dictionary:
				var f := _find_free(a)
				if not f["ok"]:
					return f
				var to := 0
				if a.has("to_track"):
					var r := ControlRefs.track(DAW.state, a["to_track"])
					if not r["ok"]:
						return r
					to = r["index"] if r["index"] != f["track"] else 0
				if a.get("ripple", false):
					if to != 0:
						return T.fail("ripple moves items within one track; drop to_track")
					DAW.ripple_move_item(f["track"], f["item"], float(a["start"]))
				else:
					DAW.move_item(f["track"], f["item"], float(a["start"]), to)
				return T.ok({"note": "list the track again: items re-sort by start"})))

	api.add(T.make("item_trim", "Set an item's edges: it then runs from `start` to `end` seconds (the sound under it stays put; a MIDI clip's notes outside are cut). With ripple, later items follow the change.",
			{"track": trk, "item": item_p, "start": T.num_p("seconds", 0), "end": T.num_p("seconds", 0), "ripple": T.bool_p("carry later items along")},
			["track", "item", "start", "end"], T.EDIT, func(a: Dictionary) -> Dictionary:
				var f := _find_free(a)
				if not f["ok"]:
					return f
				if float(a["end"]) - float(a["start"]) < DAWBackend.MIN_ITEM_SECONDS:
					return T.fail("an item must be at least %s seconds long" % DAWBackend.MIN_ITEM_SECONDS)
				if a.get("ripple", false):
					DAW.ripple_trim_item(f["track"], f["item"], float(a["start"]), float(a["end"]))
				else:
					DAW.trim_item(f["track"], f["item"], float(a["start"]), float(a["end"]))
				return T.ok()))

	api.add(T.make("item_split", "Cut every item that spans `seconds` into two. Acts on the named items of one track (track, optional items) or, with no track, on the current selection. Both halves stay selected.",
			{"seconds": T.num_p("song position to cut at", 0), "track": trk, "items": arr_ints()}, ["seconds"], T.EDIT, func(a: Dictionary) -> Dictionary:
				var t := _target(a)
				if not t["ok"]:
					return t
				var s := float(a["seconds"])
				var hit := 0
				for p in DAW.state.selected_items():
					var it := DAW.state.item(p[0], p[1])
					if it != null and it.contains(s) and not it.locked:
						hit += 1
				if hit == 0:
					return T.fail("no selected, unlocked item spans %s seconds" % s)
				DAW.split_selected(s)
				return T.ok({"cut": hit, "note": "list the track again: new items appear"})))

	api.add(T.make("item_glue", "Glue the selected items (or the named items of one track) into one per track: MIDI clips, or cuts of one file that follow on. Refused quietly by the DAW when they cannot be glued, so check with item_list.",
			sel_args, [], T.EDIT, func(a: Dictionary) -> Dictionary:
				var t := _target(a)
				if not t["ok"]:
					return t
				var before := _count_items()
				DAW.glue_selected()
				if _count_items() >= before:
					return T.fail("nothing was glued: the items must be MIDI, or consecutive cuts of one file, on the same track")
				return T.ok({"note": "list the track again"})))

	api.add(T.make("item_duplicate", "Duplicate the selected items (or the named items of one track), each placed straight after the original.",
			sel_args, [], T.EDIT, func(a: Dictionary) -> Dictionary:
				var t := _target(a)
				if not t["ok"]:
					return t
				DAW.duplicate_selected()
				return T.ok({"copied": t["count"]})))

	api.add(T.make("item_copy_to", "Copy the selected items (or the named items of one track) so that the first begins at `seconds`, keeping their spacing, on their own tracks.",
			{"seconds": T.num_p("where the copy starts", 0), "track": trk, "items": arr_ints()}, ["seconds"], T.EDIT, func(a: Dictionary) -> Dictionary:
				var t := _target(a)
				if not t["ok"]:
					return t
				DAW.copy_selected_to(float(a["seconds"]))
				return T.ok({"copied": t["count"]})))

	api.add(T.make("item_paste", "Copy one item onto a track (the same or another) at `start` seconds, with its notes, sound, fades and gain. Host only. The DAW's refusal text is returned when it cannot (a frozen track, MIDI onto an audio-input track, a file not on this machine).",
			{"track": trk, "item": item_p, "to_track": trk, "start": T.num_p("seconds", 0)}, ["track", "item", "to_track", "start"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				var f := _find(a)
				if not f["ok"]:
					return f
				var r := ControlRefs.track(DAW.state, a["to_track"])
				if not r["ok"]:
					return r
				var packed := MixWire.pack_item(f["it"])
				var why := DAW.paste_refusal(r["index"], packed)
				if why.is_empty():
					why = DAW.paste_item(r["index"], float(a["start"]), packed)
				if not why.is_empty():
					return T.fail(why)
				return T.ok({"note": "list the track to find the new item"})))

	api.add(T.make("item_nudge", "Move the selected unlocked items (or the named items of one track) by `amount` of `unit`: seconds, beats or bars along the tempo map; negative is earlier. None goes before the song's start.",
			{"amount": T.num_p("how far; negative is earlier"), "unit": T.str_p("seconds, beats or bars", NUDGE_UNITS), "track": trk, "items": arr_ints()},
			["amount", "unit"], T.EDIT, func(a: Dictionary) -> Dictionary:
				var t := _target(a)
				if not t["ok"]:
					return t
				DAW.nudge_selected(float(a["amount"]), NUDGE_UNITS.find(str(a["unit"])))
				return T.ok({"note": "list the track again: items re-sort by start"})))

	api.add(T.make("item_set_gain", "Set an item's own gain in dB (-60 to +24; 0 is unchanged). Audio and MIDI both.",
			{"track": trk, "item": item_p, "db": T.num_p("dB", DAWBackend.ITEM_GAIN_MIN, DAWBackend.ITEM_GAIN_MAX)},
			["track", "item", "db"], T.EDIT, func(a: Dictionary) -> Dictionary:
				var f := _find_free(a)
				if not f["ok"]:
					return f
				DAW.set_item_gain(f["track"], f["item"], float(a["db"]))
				return T.ok({"gain_db": _fresh(f).gain_db})))

	api.add(T.make("item_normalise", "Raise or lower an audio item's gain so its loudest moment sits at full scale (0 dBFS). Nothing happens for an item with no sound to measure (MIDI). Returns the new gain in dB.",
			{"track": trk, "item": item_p}, ["track", "item"], T.EDIT, func(a: Dictionary) -> Dictionary:
				var f := _find_audio(a)
				if not f["ok"]:
					return f
				if f["it"].locked:
					return _locked(f)
				if f["it"].sound_peak() <= 0.0:
					return T.fail("this item has no overview to measure")
				DAW.normalise_item(f["track"], f["item"])
				return T.ok({"gain_db": _fresh(f).gain_db})))

	api.add(T.make("item_process", "Render an audio item's sound into a new file: kind 'stretch' (amount = new length over old, keeping pitch, e.g. 2 is twice as long) or 'pitch' (amount = semitones, keeping length, -24..24). Not for MIDI. Items up to a minute of sound; backends without the engine do nothing.",
			{"track": trk, "item": item_p, "kind": T.str_p("stretch or pitch", ["stretch", "pitch"]),
			"amount": T.num_p("stretch ratio (%s to %s) or semitones" % [DAWBackend.STRETCH_MIN, DAWBackend.STRETCH_MAX])},
			["track", "item", "kind", "amount"], T.EDIT, func(a: Dictionary) -> Dictionary:
				var f := _find_audio(a)
				if not f["ok"]:
					return f
				if f["it"].locked:
					return _locked(f)
				var kind := DAWBackend.PROCESS_STRETCH if a["kind"] == "stretch" else DAWBackend.PROCESS_PITCH
				var length_before: float = f["it"].length
				DAW.process_item(f["track"], f["item"], kind, float(a["amount"]))
				return T.ok({"length_before": length_before, "note": "list the track to see the result"})))

	api.add(T.make("item_set_fades", "Set an item's fades: fade_in and fade_out lengths in seconds (0 = none), and their shapes: linear, equal_power, slow, fast, s_curve. Any you leave out keep their current value.",
			{"track": trk, "item": item_p, "fade_in": T.num_p("seconds", 0), "fade_out": T.num_p("seconds", 0),
			"in_shape": T.str_p("shape of the fade in", FADE_NAMES), "out_shape": T.str_p("shape of the fade out", FADE_NAMES)},
			["track", "item"], T.EDIT, func(a: Dictionary) -> Dictionary:
				var f := _find_free(a)
				if not f["ok"]:
					return f
				var it: MixState.ItemState = f["it"]
				if a.has("fade_in") or a.has("fade_out"):
					DAW.set_item_fades(f["track"], f["item"], float(a.get("fade_in", it.fade_in)), float(a.get("fade_out", it.fade_out)))
				if a.has("in_shape") or a.has("out_shape"):
					DAW.set_item_fade_shape(f["track"], f["item"],
							FADE_NAMES.find(str(a["in_shape"])) if a.has("in_shape") else it.fade_shape,
							FADE_NAMES.find(str(a["out_shape"])) if a.has("out_shape") else it.fade_out_shape)
				return T.ok(_row(f["track"], _fresh(f)))))

	api.add(T.make("item_crossfade", "Crossfade two overlapping items of one track over their overlap (equal power: the earlier out, the later in). Refused when they do not overlap or either is locked.",
			{"track": trk, "first": item_p, "second": item_p}, ["track", "first", "second"], T.EDIT, func(a: Dictionary) -> Dictionary:
				var r := ControlRefs.track(DAW.state, a["track"])
				if not r["ok"]:
					return r
				if not DAW.crossfade_items(r["index"], int(a["first"]), int(a["second"])):
					return T.fail("those two items cannot be crossfaded: they must be two different items of the track that overlap, and neither locked")
				return T.ok()))

	api.add(T.make("item_set", "Change an item's flags and name; any you leave out stay as they are. muted, locked (a locked item refuses moves and edits), reversed (audio plays backwards), lane (take lane, 0 the first), name.",
			{"track": trk, "item": item_p, "muted": T.bool_p("silence it"), "locked": T.bool_p("lock it"), "reversed": T.bool_p("audio backwards"),
			"lane": T.int_p("take lane, 0 first", 0, 31), "name": T.str_p("new name")},
			["track", "item"], T.EDIT, func(a: Dictionary) -> Dictionary:
				var f := _find(a)
				if not f["ok"]:
					return f
				var it: MixState.ItemState = f["it"]
				if it.locked and (a.has("reversed") or a.has("lane")):
					return _locked(f)
				if a.has("reversed") and _kind(it) != "audio":
					return T.fail("only audio items can be reversed")
				var ti: int = f["track"]
				var n: int = f["item"]
				if a.has("muted"):
					DAW.set_item_muted(ti, n, bool(a["muted"]))
				if a.has("reversed"):
					DAW.set_item_reversed(ti, n, bool(a["reversed"]))
				if a.has("lane"):
					DAW.set_item_lane(ti, n, int(a["lane"]))
				if a.has("name"):
					DAW.rename_item(ti, n, str(a["name"]))
				if a.has("locked"):
					DAW.set_item_locked(ti, n, bool(a["locked"]))
				return T.ok(_row(ti, _fresh(f)))))

	api.add(T.make("item_set_comp", "Make take lane `lane` the one that sounds on a track between `from` and `to` seconds (comping). Use item_set lane to put takes on lanes first.",
			{"track": trk, "from": T.num_p("seconds", 0), "to": T.num_p("seconds", 0), "lane": T.int_p("take lane", 0, 31)},
			["track", "from", "to", "lane"], T.EDIT, func(a: Dictionary) -> Dictionary:
				var r := ControlRefs.track(DAW.state, a["track"])
				if not r["ok"]:
					return r
				if float(a["to"]) <= float(a["from"]):
					return T.fail("'to' must be after 'from'")
				DAW.set_comp(r["index"], float(a["from"]), float(a["to"]), int(a["lane"]))
				return T.ok(DAW.state.track(r["index"], false).comp)))

	api.add(T.make("item_flatten_comp", "Make a track's comp plain: each item cut to what the comp plays of it, all on the first lane.",
			{"track": trk}, ["track"], T.EDIT, func(a: Dictionary) -> Dictionary:
				var r := ControlRefs.track(DAW.state, a["track"])
				if not r["ok"]:
					return r
				if DAW.state.track(r["index"], false).comp.is_empty():
					return T.fail("track %d has no comp to flatten (see item_set_comp)" % r["index"])
				DAW.flatten_comp(r["index"])
				return T.ok()))

	api.add(T.make("item_freeze_track", "Freeze a track: render its sound (items and plugins) to one audio file the length of the song, bypassing its plugins. Undo with item_thaw_track.",
			{"track": trk}, ["track"], T.EDIT, func(a: Dictionary) -> Dictionary:
				var r := ControlRefs.track(DAW.state, a["track"])
				if not r["ok"]:
					return r
				if DAW.state.track(r["index"], false).is_frozen():
					return T.fail("track %d is already frozen" % r["index"])
				DAW.freeze_track(r["index"])
				return T.ok({"frozen": DAW.state.track(r["index"], false).is_frozen()})))

	api.add(T.make("item_thaw_track", "Thaw a frozen track: put its items and plugins back as they were.",
			{"track": trk}, ["track"], T.EDIT, func(a: Dictionary) -> Dictionary:
				var r := ControlRefs.track(DAW.state, a["track"])
				if not r["ok"]:
					return r
				if not DAW.state.track(r["index"], false).is_frozen():
					return T.fail("track %d is not frozen" % r["index"])
				DAW.thaw_track(r["index"])
				return T.ok()))

	api.add(T.make("item_set_controls", "Set a MIDI item's controller lane: kind is a CC number 0-127 (value 0-127), 128 pitch bend (value -8192 to 8191, 0 centre) or 129 aftertouch (0-127); channel 0-15; points are [[seconds from the item's start, value], ...]. An empty list removes the lane.",
			{"track": trk, "item": item_p, "kind": T.int_p("CC number, 128 bend, 129 aftertouch", 0, 129), "channel": T.int_p("MIDI channel 0-15", 0, 15),
			"points": T.arr_p("[[seconds, value], ...]", {"type": "array"})},
			["track", "item", "kind", "points"], T.EDIT, func(a: Dictionary) -> Dictionary:
				var f := _find_midi(a)
				if not f["ok"]:
					return f
				for p in a["points"]:
					if typeof(p) != TYPE_ARRAY or p.size() != 2 or typeof(p[0]) not in [TYPE_INT, TYPE_FLOAT] or typeof(p[1]) not in [TYPE_INT, TYPE_FLOAT]:
						return T.fail("each point is [seconds, value]")
				DAW.set_item_controls(f["track"], f["item"], int(a["kind"]), int(a.get("channel", 0)), a["points"])
				return T.ok()))


static func _count_items() -> int:
	var n := 0
	for ti in DAW.state.track_indices():
		n += DAW.state.track(ti, false).items.size()
	return n


static func _register_selection(api: ControlApi) -> void:
	var T := ControlTool
	var trk := T.ref_p("the track: a name or a number (see track_list)")

	api.add(T.make("item_select", "Select one item (selection is what split, glue, duplicate, nudge, copy and loop act on). additive keeps the others selected.",
			{"track": trk, "item": T.int_p("item number", 0), "additive": T.bool_p("add to the selection")}, ["track", "item"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				var f := _find(a)
				if not f["ok"]:
					return f
				DAW.select_item(f["track"], f["item"], bool(a.get("additive", false)))
				return T.ok({"selected": DAW.state.selected_items().size()})))

	api.add(T.make("item_select_clear", "Select nothing.", {}, [], T.EDIT, func(_a: Dictionary) -> Dictionary:
		DAW.clear_item_selection()
		return T.ok()))

	api.add(T.make("item_select_all", "Select every item on every track, or only those on one track.",
			{"track": trk}, [], T.EDIT, func(a: Dictionary) -> Dictionary:
				if a.has("track"):
					var r := ControlRefs.track(DAW.state, a["track"])
					if not r["ok"]:
						return r
					DAW.select_track_items(r["index"])
				else:
					DAW.select_all_items()
				return T.ok({"selected": DAW.state.selected_items().size()})))

	api.add(T.make("item_loop_selected", "Set the loop range round the selected items (first start to last end) and switch looping on. Fails when nothing is selected.",
			{"track": trk, "items": arr_ints()}, [], T.EDIT, func(a: Dictionary) -> Dictionary:
				var t := _target(a)
				if not t["ok"]:
					return t
				if not DAW.loop_selected_items():
					return T.fail("the selection is too short to loop")
				return T.ok({"loop_start": DAW.state.loop_start, "loop_end": DAW.state.loop_end})))


static func _register_midi(api: ControlApi) -> void:
	var T := ControlTool
	var item_p := T.int_p("the MIDI item's number in item_list", 0)
	var trk := T.ref_p("the track: a name or a number (see track_list)")
	var base := {"track": trk, "item": item_p}

	api.add(T.make("note_quantize", "Pull a MIDI item's notes onto a grid. grid_beats: 1 a quarter note, 0.25 a sixteenth (0.03125 to 16). strength 0-1 (1 snaps fully), swing 0-1 (0 straight, 1 every off-beat a third late).",
			{"track": trk, "item": item_p, "grid_beats": T.num_p("grid in beats", DAWBackend.QUANTIZE_GRID_MIN, DAWBackend.QUANTIZE_GRID_MAX),
			"strength": T.num_p("0 to 1, default 1", 0, 1), "swing": T.num_p("0 to 1, default 0", 0, DAWBackend.SWING_MAX)},
			["track", "item", "grid_beats"], T.EDIT, func(a: Dictionary) -> Dictionary:
				var f := _find_midi(a)
				if not f["ok"]:
					return f
				DAW.quantize_item(f["track"], f["item"], float(a["grid_beats"]), float(a.get("strength", 1.0)), float(a.get("swing", 0.0)))
				return T.ok()))

	api.add(T.make("note_groove", "Pull a MIDI item's timing onto the feel of another MIDI item (its timing against a straight grid of grid_beats, per slot of a bar). from_track/from_item name the item to copy the feel from.",
			{"track": trk, "item": item_p, "from_track": trk, "from_item": T.int_p("the groove item's number", 0),
			"grid_beats": T.num_p("grid in beats", DAWBackend.QUANTIZE_GRID_MIN, DAWBackend.QUANTIZE_GRID_MAX), "strength": T.num_p("0 to 1, default 1", 0, 1)},
			["track", "item", "from_track", "from_item", "grid_beats"], T.EDIT, func(a: Dictionary) -> Dictionary:
				var f := _find_midi(a)
				if not f["ok"]:
					return f
				var g := _find_midi({"track": a["from_track"], "item": a["from_item"]}, false)
				if not g["ok"]:
					return g
				DAW.groove_item(f["track"], f["item"], g["track"], g["item"], float(a["grid_beats"]), float(a.get("strength", 1.0)))
				return T.ok()))

	api.add(T.make("note_humanise", "Loosen a MIDI item: each note moved by a random amount up to `seconds` (0 to 0.1) and its velocity by up to `velocity` (0 to 40).",
			{"track": trk, "item": item_p, "seconds": T.num_p("timing spread, seconds", 0, DAWBackend.HUMANISE_SECONDS_MAX),
			"velocity": T.int_p("velocity spread", 0, DAWBackend.HUMANISE_VELOCITY_MAX)},
			["track", "item", "seconds", "velocity"], T.EDIT, func(a: Dictionary) -> Dictionary:
				var f := _find_midi(a)
				if not f["ok"]:
					return f
				DAW.humanise_item(f["track"], f["item"], float(a["seconds"]), int(a["velocity"]))
				return T.ok()))

	api.add(T.make("note_transpose_all", "Move every note of a MIDI item by `semitones` (-48 to 48), kept within MIDI's range.",
			{"track": trk, "item": item_p, "semitones": T.int_p("semitones", -DAWBackend.TRANSPOSE_MAX, DAWBackend.TRANSPOSE_MAX)},
			["track", "item", "semitones"], T.EDIT, func(a: Dictionary) -> Dictionary:
				var f := _find_midi(a)
				if not f["ok"]:
					return f
				DAW.transpose_item(f["track"], f["item"], int(a["semitones"]))
				return T.ok()))

	api.add(T.make("note_shift_velocity", "Raise or lower every note's velocity in a MIDI item by `by` (-126 to 126); results stay 1-127.",
			{"track": trk, "item": item_p, "by": T.int_p("velocity steps", -DAWBackend.VELOCITY_SHIFT_MAX, DAWBackend.VELOCITY_SHIFT_MAX)},
			["track", "item", "by"], T.EDIT, func(a: Dictionary) -> Dictionary:
				var f := _find_midi(a)
				if not f["ok"]:
					return f
				DAW.shift_velocity(f["track"], f["item"], int(a["by"]))
				return T.ok()))

	api.add(T.make("note_legato", "Hold every note of a MIDI item until the next one starts.", base, ["track", "item"], T.EDIT,
			func(a: Dictionary) -> Dictionary: return _midi_verb(a, DAW.legato_item)))
	api.add(T.make("note_staccato", "Cut every note of a MIDI item to half its length.", base, ["track", "item"], T.EDIT,
			func(a: Dictionary) -> Dictionary: return _midi_verb(a, DAW.staccato_item)))
	api.add(T.make("note_retrograde", "Play a MIDI item's notes backwards: the last first, each keeping its length.", base, ["track", "item"], T.EDIT,
			func(a: Dictionary) -> Dictionary: return _midi_verb(a, DAW.retrograde_item)))
	api.add(T.make("note_even_velocity", "Give every note of a MIDI item the item's average velocity.", base, ["track", "item"], T.EDIT,
			func(a: Dictionary) -> Dictionary: return _midi_verb(a, DAW.even_velocity)))


static func _midi_verb(a: Dictionary, verb: Callable) -> Dictionary:
	var f := _find_midi(a)
	if not f["ok"]:
		return f
	verb.call(f["track"], f["item"])
	return ControlTool.ok()


static func _register_notes(api: ControlApi) -> void:
	var T := ControlTool
	var item_p := T.int_p("the MIDI item's number in item_list", 0)
	var trk := T.ref_p("the track: a name or a number (see track_list)")
	var note_p := T.int_p("the note's number in note_list", 0)

	api.add(T.make("note_list", "List a MIDI item's notes in the item's own order. Each row: note (the number other note tools take), on and off in seconds from the item's start, pitch (0-127, 60 middle C), pitch_name, velocity (1-127), channel. Note numbers can change after an edit: list again.",
			{"track": trk, "item": item_p, "limit": T.int_p("most rows, default %d" % NOTES_DEFAULT, 1, NOTES_MAX), "offset": T.int_p("rows to skip", 0)},
			["track", "item"], T.READ, func(a: Dictionary) -> Dictionary:
				var f := _find_midi(a, false)
				if not f["ok"]:
					return f
				var rows := _notes_of(f["it"])
				for r in rows:
					r["pitch_name"] = _pitch_name(r["pitch"])
				var off := int(a.get("offset", 0))
				var lim := int(a.get("limit", NOTES_DEFAULT))
				return T.ok({"total": rows.size(), "item_length": f["it"].length, "offset": off, "notes": rows.slice(off, off + lim)})))

	api.add(T.make("note_add", "Put one note into a MIDI item: on and off in seconds from the item's start (kept inside the item), pitch 0-127, optional velocity 1-127 (default the usual one). Returns the note's number.",
			{"track": trk, "item": item_p, "on": T.num_p("seconds from the item's start", 0), "off": T.num_p("seconds from the item's start", 0),
			"pitch": T.int_p("0-127, 60 middle C", 0, 127), "velocity": T.int_p("1-127", 1, 127)},
			["track", "item", "on", "off", "pitch"], T.EDIT, func(a: Dictionary) -> Dictionary:
				var f := _find_midi(a)
				if not f["ok"]:
					return f
				var it: MixState.ItemState = f["it"]
				var on := float(a["on"])
				var off := float(a["off"])
				if off <= on:
					return T.fail("off must be after on")
				if on >= it.length:
					return T.fail("on is past the end of the item (%s seconds long)" % it.length)
				var before := it.notes.size()
				DAW.insert_note(f["track"], f["item"], on, off, int(a["pitch"]))
				it = _fresh(f)
				if it == null or it.notes.size() <= before:
					return T.fail("the note was not added (the item may be full)")
				var found := -1
				var rows := _notes_of(it)
				for r in rows:
					if r["pitch"] == int(a["pitch"]) and absf(r["on"] - on) < 0.01:
						found = r["note"]
				if found >= 0 and a.has("velocity"):
					DAW.set_note_velocity(f["track"], f["item"], found, int(a["velocity"]))
				return T.ok({"note": found, "notes": rows.size()})))

	api.add(T.make("note_set", "Change one note of a MIDI item; leave out what stays. velocity 1-127; end: seconds from the item's start where it ends (cut short or held longer, within the item); move_by: seconds earlier (negative) or later; semitones: up or down. move_by and semitones together are one step. Note numbers may change after a move: list again.",
			{"track": trk, "item": item_p, "note": note_p, "velocity": T.int_p("1-127", 1, 127), "end": T.num_p("seconds from the item's start", 0),
			"move_by": T.num_p("seconds"), "semitones": T.int_p("semitones", -DAWBackend.TRANSPOSE_MAX, DAWBackend.TRANSPOSE_MAX)},
			["track", "item", "note"], T.EDIT, func(a: Dictionary) -> Dictionary:
				var f := _find_midi(a)
				if not f["ok"]:
					return f
				var n := int(a["note"])
				if _note_at(f["it"], n) == null:
					return T.fail("item has %d note(s), numbered from 0; no note %d" % [f["it"].notes.size() / MidiTake.NOTE_WIDTH, n])
				var ti: int = f["track"]
				var ii: int = f["item"]
				if a.has("velocity"):
					DAW.set_note_velocity(ti, ii, n, int(a["velocity"]))
				if a.has("end"):
					DAW.set_note_end(ti, ii, n, float(a["end"]))
				var by := float(a.get("move_by", 0.0))
				var semi := int(a.get("semitones", 0))
				if a.has("move_by") and a.has("semitones"):
					DAW.place_note(ti, ii, n, by, semi)
				elif a.has("move_by"):
					DAW.move_note(ti, ii, n, by)
				elif a.has("semitones"):
					DAW.transpose_note(ti, ii, n, semi)
				return T.ok({"note": "list the notes again: numbers can change"})))

	api.add(T.make("note_remove", "Delete one note of a MIDI item by its number in note_list. Later notes are renumbered.",
			{"track": trk, "item": item_p, "note": note_p}, ["track", "item", "note"], T.EDIT, func(a: Dictionary) -> Dictionary:
				var f := _find_midi(a)
				if not f["ok"]:
					return f
				var n := int(a["note"])
				if _note_at(f["it"], n) == null:
					return T.fail("item has %d note(s), numbered from 0; no note %d" % [f["it"].notes.size() / MidiTake.NOTE_WIDTH, n])
				DAW.delete_note(f["track"], f["item"], n)
				return T.ok({"notes": _fresh(f).notes.size() / MidiTake.NOTE_WIDTH})))
