class_name HandSkeleton
extends Node3D

## A tracked bare hand, drawn from its joints: a bead at every knuckle and a thin bone between
## them, so you can see the headset knows where each finger is before you reach for a fader with
## one. No hand model ships with the project, and an honest stick hand reads better than a
## generic glove that does not quite line up with your own fingers. Translucent, because in
## passthrough your real hand is right there behind it and a solid one would hide it.
##
## The index fingertip is lit while it is touching something (`touching`), which is the feedback
## a fingertip has instead of a click.
##
## Parented to the XROrigin3D, whose space the joints are reported in. Hidden whenever the hand
## is not tracked -- a controller in it, or out of view.
##
## `wrist` rides the wrist joint, for what is worn there: the player's own keys' jack and, up the
## arm from it, the socket that takes out whatever goes into them (docs/spatial_loop.md slice 6),
## and on the chord hand its own jack, MY CHORDS (part two, slice 33), down onto the back of the
## hand beside MY KEYS; all pressed by the other hand. They are hidden with the hand.
##
## While the hand's fingertips play notes (docs/spatial_loop.md slice 8), each fingertip is
## lettered with the note it plays, grown while pinched, and the chord over the palm (`letter`).

@export var tracker_name: StringName = &"/user/hand_tracker/right"
## Set by the rig from the hand's PokeInteractor each frame.
var touching := false
## On the wrist joint while the hand is tracked: its back, facing up out of the hand (-Z out).
var wrist: Node3D

const JOINTS := XRHandTracker.HAND_JOINT_MAX
## Every finger as a chain from the wrist out: the bones are the links between neighbours.
const CHAINS := [
	[XRHandTracker.HAND_JOINT_WRIST, XRHandTracker.HAND_JOINT_THUMB_METACARPAL,
			XRHandTracker.HAND_JOINT_THUMB_PHALANX_PROXIMAL, XRHandTracker.HAND_JOINT_THUMB_PHALANX_DISTAL,
			XRHandTracker.HAND_JOINT_THUMB_TIP],
	[XRHandTracker.HAND_JOINT_WRIST, 6, 7, 8, 9, 10],
	[XRHandTracker.HAND_JOINT_WRIST, 11, 12, 13, 14, 15],
	[XRHandTracker.HAND_JOINT_WRIST, 16, 17, 18, 19, 20],
	[XRHandTracker.HAND_JOINT_WRIST, 21, 22, 23, 24, 25],
]
const BONE_RADIUS := 0.0035
const COLOUR := Color(0.78, 0.86, 1.0, 0.38)
const TOUCH_COLOUR := Color(1.0, 0.72, 0.3, 0.9)

var _beads: MultiMeshInstance3D
var _bones: MultiMeshInstance3D
var _bone_pairs: Array = []
var _tip: MeshInstance3D
var _tip_material: StandardMaterial3D
## The fingertips' notes, index to little, and the chord over the palm: made at the first
## `letter`, hidden with no words.
var _letters: Array[Label3D] = []
var _chord: Label3D


func _ready() -> void:
	for chain in CHAINS:
		for i in chain.size() - 1:
			_bone_pairs.append([chain[i], chain[i + 1]])
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 10
	sphere.rings = 6
	_beads = _multi("Joints", sphere, JOINTS)
	var rod := CylinderMesh.new()
	rod.top_radius = BONE_RADIUS
	rod.bottom_radius = BONE_RADIUS
	rod.height = 1.0
	rod.radial_segments = 6
	rod.rings = 1
	_bones = _multi("Bones", rod, _bone_pairs.size())

	_tip = MeshInstance3D.new()
	_tip.name = "Fingertip"
	var tip_mesh := SphereMesh.new()
	tip_mesh.radius = 0.0065
	tip_mesh.height = 0.013
	_tip.mesh = tip_mesh
	_tip_material = _material(COLOUR)
	_tip.material_override = _tip_material
	_quiet(_tip)
	add_child(_tip)
	wrist = Node3D.new()
	wrist.name = "Wrist"
	add_child(wrist)
	visible = false


func _process(_delta: float) -> void:
	show_hand(XRServer.get_tracker(tracker_name) as XRHandTracker)


## Lay the beads and bones on `hand`'s joints; hidden if it has none.
func show_hand(hand: XRHandTracker) -> void:
	if hand == null or not hand.has_tracking_data:
		visible = false
		return
	visible = true
	var valid := XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID
	var at: Array[Vector3] = []
	var ok: Array[bool] = []
	for j in JOINTS:
		at.append(hand.get_hand_joint_transform(j).origin)
		ok.append(hand.get_hand_joint_flags(j) & valid != 0)
	var gone := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO)
	for j in JOINTS:
		var r := clampf(hand.get_hand_joint_radius(j), 0.004, 0.012) * 0.75
		_beads.multimesh.set_instance_transform(j,
				Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * r), at[j]) if ok[j] else gone)
	for b in _bone_pairs.size():
		var a: int = _bone_pairs[b][0]
		var z: int = _bone_pairs[b][1]
		if not ok[a] or not ok[z] or at[a].distance_to(at[z]) < 0.001:
			_bones.multimesh.set_instance_transform(b, gone)
			continue
		_bones.multimesh.set_instance_transform(b, bone(at[a], at[z]))
	var w := XRHandTracker.HAND_JOINT_WRIST
	if ok[w]:
		wrist.transform = wrist_mount(hand.get_hand_joint_transform(w))
	for f in _letters.size():
		var j: int = HandPose.TIPS[f]
		_letters[f].position = at[j] + Vector3.UP * LETTER_ABOVE
	if _chord != null:
		_chord.position = at[XRHandTracker.HAND_JOINT_PALM] + Vector3.UP * CHORD_ABOVE
	var tip := XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP
	_tip.visible = ok[tip]
	_tip.position = at[tip]
	_tip_material.albedo_color = TOUCH_COLOUR if touching else COLOUR


## How far over a fingertip its note is lettered, and over the palm the chord (m).
const LETTER_ABOVE := 0.018
const CHORD_ABOVE := 0.06


## What each finger plays, index to little, the chord, and which are pinched (HandPose's mask):
## lettered at the fingertips, a pinched one grown, and over the palm. Empty names hide them.
func letter(names: PackedStringArray, chord: String, pinched := 0) -> void:
	if _letters.is_empty():
		if names.is_empty():
			return
		for f in 4:
			_letters.append(letter_label(36))
			add_child(_letters[-1])
		_chord = letter_label(48)
		add_child(_chord)
	for f in _letters.size():
		var l := _letters[f]
		l.visible = f < names.size() and names[f] != ""
		if l.visible:
			l.text = names[f]
		l.scale = Vector3.ONE * (1.5 if pinched & HandPose.FINGER_BITS[f] else 1.0)
	_chord.visible = chord != ""
	_chord.text = chord


## A fingertip's or a chord's name, `font_size` at HandSkeleton's scale: billboarded, drawn over the
## hand it names, only in your own eyes, and hidden until it is given words. Not yet in the tree.
## A controller's lettering (FingertipNotes) is made of the same.
static func letter_label(font_size: int) -> Label3D:
	var l := Label3D.new()
	l.font_size = font_size
	l.pixel_size = 0.0002
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Over the hand they name, whatever of it is nearer.
	l.no_depth_test = true
	l.render_priority = 10
	l.outline_render_priority = 9
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.modulate = Color(0.98, 0.96, 0.9)
	l.visible = false
	Lettering.range_to_legibility(l)
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.layers = Mirror.NOT_REFLECTED
	return l


## Where a thing worn on the wrist sits, from the wrist joint's pose: a little up its back (the
## joint's +Y is the back of the hand), turned so its -Z faces out of the back.
static func wrist_mount(joint: Transform3D) -> Transform3D:
	var basis := joint.basis.orthonormalized()
	var up := basis.y
	var along := -basis.z
	var turned := Basis.looking_at(up, along if absf(up.dot(along)) < 0.95 else basis.x)
	return Transform3D(turned, joint.origin + up * 0.02)


## A unit-high rod (standing along Y) stretched from `a` to `b`.
static func bone(a: Vector3, b: Vector3) -> Transform3D:
	var along := b - a
	var y := along.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	return Transform3D(Basis(x, y * along.length(), z), (a + b) * 0.5)


func _multi(node_name: String, mesh: Mesh, count: int) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = count
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = multi
	node.material_override = _material(COLOUR)
	_quiet(node)
	add_child(node)
	return node


static func _material(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = colour
	m.no_depth_test = false
	return m


## Only in your own eyes: no shadow on the desk, and not in the mirrors, which show your ghost.
static func _quiet(node: GeometryInstance3D) -> void:
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.layers = Mirror.NOT_REFLECTED
