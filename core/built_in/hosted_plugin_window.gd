class_name HostedPluginWindow
extends PluginWindow

## The window of a plugin the built-in engine hosts (DawKitPlugin): embedded by dawkit in a window
## of its own kept off every screen, read back a frame at a time, and worked by pointer events
## sent into it. Nothing appears on the desktop.

var plugin: Object


static func opening(p: Object) -> HostedPluginWindow:
	if p == null or not p.editor_supported() or not p.editor_open():
		return null
	var w := HostedPluginWindow.new()
	w.plugin = p
	return w


func poll() -> void:
	if plugin == null or not plugin.editor_is_open():
		_open = false
		return
	if not plugin.editor_capture():
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
