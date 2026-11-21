extends RefCounted

## The keyboard and mouse pass's tests, called from tests/run_tests.gd's `_test_keys_*`: the 2D view's edit keys reaching the DAW, and the help card listing them.

var t: Node


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


func close_to(label: String, a: float, b: float, epsilon := 0.0001) -> void:
	t.close_to(label, a, b, epsilon)


## A bare timeline, as `role` and peer `me`.
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


func _done(hear: Callable) -> void:
	if Session.notice.is_connected(hear):
		Session.notice.disconnect(hear)
	Session.keep_intents = false
	Session.kept_intents.clear()
	Session.start_solo()
	t._offline()


func flat_clipboard_reaches_the_daw() -> void:
	var said: Array = []
	var hear := func(words: String) -> void: said.append(words)
	Session.notice.connect(hear)
	var s := _fresh()
	var host := FlatHost.new()
	var a := _clip(2, 1.0, 2.0, "low")
	var b := _clip(4, 3.5, 1.0, "high")
	DAW.select_item(a[0], a[1])
	DAW.select_item(b[0], b[1], true)
	host.copy_clips()
	host.paste_clips(ProjectBridge.id_of(5), 10.0)
	check("2D copy and paste keep time and tracks (%s, %s)" % [_starts(5), _starts(7)],
			_starts(5) == [10.0] and _starts(7) == [12.5])
	DAW.paste_items(8, 20.0)
	check("what 2D copied, the room pastes (%s)" % [_starts(8)], _starts(8) == [20.0] and s.track(8).items[0].name == "low")
	DAW.copy_items([a])
	host.paste_clips(ProjectBridge.id_of(11), 30.0)
	check("what the room copied, 2D pastes (%s)" % [_starts(11)],
			_starts(11) == [30.0] and s.track(11).items[0].name == "low")
	DAW.clear_item_selection()
	DAW.select_item(b[0], b[1])
	host.cut_clips()
	check("2D cut takes the clip off the song", _starts(4).is_empty())
	host.paste_clips(ProjectBridge.id_of(12), 40.0)
	check("and it pastes back", _starts(12) == [40.0] and s.track(12).items[0].name == "high")
	var depth := s.undo_depth
	var counts: Array = s.track_indices().map(func(i): return s.track(i).items.size())
	said.clear()
	host.paste_clips("", 5.0)
	check("a paste with nowhere to go changes nothing, and says so (%s)" % [said], s.undo_depth == depth
			and s.track_indices().map(func(i): return s.track(i).items.size()) == counts
			and said.size() == 1 and said[0].contains("lane"))
	_fresh(Session.Role.HOST, 1)
	var hers := _clip(2, 0.0, 1.0, "hers")
	var mine := _clip(3, 0.0, 1.0, "mine")
	DAW.apply_intent(&"clipboard_copy", [[hers]], 5)
	DAW.select_item(mine[0], mine[1])
	host.copy_clips()
	host.paste_clips(ProjectBridge.id_of(7), 2.0)
	check("on a host, 2D pastes the host's own clipboard and not a guest's",
			DAW.state.track(7).items.size() == 1 and DAW.state.track(7).items[0].name == "mine")
	# Laid down solo: a guest's take goes to the host, and there is no host here to send it back.
	_fresh()
	var theirs := _clip(2, 0.0, 1.0)
	DAW.state.track(2).items[theirs[1]].selected = true
	t._as_session(Session.Role.GUEST, 5)
	Session.keep_intents = true
	Session.kept_intents.clear()
	host.copy_clips()
	host.paste_clips(ProjectBridge.id_of(6), 2.0)
	host.paste_clips("", 2.0)
	var verbs: Array = Session.kept_intents.map(func(i: Array) -> StringName: return i[0])
	check("a guest's 2D copy and paste go to the host, and an empty paste does not (%s)" % [verbs],
			verbs == [&"clipboard_copy", &"clipboard_paste"])
	_done(hear)


func flat_select_all_is_one_intent() -> void:
	var hear := func(_words: String) -> void: pass
	var s := _fresh()
	var host := FlatHost.new()
	_clip(2, 0.0, 1.0)
	_clip(2, 2.0, 1.0)
	_clip(5, 1.0, 1.0)
	host.select_all_clips()
	var picked := 0
	for index in s.track_indices():
		for item in s.track(index).items:
			picked += 1 if item.selected else 0
	check("select all picks every clip (%d)" % picked, picked == 3)
	Session.role = Session.Role.GUEST
	Session.local_peer_id = 5
	Session.keep_intents = true
	Session.kept_intents.clear()
	host.select_all_clips()
	check("from a guest it is one intent (%s)" % [Session.kept_intents],
			Session.kept_intents.size() == 1 and Session.kept_intents[0][0] == &"select_all_items")
	_done(hear)


func flat_gesture_is_one_undo() -> void:
	var hear := func(_words: String) -> void: pass
	var s := _fresh()
	var host := FlatHost.new()
	var clip := _clip(3, 0.0, 2.0)
	var id := ProjectBridge.id_of(3)
	var velocity := func() -> int: return int(s.item(3, clip[1]).notes[3])
	var before := maxi(s.undo_depth, 0)
	host.begin_gesture("velocity")
	check("the gesture is an open edit", DAW.backend.edit_open())
	for v in [90, 70, 40]:
		host.set_note_velocity(id, clip[1], 0, v)
	host.end_gesture()
	check("let go, the edit is closed", not DAW.backend.edit_open())
	check("a drag of three values is one step (%d to %d)" % [before, s.undo_depth], maxi(s.undo_depth, 0) == before + 1)
	check("at the last value", velocity.call() == 40)
	host.begin_gesture("velocity")
	host.set_note_velocity(id, clip[1], 0, 20)
	host.end_gesture()
	check("a second drag is a step of its own", maxi(s.undo_depth, 0) == before + 2)
	DAW.undo()
	check("one undo takes back the second drag (%d)" % velocity.call(), velocity.call() == 40)
	DAW.undo()
	check("and one more the whole first drag (%d)" % velocity.call(), velocity.call() == 100)
	Session.role = Session.Role.GUEST
	Session.local_peer_id = 5
	Session.keep_intents = true
	Session.kept_intents.clear()
	host.begin_gesture("velocity")
	host.end_gesture()
	var verbs: Array = Session.kept_intents.map(func(i: Array) -> StringName: return i[0])
	check("a guest's gesture opens and closes on the host (%s)" % [verbs], verbs == [&"open_edit", &"close_edit"])
	_done(hear)


func help_lists_the_edit_keys() -> void:
	DAW.use(OfflineBackend.new())
	var card := WelcomeCard.new()
	var said := ""
	for p: Dictionary in card.pages():
		for line: Array in p["lines"]:
			said += "%s %s\n" % [line[0], line[1]]
	for key in ["Delete", "Ctrl-X", "Ctrl-C", "Ctrl-V", "Ctrl-D", "Ctrl-A", "Ctrl-Shift-A", "Ctrl-Z", "Ctrl-Shift-Z", "Ctrl-Y"]:
		check("the card names %s" % key, said.contains(key))
	check("it says Delete acts on the clip under the pointer", said.contains("Delete acts on the clip under the pointer"))
	check("it says Shift+Space sinks", said.contains("Shift+Space sinks"))
	card.free()
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	t.add_child(studio)
	await t.get_tree().physics_frame
	card = WelcomeCard.new()
	card.seen_path = "user://test_keyboard_welcome_seen"
	card.studio = studio
	t.add_child(card)
	check("closed, the card holds nothing", not KeyChord.modal_open(t.get_tree()))
	studio._lean_key = true
	card.open()
	check("open, it is a modal screen", card.is_in_group(KeyChord.MODAL) and KeyChord.modal_open(t.get_tree()))
	check("and what the room held is let go", not studio._lean_key)
	card.close()
	check("closed again, the room has its keys", not KeyChord.modal_open(t.get_tree()))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(card.seen_path))
	card.queue_free()
	studio.queue_free()
	await t.get_tree().process_frame
