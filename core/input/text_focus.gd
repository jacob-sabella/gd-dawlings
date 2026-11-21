class_name TextFocus
extends RefCounted

## Whether a text field has the keyboard. Every handler that reads keys before the GUI does
## (`_input` runs ahead of the focused control) asks this first, so typing a name, a search or a
## join code is never eaten as pads, notes or shortcuts: while a LineEdit or TextEdit has focus,
## every printable key, Backspace, Enter, Escape and paste belong to it; click away, or Enter or
## Escape in the field, and the keys are the room's again.


## Whether a LineEdit or TextEdit in `viewport` holds focus and can be typed into.
static func held(viewport: Viewport) -> bool:
	if viewport == null:
		return false
	var owner := viewport.gui_get_focus_owner()
	if owner is LineEdit:
		return (owner as LineEdit).editable
	if owner is TextEdit:
		return (owner as TextEdit).editable
	return false


## Whether a field keeps Ctrl chords for itself. Narrower than `held`, which still blocks plain
## keys: a LineEdit after Enter keeps focus but is done editing, so Ctrl+Z is the room's again.
## Any focused TextEdit owns them, read-only too, or the Workshop's preview loses Ctrl+C.
static func owns_keys(viewport: Viewport) -> bool:
	if viewport == null:
		return false
	var owner := viewport.gui_get_focus_owner()
	if owner is LineEdit:
		return (owner as LineEdit).editable and (owner as LineEdit).is_editing()
	return owner is TextEdit
