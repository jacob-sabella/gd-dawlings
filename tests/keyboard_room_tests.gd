extends RefCounted

## The keyboard and mouse pass's tests, called from tests/run_tests.gd's `_test_keys_*`: Delete, undo and paste from the room: what the pointer is on, and when they refuse.

var t: Node


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


func close_to(label: String, a: float, b: float, epsilon := 0.0001) -> void:
	t.close_to(label, a, b, epsilon)


## A hand that is only where the test says: never in the tree, so nothing moves its hover.
class Hand extends Interactor:
	func aim() -> Transform3D:
		return Transform3D.IDENTITY
	func fine() -> bool:
		return false


## A screen that says it is open, for the registries.
class Screen extends Node:
	func is_open() -> bool:
		return true


## A DAW with no history of its own to read: counts what it is asked.
class CountingBackend extends DAWBackend:
	var undos := 0
	var redos := 0
	func undo() -> void:
		undos += 1
	func redo() -> void:
		redos += 1


var _said: Array = []
var _timeline: TimelineSurface
var _lanes: TimelineLanes
var _hand: Hand
var _keys: RoomShortcuts


func _hear(words: String) -> void:
	_said.append(words)


## A clean solo session, a timeline showing 0 to 40 seconds, a hand and the keys.
func _rig(role: int = Session.Role.SOLO, me := 1) -> MixState:
	t._offline()
	t._as_session(role, me)
	var s: MixState = DAW.state
	# Stopped: a playing timeline's window follows the playhead away from the clips.
	DAW.transport_stop()
	for index in s.track_indices():
		s.track(index).items.clear()
	_timeline = TimelineSurface.new()
	t.add_child(_timeline)
	_timeline._process(0.0)
	_timeline.set_view(0.0, 40.0)
	_lanes = _timeline._lanes
	_hand = Hand.new()
	_keys = RoomShortcuts.new()
	_keys.hand = _hand
	t.add_child(_keys)
	t.get_viewport().gui_release_focus()
	_said = []
	if not Session.notice.is_connected(_hear):
		Session.notice.connect(_hear)
	return s


func _done() -> void:
	if Session.notice.is_connected(_hear):
		Session.notice.disconnect(_hear)
	t.get_viewport().gui_release_focus()
	_hand.free()
	t.remove_child(_keys)
	_keys.free()
	t.remove_child(_timeline)
	_timeline.free()
	t._as_session(Session.Role.SOLO, 1)


func _clip(track: int, start: float, length: float) -> void:
	DAW.insert_midi_take(track, start, start + length, [[start, start + length * 0.5, 60, 100, 0]], "clip")
	# The window is clamped to the song, so it is set again now the song is this long.
	_timeline.set_view(0.0, 40.0)
	_timeline._process(0.0)


func _at(track: int, seconds: float) -> Vector3:
	var row: int = _timeline._shown().find(track)
	return _timeline.to_global(Vector3(_timeline._x_for(seconds), _timeline._lane_y[row], _lanes.position.z))


func _point(track: int, seconds: float) -> void:
	_hand.hovered = _lanes
	_hand.hover_point = _at(track, seconds)


func _key(code: Key, ctrl := false, shift := false, echo := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	e.echo = echo
	e.ctrl_pressed = ctrl
	e.shift_pressed = shift
	return e


func _last() -> String:
	return str(_said[-1]) if not _said.is_empty() else ""


func _select(track: int, index: int, additive := true) -> void:
	DAW.select_item(track, index, additive)


func delete_needs_the_timeline() -> void:
	var s := _rig()
	_clip(3, 4.0, 2.0)
	_select(3, 0)
	check("Delete with the pointer on nothing is the room's to refuse", _keys.handle(_key(KEY_DELETE)))
	check("and removes nothing", s.track(3).items.size() == 1)
	check("and says why (%s)" % _last(), _last().contains("Point at a clip"))
	check("Backspace off the lanes is left for the stage", not _keys.handle(_key(KEY_BACKSPACE)))
	check("Shift+Delete is no binding", not _keys.handle(_key(KEY_DELETE, false, true)))
	check("Ctrl+S is left for the session panel", not _keys.handle(_key(KEY_S, true)))
	_done()


func bare_lane_and_automation_do_nothing() -> void:
	var s := _rig()
	_clip(3, 4.0, 2.0)
	_select(3, 0)
	_point(3, 20.0)
	check("Delete on bare lane is heard", _keys.handle(_key(KEY_DELETE)))
	check("and leaves the selected clip alone", s.track(3).items.size() == 1)
	check("and says so (%s)" % _last(), _last().contains("No clip under the pointer"))
	_keys.handle(_key(KEY_X, true))
	check("Ctrl+X on bare lane cuts nothing", s.track(3).items.size() == 1 and _last().contains("nothing was cut"))
	_keys.handle(_key(KEY_D, true))
	check("Ctrl+D on bare lane duplicates nothing", s.track(3).items.size() == 1 and _last().contains("nothing was duplicated"))

	# The automation row, drawn over a clip: the row wins, whatever is under it.
	_point(3, 5.0)
	_timeline.shown_lane = "volume"
	_timeline._auto_row_y = _timeline.to_local(_hand.hover_point).y
	_keys.handle(_key(KEY_DELETE))
	check("Delete on the automation row removes nothing", s.track(3).items.size() == 1)
	check("and names the row (%s)" % _last(), _last().contains("automation row"))
	_keys.handle(_key(KEY_V, true))
	check("Ctrl+V on the row pastes nothing", s.track(3).items.size() == 1 and _last().contains("to paste"))
	_timeline.shown_lane = ""
	_done()


func hidden_selection_refuses() -> void:
	var s := _rig()
	_clip(3, 4.0, 2.0)
	_clip(3, 60.0, 2.0)
	_select(3, 0)
	_select(3, 1)
	_point(3, 5.0)
	var view := _timeline.selection_in_view()
	check("the selection names both (%d)" % (view["targets"] as Array).size(), (view["targets"] as Array).size() == 2)
	check("and counts the one past the window (%d)" % view["hidden"], view["hidden"] == 1)
	_keys.handle(_key(KEY_DELETE))
	check("a selection partly out of view is refused", s.track(3).items.size() == 2)
	check("with a count (%s)" % _last(), _last().contains("1 of the 2"))

	# On a track past the lanes on the panel.
	var last: int = s.track_indices()[-1]
	var kept := _timeline.lane_first
	_timeline.lane_first = 0
	if not last in _timeline._shown():
		_clip(last, 4.0, 1.0)
		_select(last, 0)
		check("a track off the panel counts as hidden", int(_timeline.selection_in_view()["hidden"]) >= 1)
	_timeline.lane_first = kept

	# All of it in view, the whole selection goes, as one step.
	_timeline.set_view(0.0, 80.0)
	_timeline._process(0.0)
	DAW.clear_item_selection()
	_select(3, 0)
	_select(3, 1)
	_point(3, 5.0)
	var depth := s.undo_depth
	_keys.handle(_key(KEY_DELETE))
	check("in view, the whole selection goes", s.track(3).items.is_empty())
	check("as one undo step", s.undo_depth == depth + 1)
	check("and the notice gives the count and the way back (%s)" % _last(),
			_last().contains("2 clips") and _last().contains("Ctrl+Z"))
	_done()


func overlap_refuses() -> void:
	var s := _rig()
	_clip(3, 4.0, 4.0)
	_clip(3, 6.0, 4.0)
	_point(3, 7.0)
	check("both takes are under the pointer", _timeline.items_at_point(_hand.hover_point).size() == 2)
	_keys.handle(_key(KEY_DELETE))
	check("overlapping unselected takes are refused", s.track(3).items.size() == 2)
	check("saying to click one (%s)" % _last(), _last().contains("overlap") and _last().contains("click one"))
	_select(3, 1, false)
	_keys.handle(_key(KEY_DELETE))
	check("with one selected, it goes", s.track(3).items.size() == 1)
	_done()


func delete_takes_the_item_under_the_pointer() -> void:
	var s := _rig()
	_clip(3, 4.0, 2.0)
	_clip(3, 10.0, 2.0)
	_select(3, 1, false)
	_point(3, 5.0)
	_keys.handle(_key(KEY_DELETE))
	check("an unselected clip under the pointer is the only target",
			s.track(3).items.size() == 1 and is_equal_approx(s.track(3).items[0].start, 10.0))
	check("said once (%s)" % _last(), _last().contains("1 clip") and _last().contains("restores it"))
	DAW.undo()
	check("Ctrl+Z's step brings it back", s.track(3).items.size() == 2)

	s.track(3).items[0].locked = true
	DAW.clear_item_selection()
	_select(3, 0)
	_select(3, 1)
	_point(3, 5.0)
	_keys.handle(_key(KEY_BACKSPACE))
	check("Backspace on the lanes follows the same rule, a locked clip staying", s.track(3).items.size() == 1)
	check("and the count says so (%s)" % _last(), _last().contains("1 locked stayed"))
	_done()


func nothing_to_act_on_says_so() -> void:
	var s := _rig()
	_keys.handle(_key(KEY_A, true))
	check("Ctrl+A with no clips (%s)" % _last(), _last().contains("no clips"))
	_keys.handle(_key(KEY_A, true, true))
	check("Ctrl+Shift+A with none selected (%s)" % _last(), _last().contains("Nothing is selected"))
	_keys.handle(_key(KEY_C, true))
	check("Ctrl+C with none selected (%s)" % _last(), _last().contains("Nothing is selected"))
	_keys.handle(_key(KEY_V, true))
	check("Ctrl+V pointing at nothing (%s)" % _last(), _last().contains("to paste"))
	_point(3, 5.0)
	_keys.handle(_key(KEY_V, true))
	check("Ctrl+V with nothing copied (%s)" % _last(), _last().contains("Nothing is copied"))
	_clip(3, 4.0, 2.0)
	_keys.handle(_key(KEY_A, true))
	check("Ctrl+A counts (%s)" % _last(), _last().contains("1 clip") and s.track(3).items[0].selected)
	_keys.handle(_key(KEY_C, true))
	check("Ctrl+C says what it took (%s)" % _last(), _last().contains("Copying 1 clip"))
	_keys.handle(_key(KEY_A, true, true))
	check("Ctrl+Shift+A clears (%s)" % _last(), _last().contains("cleared") and not s.track(3).items[0].selected)
	_point(3, 20.0)
	_keys.handle(_key(KEY_V, true))
	check("Ctrl+V lands on the lane under the pointer", s.track(3).items.size() == 2)
	_done()


func undo_names_the_step() -> void:
	var s := _rig()
	DAW.set_track_mute(3, true)
	var named := str(s.undo_names[s.undo_depth - 1])
	check("Ctrl+Z is the room's", _keys.handle(_key(KEY_Z, true)))
	check("and undoes", not s.track(3).mute)
	check("naming the step (%s)" % _last(), _last() == "Undo: %s" % named)
	_keys.handle(_key(KEY_Z, true, true))
	check("Ctrl+Shift+Z redoes", s.track(3).mute)
	check("naming it too (%s)" % _last(), _last() == "Redo: %s" % named)
	_keys.handle(_key(KEY_Z, true))
	_keys.handle(_key(KEY_Y, true))
	check("Ctrl+Y redoes", s.track(3).mute)
	var heard := _said.size()
	check("an echo still undoes", _keys.handle(_key(KEY_Z, true, false, true)) and not s.track(3).mute)
	check("and posts nothing", _said.size() == heard)
	_keys.handle(_key(KEY_Z, true))
	check("nothing left says so (%s)" % _last(), _last() == "Nothing to undo.")
	_done()


func undo_is_never_suppressed_by_depth() -> void:
	var keep := _rig()
	check("the rig has a state", keep != null)
	var backend := CountingBackend.new()
	backend.state = MixState.new()
	DAW.use(backend)
	DAW.state.undo_depth = 0
	DAW.state.redo_depth = 0
	_keys.handle(_key(KEY_Z, true))
	check("a depth of 0 still sends the undo", backend.undos == 1)
	check("and, the depth not being known, says only Undo (%s)" % _last(), _last() == "Undo")
	_keys.handle(_key(KEY_Y, true))
	check("and the redo (%s)" % _last(), backend.redos == 1 and _last() == "Redo")
	_done()
	t._offline()


func refused_during_a_lane_drag() -> void:
	var s := _rig()
	_clip(3, 4.0, 2.0)
	DAW.set_track_mute(3, true)
	_point(3, 5.0)
	_hand.held = _lanes
	var depth := s.undo_depth
	for chord: Array in [[KEY_Z, false], [KEY_Z, true], [KEY_Y, false]]:
		_said.clear()
		check("a history key is held back during the drag", _keys.handle(_key(chord[0], true, chord[1])))
		check("saying so (%s)" % _last(), _last() == RoomShortcuts.LET_GO)
	check("history did not move", s.undo_depth == depth and s.track(3).mute)
	_said.clear()
	_keys.handle(_key(KEY_Z, true, false, true))
	check("an echo during the drag is silent", _said.is_empty() and s.undo_depth == depth)
	for code: Key in [KEY_X, KEY_D, KEY_V, KEY_A]:
		_said.clear()
		_keys.handle(_key(code, true))
		check("Ctrl+%s waits for the drag" % OS.get_keycode_string(code), _last() == RoomShortcuts.LET_GO)
	_keys.handle(_key(KEY_DELETE))
	check("Delete waits for it", s.track(3).items.size() == 1 and _last() == RoomShortcuts.LET_GO)
	_hand.held = null
	_done()


func a_drag_follows_its_clip_past_a_delete() -> void:
	var s := _rig(Session.Role.HOST, 1)
	_clip(3, 1.0, 2.0)
	_clip(3, 5.0, 2.0)
	_clip(3, 9.0, 2.0)
	_lanes._on_grab_begin(_at(3, 5.5))
	_lanes._on_grab_move(_at(3, 7.5))
	check("the 5s clip is in the hand", _lanes._hit == [3, 1])
	DAW._clipboard_intent(&"edit_targets", ["delete", [[3, 0, 1.0, 2.0]]], 2)
	check("a guest deleted the clip before it", s.track(3).items.size() == 2)
	_lanes._on_grab_move(_at(3, 7.6))
	_lanes._on_grab_end()
	var starts: Array = s.track(3).items.map(func(it): return snappedf(it.start, 0.001))
	check("the neighbour stayed at 9 (%s)" % [starts], 9.0 in starts)
	check("and the held clip moved (%s)" % [starts], not 5.0 in starts)
	_done()

	s = _rig(Session.Role.HOST, 1)
	_clip(3, 1.0, 2.0)
	_clip(3, 5.0, 2.0)
	_clip(3, 9.0, 2.0)
	_lanes._on_grab_begin(_at(3, 5.5))
	_lanes._on_grab_move(_at(3, 7.5))
	DAW._clipboard_intent(&"edit_targets", ["delete", [[3, 1, 5.0, 2.0]]], 2)
	_lanes._on_grab_end()
	var left: Array = s.track(3).items.map(func(it): return snappedf(it.start, 0.001))
	check("the held clip itself gone: nothing else moves (%s)" % [left], left == [1.0, 9.0])
	check("and the hand is told (%s)" % _last(), "changed while you held it" in _last())
	_done()


func refused_during_any_grab() -> void:
	var s := _rig()
	_clip(3, 4.0, 2.0)
	DAW.set_track_mute(3, true)
	_point(3, 5.0)
	var fader := ControlAffordance.new()
	_hand.held = fader
	_keys.handle(_key(KEY_DELETE))
	check("Delete waits for a grabbed control", s.track(3).items.size() == 1 and _last() == RoomShortcuts.LET_GO)
	_keys.handle(_key(KEY_X, true))
	check("so does cut", s.track(3).items.size() == 1 and _last() == RoomShortcuts.LET_GO)
	_keys.handle(_key(KEY_Z, true))
	check("undo does not: only a lane drag holds indices", not s.track(3).mute)
	_hand.held = null
	fader.free()

	DAW.open_edit("a held fader")
	check("an open edit shows", DAW.backend.edit_open(0))
	_point(3, 5.0)
	_said.clear()
	_keys.handle(_key(KEY_DELETE))
	check("Delete waits for an open edit", s.track(3).items.size() == 1 and _last() == RoomShortcuts.LET_GO)
	_said.clear()
	_keys.handle(_key(KEY_V, true))
	check("so does paste", _last() == RoomShortcuts.LET_GO)
	DAW.close_edit()
	_done()


func refused_during_look_solo() -> void:
	var s := _rig()
	_clip(3, 4.0, 2.0)
	var solo := LookSolo.new()
	solo.press(3)
	check("look to solo holds an edit open", DAW.backend.edit_open(0))
	_point(3, 5.0)
	for code: Key in [KEY_X, KEY_D, KEY_V]:
		_said.clear()
		_keys.handle(_key(code, true))
		check("Ctrl+%s waits for look to solo" % OS.get_keycode_string(code), _last() == RoomShortcuts.LET_GO)
	_said.clear()
	_keys.handle(_key(KEY_DELETE))
	check("Delete waits for it", s.track(3).items.size() == 1 and _last() == RoomShortcuts.LET_GO)
	solo.release()
	_keys.handle(_key(KEY_DELETE))
	check("let go, Delete works", s.track(3).items.is_empty())
	_done()


func refused_in_a_modal_or_text() -> void:
	var s := _rig()
	_clip(3, 4.0, 2.0)
	DAW.set_track_mute(3, true)
	_point(3, 5.0)
	var depth := s.undo_depth

	var modal := Screen.new()
	modal.add_to_group(KeyChord.MODAL)
	t.add_child(modal)
	for chord: Array in [[KEY_DELETE, false], [KEY_Z, true], [KEY_V, true], [KEY_A, true]]:
		check("a modal keeps %s" % OS.get_keycode_string(chord[0]), not _keys.handle(_key(chord[0], chord[1])))
	t.remove_child(modal)
	modal.free()

	var panel := Screen.new()
	panel.add_to_group(KeyChord.PANEL)
	t.add_child(panel)
	check("a panel keeps Delete", not _keys.handle(_key(KEY_DELETE)))
	check("and paste", not _keys.handle(_key(KEY_V, true)))
	check("but undo reaches the song", _keys.handle(_key(KEY_Z, true)) and not s.track(3).mute)
	check("and redo", _keys.handle(_key(KEY_Z, true, true)) and s.track(3).mute)
	t.remove_child(panel)
	panel.free()

	var field := LineEdit.new()
	t.add_child(field)
	field.grab_focus()
	field.edit()
	check("the field is being typed in", field.is_editing())
	check("typing keeps Delete", not _keys.handle(_key(KEY_DELETE)))
	check("and Backspace", not _keys.handle(_key(KEY_BACKSPACE)))
	check("and Ctrl+Z", not _keys.handle(_key(KEY_Z, true)))
	check("and Ctrl+V", not _keys.handle(_key(KEY_V, true)))
	field.unedit()
	check("after Enter, Delete is still kept from the room", not _keys.handle(_key(KEY_DELETE)))
	check("but Ctrl+Z is the room's again", _keys.handle(_key(KEY_Z, true)))
	check("the clip is still there", s.track(3).items.size() == 1 and s.undo_depth == depth - 1)
	t.remove_child(field)
	field.free()
	_done()


func piano_passes_only_ctrl_chords() -> void:
	var s := _rig()
	_clip(3, 4.0, 2.0)
	DAW.set_track_mute(3, true)
	_point(3, 5.0)
	var piano := KeyCatcher.new()
	piano.focus_mode = Control.FOCUS_ALL
	t.add_child(piano)
	piano.grab_focus()
	check("the piano has the keyboard", t.get_viewport().gui_get_focus_owner() == piano)
	check("plain Delete stays off the song", not _keys.handle(_key(KEY_DELETE)))
	check("so does plain Backspace", not _keys.handle(_key(KEY_BACKSPACE)))
	check("the clip is there", s.track(3).items.size() == 1)
	check("Ctrl+Z passes", _keys.handle(_key(KEY_Z, true)) and not s.track(3).mute)
	check("Ctrl+X passes", _keys.handle(_key(KEY_X, true)) and s.track(3).items.is_empty())
	t.remove_child(piano)
	piano.free()
	_done()


func ctrl_v_cassette_before_clipboard() -> void:
	t._as_session(Session.Role.SOLO, 1)
	var saved_layout = Session.layout
	var studio: Studio = t._cassette_studio()
	await t.get_tree().physics_frame
	var s: MixState = DAW.state
	var mouse := studio.get_node("MouseHand") as MouseInteractor
	var keys := studio.get_node("RoomShortcuts") as RoomShortcuts
	check("the room has its keys, on the mouse's hand", keys != null and keys.hand == mouse)
	var timeline := studio.timeline
	timeline._process(0.0)
	timeline.set_view(0.0, s.bar_to_seconds(41.0))
	await t.get_tree().physics_frame
	var lanes: TimelineLanes = timeline._lanes
	var on := func(track_index: int, seconds: float) -> Vector3:
		var row := timeline._shown().find(track_index)
		return timeline.to_global(Vector3(timeline._x_for(seconds), timeline._lane_y[row], lanes.position.z))

	# Something else on the clipboard, to tell the two pastes apart.
	var first: MixState.ItemState = s.track(2).items[0]
	DAW.copy_items([[2, 0, first.start, first.length]])
	var take = t._bent_clip(6, 30.0, 8.0, 20.0)
	studio.item_host._on_clip_pulled(6, take.index, mouse)
	var cassette := mouse.carrying as CassetteItem
	check("a cassette is in the hand", cassette != null and cassette.pastes())

	var bar := s.bar_to_seconds(30.0)
	var count: int = s.track(4).items.size()
	var depth: int = maxi(s.undo_depth, 0)
	mouse.hovered = lanes
	mouse.hover_point = on.call(4, bar)
	check("Ctrl+V is heard", keys.handle(_key(KEY_V, true)))
	var landed: Array = s.track(4).items.filter(func(it): return absf(it.start - bar) < 0.01)
	check("the cassette pastes, not the clipboard", s.track(4).items.size() == count + 1 and landed.size() == 1
			and is_equal_approx(landed[0].length, take.length))
	check("as one step", s.undo_depth == depth + 1)
	check("and stays in the hand", mouse.carrying == cassette)
	mouse.hovered = null
	check("no control under it: the wrapper says no", not mouse.paste_carried())

	# Ctrl+V through the real input path leaves the venue where it is.
	var venue = studio.venue
	mouse.lose_carrying()
	mouse.hovered = null
	t.get_viewport().push_input(_key(KEY_V, true))
	await t.get_tree().process_frame
	check("Ctrl+V no longer changes the venue", studio.venue == venue)

	studio.queue_free()
	await t.get_tree().process_frame
	t._as_session(Session.Role.SOLO, 1)
	Session.layout = saved_layout


func plugin_window_blocks_edits() -> void:
	var s := _rig()
	_clip(3, 4.0, 2.0)
	_select(3, 0)
	var screen := PluginScreen.new()
	_hand.hovered = screen
	for chord: Array in [[KEY_DELETE, false], [KEY_BACKSPACE, false], [KEY_X, true], [KEY_C, true], [KEY_V, true],
			[KEY_D, true], [KEY_A, true]]:
		_said.clear()
		check("%s is held back" % OS.get_keycode_string(chord[0]), _keys.handle(_key(chord[0], chord[1])))
		check("saying keys do not reach it", _last() == RoomShortcuts.PLUGIN_WINDOW)
	check("nothing changed", s.track(3).items.size() == 1)
	DAW.set_track_mute(3, true)
	_keys.handle(_key(KEY_Z, true))
	check("undo still works over a plugin", not s.track(3).mute)
	_hand.hovered = null
	screen.free()
	_done()


func no_hand_in_xr_is_safe() -> void:
	var s := _rig()
	_clip(3, 4.0, 2.0)
	DAW.set_track_mute(3, true)
	var spare := _hand
	_keys.hand = null
	for chord: Array in [[KEY_DELETE, false], [KEY_BACKSPACE, false], [KEY_X, true], [KEY_C, true], [KEY_V, true],
			[KEY_D, true], [KEY_A, true]]:
		check("with no hand, %s is left alone" % OS.get_keycode_string(chord[0]),
				not _keys.handle(_key(chord[0], chord[1])))
	check("nothing changed", s.track(3).items.size() == 1)
	check("undo acts", _keys.handle(_key(KEY_Z, true)) and not s.track(3).mute)
	check("redo acts", _keys.handle(_key(KEY_Y, true)) and s.track(3).mute)
	_keys.hand = spare
	_done()

	var rigged := Studio.new()
	rigged.medium = Presentation.Medium.AR
	t.add_child(rigged)
	var keys := rigged.get_node_or_null("RoomShortcuts") as RoomShortcuts
	check("a headset's room has the keys", keys != null)
	check("with no hand on them", keys != null and keys.hand == null)
	rigged.queue_free()
	await t.get_tree().process_frame
