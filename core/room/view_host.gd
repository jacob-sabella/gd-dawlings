class_name ViewHost
extends RefCounted

## The per-frame work and the view: `_process`, gliding surfaces, text scale, expanding, the viewport shape, escape, stray
## screens, the camera, the kit and the desk pads. Moved out of `scenes/studio.gd` without change of behaviour; the state stays on the studio, which delegates the calls other code makes.

## Each frame: this player's keys play the rack while they are at it (or its PLAY has the computer
## keys), its controls take the pointer only then, its lamps follow its meters, and the case glows with
## what it plays in the venue's mood. The song's recording is caught from it on the host.
var _modular_owed := 1.0

# --- drum pads on anything (docs/spatial_loop.md part two, slice 41) ------------------------------
#
# The room's kit (KitItem) stands on the console's front rail, six pads KICK to RIM, struck by a
# click, by 4 to 9, or by a hand or a controller's tip (Strike). This player's own pads on real
# surfaces (SurfacePads) are its faces too: marked in a headset from the PADS card under the rail.

## How far the kit may be from the rail before it is stood there again (m): a desk that moved, grew
## or was brought (FocusRig) takes its pads with it.
const KIT_FOLLOW := 0.001

var studio: Studio


func _init(of: Studio) -> void:
	studio = of


func _process(delta: float) -> void:
	studio.input_host._follow_hit_voices()
	studio.signal_views._follow_signal(delta)
	studio.room_rows._drive_pushed()
	studio.surface_host._refresh_looms_if_moved(delta)
	studio.mix_follow._follow_clap(delta)
	studio.signal_views._follow_look_solo(delta)
	studio.mix_follow._follow_lean()
	studio.mix_follow._follow_ear()
	studio.venue_switch._follow_wheel()
	_modular_owed += studio.get_process_delta_time()
	if _modular_owed >= 1.0 / 30.0 - 0.001:
		_modular_owed = 0.0
		studio.rack_host._follow_modular()
		studio.rack_host._follow_pads()
	studio.item_host._follow_making()
	studio.sampler_host._follow_gives(delta)
	_follow_kit()
	if studio.venue != null and DAW.state != null:
		# A room that holds still for anyone who has asked it to (COMFORT's "Room reacts").
		studio.venue.reactive = studio.ergonomics.room_reacts
		studio.venue.lift_on_clip = studio.ergonomics.lift_on_clip
		studio.venue.pulse(studio.fed_level if studio.fed_level >= 0.0 else maxf(maxf(DAW.state.master.vu_l, DAW.state.master.vu_r), studio.rack_host.rack_level()))
		studio.venue_look.follow_clip(delta)
	if studio.camera == null or not studio.god_mode:
		return
	# Not while typing a name into the session panel, or every "s" in it flies backwards.
	if studio.get_viewport().gui_get_focus_owner() != null:
		return
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): move.z -= 1.0
	if Input.is_key_pressed(KEY_S): move.z += 1.0
	if Input.is_key_pressed(KEY_A): move.x -= 1.0
	if Input.is_key_pressed(KEY_D): move.x += 1.0
	if move != Vector3.ZERO:
		var yaw := Basis(Vector3.UP, studio._orbit_yaw)
		studio._orbit_target += yaw * move.normalized() * delta * 1.4
		_update_camera()


## Move a surface to where the focus rig wants it, over time rather than instantly.
##
## The glide is not decoration. Something large arriving next to your face with no transit is
## disorienting and leaves you unsure what you are now looking at; watching it travel tells you
## which thing came and where it came from. It is also the first thing someone prone to motion
## sickness needs to turn off, which is why the duration is a property of the person.
func _glide(surface: Surface, parent: Node3D, local: Transform3D) -> void:
	# Reparented first, keeping the world pose, so the travel is computed inside the frame it is
	# travelling to. Reparenting at the END would teleport the surface on arrival; reparenting
	# without keeping the pose teleports it on departure.
	if parent != null and surface.get_parent() != parent:
		surface.reparent(parent, true)
	var seconds := 0.42 * clampf(studio.ergonomics.motion_scale, 0.0, 2.0)
	if seconds <= 0.01:
		surface.transform = local
		return
	var tween := studio.create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(surface, "transform", local, seconds)


## Lettering is sized once, when a label is built, and then enforced by the rendering server.
## So changing whose eyes it is for means rebuilding the labels -- which is cheap, and is the
## honest consequence of the visibility range being server-side rather than per-frame script.
func _set_text_scale(to: float) -> void:
	studio.ergonomics.text_scale = clampf(to, 0.4, 4.0)
	Ergonomics.current = studio.ergonomics
	for node in studio.find_children("*", "Node3D", true, false):
		if node is Surface:
			(node as Surface).mark_dirty()
	if studio.focus != null and studio.focus.is_focused():
		studio.focus.focus(studio.focus.focused_id)


## Put the screen camera where the mixer is standing, looking at whatever they just summoned.
##
## Focusing moves the gear to the body. On a monitor that is only half the gesture: the body is
## a fixed mix position, so without this you summon a console to a spot in the room and then go
## on watching it from wherever you happened to be orbiting -- usually behind and above it,
## where a wrapped desk reads as four tiers of scaffolding rather than as a desk. The whole
## point of an arc is that it is right from ONE place.
##
## A no-op in AR and VR, where the camera is a head and moving it is not ours to do.
## Swap the focused desk between its paged bank and its full width.
##
## Only the console has two sizes, so this does nothing anywhere else rather than inventing a
## meaning for "expanded" on a tape deck. The re-seat comes free: the desk emits `rebuilt`, and
## the camera is already listening for that.
func _toggle_expanded() -> void:
	if studio.focus == null or not studio.focus.is_focused():
		return
	for surface in studio.focus.surfaces:
		if surface.surface_id != studio.focus.focused_id:
			continue
		var console := surface as ConsoleSurface
		if console != null:
			console.expanded = not console.expanded
		return


## Keep the rig's idea of the frame in step with the actual window.
##
## Resizing changes how much gear fits in view, and gear placed for the old shape is cropped by
## the new one. Cheap enough to redo on every resize: it sets one number and marks the surfaces,
## and a person dragging a window edge is not in the middle of anything precise.
func _follow_viewport_shape() -> void:
	var view := studio.get_viewport()
	if view == null:
		return
	var size := view.get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var aspect := size.x / size.y
	if is_equal_approx(aspect, studio.ergonomics.view_aspect):
		return
	studio.ergonomics.view_aspect = aspect
	if studio.focus != null:
		for surface in studio.focus.surfaces:
			surface.mark_dirty()


## A surface someone's hand caught in SCREEN mode by accident -- the handle that does it is a
## small bar beside whichever control they actually meant to reach, and once its surface fills
## the view the handle is off at the edge of a much bigger picture, nowhere near where they
## would think to look for it (2026-10-11: "escape was not working" trying to get a
## full-screened rack back). Leaves a surface that is in SCREEN mode on purpose -- the timeline
## defaults there -- exactly alone.
## Escape on a keyboard, the menu button or two fists in a headset: let go of what has focus, send
## anything pinned to the face back where it belongs, and sit back down at the desk.
func _on_escape() -> void:
	if studio.focus != null:
		studio.focus.release()
	_release_stray_screens()
	studio.station_host._sit_down()


func _release_stray_screens() -> void:
	for id in studio.mount.mounted_ids():
		if studio.mount.mode_of(id) == Presentation.Mode.SCREEN \
				and studio.mount.mode_of(id) != studio.mount.default_mode_of(id, studio.medium):
			studio.mount.set_mode(id, studio.mount.default_mode_of(id, studio.medium))


## No-op in a headset, where the camera is a head. Kept callable either way so the screenshot
## harness does not have to know which medium it is pointing at.
func frame(target: Vector3, distance: float, yaw: float, pitch: float) -> void:
	if studio.camera == null:
		return
	studio._orbit_target = target
	studio._orbit_distance = distance
	studio._orbit_yaw = yaw
	studio._orbit_pitch = pitch
	if studio.walker != null and not studio.god_mode:
		var eye := target + Basis(Vector3.UP, yaw) * (Basis(Vector3.RIGHT, pitch) * Vector3(0, 0, distance))
		studio.walker.travel_to(eye, target, 0.0)
		return
	_update_camera()


func _update_camera() -> void:
	if studio.walker != null and not studio.god_mode:
		studio.walker._place_camera()
		return
	var offset := Basis(Vector3.UP, studio._orbit_yaw) * (Basis(Vector3.RIGHT, studio._orbit_pitch) * Vector3(0, 0, studio._orbit_distance))
	studio.camera.position = studio._orbit_target + offset
	studio.camera.look_at(studio._orbit_target, Vector3.UP)


## A write bead pulled out (WriteBead.on_pull): its lane shown on the timeline, its track picked, so
## each pass is seen to land there.
func _show_written_lane(track: int, target: String) -> void:
	if studio.timeline != null and is_instance_valid(studio.timeline):
		studio.timeline.pick_track(track)
		studio.timeline.show_lane(target)


## The kit's place on the console's rail (ConsoleSurface.pad_rail), in the items' frame; null with no
## console or no room of items.
func kit_home() -> Variant:
	if studio.console == null or studio.items == null or not studio.console.is_inside_tree() or not studio.items.is_inside_tree():
		return null
	var at := studio.items.global_transform.affine_inverse() * studio.console.global_transform * studio.console.pad_rail()
	return at.orthonormalized()


## This player's pads on real surfaces, the kit's: drawn through the session frame (RoomAnchor), moved
## with the play space when it travels (XRRig.away_from_home), saved on this machine; marked from the
## PADS card, which hangs off the rail under the kit's pads. At a desk there are no hands to mark
## with, and the card says how a desk plays them.
func _build_pads() -> void:
	var kit := studio.items.items.get(KitItem.KIND) as KitItem if studio.items != null else null
	studio.pads = SurfacePads.new()
	studio.pads.name = "SurfacePads"
	studio.pads.hands = studio.medium != Presentation.Medium.SCREEN
	studio.pads.frame = func() -> Transform3D:
		var anchor := studio.room_anchor.global_transform if studio.room_anchor != null else Transform3D.IDENTITY
		return (studio.rig.away_from_home() if studio.rig != null else Transform3D.IDENTITY) * anchor
	studio.pads.eye = func() -> Vector3:
		var eye: Node3D = studio.rig.head if studio.rig != null else studio.camera
		return eye.global_position if eye != null and eye.is_inside_tree() else Vector3.ZERO
	studio.pads.kit = kit
	studio.pads.told.connect(func(text: String) -> void: Session.notice.emit(text))
	# None are drawn at a desk: there is no real surface under a mouse.
	studio.pads.visible = studio.pads.hands
	studio.add_child(studio.pads)
	if kit == null:
		return
	kit.surface = studio.pads if studio.pads.hands else null
	var card := studio.pads.build_card()
	card.transform = Transform3D(Basis(Vector3.RIGHT, -deg_to_rad(SurfacePads.CARD_TILT)), KitItem.CARD_AT)
	kit.add_child(card)
	studio.console.rebuilt.connect(_follow_kit.bind(true))
	_follow_kit(true)


## The kit stood on the rail again wherever the desk now is; and, `retag`, its jack's tag shown again,
## since a new desk may have a new drum track (KitItem.default_sink).
func _follow_kit(retag := false) -> void:
	var kit := studio.items.items.get(KitItem.KIND) as KitItem if studio.items != null else null
	if kit == null:
		return
	var at: Variant = kit_home()
	if at == null:
		return
	if not studio.items.stands(KitItem.KIND):
		studio.items.stand(KitItem.KIND, at)
	elif (at as Transform3D).origin.distance_to(kit.home.origin) > KIT_FOLLOW \
			or not (at as Transform3D).basis.is_equal_approx(kit.home.basis):
		# Carried along with a desk on the move, quietly: it never left home, so nothing is told.
		kit.home = at
		kit.transform = at
	if retag and kit.jack != null and studio.jacks != null:
		kit.jack.show_sink(studio.jacks.sink_of(kit.id))


## The desk's pad `n` (0 to 5, KICK to RIM) struck from the keyboard, as a click on it is: 96, or 64
## with Shift.
func strike_desk_pad(n: int, soft := false) -> void:
	var kit := studio.items.items.get(KitItem.KIND) as KitItem if studio.items != null else null
	if kit == null or not studio.items.stands(KitItem.KIND):
		return
	kit.strike_rail(n, Strike.CLICK_SOFT if soft else Strike.CLICK)
