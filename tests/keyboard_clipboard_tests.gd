extends RefCounted

## The keyboard and mouse pass's tests, called from tests/run_tests.gd's `_test_keys_*`: copy, cut, paste and duplicate on exact targets, on both engines, and the clip editor following its clip.

var t: Node


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


func close_to(label: String, a: float, b: float, epsilon := 0.0001) -> void:
	t.close_to(label, a, b, epsilon)


## A solo session on a clean project, with nothing on the lanes the tests use.
func _fresh(role: int = Session.Role.SOLO, me := 1) -> MixState:
	t._offline()
	t._as_session(role, me)
	var s := DAW.state
	for index in s.track_indices():
		s.track(index).items.clear()
	return s


func _clip(track: int, start: float, length: float, title := "clip") -> Array:
	DAW.insert_midi_take(track, start, start + length, [[start, start + length * 0.5, 60, 100, 0]], title)
	var items: Array = DAW.state.track(track).items
	for i in items.size():
		if is_equal_approx(items[i].start, start):
			return [track, i, items[i].start, items[i].length]
	return []


func _starts(track: int) -> Array:
	return DAW.state.track(track).items.map(func(it): return snappedf(it.start, 0.001))


## What Session.notice says from now until _done, this file's own listener and nobody else's.
func _heard() -> Array:
	_said = []
	if not Session.notice.is_connected(_hear):
		Session.notice.connect(_hear)
	return _said


var _said: Array = []


func _hear(words: String) -> void:
	_said.append(words)


func over_the_limit_is_said() -> void:
	var s := _fresh()
	_heard()
	var many: Array = []
	for i in DAW.EDIT_TARGETS_MAX + 1:
		many.append([1, i, float(i), 0.5])
	var first := _clip(2, 1.0, 1.0)
	DAW.copy_items([first])
	DAW.copy_items(many)
	check("a copy over the limit says the count and the limit (%s)" % [_said],
			not _said.is_empty() and "513" in str(_said[-1]) and "512" in str(_said[-1]))
	_said.clear()
	DAW.cut_items(many)
	check("so does a cut", not _said.is_empty() and "nothing was cut" in str(_said[-1]))
	_said.clear()
	DAW.edit_targets("delete", many)
	check("and a delete", not _said.is_empty() and "nothing was deleted" in str(_said[-1]))
	_said.clear()
	DAW._clipboard_intent(&"clipboard_copy", [many], 1)
	check("the host says it too, to whoever asked", not _said.is_empty() and "513" in str(_said[-1]))
	DAW.paste_items(3, 4.0)
	check("and the older clipboard was not replaced by it", s.track(3).items.size() == 1)
	_done()


func a_new_project_clears_the_clipboard() -> void:
	_fresh()
	_heard()
	DAW.copy_items([_clip(1, 1.0, 1.0)])
	check("copied", DAW._clipboards.has(Session.local_peer_id))
	DAW.open_project("/nonexistent/no_such.dawkit")
	check("a project that failed to open leaves it", DAW._clipboards.has(Session.local_peer_id))
	DAW.new_project()
	check("a new project empties it", DAW._clipboards.is_empty())
	_said.clear()
	DAW.paste_items(1, 2.0)
	check("and a paste says so (%s)" % [_said], not _said.is_empty() and "Nothing is copied" in str(_said[-1]))
	_done()


func _done() -> void:
	if Session.notice.is_connected(_hear):
		Session.notice.disconnect(_hear)
	Session.start_solo()
	t._offline()


func copy_paste_keeps_time_and_tracks() -> void:
	var s := _fresh()
	var a := _clip(2, 1.0, 2.0, "low")
	var b := _clip(4, 3.5, 1.0, "high")
	DAW.copy_items([a, b])
	check("a copy changes nothing", _starts(2) == [1.0] and _starts(4) == [3.5])
	DAW.paste_items(5, 10.0)
	check("the top clip lands on the track and time named (%s)" % [_starts(5)], _starts(5) == [10.0])
	check("the other keeps its two tracks and 2.5 s from it (%s)" % [_starts(7)], _starts(7) == [12.5])
	check("as the clips they were", s.track(5).items[0].name == "low" and s.track(7).items[0].name == "high"
			and s.track(5).items[0].notes == s.track(2).items[0].notes)
	_done()


func cut_is_one_undo() -> void:
	var s := _fresh()
	var a := _clip(2, 1.0, 2.0)
	var b := _clip(3, 1.0, 2.0)
	var depth: int = s.undo_depth
	DAW.cut_items([a, b])
	check("cut takes both", _starts(2).is_empty() and _starts(3).is_empty())
	check("in one step (%d)" % (s.undo_depth - depth), s.undo_depth == depth + 1)
	DAW.undo()
	check("one undo puts both back", _starts(2) == [1.0] and _starts(3) == [1.0])
	DAW.redo()
	DAW.paste_items(6, 4.0)
	check("and what was cut can be pasted", _starts(6) == [4.0] and _starts(7) == [4.0])
	_done()


func paste_is_one_undo() -> void:
	var s := _fresh()
	var a := _clip(2, 0.0, 1.0)
	var b := _clip(3, 2.0, 1.0)
	DAW.copy_items([a, b])
	var depth: int = s.undo_depth
	DAW.paste_items(6, 8.0)
	check("a paste of two is one step (%d)" % (s.undo_depth - depth), s.undo_depth == depth + 1)
	DAW.undo()
	check("one undo takes both off", _starts(6).is_empty() and _starts(7).is_empty())
	_done()


func paste_selects_the_copies() -> void:
	var s := _fresh()
	var a := _clip(2, 0.0, 1.0)
	DAW.select_item(2, 0)
	DAW.copy_items()
	DAW.paste_items(3, 5.0)
	check("the paste is the selection", s.track(3).items[0].selected)
	check("and the original no longer is", not s.track(2).items[0].selected)
	check("the copy came from the selection, with no list named", DAW._clipboards[1].size() == 1
			and is_equal_approx(float(a[2]), 0.0))
	_done()


func paste_past_the_last_track_refuses() -> void:
	var s := _fresh()
	var said := _heard()
	var a := _clip(2, 0.0, 1.0)
	var b := _clip(4, 0.0, 1.0)
	DAW.copy_items([a, b])
	var last: int = s.track_indices().back()
	var depth: int = s.undo_depth
	DAW.paste_items(last, 3.0)
	check("nothing lands, not even the row that fits", _starts(last).is_empty() and s.undo_depth == depth)
	check("and it says why (%s)" % [said], said.any(func(w): return w.contains("past the last track")))
	_done()


func frozen_track_refuses() -> void:
	var s := _fresh()
	var said := _heard()
	var a := _clip(2, 0.0, 1.0)
	var b := _clip(3, 0.0, 1.0)
	DAW.copy_items([a])
	s.track(5).frozen = {"items": [], "comp": [], "fx_on": {}}
	var depth: int = s.undo_depth
	DAW.paste_items(5, 1.0)
	check("a paste onto a frozen track refuses", _starts(5).is_empty() and s.undo_depth == depth)
	s.track(3).frozen = {"items": [], "comp": [], "fx_on": {}}
	for op in ["delete", "cut", "duplicate"]:
		DAW.edit_targets(op, [a, b])
		check("%s with one target frozen changes nothing" % op, _starts(2) == [0.0] and _starts(3) == [0.0]
				and s.undo_depth == depth)
	check("and it names the track (%s)" % [said], said.any(func(w): return w.contains("frozen")))
	s.track(3).frozen = {}
	s.track(5).frozen = {}
	_done()


func exact_targets_refuse_a_moved_clip() -> void:
	var s := _fresh()
	var said := _heard()
	var a := _clip(2, 0.0, 1.0)
	var b := _clip(2, 4.0, 1.0)
	DAW.move_item(2, 1, 4.25)
	var depth: int = s.undo_depth
	for op in ["delete", "cut", "duplicate"]:
		DAW.edit_targets(op, [a, b])
	check("a stale target refuses the whole edit (%s)" % [_starts(2)], _starts(2) == [0.0, 4.25] and s.undo_depth == depth)
	check("and says so", said.any(func(w): return w.contains("changed before")))
	var near := [2, 1, 4.2504, 1.0]
	DAW.edit_targets("delete", [near])
	check("half a millisecond off is the same clip", _starts(2) == [0.0])
	DAW.apply_intent(&"edit_targets", ["delete", [[2, 0, NAN, 1.0]]])
	DAW.apply_intent(&"edit_targets", ["explode", [[2, 0, 0.0, 1.0]]])
	DAW.apply_intent(&"edit_targets", ["delete", [[2, 0, 0.0, 1.0], [2, 0, 0.0, 1.0]]])
	var many: Array = []
	for n in DAW.EDIT_TARGETS_MAX + 1:
		many.append([2, n, 0.0, 1.0])
	DAW.apply_intent(&"edit_targets", ["delete", many])
	check("malformed, repeated and oversized requests change nothing", _starts(2) == [0.0])
	_done()


func guest_clipboard_stays_on_host() -> void:
	var s := _fresh(Session.Role.HOST, 1)
	var a := _clip(2, 0.0, 1.0, "hers")
	var b := _clip(3, 0.0, 1.0, "mine")
	DAW.apply_intent(&"clipboard_copy", [[a]], 5)
	DAW.copy_items([b])
	check("each player's clipboard is kept on the host", DAW._clipboards.has(5) and DAW._clipboards.has(1))
	DAW.apply_intent(&"clipboard_paste", [6, 2.0], 5)
	DAW.paste_items(7, 2.0)
	check("the guest pastes hers", s.track(6).items.size() == 1 and s.track(6).items[0].name == "hers")
	check("and the host pastes its own", s.track(7).items.size() == 1 and s.track(7).items[0].name == "mine")
	DAW.close_edits_of(5)
	check("a guest who leaves is forgotten, and nobody else", not DAW._clipboards.has(5) and DAW._clipboards.has(1))
	_done()


func guest_drag_lands_on_its_clip() -> void:
	var s := _fresh(Session.Role.HOST, 1)
	_clip(3, 1.0, 2.0)
	_clip(3, 5.0, 2.0)
	_clip(3, 9.0, 2.0)
	# The guest picked up index 1 (5s). The clip before it goes while the release is on the wire.
	DAW.apply_intent(&"edit_targets", ["delete", [[3, 0, 1.0, 2.0]]], 6)
	DAW.apply_intent(&"held_item_edit", [&"move_item", 3, 1, 5.0, 7.0, [6.0, 0]], 5)
	check("the guest's clip moved and not its neighbour (%s)" % [_starts(3)], _starts(3) == [6.0, 9.0])

	# The clip itself gone: nothing moves.
	DAW.apply_intent(&"edit_targets", ["delete", [[3, 0, 6.0, 2.0]]], 6)
	DAW.apply_intent(&"held_item_edit", [&"trim_item", 3, 0, 6.0, 8.0, [6.5, 7.5]], 5)
	check("a clip that has gone edits nothing (%s)" % [_starts(3)], _starts(3) == [9.0] \
			and is_equal_approx(s.track(3).items[0].length, 2.0))

	# Two clips with that span are not a guess.
	_clip(4, 1.0, 1.0)
	_clip(4, 3.0, 1.0)
	_clip(4, 3.0, 1.0)
	DAW.apply_intent(&"edit_targets", ["delete", [[4, 0, 1.0, 1.0]]], 6)
	DAW.apply_intent(&"held_item_edit", [&"move_item", 4, 7, 3.0, 4.0, [8.0, 0]], 5)
	check("an ambiguous clip stays put (%s)" % [_starts(4)], _starts(4) == [3.0, 3.0])

	# Only the drag's verbs, and only well formed.
	DAW.apply_intent(&"held_item_edit", [&"remove_track", 3, 0, 9.0, 11.0, []], 5)
	DAW.apply_intent(&"held_item_edit", [&"move_item", 3, 0, 9.0, 11.0, [NAN, 0]], 5)
	DAW.apply_intent(&"held_item_edit", [&"move_item", 3, 0, 9.0, 11.0, [1.0]], 5)
	check("a bad intent changes nothing", s.tracks.has(3) and _starts(3) == [9.0])
	_done()


func guest_paste_keeps_host_drag() -> void:
	var s := _fresh(Session.Role.HOST, 1)
	var a := _clip(2, 0.0, 1.0)
	DAW.apply_intent(&"clipboard_copy", [[a]], 5)
	var depth: int = s.undo_depth
	var was: float = s.track(1).volume
	var was_pan: float = s.track(1).pan
	DAW.open_edit("host drag")
	DAW.set_track_volume(1, 0.5)
	DAW.apply_intent(&"clipboard_paste", [6, 2.0], 5)
	check("the guest's paste lands", _starts(6) == [2.0])
	check("and the host's edit is still open", DAW.backend.edit_open(0))
	DAW.set_track_pan(1, 0.25)
	DAW.close_edit()
	check("the drag and the paste are one step each (%d)" % (s.undo_depth - depth), s.undo_depth == depth + 2)
	DAW.undo()
	check("the paste comes off alone", _starts(6).is_empty() and is_equal_approx(s.track(1).volume, 0.5))
	DAW.undo()
	check("and the drag, volume and pan after the paste together, as one (%s, %s; was %s, %s)" % [s.track(1).volume,
			s.track(1).pan, was, was_pan], is_equal_approx(s.track(1).volume, was) and is_equal_approx(s.track(1).pan, was_pan))
	_done()


func edit_refused_with_open_edit() -> void:
	var s := _fresh(Session.Role.HOST, 1)
	var said := _heard()
	var a := _clip(2, 0.0, 1.0)
	DAW.copy_items([a])
	DAW.apply_intent(&"clipboard_copy", [[a]], 5)
	DAW.backend.acting_peer = 5
	DAW.backend.open_edit("guest drag")
	DAW.backend.acting_peer = 0
	var depth: int = s.undo_depth
	DAW.apply_intent(&"clipboard_paste", [6, 2.0], 5)
	DAW.apply_intent(&"edit_targets", ["delete", [a]], 5)
	DAW.apply_intent(&"clipboard_cut", [[a]], 5)
	check("a player with an edit open cannot paste, delete or cut", _starts(6).is_empty() and _starts(2) == [0.0]
			and s.undo_depth == depth)
	DAW.paste_items(7, 2.0)
	check("while the host, with none open, still can", _starts(7) == [2.0])
	DAW.backend.acting_peer = 5
	DAW.backend.close_edit()
	DAW.backend.acting_peer = 0
	DAW.open_edit("mine")
	DAW.paste_items(8, 2.0)
	check("the host with its own edit open is refused too, and told", _starts(8).is_empty()
			and said.any(func(w): return w.contains("Let go")))
	DAW.close_edit()
	_done()


func host_refusal_is_heard() -> void:
	_fresh()
	var said := _heard()
	DAW.paste_items(2, 0.0)
	check("solo: a refusal is a notice here (%s)" % [said], said.size() == 1 and said[0].contains("Nothing is copied"))
	said.clear()
	t._as_session(Session.Role.HOST, 3)
	DAW.paste_items(2, 0.0)
	check("hosted with any peer id, from == 0 reaches this machine (%s)" % [said], said.size() == 1)
	said.clear()
	DAW.apply_intent(&"clipboard_paste", [2, 0.0], 9)
	check("a guest's refusal is not said on the host's screen", said.is_empty())
	_done()


func cut_refuses_what_cannot_paste() -> void:
	var s := _fresh()
	var said := _heard()
	DAW.insert_audio_take(2, 0.0, "suite-gone.wav", 2.0, PackedByteArray(), "Gone")
	var target := [2, 0, 0.0, 2.0]
	var depth: int = s.undo_depth
	DAW.cut_items([target])
	check("a clip that could not be pasted back is not cut", _starts(2) == [0.0] and s.undo_depth == depth)
	check("nothing went on the clipboard", not DAW._clipboards.has(1))
	check("and it says why (%s)" % [said], said.any(func(w): return w.contains("Nothing was cut")))
	_done()


func locked_stay_out_of_cut() -> void:
	var s := _fresh()
	var said := _heard()
	var a := _clip(2, 0.0, 1.0, "free")
	var b := _clip(3, 0.0, 1.0, "held")
	DAW.set_item_locked(3, 0, true)
	DAW.cut_items([a, b])
	check("the free clip is cut and the locked one stays", _starts(2).is_empty() and _starts(3) == [0.0])
	check("the notice counts it (%s)" % [said], said.any(func(w): return w.contains("1 locked stayed")))
	check("only the free clip is on the clipboard", DAW._clipboards[1].size() == 1
			and DAW._clipboards[1][0]["name"] == "free")
	said.clear()
	DAW.edit_targets("delete", [[3, 0, 0.0, 1.0]])
	check("a delete of only locked clips changes nothing and says so", _starts(3) == [0.0]
			and said.any(func(w): return w.contains("locked")))
	check("and the lock survived", s.track(3).items[0].locked)
	_done()


func duplicate_keeps_a_phrase_whole() -> void:
	var s := _fresh()
	_clip(2, 0.0, 4.0, "A")
	_clip(2, 4.0, 4.0, "B")
	DAW.select_item(2, 0)
	DAW.select_item(2, 1, true)
	var depth: int = s.undo_depth
	DAW.duplicate_selected()
	check("A 0-4 and B 4-8 repeat at 8-12 and 12-16 (%s)" % [_starts(2)], _starts(2) == [0.0, 4.0, 8.0, 12.0])
	check("in order", s.track(2).items[2].name == "A" and s.track(2).items[3].name == "B")
	check("the copies are the selection", s.track(2).items[2].selected and s.track(2).items[3].selected
			and not s.track(2).items[0].selected and not s.track(2).items[1].selected)
	check("one step", s.undo_depth == depth + 1)
	DAW.undo()
	DAW.edit_targets("duplicate", [[2, 0, 0.0, 4.0], [2, 1, 4.0, 4.0]])
	check("by exact targets the same", _starts(2) == [0.0, 4.0, 8.0, 12.0])
	_done()


func _lua(part: String) -> void:
	var lua := ""
	for candidate in ["lua5.4", "lua", "luajit"]:
		if OS.execute("sh", ["-c", "command -v " + candidate]) == 0:
			lua = candidate
			break
	if lua == "":
		return
	var said: Array = []
	var rc := OS.execute(lua, [ProjectSettings.globalize_path("res://tests/bridge_clipboard_test.lua"), part], said, true)
	check("the bridge's %s checks pass (%s)" % [part, str(said).substr(0, 400)], rc == 0
			and str(said).contains(" checks, 0 failed"))


func bridge_clipboard_round_trip() -> void:
	_lua("round_trip")


func bridge_targets_ignore_reaper_selection() -> void:
	_lua("targets")


func bridge_cut_waits_for_copy() -> void:
	var dir := ProjectSettings.globalize_path("user://test_clipboard_bridge")
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	t._as_session(Session.Role.SOLO, 1)
	var reaper := ReaperBackend.new()
	reaper.state = MixState.new()
	DAW.use(reaper, false)
	reaper._bridge = ScriptBridge.new()
	reaper._bridge.open(dir)
	var s := reaper.state
	var clip := MixState.ItemState.new()
	clip.start = 2.0
	clip.length = 1.0
	clip.name = "native"
	s.track(1)
	s.track(2).items = [clip]
	var said := _heard()
	var pending := func() -> Array:
		var out: Array = []
		var ids: Array = reaper._bridge._pending.keys()
		ids.sort()
		for id in ids:
			out.append(reaper._bridge._pending[id]["fn"])
		return out
	var answer := func(result: Variant) -> void:
		var id: int = reaper._bridge._pending.keys().min()
		var cb: Callable = reaper._bridge._pending[id]["cb"]
		reaper._bridge._pending.erase(id)
		cb.call(result)
	var target := [2, 0, 2.0, 1.0]

	DAW.cut_items([target])
	check("a cut asks for the copy first, alone (%s)" % [pending.call()], pending.call() == ["CopyToClipboard"])
	check("and nothing has left the lane", s.track(2).items.size() == 1)
	answer.call({"ok": false, "error": "item moved"})
	check("a failed copy sends no delete (%s)" % [pending.call()], (pending.call() as Array).is_empty())
	check("deletes nothing and holds nothing", s.track(2).items.size() == 1 and not DAW._clipboards.has(1))
	check("and says so (%s)" % [said], said.any(func(w): return w.contains("nothing was cut")))

	DAW.cut_items([target])
	answer.call(null)
	check("a copy never answered deletes nothing", (pending.call() as Array).is_empty() and s.track(2).items.size() == 1)

	DAW.cut_items([target])
	answer.call({"ok": true, "copied": 1})
	check("a copy that held sends the delete (%s)" % [pending.call()], pending.call() == ["DeleteItems"])
	check("the cache waits for its answer", s.track(2).items.size() == 1)
	answer.call({"ok": true, "deleted": 1, "locked": 0})
	check("and moves on the ok", s.track(2).items.is_empty())

	DAW.paste_items(1, 8.0)
	check("a paste goes to the slot (%s)" % [pending.call()], pending.call() == ["PasteClipboard"])
	answer.call({"ok": false, "error": "no clipboard"})
	check("a slot the bridge lost leaves the cache alone and says to copy again (%s)" % [said],
			s.track(1).items.is_empty() and said.any(func(w): return w.contains("copy it again")))
	reaper._bridge._pending.clear()
	reaper._bridge.close()
	reaper._bridge = null
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	_done()


## An editor open on `track`'s clip at `index`, on the runner so its signals are live.
func _editor(track: int, index: int) -> ClipEditorSurface:
	var editor := ClipEditorSurface.new()
	t.add_child(editor)
	editor.open(track, index)
	return editor


func editor_follows_its_clip() -> void:
	_fresh()
	var a := _clip(2, 0.0, 1.0, "before")
	_clip(2, 4.0, 1.0, "mine")
	_clip(2, 8.0, 1.0, "after")
	var editor := _editor(2, 1)
	DAW.edit_targets("delete", [a])
	check("a clip deleted before it: the same clip, one index down (%s)" % [editor.target],
			editor.is_open() and editor.target == [2, 0] and editor.item().name == "mine")
	DAW.copy_items([[2, 1, 8.0, 1.0]])
	DAW.paste_items(2, 1.0)
	check("a clip pasted before it: the same clip, one index up (%s)" % [editor.target],
			editor.is_open() and editor.target == [2, 1] and editor.item().name == "mine")
	DAW.undo()
	check("the paste undone: back with it", editor.is_open() and editor.target == [2, 0]
			and editor.item().name == "mine")
	DAW.undo()
	check("the delete undone: back with it", editor.is_open() and editor.target == [2, 1]
			and editor.item().name == "mine")
	DAW.set_item_gain(2, 1, -3.0)
	check("an edit that moves nothing leaves it where it is", editor.is_open() and editor.target == [2, 1])
	editor.free()
	_done()


func editor_closes_rather_than_switch() -> void:
	_fresh()
	var mine := _clip(2, 0.0, 2.0, "mine")
	_clip(2, 2.0, 2.0, "touching")
	var editor := _editor(2, 0)
	DAW.edit_targets("delete", [mine])
	check("its clip deleted, with a neighbour butted up to it: closed", not editor.is_open())
	DAW.undo()
	var late := _clip(3, 5.0, 1.0, "last")
	editor.open(3, 0)
	DAW.edit_targets("delete", [late])
	check("the only clip on the lane deleted: closed", not editor.is_open())
	# The hard one: the neighbour lands on the index, over the same time, with the same (no) file.
	_fresh()
	var low := _clip(4, 0.0, 4.0, "low")
	_clip(4, 2.0, 4.0, "over")
	editor.open(4, 0)
	DAW.edit_targets("delete", [low])
	check("an overlapping clip takes the index: still closed, not switched", not editor.is_open())
	_fresh()
	var same := _clip(5, 0.0, 4.0, "short")
	DAW.insert_midi_take(5, 0.0, 6.0, [[0.0, 3.0, 60, 100, 0]], "long")
	var at := DAW.state.track(5).items.find_custom(func(it): return it.name == "short")
	editor.open(5, at)
	same[1] = at
	DAW.edit_targets("delete", [same])
	check("one that starts with it and runs on: closed too", not editor.is_open())
	editor.free()
	_done()


func editor_survives_its_own_trim() -> void:
	_fresh()
	_clip(2, 1.0, 4.0, "mine")
	_clip(2, 8.0, 1.0, "after")
	var editor := _editor(2, 0)
	editor.commit({"start": 2.0})
	check("its start trimmed past its only note: open on it (%s)" % [editor.target], editor.is_open() and editor.target == [2, 0])
	close_to("and it has the new edge", editor.item().start, 2.0)
	editor.commit({"end": 3.0})
	check("its end trimmed too: open still", editor.is_open() and editor.item().name == "mine")
	DAW.undo()
	DAW.undo()
	check("both undone: open on it as it was", editor.is_open() and is_equal_approx(editor.item().start, 1.0)
			and is_equal_approx(editor.item().end(), 5.0))
	# A trim that carries the clip past the one beside it renumbers both.
	_fresh()
	_clip(3, 0.0, 4.0, "mine")
	_clip(3, 1.0, 4.0, "over")
	editor.open(3, 0)
	editor.commit({"start": 2.0})
	check("trimmed past its neighbour's start: it follows to the new index (%s)" % [editor.target],
			editor.is_open() and editor.target == [3, 1] and editor.item().name == "mine")
	DAW.set_item_gain(3, 1, -2.0)
	check("and the next edit still finds it", editor.is_open() and editor.item().name == "mine")
	check("the lane is as it should be (%s)" % [_starts(3)], _starts(3) == [1.0, 2.0])
	editor.free()
	_done()
