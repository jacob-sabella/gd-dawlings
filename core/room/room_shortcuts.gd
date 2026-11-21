class_name RoomShortcuts
extends Node

## The room's edit keys: Delete, undo and redo, the clipboard, duplicate and select all. One place
## decides whether a press is for the room at all and what it is on, because these keys change the
## song and the pointer may be on nothing, or on something the player cannot see.
##
## Delete, Ctrl+X and Ctrl+D need the pointer on a clip. Each names exact targets, so a clip that
## moved before the host heard refuses the edit (DAW.edit_targets). A selection reaching outside the
## lanes or the time on the panel is refused with a count: nobody deletes what they cannot see.
##
## In a headset there is no mouse hand, so only undo and redo act.

const LET_GO := "Let go of the drag first."
const PLUGIN_WINDOW := "Keys do not reach plugin windows yet: point away from it to edit the song."
const HISTORY := [&"undo", &"redo"]

var studio: Studio
## The mouse's hand, or null in a headset.
var hand: Interactor


func _shortcut_input(event: InputEvent) -> void:
	if handle(event):
		get_viewport().set_input_as_handled()


## Never consumes. Here because a field can take a key before _shortcut_input.
func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		_note_key(event)


## What this press means, with its modifiers exact, or &"" for none of these keys.
static func verb_of(key: InputEventKey) -> StringName:
	if key.alt_pressed or key.meta_pressed:
		return &""
	if not key.ctrl_pressed:
		if key.shift_pressed or not key.keycode in [KEY_DELETE, KEY_BACKSPACE]:
			return &""
		return &"delete"
	match key.keycode:
		KEY_Z:
			return &"redo" if key.shift_pressed else &"undo"
		KEY_A:
			return &"clear" if key.shift_pressed else &"select"
	if key.shift_pressed:
		return &""
	match key.keycode:
		KEY_Y:
			return &"redo"
		KEY_X:
			return &"cut"
		KEY_C:
			return &"copy"
		KEY_V:
			return &"paste"
		KEY_D:
			return &"duplicate"
	return &""


## Whether this event was one of the room's edit keys, acted on or refused aloud. False leaves it
## for whoever is next: Ctrl+S for the session panel, Backspace off the lanes for the stage.
func handle(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return false
	_note_key(key)
	var verb := verb_of(key)
	if verb == &"" or DAW.state == null or not is_inside_tree():
		return false
	var history: bool = verb in HISTORY
	if key.echo and not history:
		return false
	if KeyChord.modal_open(get_tree()):
		return false
	var view := get_viewport()
	if verb == &"delete":
		if TextFocus.held(view) or TextFocus.owns_keys(view) or view.gui_get_focus_owner() is KeyCatcher:
			return false
	elif TextFocus.owns_keys(view):
		return false
	if not history and KeyChord.panel_open(get_tree()):
		return false

	var has_hand := is_instance_valid(hand)
	var held: ControlAffordance = hand.held if has_hand and is_instance_valid(hand.held) else null
	var hovered: ControlAffordance = hand.hovered if has_hand and is_instance_valid(hand.hovered) else null
	if history:
		if held is TimelineLanes:
			if not key.echo:
				Session.notice.emit(LET_GO)
			return true
		_step_history(verb, key.echo)
		return true
	if not has_hand:
		return false

	# Backspace off the lanes is the stage's: it resets the voice under the hand (InputHost).
	if key.keycode == KEY_BACKSPACE:
		var under: ControlAffordance = held if held != null else hovered
		if not under is TimelineLanes and not under is PluginScreen:
			return false

	if held is TimelineLanes and verb in [&"select", &"clear"]:
		Session.notice.emit(LET_GO)
		return true
	if verb in [&"cut", &"delete", &"duplicate", &"paste"] and (held != null or _host_edit_open()):
		Session.notice.emit(LET_GO)
		return true
	if verb != &"clear" and (hovered is PluginScreen or held is PluginScreen):
		Session.notice.emit(PLUGIN_WINDOW)
		return true

	match verb:
		&"delete":
			_edit("delete", "deleted", hovered)
		&"cut":
			_edit("cut", "cut", hovered)
		&"duplicate":
			_edit("duplicate", "duplicated", hovered)
		&"copy":
			_copy()
		&"paste":
			_paste(hovered)
		&"select":
			_select_all()
		&"clear":
			_clear_selection()
	return true


func _note_key(key: InputEventKey) -> void:
	# From the event, which has the modifier on it: a Ctrl let go before the next poll is not seen.
	if key.pressed and not key.echo and KeyChord.commanded(key):
		KeyChord.latch_chord(key.keycode)


## On the host, whether this machine has an edit open. A guest's is checked by the host.
func _host_edit_open() -> bool:
	return Session.is_authority() and DAW.backend != null and DAW.backend.edit_open(0)


## Always sent, whatever the depth says: on Reaper and for a guest the depth can be stale. Only the
## host's own offline history is known well enough to name the step.
func _step_history(verb: StringName, echo: bool) -> void:
	var undoing := verb == &"undo"
	var words := "Undo" if undoing else "Redo"
	if not echo and Session.is_authority() and DAW.backend is OfflineBackend and DAW.state.undo_depth >= 0:
		var names: Array = DAW.state.undo_names
		var at: int = DAW.state.undo_depth - 1 if undoing else DAW.state.undo_depth
		if at < 0 or at >= names.size():
			words = "Nothing to undo." if undoing else "Nothing to redo."
		else:
			words = "%s: %s" % [words, names[at]]
	if undoing:
		DAW.undo()
	else:
		DAW.redo()
	if not echo:
		Session.notice.emit(words)


## Delete, cut or duplicate what the pointer is on. `done` is the verb as said when nothing happens.
func _edit(op: String, done: String, hovered: ControlAffordance) -> void:
	var targets := _targets_under(done, hovered)
	if targets.is_empty():
		return
	if op == "cut":
		DAW.cut_items(targets)
	else:
		DAW.edit_targets(op, targets)


## The clips an edit at the pointer acts on, or [] having said why not.
func _targets_under(done: String, hovered: ControlAffordance) -> Array:
	var lanes := hovered as TimelineLanes
	if lanes == null:
		Session.notice.emit("Point at a clip on the timeline: nothing was %s." % done)
		return []
	var surface := lanes.surface as TimelineSurface
	if surface.on_shown_lane(hand.hover_point):
		Session.notice.emit("That is the automation row, not a clip: nothing was %s." % done)
		return []
	var under := surface.items_at_point(hand.hover_point)
	if under.is_empty():
		Session.notice.emit("No clip under the pointer: nothing was %s." % done)
		return []
	var picked := under.filter(func(pair: Array) -> bool:
		return DAW.state.item(pair[0], pair[1]).selected)
	if picked.is_empty():
		if under.size() > 1:
			Session.notice.emit("%d takes overlap here: click one first. Nothing was %s." % [under.size(), done])
			return []
		var item: MixState.ItemState = DAW.state.item(under[0][0], under[0][1])
		return [[under[0][0], under[0][1], item.start, item.length]]
	var view := surface.selection_in_view()
	var hidden := int(view["hidden"])
	if hidden > 0:
		Session.notice.emit("%d of the %d selected clips are out of view: nothing was %s. Bring them into view, or click one clip."
				% [hidden, (view["targets"] as Array).size(), done])
		return []
	return view["targets"]


## Said as it is sent: a refusal from the host arrives after, and is the last word.
func _copy() -> void:
	var count := DAW.selected_targets().size()
	if count > 0 and count <= DAW.EDIT_TARGETS_MAX:
		Session.notice.emit("Copying %s." % _clips(count))
	DAW.copy_items()


## A cassette in the hand goes first, where the control takes it: the clipboard is the fallback.
func _paste(hovered: ControlAffordance) -> void:
	if hand.paste_carried():
		return
	var lanes := hovered as TimelineLanes
	if hovered == null or (lanes != null and (lanes.surface as TimelineSurface).on_shown_lane(hand.hover_point)):
		Session.notice.emit("Point at a timeline lane, a channel strip or a stage voice to paste.")
		return
	var spot := hovered.paste_spot(hand.hover_point, hand.fine())
	if spot.is_empty():
		Session.notice.emit("Nothing pastes here: point at a timeline lane, a channel strip or a stage voice.")
		return
	Session.notice.emit("Pasting onto %s at %s." % [DAW.state.track(spot[0]).display_name(),
			DAW.state.bar_beat(spot[1])])
	DAW.paste_items(int(spot[0]), float(spot[1]))


func _select_all() -> void:
	var count := 0
	for index in DAW.state.track_indices():
		count += DAW.state.track(index).items.size()
	var whole: bool = DAW.backend == null or DAW.backend.whole_project_shown()
	if count == 0 and whole:
		Session.notice.emit("There are no clips to select.")
		return
	DAW.select_all_items()
	if whole:
		Session.notice.emit("Selected %s." % _clips(count))
	else:
		Session.notice.emit("Selected every clip in the project, on tracks not shown here too.")


## Sent even with nothing selected here: Reaper can hold a selection past the tracks in the cache.
func _clear_selection() -> void:
	var had := DAW.selected_targets().size()
	DAW.clear_item_selection()
	Session.notice.emit("Selection cleared." if had > 0 else "Nothing is selected.")


static func _clips(count: int) -> String:
	return "%d clip%s" % [count, "" if count == 1 else "s"]
