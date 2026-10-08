class_name Presence
extends Node3D

## Everyone else in the room: where they are, what they are pointing at, what they are holding.
##
## Two directions, one node. OUT: this participant's head and pointer, published to the session
## at PUBLISH_HZ, and every grab a local hand makes, claimed with the host. IN: an avatar for
## each other participant, a beam from them to whatever they are pointing at, their colour round
## anything they hold -- and that control refused to anyone else's hand until they let go.
##
## Lives beside the surfaces and never inside one. The console does not know anyone else is in
## the room, which is the presentation rule (docs/architecture.md); it learns that a fader is
## taken the same way it learns anything, by its affordance saying no.
##
## Pointers travel by CONTROL, not by position. Each participant has the gear where they put it,
## so a hit point in the sender's world is a patch of empty floor in mine. "Kick volume, 2cm up
## the travel" lands on my kick fader wherever my console is -- which is the one they mean.

const PUBLISH_HZ := 20.0
## How quickly an avatar catches up with the newest pose. Poses arrive at 20Hz and frames at 60
## or 90; drawn raw, a head steps three times a second's worth of jitter across a headset.
const FOLLOW_RATE := 14.0
## Closer than this to my own eye and an avatar is hidden: two desktop participants both spawn
## at the mix position, and the inside of somebody's head is not a view of the desk.
const PERSONAL_SPACE := 0.45
## Silent this long and an avatar is drawn as away rather than as a person standing very still.
const STALE_MSEC := 3000

## Whose eyes this participant sees through: the desktop camera, or the headset.
var head_node: Node3D
## Session space. Poses go out relative to it and come back through it, so two headsets that
## each started somewhere different agree where a person is. See core/xr/room_anchor.gd.
var frame: Node3D

var _avatars: Dictionary = {}
var _publish_clock := 0.0
var _by_key: Dictionary = {}
var _scan_msec := -100000
var _claimed: Array[ControlAffordance] = []
var _claim_clock := 0.0
## {interactor: key it has claimed}, so a release names what the grab claimed even if the
## control has been renamed in between -- a track renamed mid-drag.
var _my_claims: Dictionary = {}


## Listening only while in the tree. A studio taken out of the scene -- the suite builds dozens --
## must not go on answering for a session it is no longer part of.
func _enter_tree() -> void:
	Session.roster_changed.connect(_sync_avatars)
	Session.holds_changed.connect(_apply_holds)
	Session.hold_refused.connect(_on_hold_refused)
	Session.role_changed.connect(_on_role_changed)


func _exit_tree() -> void:
	Session.roster_changed.disconnect(_sync_avatars)
	Session.holds_changed.disconnect(_apply_holds)
	Session.hold_refused.disconnect(_on_hold_refused)
	Session.role_changed.disconnect(_on_role_changed)


func _ready() -> void:
	_sync_avatars()


func _physics_process(delta: float) -> void:
	_hook_interactors()
	_publish_clock += delta
	if _publish_clock >= 1.0 / PUBLISH_HZ:
		_publish_clock = 0.0
		_publish()
	# Controls are rebuilt under a hold -- a bank moves, a rack page turns -- and a new fader
	# with the held name has to be told it is taken just as the old one was.
	if not Session.holds.is_empty():
		_claim_clock += delta
		if _claim_clock > 0.5:
			_claim_clock = 0.0
			_apply_holds()


func _process(delta: float) -> void:
	var eye := head_node.global_position if head_node != null else Vector3(0, 1e6, 0)
	var weight := 1.0 - exp(-delta * FOLLOW_RATE)
	for id in _avatars:
		var avatar: Avatar = _avatars[id]
		var p = Session.participants.get(id)
		if p == null:
			continue
		# Nobody is drawn until they have been heard from: a participant with no pose yet --
		# or a headless host that will never send one -- would stand at the session origin.
		avatar.visible = p.heard_msec > 0
		if not avatar.visible:
			continue
		var target := _from_session(p.head)
		if not avatar.placed:
			avatar.snap(target)
		avatar.follow(target, weight)
		avatar.set_close(avatar.head_position().distance_to(eye) < PERSONAL_SPACE)
		avatar.set_away(p.heard_msec > 0 and Time.get_ticks_msec() - p.heard_msec > STALE_MSEC)
		var held_key := _key_held_by(id)
		var key: String = held_key if not held_key.is_empty() else p.pointing_at
		var control := find_control(key)
		if control != null:
			avatar.point_at(control, control.global_transform * p.pointing_local, not held_key.is_empty())
		else:
			avatar.point_at(null, Vector3.ZERO, false)
		avatar.set_caption(_caption(p, held_key))


# --- out ----------------------------------------------------------------------------------

func _publish() -> void:
	# A headless process is a host in a rack: there is nobody at it, and its "head" is a camera
	# no one is looking through, parked at the mix position with a cursor stuck in a corner.
	# Published, it stood an avatar in the middle of everybody's desk pointing at the timeline.
	if head_node == null or DisplayServer.get_name() == "headless":
		return
	var key := ""
	var local := Vector3.ZERO
	for hand in get_tree().get_nodes_in_group(Interactor.GROUP):
		var interactor := hand as Interactor
		if interactor == null or not interactor.is_inside_tree():
			continue
		var control: ControlAffordance = interactor.held if interactor.held != null else interactor.hovered
		if control == null or not is_instance_valid(control):
			continue
		key = control.network_key()
		local = control.to_local(interactor.hover_point) if interactor.hovered == control \
				else Vector3.ZERO
		break
	Session.publish_presence(_to_session(head_node.global_transform), key, local)


func _hook_interactors() -> void:
	for hand in get_tree().get_nodes_in_group(Interactor.GROUP):
		var interactor := hand as Interactor
		if interactor == null or interactor.grabbed.is_connected(_on_grabbed):
			continue
		interactor.grabbed.connect(_on_grabbed.bind(interactor))
		interactor.released.connect(_on_released.bind(interactor))


func _on_grabbed(control: ControlAffordance, interactor: Interactor) -> void:
	var key := control.network_key()
	_my_claims[interactor] = key
	Session.claim_hold(key)


func _on_released(_control: ControlAffordance, interactor: Interactor) -> void:
	var key: String = _my_claims.get(interactor, "")
	_my_claims.erase(interactor)
	Session.release_hold(key)


## Somebody else's hand was there first. Ours opens, and whatever we did in the moment before
## the host's answer came back is overwritten by theirs as the mix replicates.
func _on_hold_refused(key: String, holder: int) -> void:
	for interactor in _my_claims.keys():
		if _my_claims[interactor] == key and is_instance_valid(interactor):
			_my_claims.erase(interactor)
			interactor.let_go()
	Session.notice.emit("%s already has %s." % [Session.name_of(holder), key.to_lower()])


# --- in -----------------------------------------------------------------------------------

func _sync_avatars() -> void:
	for id in _avatars.keys():
		if not Session.participants.has(id) or id == Session.local_peer_id:
			_avatars[id].queue_free()
			_avatars.erase(id)
	for id in Session.participants:
		if id == Session.local_peer_id:
			continue
		var p = Session.participants[id]
		if not _avatars.has(id):
			var avatar := Avatar.new()
			avatar.name = "Avatar%d" % id
			add_child(avatar)
			_avatars[id] = avatar
		_avatars[id].dress(p.display_name, p.colour, p.medium, id == 1)


func _on_role_changed() -> void:
	_my_claims.clear()
	_apply_holds()
	_sync_avatars()


## Every control another participant holds is refused to this participant's hands, and every
## control that was and no longer is, is given back.
func _apply_holds() -> void:
	var now_claimed: Array[ControlAffordance] = []
	for key in Session.holds:
		var holder: int = Session.holds[key]
		if holder == Session.local_peer_id:
			continue
		var control := find_control(key)
		if control == null:
			continue
		control.claimed_by = Session.participants.get(holder)
		now_claimed.append(control)
	for control in _claimed:
		if is_instance_valid(control) and not control in now_claimed:
			control.claimed_by = null
	_claimed = now_claimed


func _key_held_by(peer_id: int) -> String:
	for key in Session.holds:
		if Session.holds[key] == peer_id:
			return key
	return ""


## The control on THIS desk that goes by `key`. Cached, and the cache is distrusted on every
## read, because the strip that was "KICK" a moment ago is "SNARE" after a bank change.
func find_control(key: String) -> ControlAffordance:
	if key.is_empty():
		return null
	# Untyped until checked: the cache can hold a control freed since it was filled, and a
	# typed variable refuses even to hold one long enough to ask.
	var cached = _by_key.get(key)
	if cached != null and is_instance_valid(cached) and cached.is_inside_tree() \
			and cached.network_key() == key:
		return cached as ControlAffordance
	# Rescanned at most four times a second. A key nobody here has -- a rack page this
	# participant has not opened -- would otherwise rescan the whole room every frame.
	var now := Time.get_ticks_msec()
	if now - _scan_msec < 250:
		return null
	_scan_msec = now
	_by_key.clear()
	for node in get_tree().get_nodes_in_group(ControlAffordance.GROUP):
		var control := node as ControlAffordance
		if control == null or not control.is_visible_in_tree():
			continue
		var k := control.network_key()
		if not _by_key.has(k):
			_by_key[k] = control
	var found: ControlAffordance = _by_key.get(key)
	return found


func _caption(p, held_key: String) -> String:
	var role := "HOST" if p.peer_id == 1 else "GUEST"
	var medium: String = ["SCREEN", "AR", "VR"][clampi(p.medium, 0, 2)]
	if not held_key.is_empty():
		return "HOLDING  %s" % held_key
	return "%s  ·  %s" % [role, medium]


func _to_session(world: Transform3D) -> Transform3D:
	if frame == null:
		return world
	return frame.global_transform.affine_inverse() * world


func _from_session(session: Transform3D) -> Transform3D:
	if frame == null:
		return session
	return frame.global_transform * session


## One other person, drawn.
##
## A head and shoulders and nothing below: a screen participant has no tracked body, and
## inventing legs for a camera that flies through walls in god mode would be a lie about where
## they are. The visor band runs all the way round so the colour reads from behind, which is
## the side you see of somebody leaning over the desk next to you.
class Avatar extends Node3D:
	var _head := Node3D.new()
	var _body := Node3D.new()
	var _tag := Label3D.new()
	var _caption := Label3D.new()
	var _beam := MeshInstance3D.new()
	var _dot := MeshInstance3D.new()
	var _rim := HoverRim.new()
	var _glow := StandardMaterial3D.new()
	var _beam_material := StandardMaterial3D.new()
	var _shell := StandardMaterial3D.new()
	var _colour := Color.WHITE
	var _close := false
	var _away := false
	var _pose := Transform3D.IDENTITY
	var placed := false

	func _init() -> void:
		_shell.albedo_color = Color(0.20, 0.205, 0.22)
		_shell.metallic = 0.35
		_shell.roughness = 0.38
		_shell.clearcoat_enabled = true
		_shell.clearcoat = 0.6
		_shell.rim_enabled = true
		_shell.rim = 0.8
		_shell.rim_tint = 0.3

		_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_beam_material.cull_mode = BaseMaterial3D.CULL_DISABLED

		add_child(_body)
		add_child(_head)

		var skull := SphereMesh.new()
		skull.radius = 0.1
		skull.height = 0.225
		_part(skull, _shell, _head)
		var band := CylinderMesh.new()
		band.top_radius = 0.1025
		band.bottom_radius = 0.1015
		band.height = 0.042
		_part(band, _glow, _head).position = Vector3(0, 0.008, 0)
		# The lens: the band is the colour, this says which way they are facing.
		var lens := BoxMesh.new()
		lens.size = Vector3(0.13, 0.046, 0.03)
		_part(lens, _glow, _head).position = Vector3(0, 0.008, -0.09)

		var neck := CylinderMesh.new()
		neck.top_radius = 0.038
		neck.bottom_radius = 0.05
		neck.height = 0.07
		_part(neck, _shell, _body).position = Vector3(0, -0.13, 0.008)
		var collar := TorusMesh.new()
		collar.inner_radius = 0.05
		collar.outer_radius = 0.064
		_part(collar, _glow, _body).position = Vector3(0, -0.165, 0.008)
		# Shoulders: one capsule lying across, so the silhouette says "person" from any side
		# before the colour has said who.
		var yoke := CapsuleMesh.new()
		yoke.radius = 0.056
		yoke.height = 0.42
		var shoulders := _part(yoke, _shell, _body)
		shoulders.rotation = Vector3(0, 0, PI / 2.0)
		shoulders.position = Vector3(0, -0.215, 0.015)
		shoulders.scale = Vector3(1.0, 1.0, 0.7)
		# A chest that tapers to a lit hem and stops: a bust floating where the person is, not
		# a body with its legs cut off. The hem is what makes the stop read as meant.
		var chest := CylinderMesh.new()
		chest.top_radius = 0.165
		chest.bottom_radius = 0.10
		chest.height = 0.25
		var torso := _part(chest, _shell, _body)
		torso.scale = Vector3(1.0, 1.0, 0.56)
		torso.position = Vector3(0, -0.33, 0.015)
		var hem := TorusMesh.new()
		hem.inner_radius = 0.094
		hem.outer_radius = 0.108
		var hem_node := _part(hem, _glow, _body)
		hem_node.scale = Vector3(1.0, 1.0, 0.56)
		hem_node.position = Vector3(0, -0.455, 0.015)
		# Their colour down the spine and across the chest, for the person behind and the
		# person in front. Laid on the chest's slope.
		var slope := atan2((0.165 - 0.10) * 0.56, 0.25)
		for side in [-1.0, 1.0]:
			var stripe := BoxMesh.new()
			stripe.size = Vector3(0.026, 0.16, 0.006)
			var s_node := _part(stripe, _glow, _body)
			s_node.position = Vector3(0, -0.34, 0.015 + side * 0.074)
			s_node.rotation = Vector3(side * slope, 0, 0)

		for label in [_tag, _caption]:
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = true
			label.render_priority = 5
			label.outline_render_priority = 4
			label.outline_modulate = Color(0, 0, 0, 0.85)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.double_sided = true
			add_child(label)
		_tag.font_size = 64
		_tag.outline_size = 14
		_tag.pixel_size = 0.0011
		_caption.font_size = 36
		_caption.outline_size = 10
		_caption.pixel_size = 0.0011
		_caption.modulate = Color(0.82, 0.85, 0.9)

		var rod := CylinderMesh.new()
		rod.top_radius = 0.0022
		rod.bottom_radius = 0.0022
		rod.height = 1.0
		rod.radial_segments = 6
		rod.rings = 1
		_beam.mesh = rod
		_beam.material_override = _beam_material
		_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_beam.top_level = true
		add_child(_beam)
		var bead := SphereMesh.new()
		bead.radius = 0.008
		bead.height = 0.016
		_dot.mesh = bead
		var dot_material := _glow.duplicate() as StandardMaterial3D
		dot_material.no_depth_test = true
		dot_material.render_priority = 9
		_dot.material_override = dot_material
		_dot.top_level = true
		add_child(_dot)
		_rim.name = "Rim"
		add_child(_rim)

	func _part(mesh: Mesh, material: Material, parent: Node3D) -> MeshInstance3D:
		var m := MeshInstance3D.new()
		m.mesh = mesh
		m.material_override = material
		parent.add_child(m)
		return m

	func dress(display_name: String, colour: Color, _medium: int, _is_host: bool) -> void:
		_colour = colour
		_tag.text = display_name
		_tag.modulate = colour.lightened(0.25)
		_glow.albedo_color = colour
		(_dot.material_override as StandardMaterial3D).albedo_color = colour.lightened(0.3)
		_beam_material.albedo_color = Color(colour, 0.55)
		_rim.tint = colour

	func set_caption(text: String) -> void:
		if _caption.text != text:
			_caption.text = text

	func snap(pose: Transform3D) -> void:
		placed = true
		_pose = pose
		_place()

	func follow(pose: Transform3D, weight: float) -> void:
		_pose = _pose.interpolate_with(pose, weight)
		_place()

	func head_position() -> Vector3:
		return _pose.origin

	## The head takes the whole pose; the body only its yaw, because a person looking down at
	## a fader bends their neck, not their spine.
	func _place() -> void:
		_head.global_transform = _pose.orthonormalized()
		var forward := -_pose.basis.z
		forward.y = 0.0
		var yaw := atan2(-forward.x, -forward.z) if forward.length() > 0.01 else 0.0
		_body.global_transform = Transform3D(Basis(Vector3.UP, yaw), _pose.origin)
		_tag.global_position = _pose.origin + Vector3(0, 0.23, 0)
		_caption.global_position = _pose.origin + Vector3(0, 0.165, 0)

	func set_close(close: bool) -> void:
		if close == _close:
			return
		_close = close
		_head.visible = not close
		_body.visible = not close
		_tag.visible = not close
		_caption.visible = not close

	func set_away(away: bool) -> void:
		if away == _away:
			return
		_away = away
		_glow.albedo_color = _colour.darkened(0.6) if away else _colour
		_tag.modulate = Color(0.6, 0.6, 0.62) if away else _colour.lightened(0.25)

	## A beam from where their hand would be to the point on MY copy of what they mean.
	func point_at(control: ControlAffordance, at: Vector3, holding: bool) -> void:
		_rim.show_on(control, holding)
		var on := control != null
		# Not from inside my own head: someone standing where I stand points from beside my eye,
		# and a beam from there is a rod across the whole view. The rim and the dot still say
		# what they mean.
		_beam.visible = on and not _close
		_dot.visible = on
		if not on:
			return
		# Below and to the right of the eye: a mouse hand, roughly. From the eye itself the
		# beam would be a dot to anyone standing behind them, and a pointer is read from the
		# side.
		var from := _pose.origin + _pose.basis.orthonormalized() * Vector3(0.16, -0.24, -0.12)
		var span := at - from
		var length := span.length()
		_dot.global_position = at
		if length < 0.01 or _close:
			_beam.visible = false
			return
		var y := span / length
		var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
		var z := x.cross(y).normalized()
		_beam.global_transform = Transform3D(Basis(x, y * length, z), from + span * 0.5)
		_beam_material.albedo_color = Color(_colour, 0.8 if holding else 0.45)
		_dot.global_position = at
