class_name FlatView
extends CanvasLayer

## The whole mix as a flat DAW on the screen: dawkit's 2D interface (DawKitStudio) over the
## game's own mix (FlatHost). F2 goes to it and back.
##
## It is the same session, not a second one: every edit is an edit at the desk, a guest's goes to
## the host, and the room goes on around it -- the sound, the other players, the venue -- only
## not drawn, and not walked or reached into, while it is up.
##
## In a headset there is no screen to lay it over, so it is a panel in the room instead
## (FlatPanel), put up in front of you by holding the menu button (or F2): the room stays drawn
## and reached into around it, since the hand reaching into it is how the panel is used.

const TOGGLE_KEY := KEY_F2

## Said when it opens, and when it cannot.
signal said(text: String)

var studio: Studio
var host: FlatHost
var view: DawKitStudio
## Whether this is a headset, where it is a panel in the room rather than over the screen.
var in_headset := false
## The panel it is in a headset, or null on a screen.
var panel: FlatPanel
## The window's title before the 2D view put the project's in it, to put back.
var _window_title := ""


## The eyesight the view was built for: [text scale, colour vision]. It is built again when the
## game's changes, since its text and colours are fixed when it is made.
var _built_for := []


func _ready() -> void:
	layer = 20
	host = FlatHost.new()
	visible = false
	_build()
	view.visible = false
	_hook_rig.call_deferred()


## The panel is in the room, not under this, so it goes when this does.
func _exit_tree() -> void:
	if panel != null and is_instance_valid(panel):
		panel.queue_free()


## The menu button held is the 2D view in a headset, as F2 is on a keyboard.
func _hook_rig() -> void:
	if studio != null and studio.rig != null and not studio.rig.flat_requested.is_connected(toggle):
		studio.rig.flat_requested.connect(toggle)


## The 2D view made for the game's eyesight now: its signal colours from the palette picked for
## the reader's colour vision, its text at their text scale.
func _build() -> void:
	var eyes := Ergonomics.current
	var colours := {}
	for role in Ergonomics.SIGNAL_ROLES:
		colours[str(role)] = eyes.signal_colour(role)
	DawKitLook.use_signals(colours)
	DawKitLook.set_text_scale(eyes.text_scale)
	_built_for = [eyes.text_scale, eyes.colour_vision]
	if panel != null:
		panel.queue_free()
		panel.get_parent().remove_child(panel)
		panel = null
	elif view != null:
		view.queue_free()
		remove_child(view)
	if in_headset:
		panel = FlatPanel.new(host)
		var room: Node = studio if studio != null else get_parent()
		room.add_child(panel)
		view = panel.view
		panel.set_shown(visible)
	else:
		view = DawKitStudio.new(host)
		view.name = "DawKitStudio"
		add_child(view)
		view.visible = visible
	view.title_changed.connect(_show_title)


func is_open() -> bool:
	return visible


func toggle() -> void:
	set_open(not visible)


func set_open(on: bool) -> void:
	if on == visible:
		return
	if on and _built_for != [Ergonomics.current.text_scale, Ergonomics.current.colour_vision]:
		_build()
	if panel != null:
		_put_up(on)
		return
	visible = on
	view.visible = on
	if studio != null:
		# The room is still there behind it, and still playing, but not reached into.
		studio.set_process_unhandled_input(not on)
		var hand := studio.get_node_or_null("MouseHand")
		if hand != null:
			hand.set_process_unhandled_input(not on)
	if on:
		_window_title = get_window().title if get_window() != null else ""
		_show_title(view.title_text())
		view.refresh()
		# Something on it holds the keyboard, so the walker and the fly camera leave it alone.
		view.grab_focus()
		said.emit("2D view. F2 goes back to the room.")
	else:
		if get_window() != null and not _window_title.is_empty():
			get_window().title = _window_title
		var owner := get_viewport().gui_get_focus_owner() if get_viewport() != null else null
		if owner != null and (owner == view or view.is_ancestor_of(owner)):
			owner.release_focus()


## In a headset: the panel up in front of wherever you are looking, square to you, or put away.
## The room is not shut out, because the hand that uses the panel is a hand in the room.
func _put_up(on: bool) -> void:
	visible = on
	if on:
		var eyes := get_viewport().get_camera_3d() if get_viewport() != null else null
		if eyes != null:
			panel.face(eyes.global_transform)
		panel.set_shown(true)
		view.refresh()
		said.emit("2D view. Hold the menu button to put it away.")
	else:
		panel.set_shown(false)


## The window says which project the 2D view is showing, while it shows.
func _show_title(text: String) -> void:
	if visible and get_window() != null:
		get_window().title = "%s - %s" % [text, ProjectSettings.get_setting("application/config/name", "dawlings")]


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == TOGGLE_KEY:
		toggle()
		get_viewport().set_input_as_handled()


## While it is up, what it did not use goes no further: no key reaches the room's own shortcuts.
func _unhandled_input(event: InputEvent) -> void:
	if visible and panel == null and (event is InputEventKey or event is InputEventMouseButton):
		get_viewport().set_input_as_handled()
