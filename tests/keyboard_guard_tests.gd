extends RefCounted

## The keyboard and mouse pass's tests, called from tests/run_tests.gd's `_test_keys_*`: Ctrl never walks, modifiers keep off the room keys, held keys let go across focus and F2.

## Every key the room answers on its own, for the checks that none of them fire under a modifier.
const ROOM_KEYS: Array[Key] = [KEY_F, KEY_E, KEY_G, KEY_V, KEY_B, KEY_Q, KEY_H, KEY_N, KEY_T, KEY_I,
	KEY_X, KEY_Y, KEY_C, KEY_P, KEY_R, KEY_K, KEY_U, KEY_L, KEY_Z, KEY_O, KEY_1, KEY_2, KEY_3, KEY_4,
	KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0, KEY_BRACKETLEFT, KEY_BRACKETRIGHT, KEY_EQUAL, KEY_MINUS,
	KEY_ESCAPE]

## A screen that says it is open, for the registries.
class Screen extends Node:
	func is_open() -> bool:
		return true


var t: Node


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


func close_to(label: String, a: float, b: float, epsilon := 0.0001) -> void:
	t.close_to(label, a, b, epsilon)


func ctrl_chords_do_not_walk() -> void:
	var walker := _walker()
	for letter: Key in [KEY_S, KEY_A, KEY_D, KEY_W]:
		_hold(KEY_CTRL, true)
		_hold(letter, true)
		var name := OS.get_keycode_string(letter)
		check("Ctrl+%s asks for no walk" % name, walker.keyboard_wish(null) == Vector3.ZERO)
		walker.velocity = Vector3.ZERO
		walker._physics_process(0.05)
		check("Ctrl+%s moves nothing across the floor" % name,
			Vector2(walker.velocity.x, walker.velocity.z).is_zero_approx())
		_hold(letter, false)
		_hold(KEY_CTRL, false)
		walker.keyboard_wish(null)
	_hold(KEY_META, true)
	_hold(KEY_S, true)
	check("Meta+S asks for no walk", walker.keyboard_wish(null) == Vector3.ZERO)
	_hold(KEY_S, false)
	_hold(KEY_META, false)
	walker.keyboard_wish(null)

	# A chord pressed while a field has the focus is still a chord once the focus has gone.
	var field := LineEdit.new()
	_hold(KEY_CTRL, true)
	_hold(KEY_S, true)
	check("under focus, nothing", walker.keyboard_wish(field) == Vector3.ZERO)
	_hold(KEY_CTRL, false)
	check("focus gone, the chord's S still does not walk", walker.keyboard_wish(null) == Vector3.ZERO)
	_hold(KEY_S, false)
	walker.keyboard_wish(null)
	field.free()

	# A plain key still walks, and the claim takes the letters and leaves the arrows.
	_hold(KEY_W, true)
	check("plain W walks", walker.keyboard_wish(null) == Vector3(0, 0, -1))
	walker.keys_claimed = func() -> bool: return true
	check("claimed pads take W", walker.keyboard_wish(null) == Vector3.ZERO)
	_hold(KEY_W, false)
	_hold(KEY_UP, true)
	check("claimed pads leave the arrows", walker.keyboard_wish(null) == Vector3(0, 0, -1))
	walker.keys_claimed = Callable()

	# Alt bends a note on the move.
	_hold(KEY_ALT, true)
	check("arrows still walk under Alt", walker.keyboard_wish(null) == Vector3(0, 0, -1))
	_hold(KEY_ALT, false)
	_hold(KEY_UP, false)
	_done(walker)


func ctrl_released_first_does_not_walk() -> void:
	var walker := _walker()
	_hold(KEY_CTRL, true)
	_hold(KEY_S, true)
	walker.keyboard_wish(null)
	_hold(KEY_CTRL, false)
	check("Ctrl up, S still down: no walk", walker.keyboard_wish(null) == Vector3.ZERO)
	walker.velocity = Vector3.ZERO
	walker._physics_process(0.05)
	check("and the body stays put", Vector2(walker.velocity.x, walker.velocity.z).is_zero_approx())
	_hold(KEY_S, false)
	walker.keyboard_wish(null)
	_hold(KEY_S, true)
	check("S pressed again walks", walker.keyboard_wish(null) == Vector3(0, 0, 1))
	_hold(KEY_S, false)
	_done(walker)

	# The god's camera reads the same keys through the ViewHost.
	DAW.use(OfflineBackend.new())
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	t.add_child(studio)
	await t.get_tree().physics_frame
	studio.set_god_mode(true)
	t.get_viewport().gui_release_focus()
	KeyChord.clear_walk_latch()
	var from: Vector3 = studio._orbit_target
	_hold(KEY_CTRL, true)
	_hold(KEY_S, true)
	studio.view_host._process(0.1)
	check("Ctrl+S does not fly the god camera", studio._orbit_target == from)
	_hold(KEY_CTRL, false)
	studio.view_host._process(0.1)
	check("nor once Ctrl is up first", studio._orbit_target == from)
	_hold(KEY_S, false)
	studio.view_host._process(0.1)
	_hold(KEY_S, true)
	studio.view_host._process(0.1)
	check("a plain S still flies it", studio._orbit_target != from)
	_hold(KEY_S, false)
	var there: Vector3 = studio._orbit_target
	studio.walker.keys_claimed = func() -> bool: return true
	_hold(KEY_W, true)
	studio.view_host._process(0.1)
	check("claimed pads hold the god camera too", studio._orbit_target == there)
	_hold(KEY_W, false)
	studio.walker.keys_claimed = Callable()
	KeyChord.clear_walk_latch()
	studio.queue_free()
	await t.get_tree().process_frame


func shift_space_sinks_on_the_move() -> void:
	var walker := _walker()
	check("no Space, no rise", Walker.rise_wanted() == 0.0)
	_hold(KEY_SPACE, true)
	check("Space rises", Walker.rise_wanted() == 1.0)
	_hold(KEY_SHIFT, true)
	check("Shift+Space sinks", Walker.rise_wanted() == -1.0)

	# Through the real tick, walking: forward and down at once.
	_hold(KEY_W, true)
	walker.global_position = Vector3(0, 1.0, 0)
	walker.velocity = Vector3.ZERO
	walker._physics_process(0.1)
	check("the body sinks", walker.velocity.y < -0.5)
	check("and keeps walking", walker.velocity.z < -0.1)
	_hold(KEY_W, false)
	_hold(KEY_SHIFT, false)
	_hold(KEY_SPACE, false)

	# Ctrl means nothing to height now.
	walker.global_position = Vector3(0, 1.0, 0)
	walker.velocity = Vector3.ZERO
	_hold(KEY_CTRL, true)
	walker._physics_process(0.3)
	check("Ctrl alone does not sink", walker.velocity.y >= -0.01)
	_hold(KEY_CTRL, false)
	_done(walker)


func ctrl_keeps_you_walking() -> void:
	var walker := _walker()
	for code: Key in [KEY_W, KEY_UP]:
		_hold(code, true)
		check("%s walks" % OS.get_keycode_string(code), walker.keyboard_wish(null) == Vector3(0, 0, -1))
		_hold(KEY_CTRL, true)
		check("and goes on under Ctrl", walker.keyboard_wish(null) == Vector3(0, 0, -1))
		_hold(KEY_CTRL, false)
		check("and after it", walker.keyboard_wish(null) == Vector3(0, 0, -1))
		_hold(code, false)
		walker.keyboard_wish(null)
	_hold(KEY_CTRL, true)
	_hold(KEY_UP, true)
	check("an arrow pressed under Ctrl is no step", walker.keyboard_wish(null) == Vector3.ZERO)
	_hold(KEY_CTRL, false)
	check("nor once Ctrl is up", walker.keyboard_wish(null) == Vector3.ZERO)
	_hold(KEY_UP, false)
	_done(walker)


func every_modal_registers() -> void:
	# The pickers add themselves to the root, which is busy until the runner's first frame is over.
	await t.get_tree().process_frame
	DAW.use(OfflineBackend.new())
	var kept := _clear_registry()
	var tree := t.get_tree()
	check("nothing registered, nothing open", not KeyChord.modal_open(tree) and not KeyChord.panel_open(tree))

	# The ones that exist only while they ask: open by being there, closed by going.
	var asking := {
		"input picker": InputPicker.ask(t, 0),
		"name prompt": NamePrompt.ask(t, "Name", "x"),
		"plugin picker": PluginPicker.ask(t, "Add", [["a", "Alpha"]]),
		"Workshop context": WorkshopPanel.ContextOverlay.open(t, "context"),
	}
	for label: String in asking:
		var node: Node = asking[label]
		check("the %s is a modal" % label, node.is_in_group(KeyChord.MODAL))
		check("the %s is open while it asks" % label, node.is_open() and KeyChord.modal_open(tree))
	var last: Array = asking.values()
	for i in last.size():
		last[i].queue_free()
		check("queued to go, %s no longer counts" % asking.keys()[i],
			not last[i].is_open() and KeyChord.modal_open(tree) == (i < last.size() - 1))
	await tree.process_frame
	check("all gone, no modal open", not KeyChord.modal_open(tree))

	# The ones that stay up all their lives, with a panel that comes and goes.
	for screen: Node in [RealmLeavePrompt.new(), RackFinderScreen.new(), RackHelpScreen.new(),
			RackPresetScreen.new(), MilkFinderScreen.new(), AssistantScreen.new()]:
		_registered(screen, KeyChord.MODAL)
	for screen: Node in [SessionPanel.new(), StageManager.new(), LayoutEditor.new(), RoomMaker.new(),
			ModsScreen.new()]:
		_registered(screen, KeyChord.PANEL)

	# The 2D view: it holds the keyboard on the desktop, and not as a headset's panel.
	var flat := FlatView.new()
	t.add_child(flat)
	check("the 2D view is a modal", flat.is_in_group(KeyChord.MODAL))
	check("closed, it holds nothing", not flat.holds_keyboard() and not KeyChord.modal_open(tree))
	flat.visible = true
	check("up on the desktop, it holds the keyboard", flat.holds_keyboard() and KeyChord.modal_open(tree))
	flat.panel = FlatPanel.new(flat.host)
	check("up in a headset, the room keeps it", not flat.holds_keyboard() and not KeyChord.modal_open(tree))
	flat.panel.free()
	flat.panel = null
	flat.visible = false
	t.remove_child(flat)
	flat.free()
	_restore_registry(kept)


func a_closed_stage_manager_is_not_open() -> void:
	var kept := _clear_registry()
	var tree := t.get_tree()
	var manager := StageManager.new()
	t.add_child(manager)
	check("a CanvasLayer stays visible when closed", manager.visible)
	check("closed, it says so", not manager.is_open())
	check("and blocks nothing", not KeyChord.panel_open(tree) and not KeyChord.modal_open(tree))
	manager.open()
	check("opened, it says so", manager.is_open() and KeyChord.panel_open(tree))
	manager._unhandled_input(_press(KEY_TAB))
	check("Tab closes it", not manager.is_open() and not KeyChord.panel_open(tree))
	t.remove_child(manager)
	manager.free()
	_restore_registry(kept)


func panel_toggles_ignore_modifiers() -> void:
	DAW.use(OfflineBackend.new())
	var session := SessionPanel.new()
	var manager := StageManager.new()
	var maker := RoomMaker.new()
	for node: Node in [session, manager, maker]:
		t.add_child(node)
	for toggle: Array in [[session, KEY_M, "M"], [manager, KEY_TAB, "Tab"], [maker, KEY_F4, "F4"]]:
		var node: Node = toggle[0]
		var code: Key = toggle[1]
		var name: String = toggle[2]
		for mods: Array in [[true, false, false], [false, true, false], [false, false, true]]:
			node._unhandled_input(_press(code, mods[0], mods[1], mods[2]))
			check("%s with %s does not open it" % [name, mods], not node.is_open())
		node._unhandled_input(_press(code))
		check("plain %s opens it" % name, node.is_open())
		for mods: Array in [[true, false, false], [false, true, false], [false, false, true]]:
			node._unhandled_input(_press(code, mods[0], mods[1], mods[2]))
			check("%s with %s does not close it" % [name, mods], node.is_open())
		node._unhandled_input(_press(code))
		check("plain %s closes it" % name, not node.is_open())

	# Shift is the run key, not a command.
	session._unhandled_input(_press(KEY_M, false, false, false, true))
	check("Shift+M still opens the session panel", session.is_open())
	session.close()

	# A clicked button lets go of the keyboard.
	var button := session._button("x", false)
	check("a session panel button never takes focus", button.focus_mode == Control.FOCUS_NONE)
	button.free()
	for node: Node in [session, manager, maker]:
		t.remove_child(node)
		node.free()

	# Alt-drag in 2D is 2D's: the room's hand stops hearing it, and hears it again after.
	var flat := FlatView.new()
	var room := Studio.new()
	room.medium = Presentation.Medium.SCREEN
	t.add_child(room)
	await t.get_tree().physics_frame
	var hand := room.get_node_or_null("MouseHand")
	check("the room has a mouse hand", hand != null)
	flat.studio = room
	t.add_child(flat)
	if hand != null:
		check("the hand hears input in the room", hand.is_processing_input())
		flat.set_open(true)
		check("in 2D it does not", not hand.is_processing_input())
		flat.set_open(false)
		check("back in the room it does", hand.is_processing_input())
	t.remove_child(flat)
	flat.free()
	room.queue_free()
	await t.get_tree().process_frame


func modifiers_do_not_fire_room_keys() -> void:
	var room: Studio = await _room()
	var hand := room.get_node("MouseHand") as MouseInteractor
	_clip(1, 1.0, 2.0)
	DAW.select_item(1, 0, true)
	DAW.seek(2.0)
	var fired := [0]
	var count := func(_a: Variant = null) -> void: fired[0] += 1
	room.computer_keys_toggled.connect(count)
	hand.bare_jack.connect(count)
	Session.notice.connect(count)
	var before := _state(room)
	for code: Key in ROOM_KEYS:
		for mods: Array in [[true, false, false], [false, true, false], [false, false, true]]:
			var e := _press(code, mods[0], mods[1], mods[2])
			hand._unhandled_input(e)
			room.point_and_mark._unhandled_input(e)
			room._unhandled_input(e)
	check("no room key fires under Ctrl, Alt or Meta (%s)" % [_state(room)], _state(room) == before)
	check("and none so much as speaks (%d)" % fired[0], fired[0] == 0)
	room.computer_keys_toggled.disconnect(count)
	hand.bare_jack.disconnect(count)
	Session.notice.disconnect(count)

	# The same keys bare still work, so the checks above are not passing on a dead handler.
	room._unhandled_input(_press(KEY_B))
	check("a plain B still splits", DAW.state.track(1).items.size() == 2)
	room._unhandled_input(_press(KEY_X))
	check("a plain X still shows the signal", room.signal_key_on)
	room._unhandled_input(_press(KEY_X))
	var scale := room.ergonomics.text_scale
	room._unhandled_input(_press(KEY_EQUAL))
	check("a plain = still scales the text", room.ergonomics.text_scale > scale)
	room._unhandled_input(_press(KEY_0))
	room._unhandled_input(_press(KEY_C, false, false, false, true))
	check("Shift is not a command: Shift+C is the chord layer", room.chord_hand.layer)
	room._unhandled_input(_press(KEY_C))
	check("and C ends it", not room.chord_hand.layer)

	# Through the real viewport, with a screen up: Ctrl+V never changes the venue, and Ctrl+Z is
	# undo under a panel and nothing under a modal.
	var kept := _clear_registry()
	t.get_viewport().gui_release_focus()
	var venue: Variant = room.venue
	var panel := StageManager.new()
	t.add_child(panel)
	panel.open()
	var depth := maxi(DAW.state.undo_depth, 0)
	_push(_press(KEY_V, true))
	check("Ctrl+V under a panel leaves the venue", room.venue == venue)
	_push(_press(KEY_Z, true))
	check("Ctrl+Z under a panel still undoes", maxi(DAW.state.undo_depth, 0) < depth)
	t.remove_child(panel)
	panel.free()
	var modal := RackHelpScreen.new()
	t.add_child(modal)
	modal._panel.visible = true
	depth = maxi(DAW.state.undo_depth, 0)
	_push(_press(KEY_V, true))
	check("Ctrl+V under a modal leaves the venue", room.venue == venue)
	_push(_press(KEY_Z, true))
	check("Ctrl+Z under a modal undoes nothing", maxi(DAW.state.undo_depth, 0) == depth)
	t.remove_child(modal)
	modal.free()
	_restore_registry(kept)
	await _leave(room)


func a_release_survives_a_modifier() -> void:
	var room: Studio = await _room()
	var hand := room.get_node("MouseHand") as MouseInteractor

	room.signal_key_on = true
	room._unhandled_input(_press(KEY_U))
	check("U held solos", room._look_by == &"key")
	room._unhandled_input(_up(KEY_U, true))
	check("U let go under Ctrl: the solo ends", room._look_by == &"")
	room.signal_key_on = false

	room.key_clap.press(1, true)
	check("K held mutes", DAW.state.track(1).mute)
	room.key_clap._for = 1.0
	room._unhandled_input(_up(KEY_K, false, true))
	check("K let go under Alt: the mute comes off", not room.key_clap.pressed and not DAW.state.track(1).mute)

	room._unhandled_input(_press(KEY_L))
	check("L held leans", room._lean_key)
	room._unhandled_input(_up(KEY_L, false, false, true))
	check("L let go under Meta: the lean ends", not room._lean_key)

	hand.ear_held = true
	hand._unhandled_input(_up(KEY_L, true))
	check("L let go under Ctrl: off the ear", not hand.ear_held)

	var ball: Item = room.items.items[&"ball"]
	hand.pick_up(ball)
	room._unhandled_input(_press(KEY_R))
	check("R held winds up", hand._charge_from >= 0)
	room._unhandled_input(_up(KEY_R, true))
	check("R let go under Ctrl: thrown, as any R let go is", hand.carrying == null and hand._charge_from < 0)

	room.point_and_mark._unhandled_input(_press(KEY_Z))
	check("Z held points", hand.pointing)
	room.point_and_mark._unhandled_input(_up(KEY_Z, true))
	check("Z let go under Ctrl: pointing ends", not hand.pointing)
	await _leave(room)


func focus_out_clears_held_keys() -> void:
	for what: int in [Node.NOTIFICATION_APPLICATION_FOCUS_OUT, Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		var room: Studio = await _room()
		var ball := _hold_everything(room)
		room._notification(what)
		_check_all_let_go(room, ball, "focus out %d" % what)
		await _leave(room)


func f2_clears_held_keys() -> void:
	var room: Studio = await _room()
	var ball := _hold_everything(room)
	var flat := FlatView.new()
	flat.studio = room
	t.add_child(flat)
	flat.set_open(true)
	_check_all_let_go(room, ball, "F2")
	flat.set_open(false)
	t.remove_child(flat)
	flat.free()
	await _leave(room)


func a_pad_held_through_f2_ends() -> void:
	var room: Studio = await _room()
	var deck: PadDeck = room.tv.deck
	deck.engaged = true
	deck.focused = true
	deck.keys_on = true
	var pad := PadDeck.PAD_KEYS.find(KEY_W)
	var flat := FlatView.new()
	flat.studio = room
	t.add_child(flat)
	deck._input(_press(KEY_W))
	check("W holds its pad", deck._held.has(pad))
	flat.set_open(true)
	check("F2 does not end it by itself", deck._held.has(pad))
	deck._input(_up(KEY_W, true))
	check("W let go in 2D under Ctrl: the pad ends", not deck._held.has(pad))
	deck._input(_press(KEY_S))
	check("in 2D a press strikes no pad", deck._held.is_empty())
	flat.set_open(false)
	deck._input(_press(KEY_S))
	check("back in the room it does", deck._held.has(PadDeck.PAD_KEYS.find(KEY_S)))
	deck._input(_up(KEY_S))
	deck._input(_press(KEY_D))
	deck.engaged = false
	deck._input(_up(KEY_D))
	check("a pad held while walking off ends too", deck._held.is_empty())
	t.remove_child(flat)
	flat.free()
	await _leave(room)


func enter_then_plain_keys_stay_off() -> void:
	var room: Studio = await _room()
	var hand := room.get_node("MouseHand") as MouseInteractor
	_clip(1, 1.0, 2.0)
	DAW.select_item(1, 0, true)
	DAW.seek(2.0)
	var track: int = room.stage.voices.keys()[0]
	var voice := _stage_control(room.stage.voices[track])
	check("the voice has a control to point at", voice != null)
	DAW.set_track_pan(track, 0.8)
	var field := LineEdit.new()
	t.add_child(field)
	field.grab_focus()
	field.edit()
	field.unedit()
	check("after Enter the field keeps focus, done editing", field.has_focus() and not field.is_editing())
	hand.hovered = voice
	var shortcuts := room.get_node("RoomShortcuts") as RoomShortcuts
	room._unhandled_input(_press(KEY_B))
	check("B changes nothing", DAW.state.track(1).items.size() == 1)
	var backspace := _press(KEY_BACKSPACE)
	check("Backspace is not the shortcuts'", not shortcuts.handle(backspace))
	room._unhandled_input(backspace)
	close_to("Backspace changes nothing", DAW.state.track(track).pan, 0.8)
	# Clicked away, the same two keys are the room's, so the two above did not pass on a dead key.
	field.release_focus()
	room._unhandled_input(_press(KEY_BACKSPACE))
	close_to("focus gone, Backspace resets the voice to centre", DAW.state.track(track).pan, 0.5)
	room._unhandled_input(_press(KEY_B))
	check("and B splits", DAW.state.track(1).items.size() == 2)
	hand.hovered = null
	t.remove_child(field)
	field.free()
	await _leave(room)


func fingertips_hold_back_r() -> void:
	var room: Studio = await _room()
	var hand := room.get_node("MouseHand") as MouseInteractor
	var ball: Item = room.items.items[&"ball"]
	hand.pick_up(ball)
	_clip(1, 1.0, 2.0)
	DAW.select_item(1, 0, true)
	DAW.seek(2.0)
	room.fingertip_keys.set_active(true)
	room._unhandled_input(_press(KEY_R))
	check("R winds up nothing with the fingertips on", hand._charge_from < 0)
	room._unhandled_input(_up(KEY_R))
	check("and letting it go throws nothing", hand.carrying == ball)
	room._unhandled_input(_press(KEY_Q))
	check("Q leaves the ball in the hand", hand.carrying == ball)
	room._unhandled_input(_press(KEY_B))
	check("B splits nothing", DAW.state.track(1).items.size() == 1)
	var size := room.ergonomics.text_scale
	room._unhandled_input(_press(KEY_0))
	check("0 leaves the text", room.ergonomics.text_scale == size)
	room._unhandled_input(_press(KEY_C))
	check("C still turns the chord layer on", room.chord_hand.layer)
	room._unhandled_input(_press(KEY_C))
	check("and off, as its own card says", not room.chord_hand.layer)
	room.fingertip_keys.set_active(false)
	room._unhandled_input(_press(KEY_R))
	check("keys given back, R winds up", hand._charge_from >= 0)
	hand.cancel_throw()
	check("a dropped wind-up throws nothing", hand.carrying == ball and hand.charge() == 0.0)
	await _leave(room)


func pads_hold_the_player_still() -> void:
	var room: Studio = await _room()
	var deck: PadDeck = room.tv.deck
	deck.engaged = true
	deck.focused = true
	deck.keys_on = true
	var walker := room.walker
	check("pads come to on purpose claim the letters", walker.letters_claimed())
	for letter: Key in [KEY_W, KEY_A, KEY_S, KEY_D]:
		_hold(letter, true)
		check("%s on the pads asks for no walk" % OS.get_keycode_string(letter),
				walker.keyboard_wish(null) == Vector3.ZERO)
		walker.velocity = Vector3.ZERO
		walker._physics_process(0.05)
		check("and the body stays put", Vector2(walker.velocity.x, walker.velocity.z).is_zero_approx())
		_hold(letter, false)
		walker.keyboard_wish(null)
	deck.keys_on = false
	check("pads with their keys off claim nothing", not walker.letters_claimed())
	_hold(KEY_W, true)
	check("and W walks", walker.keyboard_wish(null) == Vector3(0, 0, -1))
	_hold(KEY_W, false)
	walker.keyboard_wish(null)
	deck.keys_on = true
	deck.engaged = false
	check("off the station they claim nothing", not walker.letters_claimed())
	await _leave(room)


func standing_near_the_pads_keeps_walking() -> void:
	var room: Studio = await _room()
	var deck: PadDeck = room.tv.deck
	var walker := room.walker
	deck.engaged = true
	deck.focused = false
	deck.keys_on = true
	check("near the deck, the letters are still feet", not walker.letters_claimed())
	_hold(KEY_W, true)
	check("and W walks", walker.keyboard_wish(null) == Vector3(0, 0, -1))
	_hold(KEY_W, false)
	walker.keyboard_wish(null)
	for letter: Key in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_F]:
		deck._input(_press(letter))
		check("%s holds no pad from just standing there" % OS.get_keycode_string(letter), deck._held.is_empty())
		deck._input(_up(letter))
	deck._input(_press(KEY_Z))
	check("a pad key that is not for walking still plays", deck._held.has(PadDeck.PAD_KEYS.find(KEY_Z)))
	deck._input(_up(KEY_Z))
	deck.toggle_keys()
	deck.toggle_keys()
	check("KEYS turned on here is asking for them", walker.letters_claimed())
	deck._input(_press(KEY_W))
	check("and then W is a pad", deck._held.has(PadDeck.PAD_KEYS.find(KEY_W)))
	deck._input(_up(KEY_W))
	deck.keys_asked = false
	deck.focused = true
	check("so is focusing the deck", walker.letters_claimed())
	deck.focused = false
	deck.engaged = false
	await _leave(room)


func plain_keys_wait_for_a_modal_or_a_field() -> void:
	var room: Studio = await _room()
	var hand := room.get_node("MouseHand") as MouseInteractor
	var marks := room.point_and_mark
	var session := SessionPanel.new()
	var manager := StageManager.new()
	t.add_child(session)
	t.add_child(manager)
	var jacks := [0]
	hand.bare_jack.connect(func(_u: bool): jacks[0] += 1)
	var ball: Item = room.items.items[&"ball"]
	var blocked := func(why: String) -> void:
		var notes := marks.asking
		hand._unhandled_input(_press(KEY_P))
		check("%s: P steps no jack" % why, jacks[0] == 0)
		marks._unhandled_input(_press(KEY_Z))
		check("%s: Z does not point" % why, not hand.pointing)
		marks._unhandled_input(_press(KEY_O))
		check("%s: O opens no note" % why, marks.asking == notes)
		session._unhandled_input(_press(KEY_M))
		check("%s: M leaves the panel" % why, not session.is_open())
		manager._unhandled_input(_press(KEY_TAB))
		check("%s: Tab leaves the stage manager" % why, not manager.is_open())
		hand.pick_up(ball)
		hand._unhandled_input(_press(KEY_L))
		check("%s: L holds nothing to the ear" % why, not hand.ear_held)
		hand.put_down() if hand.has_method(&"put_down") else hand.drop()

	var screen := Screen.new()
	screen.add_to_group(KeyChord.MODAL)
	t.add_child(screen)
	blocked.call("a modal with no focus")
	# Let go with the screen up, as a key held from before it opened is.
	hand.pointing = true
	marks._unhandled_input(_up(KEY_Z))
	check("a release still gets through a modal", not hand.pointing)
	t.remove_child(screen)
	screen.free()

	var field := LineEdit.new()
	t.add_child(field)
	field.grab_focus()
	field.edit()
	field.unedit()
	check("after Enter the field keeps focus, done editing", field.has_focus() and not field.is_editing())
	blocked.call("a field after Enter")
	field.release_focus()
	t.remove_child(field)
	field.free()

	marks._unhandled_input(_press(KEY_Z))
	check("with neither, Z points", hand.pointing)
	marks._unhandled_input(_up(KEY_Z))
	hand._unhandled_input(_press(KEY_P))
	check("and P steps the jack", jacks[0] == 1)
	t.remove_child(session)
	session.free()
	t.remove_child(manager)
	manager.free()
	await _leave(room)


func a_modal_stops_the_feet() -> void:
	var walker := _walker()
	var screen := Screen.new()
	screen.add_to_group(KeyChord.MODAL)
	t.add_child(screen)
	_hold(KEY_W, true)
	check("behind an open screen W asks for no walk", walker.keyboard_wish(null) == Vector3.ZERO)
	_hold(KEY_W, false)
	walker.keyboard_wish(null)
	check("and the latch heard it come up", not KeyChord._walk_down.has(KEY_W))
	_hold(KEY_SPACE, true)
	var y := walker.velocity.y
	walker._physics_process(0.05)
	check("Space lifts nothing behind it", walker.velocity.y <= maxf(y, 0.0))
	_hold(KEY_SPACE, false)
	t.remove_child(screen)
	screen.free()
	_hold(KEY_W, true)
	check("closed, W walks", walker.keyboard_wish(null) == Vector3(0, 0, -1))
	_hold(KEY_W, false)
	walker.keyboard_wish(null)
	walker.queue_free()


func a_chord_latches_from_its_event() -> void:
	KeyChord.clear_walk_latch()
	var keys := RoomShortcuts.new()
	t.add_child(keys)
	keys._input(_press(KEY_S, true))
	check("Ctrl gone by the first poll: S still does not walk", not KeyChord.walk_key(KEY_S, true, false))
	check("until it comes up", not KeyChord.walk_key(KEY_S, false, false))
	check("and then it walks", KeyChord.walk_key(KEY_S, true, false))
	KeyChord.walk_key(KEY_S, false, false)
	t.remove_child(keys)
	keys.free()


func focus_loss_ends_held_notes_and_pads() -> void:
	var room: Studio = await _room()
	var catcher := KeyCatcher.new()
	t.add_child(catcher)
	catcher.grab_focus()
	var offs := [0]
	catcher.note_off.connect(func(_p: int): offs[0] += 1)
	catcher.handle(KEY_A, true)
	var deck: PadDeck = room.tv.deck
	deck.engaged = true
	deck.focused = true
	deck.keys_on = true
	deck._input(_press(KEY_Z))
	check("a note and a pad are held", catcher._down.size() == 1 and deck._held.size() == 1)
	room._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	room._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	check("the window let go: the note ended", offs[0] == 1 and catcher._down.is_empty())
	check("the piano keeps the keyboard", catcher.has_focus())
	check("and the pad ended", deck._held.is_empty())
	deck.engaged = false
	deck.focused = false
	catcher.release_focus()
	t.remove_child(catcher)
	catcher.free()
	await _leave(room)


func a_panel_button_saves_the_field_first() -> void:
	DAW.use(OfflineBackend.new())
	var session := SessionPanel.new()
	t.add_child(session)
	var field := LineEdit.new()
	session.add_child(field)
	var order: Array = []
	field.focus_exited.connect(func(): order.append("saved"))
	var button := session._button("x", false)
	session.add_child(button)
	button.pressed.connect(func(): order.append("pressed"))
	field.grab_focus()
	field.edit()
	button.button_down.emit()
	button.pressed.emit()
	check("the field is saved before the button acts (%s)" % [order], order == ["saved", "pressed"])
	check("and has let go of the keys", not field.has_focus())
	t.remove_child(session)
	session.free()


## A body in the tree, on a floor, with the keys up and nothing holding focus.
func _walker() -> Walker:
	KeyChord.clear_walk_latch()
	t.get_viewport().gui_release_focus()
	var walker := Walker.new()
	walker.floor_plan = FloorPlan.new()
	walker.walkable.append(Rect2(-4, -4, 8, 8))
	t.add_child(walker)
	return walker


## A screen with a panel of its own: closed, then open through the registry, then closed.
func _registered(screen: CanvasLayer, group: StringName) -> void:
	var tree := t.get_tree()
	var label: String = screen.get_script().get_global_name()
	t.add_child(screen)
	var open := func() -> bool:
		return KeyChord.modal_open(tree) if group == KeyChord.MODAL else KeyChord.panel_open(tree)
	check("%s is registered" % label, screen.is_in_group(group))
	check("%s closed reads closed" % label, not open.call())
	var part: Control = screen._root if screen is SessionPanel else screen._panel
	part.visible = true
	check("%s open reads open" % label, open.call())
	part.visible = false
	check("%s closed again reads closed" % label, not open.call())
	t.remove_child(screen)
	screen.free()


## Takes every registered screen out of both groups, so a check sees only what it built.
func _clear_registry() -> Array:
	var kept := []
	for group: StringName in [KeyChord.MODAL, KeyChord.PANEL]:
		for node in t.get_tree().get_nodes_in_group(group):
			kept.append([node, group])
			node.remove_from_group(group)
	return kept


func _restore_registry(kept: Array) -> void:
	for entry: Array in kept:
		if is_instance_valid(entry[0]):
			entry[0].add_to_group(entry[1])


func _press(code: Key, ctrl := false, alt := false, meta := false, shift := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	e.ctrl_pressed = ctrl
	e.alt_pressed = alt
	e.meta_pressed = meta
	e.shift_pressed = shift
	return e


func _up(code: Key, ctrl := false, alt := false, meta := false) -> InputEventKey:
	var e := _press(code, ctrl, alt, meta)
	e.pressed = false
	return e


func _push(e: InputEventKey) -> void:
	t.get_viewport().push_input(e)
	var off: InputEventKey = e.duplicate()
	off.pressed = false
	t.get_viewport().push_input(off)


## A desktop room on a stopped offline song, nothing focused and nothing latched.
func _room() -> Studio:
	await t.get_tree().process_frame
	t._offline()
	t._as_session(Session.Role.SOLO, 1)
	for index in DAW.state.track_indices():
		DAW.state.track(index).items.clear()
	DAW.transport_stop()
	var room := Studio.new()
	room.medium = Presentation.Medium.SCREEN
	t.add_child(room)
	await t.get_tree().physics_frame
	t.get_viewport().gui_release_focus()
	KeyChord.clear_walk_latch()
	return room


func _leave(room: Studio) -> void:
	KeyChord.clear_walk_latch()
	t.get_viewport().gui_release_focus()
	room.queue_free()
	await t.get_tree().process_frame


func _clip(track: int, start: float, length: float) -> void:
	DAW.insert_midi_take(track, start, start + length, [[start, start + length * 0.5, 60, 100, 0]], "clip")


## The first control under `node` that says which stage track it is.
func _stage_control(node: Node) -> ControlAffordance:
	if node is ControlAffordance and node.has_meta(&"stage_track"):
		return node
	for child in node.get_children():
		var found := _stage_control(child)
		if found != null:
			return found
	return null


## What a stray room key could have changed.
func _state(room: Studio) -> Array:
	var hand := room.get_node("MouseHand") as MouseInteractor
	return [room.station, room.venue, room.god_mode, room.ergonomics.text_scale, room.chord_hand.layer,
		room.fingertip_keys.is_active(), room.signal_key_on, room._lean_key, room.key_clap.pressed,
		room._look_by, hand.ear_held, hand._charge_from, hand.pointing, hand.carrying,
		DAW.state.track(1).items.size(), room.walker.global_position, DAW.state.undo_depth]


## K, U, L, R and Z all down, with the ball wound up in the hand. Returns the ball.
func _hold_everything(room: Studio) -> Item:
	var hand := room.get_node("MouseHand") as MouseInteractor
	var ball: Item = room.items.items[&"ball"]
	hand.pick_up(ball)
	room.signal_key_on = true
	room.key_clap.press(1, true)
	room._unhandled_input(_press(KEY_U))
	room._unhandled_input(_press(KEY_L))
	room._unhandled_input(_press(KEY_R))
	room.point_and_mark._unhandled_input(_press(KEY_Z))
	hand.ear_held = true
	check("all held: mute, solo, lean, wind-up, pointing", DAW.state.track(1).mute and room._look_by == &"key"
			and room._lean_key and hand._charge_from >= 0 and hand.pointing)
	KeyChord.walk_key(KEY_S, true, true)
	return ball


func _check_all_let_go(room: Studio, ball: Item, when: String) -> void:
	var hand := room.get_node("MouseHand") as MouseInteractor
	check("%s: K is up and the mute is back, not latched" % when,
			not room.key_clap.pressed and not DAW.state.track(1).mute)
	check("%s: the solo ended" % when, room._look_by == &"")
	check("%s: the lean and the ear ended" % when, not room._lean_key and not hand.ear_held)
	check("%s: the wind-up is dropped with no throw" % when,
			hand._charge_from < 0 and hand.carrying == ball and not ball.is_flying())
	check("%s: pointing ended" % when, not hand.pointing)
	check("%s: the walk latch is clear" % when, KeyChord.walk_key(KEY_S, true, false))
	KeyChord.clear_walk_latch()


func _done(walker: Walker) -> void:
	KeyChord.clear_walk_latch()
	t.remove_child(walker)
	walker.free()


func _hold(keycode: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.physical_keycode = keycode
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()
