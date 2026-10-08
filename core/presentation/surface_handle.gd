class_name SurfaceHandle
extends ControlAffordance

## The grab tab clipped to the corner of every surface: where it lives, and how to move it.
##
## This is the in-world half of presentation switching. The flat overlay (`StageManager`) is the
## screen participant's tool and is useless the moment someone puts a headset on -- there is no
## 2D layer to put a list on, and no keyboard to press Tab with. What there is instead is a
## hand, so the control is a thing the hand can take hold of.
##
## Two gestures on one handle, told apart by whether the surface actually went anywhere:
##
##   TAP    -- grab and release without moving: cycle to the next presentation mode.
##   CARRY  -- grab and move: reposition the surface, remembered for THAT MODE only.
##
## Collapsing both onto one handle is deliberate. The alternative is a handle plus a menu, and a
## menu floating beside a console is the kind of thing that reads as software bolted to
## hardware. A tab you tap or drag reads as hardware.
##
## THE HANDLE DOES NOT KNOW WHAT MODE IT IS IN, and neither does the surface it hangs off. It
## asks the mount and tells the mount; `Surface` stays ignorant of presentation exactly as
## core/presentation/presentation.gd requires. That is also why the mount builds these rather
## than the surface doing it: the mount is already the one object allowed to read a layout.

## How far the surface must travel before a grab counts as a carry rather than a tap. Generous,
## because a tracked controller is never still: a hand holding a tab "without moving" drifts
## several millimetres over the half second it is held, and a tighter threshold turns every tap
## into a one-centimetre nudge that also fails to switch modes.
const TAP_SLOP := 0.018

const BAR := Vector3(0.036, 0.011, 0.016)
## The collision box is bigger than the thing you see. Aiming a tracked controller at a 13mm bar
## across a room is a dart throw; aiming at the 30mm box around it is a gesture.
const TARGET := Vector3(0.060, 0.034, 0.030)
## Clear of the surface's outermost control, so the tab never sits over a fader.
const MARGIN := 0.013

var surface: Surface
var mount: SurfaceMount

## Lit, because a tab the colour of the chassis it is bolted to is a tab nobody finds. One pip
## rather than a glowing slab: the gear is the thing being looked at.
const ACCENT := Color(0.38, 0.60, 0.95)

var _bar: MeshInstance3D
var _accent: MeshInstance3D
var _caption: Label3D
var _grip := Transform3D.IDENTITY
var _origin_at_grab := Vector3.ZERO
var _carried := false


static func create(for_surface: Surface, owning_mount: SurfaceMount) -> SurfaceHandle:
	var handle := SurfaceHandle.new()
	handle.name = "SurfaceHandle"
	handle.surface = for_surface
	handle.mount = owning_mount
	return handle


func _ready() -> void:
	collision_layer = 1 << (Interactor.CONTROL_LAYER - 1)
	collision_mask = 0

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = TARGET
	shape.shape = box
	add_child(shape)

	_bar = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = BAR
	_bar.mesh = mesh
	_bar.material_override = Materials.cap_plastic(Color(0.17, 0.18, 0.20))
	_mark_chrome(_bar)
	add_child(_bar)

	_accent = MeshInstance3D.new()
	var pip := BoxMesh.new()
	pip.size = Vector3(BAR.x * 0.70, 0.0022, 0.0010)
	_accent.mesh = pip
	_accent.position = Vector3(0, 0, BAR.z * 0.5 + 0.0005)
	_accent.material_override = Materials.led(ACCENT, true)
	_mark_chrome(_accent)
	add_child(_accent)

	_caption = Label3D.new()
	_caption.font_size = 52
	_caption.pixel_size = 0.00013
	_caption.position = Vector3(0, -BAR.y * 0.5 - 0.010, BAR.z * 0.5)
	_caption.modulate = Color(0.60, 0.66, 0.76)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mark_chrome(_caption)
	Lettering.range_to_legibility(_caption)
	add_child(_caption)

	grab_started.connect(func(_by): _light(true))
	grab_ended.connect(func(_by): _light(false))

	if surface != null:
		surface.rebuilt.connect(reposition)
	reposition()
	refresh()


## Clipped to the outer edge of whatever the surface currently is, at the height of its middle.
##
## Recomputed on every rebuild and not cached, because the edge moves: a console that gained
## eight tracks is a wider object, and a tab left at the old width ends up floating in the
## middle of the new strips.
##
## MID-HEIGHT, not the top corner, and that is a framing constraint rather than taste. A surface
## shown on a monitor is pitched back and fitted to the viewport at the depth of its centre; a
## tab above that centre swings toward the camera as it pitches, lands nearer than the plane
## that was fitted, and gets cropped by the edge of a frame it was measured to be inside of.
## At the centre height there is no swing.
func reposition() -> void:
	if surface == null:
		return
	var bounds := surface.content_aabb()
	if bounds.size.x <= 0.0:
		return
	var centre := bounds.get_center()
	# Lies in the plane of the WORKING FACE, which on a console is laid sixty degrees back
	# inside the carcass. A tab square to the surface's own axes would stand proud of the panel
	# it is supposed to be clipped to.
	transform = Transform3D(_face_basis(), Vector3(bounds.end.x + MARGIN, centre.y, centre.z))


func _face_basis() -> Basis:
	var face := surface.framing_root()
	if face == null or face == surface:
		return Basis.IDENTITY
	return (surface.global_transform.affine_inverse() * face.global_transform).basis.orthonormalized()


## Shows the mode the NEXT tap will move to, not the one the surface is in.
##
## A label reading the current state is useless on a control whose whole job is to change it --
## the surface in front of you already tells you where it is. What is worth knowing before you
## touch it is where it will go.
func refresh() -> void:
	if _caption == null or surface == null or mount == null:
		return
	var next := mount.next_mode(surface.surface_id)
	_caption.text = "→ %s" % String(Presentation.MODE_NAMES.get(next, "?")).to_upper()
	# Wider than the bar it hangs from is fine; wider than the gap beside it is not.
	Lettering.fit(_caption, BAR.x * 1.4, 52, 40)


func _on_grab_begin(_at: Vector3) -> void:
	var hand := held_by as Interactor
	if hand == null or surface == null:
		return
	# The surface is carried RIGIDLY relative to the hand: wrist rotation turns the console the
	# way turning a held object turns it. Reconstructing a position from the ray hit instead
	# would slide the surface along a plane and never let anyone face it toward themselves.
	_grip = hand.aim().affine_inverse() * surface.global_transform
	_origin_at_grab = surface.global_position
	_carried = false


func _on_grab_move(_at: Vector3) -> void:
	var hand := held_by as Interactor
	if hand == null or surface == null:
		return
	surface.global_transform = hand.aim() * _grip
	if surface.global_position.distance_to(_origin_at_grab) > TAP_SLOP:
		_carried = true


func _on_grab_end() -> void:
	if surface == null or mount == null:
		return
	if _carried:
		mount.remember_placement(surface.surface_id)
	else:
		# Snap back first. A tap still drifts a few millimetres, and leaving that drift behind
		# would mean every mode switch also silently nudged the surface off the placement the
		# viewer had settled on.
		surface.global_position = _origin_at_grab
		mount.cycle_mode(surface.surface_id)
	refresh()


func _light(on: bool) -> void:
	if _bar != null:
		_bar.material_override = Materials.cap_plastic(Color(0.30, 0.34, 0.40) if on \
				else Color(0.17, 0.18, 0.20))
	if _accent != null:
		_accent.material_override = Materials.led(Color(0.82, 0.90, 1.0) if on else ACCENT, true)


## Chrome is not gear. A surface measures itself to be framed on a monitor, and a tab that
## counted toward that measurement would push the surface back to make room for the tab, which
## moves the corner, which moves the tab.
func _mark_chrome(node: Node) -> void:
	node.add_to_group(&"presentation_chrome")


func _default_title() -> String:
	return "MOVE  %s" % String(surface.surface_id).to_upper() if surface != null else "MOVE"


func _default_readout() -> String:
	return ""


func hint() -> String:
	return "drag to move  ·  click to change mount"
