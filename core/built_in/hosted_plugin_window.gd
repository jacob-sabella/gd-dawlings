class_name HostedPluginWindow
extends PluginWindow

## The window of a plugin the built-in engine hosts (DawKitPlugin): embedded by dawkit in a window
## of its own kept off every screen, read back a frame at a time, and worked by pointer events
## sent into it. Nothing appears on the desktop.
##
## A Windows plugin's, through yabridge, takes seconds to open (its Wine host makes it), and dawkit
## opens it on a thread of its own: the window is open but has no picture until then
## (`DawKitPlugin.editor_opening`), and the tablet says it is opening meanwhile. One that will
## not open after all is said in a toast. ("move yabridge off the main thread", 2026-10-30.)

var plugin: Object
## Whether it was still opening when last looked at.
var _opening := false


static func opening(p: Object) -> HostedPluginWindow:
	if p == null or not p.editor_supported() or not p.editor_open():
		return null
	var w := HostedPluginWindow.new()
	w.plugin = p
	w._opening = p.editor_opening()
	return w


## Whether the plugin is still opening its window, with nothing to show yet.
func is_opening() -> bool:
	return plugin != null and plugin.editor_opening()


func poll() -> void:
	if plugin == null or not plugin.editor_is_open():
		if _opening and _open and plugin != null:
			Session.notice.emit("%s's window could not be opened: %s" % [
					plugin.info().get("name", "The plugin"), plugin.get_error()])
		_opening = false
		_open = false
		return
	# Taken over (and captured from) once dawkit's thread has it open.
	var captured: bool = plugin.editor_capture()
	_opening = plugin.editor_opening()
	if not captured:
		return
	var picture: Image = plugin.editor_image()
	if picture == null:
		return
	if _texture != null and _texture.get_size() == Vector2(picture.get_size()):
		_texture.update(picture)
	else:
		_texture = ImageTexture.create_from_image(picture)


func is_open() -> bool:
	return _open and plugin != null and plugin.editor_is_open()


func close() -> void:
	if plugin != null:
		plugin.editor_close()
	_open = false


func _send(kind: StringName, at: Vector2i, extra: int) -> void:
	super(kind, at, extra)
	if not is_open():
		return
	match kind:
		&"move":
			plugin.editor_pointer_move(at.x, at.y)
		&"down":
			plugin.editor_pointer_button(at.x, at.y, extra, true)
		&"up":
			plugin.editor_pointer_button(at.x, at.y, extra, false)
		&"wheel":
			plugin.editor_wheel(at.x, at.y, extra)
