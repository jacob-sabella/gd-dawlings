class_name FlatPanel
extends ControlAffordance

## The 2D view (DawKitStudio over the game's mix) on a panel in the room, for a headset, where
## there is no screen to put it on: a SubViewport drawn on a quad, and whatever reaches into the
## room -- the hand's ray, a controller's trigger, a pinch, a mouse on a monitor -- is the
## mouse on it.
##
## It is a control like a fader is, so every input medium gets to it the same way: hovering
## moves the pointer on it, a grab is the left button going down where the ray meets the glass,
## the grab dragging is the mouse dragging, letting go is the button coming up, and the wheel
## (a nudge) is the wheel. Holding still on one spot for HOLD_SECONDS is the right button there,
## since a hand has only one: the menus are there for a hand too.
##
## Laid out in its own frame: X along the glass, Y up it, Z out of it toward whoever reads it.

## The glass, in metres; the pixels drawn on it.
const SIZE := Vector2(1.44, 0.81)
const PIXELS := Vector2i(1600, 900)
## How long a press held still is the right button rather than the left.
const HOLD_SECONDS := 0.7
## How far a press may wander, in pixels, and still be held still.
const STILL_PIXELS := 8.0

var host: DawKitHost
var viewport: SubViewport
## The 2D view on it; null on a panel that holds something else (`content`, the session panel).
var view: DawKitStudio
## The glass's size in metres and the pixels drawn on it: SIZE and PIXELS for the 2D view.
var glass_size := SIZE
var pixels := PIXELS
## What its hover card calls it.
var called := "2D VIEW"
var screen: MeshInstance3D
## Where the hand points on the glass: the glass is drawn over the room, the ray under it, so
## this is the only pointer there is.
var dot: MeshInstance3D
## Where the pointer last was on the glass, in pixels.
var pointer := Vector2(-1, -1)

var _pressed_at := Vector2.ZERO
var _pressed_for := 0.0
## The press was taken as the right button: what follows until it lets go is not a drag.
var _held_still := false


## Built when made, not when it enters the room, so whoever made it has its view at once. With
## `content`, that is what is drawn on it instead of the 2D view, on glass `metres` across
## and `px` pixels (the session panel in a headset).
func _init(with_host: DawKitHost, content: Control = null, metres := SIZE, px := PIXELS) -> void:
	host = with_host
	glass_size = metres
	pixels = px
	name = "FlatPanel"
	collision_layer = 2
	viewport = SubViewport.new()
	viewport.name = "Viewport"
	viewport.size = pixels
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.handle_input_locally = true
	viewport.gui_embed_subwindows = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	if content != null:
		viewport.add_child(content)
	else:
		view = DawKitStudio.new(host)
		view.name = "DawKitStudio"
		viewport.add_child(view)
		view.size = Vector2(pixels)
	screen = MeshInstance3D.new()
	screen.name = "Screen"
	var quad := QuadMesh.new()
	quad.size = glass_size
	screen.mesh = quad
	var glass := StandardMaterial3D.new()
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.albedo_texture = viewport.get_texture()
	glass.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	# Over the room, as a headset's own menus are: asked for, it is the thing in front, and the
	# head-pinned gear nearer the eyes is not drawn through it.
	glass.no_depth_test = true
	glass.render_priority = 10
	screen.material_override = glass
	add_child(screen)
	dot = MeshInstance3D.new()
	dot.name = "Pointer"
	var bead := SphereMesh.new()
	bead.radius = 0.006
	bead.height = 0.012
	dot.mesh = bead
	var ink := StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.albedo_color = Color(1, 1, 1)
	ink.no_depth_test = true
	ink.render_priority = 11
	dot.material_override = ink
	dot.visible = false
	add_child(dot)
	# A thin back so it is a thing in the room and not a picture hung in the air.
	var back := MeshInstance3D.new()
	back.name = "Back"
	var box := BoxMesh.new()
	box.size = Vector3(glass_size.x + 0.03, glass_size.y + 0.03, 0.02)
	back.mesh = box
	back.position = Vector3(0, 0, -0.0105)
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color(0.08, 0.085, 0.095)
	shell.no_depth_test = true
	shell.render_priority = 9
	back.material_override = shell
	add_child(back)
	var shape := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(glass_size.x, glass_size.y, 0.02)
	shape.shape = slab
	shape.position = Vector3(0, 0, -0.01)
	add_child(shape)


## Up in the room, or put away: put away, it is neither drawn, nor drawn into, nor in a ray's way.
func set_shown(on: bool) -> void:
	visible = on
	if view != null:
		view.visible = on
	collision_layer = 2 if on else 0
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if not on:
		pointer = Vector2(-1, -1)
		dot.visible = false


## A point on the glass, in the room, as a pixel of the 2D view.
func pixel_of(world: Vector3) -> Vector2:
	var local := to_local(world)
	return Vector2((local.x / glass_size.x + 0.5) * pixels.x, (0.5 - local.y / glass_size.y) * pixels.y)


## A pixel of the 2D view as a point on the glass, in the room.
func world_of(pixel: Vector2) -> Vector3:
	return to_global(Vector3((pixel.x / pixels.x - 0.5) * glass_size.x, (0.5 - pixel.y / pixels.y) * glass_size.y, 0.0))


func personal() -> bool:
	return true


func title() -> String:
	return called


func readout() -> String:
	return ""


func hint() -> String:
	return "press to click, drag, hold still for a menu"


## Places it `distance` in front of a head and a little below the eyes, square to it.
func face(head: Transform3D, distance := 1.1) -> void:
	var ahead := -head.basis.z
	ahead.y = 0.0
	ahead = ahead.normalized() if ahead.length() > 0.01 else Vector3.FORWARD
	var at := head.origin + ahead * distance + Vector3(0, -0.12, 0)
	global_transform = Transform3D(Basis.looking_at(ahead, Vector3.UP), at)


func _process(delta: float) -> void:
	if not visible or viewport == null:
		return
	if held_by != null:
		dot.visible = true
		_pressed_for += delta
		if not _held_still and _pressed_for >= HOLD_SECONDS and pointer.distance_to(_pressed_at) <= STILL_PIXELS:
			# Held still: the left press is taken back off the glass, and the right one given.
			_held_still = true
			var off := Vector2(-10, -10)
			var away := InputEventMouseMotion.new()
			away.position = off
			away.global_position = off
			away.button_mask = MOUSE_BUTTON_MASK_LEFT
			viewport.push_input(away)
			_button(MOUSE_BUTTON_LEFT, false, off)
			# Back where the hand is, so the menu opens under it.
			var back := InputEventMouseMotion.new()
			back.position = _pressed_at
			back.global_position = _pressed_at
			viewport.push_input(back)
			_button(MOUSE_BUTTON_RIGHT, true, _pressed_at)
			_button(MOUSE_BUTTON_RIGHT, false, _pressed_at)
		return
	var over := false
	for by in _hovered_by:
		if is_instance_valid(by) and by.get(&"hover_point") is Vector3:
			_move(pixel_of(by.hover_point))
			over = true
			break
	dot.visible = over


func _on_grab_begin(at: Vector3) -> void:
	var px := pixel_of(at)
	_move(px)
	_pressed_at = px
	_pressed_for = 0.0
	_held_still = false
	_button(MOUSE_BUTTON_LEFT, true, px)


func _on_grab_move(at: Vector3) -> void:
	if not _held_still:
		_move(pixel_of(at))


func _on_grab_end() -> void:
	if not _held_still:
		_button(MOUSE_BUTTON_LEFT, false, pointer)
	_held_still = false


func _on_nudge(notches: int, _fine: bool) -> bool:
	var wheel := MOUSE_BUTTON_WHEEL_UP if notches > 0 else MOUSE_BUTTON_WHEEL_DOWN
	for _i in absi(notches):
		_button(wheel, true, pointer)
		_button(wheel, false, pointer)
	return true


func _foley_contact() -> AudioStream:
	return null


func _move(px: Vector2) -> void:
	dot.position = to_local(world_of(px)) + Vector3(0, 0, 0.002)
	if px.distance_to(pointer) < 0.5:
		return
	var e := InputEventMouseMotion.new()
	e.position = px
	e.global_position = px
	e.relative = px - pointer if pointer.x >= 0.0 else Vector2.ZERO
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if held_by != null and not _held_still else 0
	pointer = px
	viewport.push_input(e)


func _button(which: MouseButton, down: bool, px: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = which
	e.pressed = down
	e.position = px
	e.global_position = px
	if down and which == MOUSE_BUTTON_LEFT:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	viewport.push_input(e)
