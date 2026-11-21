class_name KeyChord
extends RefCounted

## What a key press means with the modifiers around it, so every handler draws the same line
## between a room key and a command. Ctrl, Alt and Meta make a press a command. Shift does not:
## it is the run key, and it picks the F, I, Y, P and pad variants.
##
## The walk latch is here because a chord outlives its modifier: let go of Ctrl a moment before
## the S of Ctrl+S and the S alone must not walk you backward. A key pressed under a command stays
## out of walking until that key itself comes up. A key already held for walking is not a chord
## because Ctrl came after it: it goes on walking, so Ctrl+Z does not stop you in your tracks.
##
## MODAL and PANEL are the registries of open screens. A screen in either says whether it is open
## with holds_keyboard() or is_open(). There is deliberately no fallback to `visible`: most of
## these are CanvasLayers that stay visible all their lives, so a node with neither method counts
## as closed.

const MODAL := &"keyboard_modal"
const PANEL := &"keyboard_panel"
const WALK_KEYS := [KEY_W, KEY_A, KEY_S, KEY_D]

## Keys down at the last walk_key, and those of them pressed under a command.
static var _walk_down := {}
static var _walk_latched := {}


## Whether this event carries Ctrl, Alt or Meta.
static func commanded(e: InputEvent) -> bool:
	if not e is InputEventWithModifiers:
		return false
	var m := e as InputEventWithModifiers
	return m.ctrl_pressed or m.alt_pressed or m.meta_pressed


## Whether this event is a Ctrl chord: Ctrl without Alt or Meta. Shift may be on it.
static func ctrl(e: InputEvent) -> bool:
	if not e is InputEventWithModifiers:
		return false
	var m := e as InputEventWithModifiers
	return m.ctrl_pressed and not m.alt_pressed and not m.meta_pressed


## Whether Ctrl, Alt or Meta is down right now.
static func command_held() -> bool:
	return Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_ALT) \
		or Input.is_key_pressed(KEY_META)


## Whether an arrow pressed now is a command: Ctrl or Meta only, so Alt can bend a note on the move.
static func arrow_commanded() -> bool:
	return Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)


## Whether this key should walk, given its state and whether a command modifier is down. Asking
## twice with the same answers changes nothing, so the Walker and the ViewHost can both ask.
## A caller should ask every frame it cares about, even while it is not walking: a release it never
## reports leaves the key looking held.
static func walk_key(keycode: int, down: bool, is_commanded: bool) -> bool:
	if not down:
		_walk_down.erase(keycode)
		_walk_latched.erase(keycode)
		return false
	if is_commanded and not _walk_down.has(keycode):
		_walk_latched[keycode] = true
	_walk_down[keycode] = true
	return not _walk_latched.has(keycode)


## A press heard as an event under a command: out of walking until it comes up, even if the modifier
## is gone before the next poll could see the two together. Only W, A, S and D come here: no room chord uses an arrow.
static func latch_chord(keycode: int) -> void:
	if keycode in WALK_KEYS:
		_walk_down[keycode] = true
		_walk_latched[keycode] = true


## Forget every held and latched key: for when the room stops hearing the keyboard.
static func clear_walk_latch() -> void:
	_walk_down.clear()
	_walk_latched.clear()


## Whether a plain press is not the room's: a text field holds focus (after Enter too) or a modal
## is open. For presses only, so a key let go always lets go.
static func room_keys_blocked(viewport: Viewport) -> bool:
	if viewport == null or not viewport.is_inside_tree():
		return false
	return TextFocus.held(viewport) or modal_open(viewport.get_tree())


## Whether a registered modal screen is open.
static func modal_open(tree: SceneTree) -> bool:
	return _any_open(tree, MODAL)


## Whether a registered panel is open.
static func panel_open(tree: SceneTree) -> bool:
	return _any_open(tree, PANEL)


static func _any_open(tree: SceneTree, group: StringName) -> bool:
	if tree == null:
		return false
	for node in tree.get_nodes_in_group(group):
		if node.is_queued_for_deletion():
			continue
		if node.has_method(&"holds_keyboard"):
			if node.call(&"holds_keyboard"):
				return true
		elif node.has_method(&"is_open") and node.call(&"is_open"):
			return true
	return false
