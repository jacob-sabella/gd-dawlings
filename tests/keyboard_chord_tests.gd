extends RefCounted

## The keyboard and mouse pass's tests, called from tests/run_tests.gd's `_test_keys_*`: what counts as a chord, a text field holding the keys, the open-screen registry, the walk latch.

var t: Node


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


func close_to(label: String, a: float, b: float, epsilon := 0.0001) -> void:
	t.close_to(label, a, b, epsilon)


func chords_are_exact() -> void:
	var plain := _key(KEY_S)
	check("a plain key is no command", not KeyChord.commanded(plain) and not KeyChord.ctrl(plain))
	var run := _key(KEY_S, true)
	check("Shift is no command", not KeyChord.commanded(run) and not KeyChord.ctrl(run))
	var save := _key(KEY_S, false, true)
	check("Ctrl is a command and a Ctrl chord", KeyChord.commanded(save) and KeyChord.ctrl(save))
	var redo := _key(KEY_Z, true, true)
	check("Ctrl+Shift is still a Ctrl chord", KeyChord.commanded(redo) and KeyChord.ctrl(redo))
	var alt := _key(KEY_S, false, false, true)
	check("Alt is a command, not a Ctrl chord", KeyChord.commanded(alt) and not KeyChord.ctrl(alt))
	var meta := _key(KEY_S, false, false, false, true)
	check("Meta is a command, not a Ctrl chord", KeyChord.commanded(meta) and not KeyChord.ctrl(meta))
	var alt_gr := _key(KEY_S, false, true, true)
	check("Ctrl+Alt is a command, not a Ctrl chord", KeyChord.commanded(alt_gr) and not KeyChord.ctrl(alt_gr))
	var midi := InputEventMIDI.new()
	check("an event without modifiers is no command", not KeyChord.commanded(midi) and not KeyChord.ctrl(midi))

	check("nothing held to start with", not KeyChord.command_held() and not KeyChord.arrow_commanded())
	_hold(KEY_ALT, true)
	check("Alt held is a command", KeyChord.command_held())
	check("Alt held is no command for an arrow", not KeyChord.arrow_commanded())
	_hold(KEY_ALT, false)
	_hold(KEY_CTRL, true)
	check("Ctrl held is a command, for an arrow too", KeyChord.command_held() and KeyChord.arrow_commanded())
	_hold(KEY_CTRL, false)
	_hold(KEY_META, true)
	check("Meta held is a command, for an arrow too", KeyChord.command_held() and KeyChord.arrow_commanded())
	_hold(KEY_META, false)
	check("nothing held afterwards", not KeyChord.command_held() and not KeyChord.arrow_commanded())


func text_focus_follows_editing() -> void:
	var viewport := t.get_viewport()
	var before := viewport.gui_get_focus_owner()
	var line := LineEdit.new()
	t.add_child(line)
	line.grab_focus()
	line.edit()
	check("an editing LineEdit is held", TextFocus.held(viewport))
	check("an editing LineEdit owns Ctrl chords", TextFocus.owns_keys(viewport))
	var enter := _key(KEY_ENTER)
	viewport.push_input(enter)
	check("Enter ends the edit and keeps focus", line.has_focus() and not line.is_editing())
	check("a LineEdit after Enter is still held for plain keys", TextFocus.held(viewport))
	check("a LineEdit after Enter no longer owns Ctrl chords", not TextFocus.owns_keys(viewport))
	line.edit()
	line.editable = false
	check("a read-only LineEdit is not held", not TextFocus.held(viewport))
	check("a read-only LineEdit does not own Ctrl chords", not TextFocus.owns_keys(viewport))
	line.free()

	var text := TextEdit.new()
	t.add_child(text)
	text.grab_focus()
	check("an editable TextEdit is held", TextFocus.held(viewport))
	check("an editable TextEdit owns Ctrl chords", TextFocus.owns_keys(viewport))
	text.editable = false
	check("a read-only TextEdit is not held", not TextFocus.held(viewport))
	check("a read-only TextEdit owns Ctrl chords", TextFocus.owns_keys(viewport))
	text.free()

	var button := Button.new()
	t.add_child(button)
	button.grab_focus()
	check("a focused button is not held", not TextFocus.held(viewport))
	check("a focused button does not own Ctrl chords", not TextFocus.owns_keys(viewport))
	button.free()
	check("no viewport owns nothing", not TextFocus.owns_keys(null))
	if before != null and is_instance_valid(before):
		before.grab_focus()


func modal_registry_reads_open_state() -> void:
	var tree := t.get_tree()
	# Anything the suite left registered is set aside, so these checks read only their own screens.
	var aside := {}
	for group: StringName in [KeyChord.MODAL, KeyChord.PANEL]:
		aside[group] = tree.get_nodes_in_group(group)
		for node: Node in aside[group]:
			node.remove_from_group(group)

	check("no screens, no modal", not KeyChord.modal_open(tree))
	check("no screens, no panel", not KeyChord.panel_open(tree))

	var bare := CanvasLayer.new()
	bare.add_to_group(KeyChord.MODAL)
	bare.add_to_group(KeyChord.PANEL)
	t.add_child(bare)
	check("a visible CanvasLayer with no open state is no modal", bare.visible and not KeyChord.modal_open(tree))
	check("a visible CanvasLayer with no open state is no panel", not KeyChord.panel_open(tree))
	bare.free()

	var screen := Screen.new()
	screen.add_to_group(KeyChord.MODAL)
	t.add_child(screen)
	check("a closed screen is not open", not KeyChord.modal_open(tree))
	screen.open = true
	check("is_open answers", KeyChord.modal_open(tree))
	check("a modal is not a panel", not KeyChord.panel_open(tree))
	screen.queue_free()
	check("a modal queued for deletion does not count", not KeyChord.modal_open(tree))
	await tree.process_frame

	var holder := Holder.new()
	holder.add_to_group(KeyChord.PANEL)
	t.add_child(holder)
	check("holds_keyboard is asked before is_open", not KeyChord.panel_open(tree))
	holder.holding = true
	check("holds_keyboard answers", KeyChord.panel_open(tree))
	check("a panel is not a modal", not KeyChord.modal_open(tree))
	holder.free()

	check("no tree, nothing open", not KeyChord.modal_open(null) and not KeyChord.panel_open(null))
	for group: StringName in aside:
		for node: Node in aside[group]:
			if is_instance_valid(node):
				node.add_to_group(group)


func walk_latch_holds_until_release() -> void:
	KeyChord.clear_walk_latch()
	check("a plain press walks", KeyChord.walk_key(KEY_W, true, false))
	check("asking again still walks", KeyChord.walk_key(KEY_W, true, false))
	check("a release stops", not KeyChord.walk_key(KEY_W, false, false))

	# Ctrl down, S down, Ctrl up, S still down.
	check("S under Ctrl does not walk", not KeyChord.walk_key(KEY_S, true, true))
	check("asking again under Ctrl does not walk", not KeyChord.walk_key(KEY_S, true, true))
	check("Ctrl up, S still down, does not walk", not KeyChord.walk_key(KEY_S, true, false))
	check("and it stays that way", not KeyChord.walk_key(KEY_S, true, false))
	check("S released", not KeyChord.walk_key(KEY_S, false, false))
	check("S pressed again walks", KeyChord.walk_key(KEY_S, true, false))
	KeyChord.walk_key(KEY_S, false, false)

	# The latch is per key.
	KeyChord.walk_key(KEY_S, true, true)
	check("another key still walks past a latched one", KeyChord.walk_key(KEY_D, true, false))
	check("the latched one does not", not KeyChord.walk_key(KEY_S, true, false))
	KeyChord.walk_key(KEY_S, false, false)
	KeyChord.walk_key(KEY_D, false, false)

	# A key already walking is not a chord because Ctrl came after it.
	check("W walks", KeyChord.walk_key(KEY_W, true, false))
	check("Ctrl does not stop a held W", KeyChord.walk_key(KEY_W, true, true))
	check("W carries on when Ctrl is up", KeyChord.walk_key(KEY_W, true, false))
	KeyChord.walk_key(KEY_W, false, false)

	KeyChord.walk_key(KEY_A, true, true)
	KeyChord.clear_walk_latch()
	check("clearing forgets the latch", KeyChord.walk_key(KEY_A, true, false))
	KeyChord.clear_walk_latch()


func _key(keycode: Key, shift := false, control := false, alt := false, meta := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.pressed = true
	e.shift_pressed = shift
	e.ctrl_pressed = control
	e.alt_pressed = alt
	e.meta_pressed = meta
	return e


func _hold(keycode: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.physical_keycode = keycode
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()


class Screen extends CanvasLayer:
	var open := false

	func is_open() -> bool:
		return open


class Holder extends CanvasLayer:
	var holding := false

	func holds_keyboard() -> bool:
		return holding

	func is_open() -> bool:
		return true
