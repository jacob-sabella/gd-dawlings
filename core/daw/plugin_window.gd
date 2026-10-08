class_name PluginWindow
extends RefCounted

## A plugin's own window, shown somewhere other than where the DAW draws it, and worked from
## there: a picture that keeps up with the window, and the pointer passed back into it.
##
## The plugin tablet shows one of these as the other face of the plugin -- the one its maker
## drew, amp heads and all -- beside the knobs face the tablet lays out itself. Both work the same
## plugin, so neither has to be complete: the knobs reach every parameter by name, and the window
## reaches what parameters never say, like a preset browser or a tuner.
##
## Only where the window really is. The window is on the host's desktop, so a guest never gets
## one; see DAW.open_plugin_window.
##
## This base is a stand-in: a picture it was given and a list of what was done to it. A backend
## that can show a real window returns its own kind; see core/reaper/reaper_plugin_window.gd.

## What was done to it, oldest first, as [kind, x, y, button-or-notches]: kind is &"move",
## &"down", &"up" or &"wheel". The stand-in keeps them for whoever is checking.
var events: Array = []

var _texture: ImageTexture
var _open := true


## A stand-in showing `picture`.
static func showing(picture: Image) -> PluginWindow:
	var w := PluginWindow.new()
	w._texture = ImageTexture.create_from_image(picture)
	return w


## The window's picture, or null until there is one: the window can take a moment to open.
func texture() -> Texture2D:
	return _texture


## The picture's size in pixels; zero until there is one.
func pixel_size() -> Vector2i:
	return _texture.get_size() if _texture != null else Vector2i.ZERO


## Call once a frame: takes in whatever the window has drawn since.
func poll() -> void:
	pass


func is_open() -> bool:
	return _open


## The pointer at `at`, in the picture's pixels. `button` is 1 left, 2 middle, 3 right.
func pointer_move(at: Vector2i) -> void:
	_send(&"move", at, 0)


func pointer_down(at: Vector2i, button := 1) -> void:
	_send(&"down", at, button)


func pointer_up(at: Vector2i, button := 1) -> void:
	_send(&"up", at, button)


## The wheel at `at`, `notches` up (positive) or down.
func wheel(at: Vector2i, notches: int) -> void:
	if notches != 0:
		_send(&"wheel", at, notches)


## Stop showing it. The DAW puts its window back the way it was.
func close() -> void:
	_open = false


func _send(kind: StringName, at: Vector2i, extra: int) -> void:
	if _open:
		events.append([kind, at.x, at.y, extra])
