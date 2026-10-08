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
const PERSONAL_SPACE := 0.6
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


## One other person, drawn: a big blue ghost.
##
## Tall, round and soft, with a pair of heavy-lidded eyes too big for the face -- a friendly
## thing to find leaning over the desk beside you, and impossible to mistake for the hardware.
## A ghost also settles the old problem of a screen participant having no body below the
## head: it never had legs, so nothing is cut off. It floats, it bobs, its hem drifts.
##
## Everyone is the same blue, because the blue is what makes it a ghost. Who it is lives in
## the glow round its edge, its name, its pointer and the rim on what it holds -- all in
## that person's colour.
##
## The origin is their eye. The ghost turns with their yaw only and leans a little with
## their pitch; the pupils do the rest of the looking, which reads better on a face this
## size than tipping the whole body over a fader.
class Avatar extends Node3D:
	const BLUE := Color(0.30, 0.55, 0.98)
	## The whole ghost, scaled about the eye. Modelled at 1.3m; at 0.72 the dome is a hand above a
	## standing person's head and the hem is at desk height, so the gear -- built to real sizes,
	## 55mm channel strips -- reads as gear and the ghost as a large person, not a building.
	const SIZE := 0.72
	## Dome apex above the eye line, and the hem below it, before SIZE.
	const TOP := 0.34
	const HEM := -0.96
	const BELLY := 0.37
	const SEGMENTS := 40
	const SCALLOPS := 6
	## Lid angles: rim height on the eye is sin(angle). Dopey is mostly open, never quite.
	const LID_AWAKE := 0.18
	const LID_SLEEPY := -0.55
	const LID_SHUT := -1.45

	const SKIN_SHADER := """
shader_type spatial;
// Not shadowed, only lit: a smooth body this size self-shadows into stripes (acne) that
// crawl as it sways and read as z-fighting. It has its own glow; it still casts a shadow.
render_mode shadows_disabled;
uniform vec4 body : source_color = vec4(0.42, 0.64, 0.95, 1.0);
uniform vec4 glow : source_color = vec4(1.0);
uniform float glow_amount = 1.0;
uniform float hem_from = 0.0;
uniform float hem_to = -0.96;
uniform float sway = 1.0;
void vertex() {
	// Nothing moves above the eyes; the hem drifts the most.
	float w = clamp((hem_from - VERTEX.y) / (hem_from - hem_to), 0.0, 1.0);
	w = w * w * w * sway;
	float a = atan(VERTEX.x, VERTEX.z);
	VERTEX.xz *= 1.0 + w * 0.06 * sin(TIME * 2.1 + a * 3.0);
	VERTEX.x += w * 0.035 * sin(TIME * 1.3);
	VERTEX.z += w * 0.025 * cos(TIME * 1.1);
}
void fragment() {
	float edge = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	ALBEDO = body.rgb;
	ROUGHNESS = 0.42;
	SPECULAR = 0.45;
	// A soft inner light, so a ghost in a dim corner is still a ghost, and their colour
	// round the silhouette, which is what you see of someone across the room.
	EMISSION = body.rgb * 0.10 + glow.rgb * edge * 0.55 * glow_amount;
}
"""

	var _ghost := Node3D.new()
	var _lean := Node3D.new()
	var _tag := Label3D.new()
	var _caption := Label3D.new()
	var _beam := MeshInstance3D.new()
	var _dot := MeshInstance3D.new()
	var _rim := HoverRim.new()
	var _skin := ShaderMaterial.new()
	## The lids are skin without the edge light: seen edge-on, a lit cap reads as glass.
	var _lid_skin := ShaderMaterial.new()
	var _eye_size := Vector3.ONE
	var _beam_material := StandardMaterial3D.new()
	var _lids: Array[Node3D] = []
	var _pupils: Array[Node3D] = []
	var _pupil_rest: Array[Vector3] = []
	var _arm := Node3D.new()
	var _arm_rest := Basis.IDENTITY
	var _colour := Color.WHITE
	var _close := false
	var _away := false
	var _pose := Transform3D.IDENTITY
	var _pitch := 0.0
	var _lid := LID_AWAKE
	var _blink_in := 2.0
	var _blink := 0.0
	var _phase := randf() * TAU
	var _clock := 0.0
	var placed := false

	func _init() -> void:
		var shader := Shader.new()
		shader.code = SKIN_SHADER
		_skin.shader = shader
		_skin.set_shader_parameter("hem_to", HEM)
		_lid_skin.shader = shader
		_lid_skin.set_shader_parameter("glow_amount", 0.0)
		_lid_skin.set_shader_parameter("sway", 0.0)

		_beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_beam_material.cull_mode = BaseMaterial3D.CULL_DISABLED

		add_child(_ghost)
		_ghost.add_child(_lean)
		_part(body_mesh(), _skin, _lean)
		_build_face()
		_build_arms()

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
		var dot_material := StandardMaterial3D.new()
		dot_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dot_material.no_depth_test = true
		dot_material.render_priority = 9
		_dot.material_override = dot_material
		_dot.top_level = true
		add_child(_dot)
		_rim.name = "Rim"
		add_child(_rim)

	## How wide the ghost is at height y (eye line = 0): a dome on top, a belly that swells
	## below the face and draws in a little toward the hem.
	static func radius_at(y: float) -> float:
		if y >= 0.0:
			var t := clampf(y / TOP, 0.0, 1.0)
			return 0.30 * sqrt(maxf(0.0, 1.0 - t * t))
		var down := clampf(-y / -HEM, 0.0, 1.0)
		var swell := sin(down * PI * 0.8)
		return 0.30 + (BELLY - 0.30) * swell * 1.15 - 0.02 * down * down

	## The ghost's skin, turned on a lathe: one smooth surface from the dome to a scalloped
	## hem, tucked under into a shallow hollow so the hem has thickness from below.
	static func body_mesh() -> ArrayMesh:
		var rings: Array[float] = []
		var count := 28
		for i in count + 1:
			# Denser near the top, where the dome curves fastest.
			var t := float(i) / count
			rings.append(TOP - (TOP - HEM) * (t * t * 0.35 + t * 0.65))
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(0)
		st.add_vertex(Vector3(0, TOP, 0))  # apex
		for y in rings.slice(1):
			var near_hem := clampf((y - (HEM + 0.25)) / -0.25, 0.0, 1.0)
			for s in SEGMENTS:
				var a := TAU * s / SEGMENTS
				var r := radius_at(y)
				var dip := near_hem * near_hem * 0.045 * (0.5 + 0.5 * cos(a * SCALLOPS))
				st.add_vertex(Vector3(sin(a) * r, y - dip, cos(a) * r))
		# Under the hem: curl in and up to a hollow.
		for ring in [[0.88, 0.035], [0.55, 0.09]]:
			for s in SEGMENTS:
				var a := TAU * s / SEGMENTS
				var r: float = radius_at(HEM) * ring[0]
				var dip: float = 0.045 * (0.5 + 0.5 * cos(a * SCALLOPS)) * ring[0]
				st.add_vertex(Vector3(sin(a) * r, HEM - dip + ring[1], cos(a) * r))
		var hollow := 1 + (rings.size() - 1 + 2) * SEGMENTS
		st.add_vertex(Vector3(0, HEM + 0.12, 0))

		for s in SEGMENTS:
			st.add_index(0)
			st.add_index(1 + (s + 1) % SEGMENTS)
			st.add_index(1 + s)
		var bands := rings.size() - 1 + 2
		for b in bands - 1:
			var top_row := 1 + b * SEGMENTS
			var low_row := top_row + SEGMENTS
			for s in SEGMENTS:
				var n := (s + 1) % SEGMENTS
				st.add_index(top_row + s)
				st.add_index(top_row + n)
				st.add_index(low_row + s)
				st.add_index(top_row + n)
				st.add_index(low_row + n)
				st.add_index(low_row + s)
		var last := 1 + (bands - 1) * SEGMENTS
		for s in SEGMENTS:
			st.add_index(last + s)
			st.add_index(last + (s + 1) % SEGMENTS)
			st.add_index(hollow)
		st.generate_normals()
		return st.commit()

	## Two big eyes set close together, high on the face, under lids that never quite open --
	## and pupils that do not quite agree on where to look.
	func _build_face() -> void:
		var white := StandardMaterial3D.new()
		white.albedo_color = Color(0.97, 0.97, 0.95)
		white.roughness = 0.25
		white.emission_enabled = true
		white.emission = Color(0.12, 0.12, 0.12)
		var black := StandardMaterial3D.new()
		black.albedo_color = Color(0.03, 0.03, 0.05)
		black.roughness = 0.15
		black.clearcoat_enabled = true
		var shine := StandardMaterial3D.new()
		shine.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		shine.albedo_color = Color.WHITE

		var eye_y := 0.07
		var size := Vector3(0.155, 0.2, 0.09)
		_eye_size = size
		for side in [-1.0, 1.0]:
			var x: float = side * 0.085
			var z := -sqrt(maxf(0.0, pow(radius_at(eye_y), 2) - x * x)) + 0.035
			var socket := Node3D.new()
			socket.position = Vector3(x, eye_y, z)
			# Facing out of the dome a little, the way eyes on a round face do.
			socket.rotation = Vector3(-0.12, -side * 0.28, 0)
			_lean.add_child(socket)
			var ball := SphereMesh.new()
			ball.radius = 0.5
			ball.height = 1.0
			_part(ball, white, socket).scale = size

			var pupil := Node3D.new()
			# Dopey: a touch low, a touch apart.
			var rest := Vector3(side * 0.016, -0.02, 0)
			pupil.position = rest
			socket.add_child(pupil)
			_pupils.append(pupil)
			_pupil_rest.append(rest)
			var dot := SphereMesh.new()
			dot.radius = 0.5
			dot.height = 1.0
			_part(dot, black, pupil).scale = Vector3(0.062, 0.078, 0.024)
			var glint := SphereMesh.new()
			glint.radius = 0.5
			glint.height = 1.0
			_part(glint, shine, pupil).transform = Transform3D(
					Basis.from_scale(Vector3(0.02, 0.02, 0.008)), Vector3(0.014, 0.018, -0.01))

			# The lid: a cap of ghost over the top of the eye, swung down by _lid.
			var lid := Node3D.new()
			socket.add_child(lid)
			var cap := SphereMesh.new()
			cap.radius = 0.5
			cap.height = 0.5
			cap.is_hemisphere = true
			_part(cap, _lid_skin, lid).scale = size * 1.04
			_lids.append(lid)

		# A small, contented mouth.
		var mouth := SphereMesh.new()
		mouth.radius = 0.5
		mouth.height = 1.0
		var my := -0.12
		var m := _part(mouth, black, _lean)
		m.scale = Vector3(0.11, 0.022, 0.03)
		m.position = Vector3(0, my, -radius_at(my) + 0.008)

	## Two stubby nubs. The right one lifts toward whatever they are pointing at.
	func _build_arms() -> void:
		for side in [-1.0, 1.0]:
			var y := -0.42
			var shoulder := Node3D.new()
			shoulder.position = Vector3(side * (radius_at(y) - 0.04), y, -0.02)
			_lean.add_child(shoulder)
			var nub := CapsuleMesh.new()
			nub.radius = 0.055
			nub.height = 0.22
			var arm := _part(nub, _skin, shoulder)
			arm.position = Vector3(0, -0.09, 0)
			shoulder.rotation = Vector3(0.15, 0, side * 0.75)
			if side > 0:
				_arm = shoulder
				_arm_rest = shoulder.basis

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
		_skin.set_shader_parameter("body", BLUE.lerp(colour, 0.12))
		_lid_skin.set_shader_parameter("body", BLUE.lerp(colour, 0.12).darkened(0.22))
		_skin.set_shader_parameter("glow", colour)
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

	func _process(delta: float) -> void:
		_clock += delta
		# Blinking: every few seconds, quick. A ghost that never blinks is a statue.
		_blink_in -= delta
		if _blink_in <= 0.0:
			_blink = 0.16
			_blink_in = randf_range(2.5, 6.0)
		_blink = maxf(0.0, _blink - delta)
		var want := LID_SLEEPY if _away else LID_AWAKE
		_lid = lerpf(_lid, want, 1.0 - exp(-delta * 3.0))
		var angle := LID_SHUT if _blink > 0.0 else _lid
		for lid in _lids:
			lid.rotation.x = angle
		_place()

	## Yaw from the pose; a slight lean for pitch; the eyes take the rest. And a slow bob,
	## so nobody is ever quite standing still.
	func _place() -> void:
		var basis := _pose.basis.orthonormalized()
		var forward := -basis.z
		_pitch = asin(clampf(forward.y, -1.0, 1.0))
		forward.y = 0.0
		var yaw := atan2(-forward.x, -forward.z) if forward.length() > 0.01 else 0.0
		var bob := sin(_clock * 1.6 + _phase) * 0.018 * SIZE
		_ghost.global_transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * SIZE),
				_pose.origin + Vector3(0, bob, 0))
		# Lean about the belly, not the eye, so the face dips toward the desk.
		var lean := clampf(_pitch, -0.6, 0.6) * 0.3
		_lean.transform = Transform3D(Basis(Vector3.RIGHT, lean), Vector3.ZERO)
		var look := clampf(_pitch, -0.8, 0.8) / 0.8
		var half := _eye_size * 0.5
		for i in _pupils.size():
			var at := _pupil_rest[i] + Vector3(0, look * 0.022, 0)
			# Sat on the surface of the eye wherever it has rolled to, not floating off it.
			var inside := 1.0 - pow(at.x / half.x, 2) - pow(at.y / half.y, 2)
			at.z = -half.z * sqrt(maxf(0.05, inside)) - 0.004
			_pupils[i].position = at
		_tag.global_position = _pose.origin + Vector3(0, TOP * SIZE + 0.16 + bob, 0)
		_caption.global_position = _pose.origin + Vector3(0, TOP * SIZE + 0.09 + bob, 0)

	func set_close(close: bool) -> void:
		if close == _close:
			return
		_close = close
		_ghost.visible = not close
		_tag.visible = not close
		_caption.visible = not close

	## Away: the glow fades and the lids droop. A ghost that has dozed off.
	func set_away(away: bool) -> void:
		if away == _away:
			return
		_away = away
		_skin.set_shader_parameter("glow_amount", 0.25 if away else 1.0)
		_tag.modulate = Color(0.6, 0.6, 0.62) if away else _colour.lightened(0.25)

	## A beam from the tip of their raised nub to the point on MY copy of what they mean.
	func point_at(control: ControlAffordance, at: Vector3, holding: bool) -> void:
		_rim.show_on(control, holding)
		var on := control != null
		_beam.visible = on and not _close
		_dot.visible = on
		if not on:
			_arm.basis = _arm.basis.slerp(_arm_rest, 0.2)
			return
		# Swing the right nub toward the target: its "down" (the way it hangs) becomes the
		# direction of the point.
		var to_target := (_arm.get_parent() as Node3D).global_transform.affine_inverse().basis \
				* (at - _arm.global_position)
		if to_target.length() > 0.01:
			var down := -to_target.normalized()
			var side := down.cross(Vector3.FORWARD if absf(down.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
			var aim := Basis(side, down, side.cross(down).normalized())
			_arm.basis = _arm.basis.slerp(aim.orthonormalized(), 0.25)
		var from := _arm.global_transform * Vector3(0, -0.2, 0)
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
