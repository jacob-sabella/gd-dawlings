class_name Glove
extends Node3D

## A floating cartoon glove: no arm, no wrist, just a hand that goes where it is sent and
## overshoots a little getting there.
##
## Everything about it is a spring. Where it is sent (`target`) it flies to, underdamped, so it
## lands with a bounce. How it is squashed (`poke`) rings out the same way: a grab is a squash,
## a let-go a stretch, and both wobble before they settle. Its fingers curl on springs of their
## own toward a pose: open, pointing (the index stays out), or gripping. And it stretches along
## its own length while it is moving fast, which is most of what makes a thing look thrown.
##
## Modelled pointing down -Z, palm down (-Y): so a right hand's thumb is toward -X and a
## left's toward +X. `top_level`, so it flies in world space however its owner is posed.
##
## Playing fingertip notes (docs/spatial_loop.md slice 8) it says which fingers the thumb is
## pinching (`pinched`, HandPose's mask): each of those curls in to meet the thumb, and the thumb
## comes across to them. A glove that plays is lettered (`make_letters`, `letter`): each fingertip
## with the note it plays, grown while it is pinched, and the chord over the back of the hand.
##
## Holding a chord shape (docs/spatial_loop.md part two, slice 32; ChordHand) it holds up the
## digits in `held_up` (HandPose.extended's mask, the thumb its THUMB bit) and curls the rest in
## (Pose.SHAPE), and says the chord over its fingertips (`say`): `IV · F`.

enum Pose { OPEN, POINT, GRIP, SHAPE }

## Palm-to-fingertip length in metres at scale 1.
const LENGTH := 0.15
## Stiffness and damping of the flight. Damping ratio ~0.4: one clear overshoot, a small second.
const STIFFNESS := 130.0
const DAMPING := 9.0
## The squash spring: stiffer and a touch less damped, so a grab reads as a "boing".
const SQUASH_STIFFNESS := 260.0
const SQUASH_DAMPING := 10.0
const CURL_RATE := 18.0
## Integration step. Fixed, so a slow frame cannot fling it through the wall.
const STEP := 1.0 / 120.0

const WHITE := Color(0.97, 0.97, 0.95)

## Where it is going. The basis is the attitude it should arrive at; its scale is ignored.
var target := Transform3D.IDENTITY
var pose := Pose.OPEN
## The fingers the thumb is pinching (HandPose.INDEX, MIDDLE, RING, LITTLE): each curls in to meet
## it, whatever the pose.
var pinched := 0
## The digits held out in Pose.SHAPE, as HandPose.extended's mask: the rest are curled in.
var held_up := 0
## Its overall size; 1 is a glove for a ghost.
var size := 1.0
## -1 for a left hand.
var side := 1.0

var velocity := Vector3.ZERO
## Positive stretches along the fingers, negative squashes.
var squash := 0.0
var _squash_speed := 0.0
var _curls: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
## Index, middle, ring, little, then the thumb: the knuckle each curls about.
var _knuckles: Array[Node3D] = []
var _palm := Node3D.new()
var _cuff_material := StandardMaterial3D.new()
var _cloth := StandardMaterial3D.new()
var _clock := randf() * TAU
var _placed := false
## The fingertips' letters, index to little, and the chord's over the hand; empty until
## `make_letters`.
var _tip_letters: Array[Label3D] = []
var _chord_letter: Label3D
## What it says over its fingertips (`say`), made the first time.
var _words: Label3D
var _lengths: Array[float] = []


func _init(hand_side := 1.0) -> void:
	side = hand_side
	top_level = true
	add_child(_palm)
	var cloth := _cloth
	cloth.albedo_color = WHITE
	cloth.roughness = 0.62
	cloth.rim_enabled = true
	cloth.rim = 0.35
	cloth.rim_tint = 0.2
	_cuff_material.albedo_color = Color(0.3, 0.55, 0.98)
	_cuff_material.roughness = 0.45

	# The palm: a puffy, flattened ball.
	var palm := SphereMesh.new()
	palm.radius = 0.045
	palm.height = 0.09
	palm.radial_segments = 20
	palm.rings = 10
	_part(palm, cloth, _palm).scale = Vector3(1.0, 0.62, 0.95)

	# Four fat fingers off the front of it, a little splayed, the little one shortest.
	var lengths: Array[float] = [0.072, 0.078, 0.072, 0.06]
	for i in 4:
		var across := -(0.0285 - i * 0.019) * side
		_finger(Vector3(across, 0.004, -0.03), lengths[i], (1.5 - i) * 0.07 * side, 0.0, cloth)
	# The thumb, round the side and forward, lying across under the palm when it curls.
	_finger(Vector3(-side * 0.04, -0.006, 0.0), 0.06, side * 0.95, 0.35, cloth)

	# A flared cuff at the back, rolled at its open end: the one bit in their colour.
	var bell := CylinderMesh.new()
	bell.top_radius = 0.026
	bell.bottom_radius = 0.04
	bell.height = 0.04
	bell.radial_segments = 20
	bell.rings = 1
	var flare := _part(bell, _cuff_material, _palm)
	flare.rotation = Vector3(PI * 0.5, 0, 0)
	flare.position = Vector3(0, 0, 0.052)
	var rim := TorusMesh.new()
	rim.inner_radius = 0.033
	rim.outer_radius = 0.051
	rim.rings = 24
	rim.ring_segments = 10
	var roll := _part(rim, _cuff_material, _palm)
	roll.rotation = Vector3(PI * 0.5, 0, 0)
	roll.position = Vector3(0, 0, 0.074)


func _finger(root: Vector3, length: float, splay: float, droop: float, cloth: Material) -> void:
	var knuckle := Node3D.new()
	knuckle.position = root
	knuckle.rotation = Vector3(-droop, splay, 0)
	_palm.add_child(knuckle)
	var bone := CapsuleMesh.new()
	bone.radius = 0.0145 if length > 0.065 else 0.0135
	bone.height = length
	bone.radial_segments = 12
	bone.rings = 4
	var finger := _part(bone, cloth, knuckle)
	finger.rotation = Vector3(PI * 0.5, 0, 0)
	finger.position = Vector3(0, 0, -length * 0.5 + bone.radius)
	_knuckles.append(knuckle)
	_lengths.append(length)


func _part(mesh: Mesh, material: Material, parent: Node3D) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = material
	parent.add_child(m)
	return m


func set_colour(colour: Color) -> void:
	_cuff_material.albedo_color = colour


## What the glove itself is made of: white cloth unless a look says otherwise.
func set_cloth(colour: Color, metallic := 0.0) -> void:
	_cloth.albedo_color = colour
	_cloth.metallic = metallic
	_cloth.roughness = 0.3 if metallic > 0.0 else 0.62


## Kick the squash spring: negative squashes (a grab), positive stretches (a let-go, a hop).
func poke(amount: float) -> void:
	_squash_speed += amount * 22.0


## Jump straight to the target, nothing in flight.
func snap() -> void:
	_placed = true
	velocity = Vector3.ZERO
	global_transform = Transform3D(target.basis.orthonormalized().scaled(Vector3.ONE * size),
			target.origin)


## Where the index fingertip is from the glove's centre, in its own frame, at its size.
func tip_offset() -> Vector3:
	return Vector3(-0.04 * side, 0.0, -0.108) * size


## Where the index fingertip is: where a beam comes from.
func fingertip() -> Vector3:
	return global_transform * Vector3(-0.04 * side, 0.0, -0.108)


func _process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	if not _placed:
		snap()
	_clock += delta
	var at := global_position
	var left := minf(delta, 0.1)
	while left > 0.0:
		var dt := minf(STEP, left)
		left -= dt
		velocity += ((target.origin - at) * STIFFNESS - velocity * DAMPING) * dt
		at += velocity * dt
		_squash_speed += (-squash * SQUASH_STIFFNESS - _squash_speed * SQUASH_DAMPING) * dt
		squash += _squash_speed * dt
	# Turning is eased, not sprung: a hand that overshoots its angle looks broken, not bouncy.
	var turned := Quaternion(global_basis.orthonormalized()).slerp(
			Quaternion(target.basis.orthonormalized()), 1.0 - exp(-delta * 14.0))
	var basis := Basis(turned)
	# Stretched along the fingers by speed, and by the squash spring; puffed out across to keep
	# its volume, which is what sells a squash as soft rather than shrunk.
	var stretch := clampf(squash + velocity.length() * 0.05, -0.45, 0.6)
	var across := 1.0 / sqrt(maxf(0.3, 1.0 + stretch))
	basis = basis * Basis.from_scale(Vector3(across, across, 1.0 + stretch) * size)
	global_transform = Transform3D(basis, at)
	_curl(delta)


func _curl(delta: float) -> void:
	var want: Array[float]
	match pose:
		Pose.GRIP:
			want = [1.25, 1.3, 1.3, 1.25, 0.7]
		Pose.POINT:
			want = [0.0, 1.35, 1.4, 1.35, 0.6]
		Pose.SHAPE:
			# Held out straight, or curled in tight; the thumb out to the side or across the palm.
			want = [0.0, 0.0, 0.0, 0.0, 0.0]
			for i in 4:
				want[i] = 0.0 if held_up & HandPose.FINGER_BITS[i] else 1.4
			want[4] = 0.0 if held_up & HandPose.THUMB else SHAPE_THUMB
		_:
			# Relaxed, and never quite still: the fingers drum a little.
			want = [0.2, 0.25, 0.3, 0.35, 0.1]
			for i in 4:
				want[i] += sin(_clock * 3.1 + i * 0.9) * 0.08
	if pinched != 0:
		# Pinched fingers bend in to the thumb, and the thumb comes across under them to meet them.
		for i in 4:
			if pinched & HandPose.FINGER_BITS[i]:
				want[i] = PINCH_CURL
		want[4] = PINCH_THUMB
	var weight := 1.0 - exp(-delta * CURL_RATE)
	for i in _knuckles.size():
		_curls[i] = lerpf(_curls[i], want[i], weight)
		var k := _knuckles[i]
		if i < 4:
			k.rotation.x = -_curls[i]
		else:
			# The thumb folds in across the palm.
			k.rotation.y = side * (0.95 - _curls[i] * 0.9)


## How far a pinched finger curls, and the thumb as it meets it: in under the palm, short of a fist.
const PINCH_CURL := 0.95
const PINCH_THUMB := 0.85
## The thumb tucked in a chord shape: past straight ahead (a curl of 0.95 / 0.9 swings it to the
## fingers' line) and on across the palm, so a shape that does not hold it up shows it folded away,
## not standing beside the fingers as a fifth digit.
const SHAPE_THUMB := 1.65
## The fingertips' letters' size, and how much a pinched one grows.
const LETTER_SIZE := 44
const LETTER_PIXEL := 0.0003
const PINCHED_GROWS := 1.5


## Letters for each fingertip and the chord, for a glove that plays: hidden until `letter` gives
## them words. Each rides its finger, so it curls in with it.
func make_letters() -> void:
	if not _tip_letters.is_empty():
		return
	for i in 4:
		var l := _letter_label(LETTER_SIZE)
		l.position = Vector3(0, 0.012, -_lengths[i] - 0.022)
		_knuckles[i].add_child(l)
		_tip_letters.append(l)
	_chord_letter = _letter_label(LETTER_SIZE + 12)
	_chord_letter.position = Vector3(0, 0.05, 0.01)
	_palm.add_child(_chord_letter)


func _letter_label(font_size: int) -> Label3D:
	var l := Label3D.new()
	l.font_size = font_size
	l.pixel_size = LETTER_PIXEL
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Over the hand they name, whatever of it is nearer.
	l.no_depth_test = true
	l.render_priority = 10
	l.outline_render_priority = 9
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.modulate = Color(0.98, 0.96, 0.9)
	l.visible = false
	Lettering.range_to_legibility(l)
	return l


## What each finger plays, index to little, and the chord: empty hides them. A pinched finger's
## grows, so which ones are down reads by size as well as by the curl.
func letter(names: PackedStringArray, chord: String) -> void:
	for i in _tip_letters.size():
		var l := _tip_letters[i]
		l.visible = i < names.size() and names[i] != ""
		if l.visible:
			l.text = names[i]
		l.scale = Vector3.ONE * (PINCHED_GROWS if pinched & HandPose.FINGER_BITS[i] else 1.0)
	if _chord_letter != null:
		_chord_letter.visible = chord != ""
		_chord_letter.text = chord


## How far beyond the palm, along the fingers, its words ride (m at size 1), and their size.
const WORDS_OUT := 0.15
const WORDS_SIZE := 64


## Its words, over its fingertips, whatever way they point: a chord shape's `IV · F`. "" hides
## them.
func say(text: String) -> void:
	if _words == null:
		if text == "":
			return
		_words = _letter_label(WORDS_SIZE)
		_words.name = "Words"
		_words.position = Vector3(0, 0, -WORDS_OUT)
		_palm.add_child(_words)
	_words.visible = text != ""
	_words.text = text


## What it says over its fingertips now, "" for nothing.
func said() -> String:
	return _words.text if _words != null and _words.visible else ""


## A fingertip's letter with the bend its note is bent by (docs/spatial_loop.md part two, slice
## 15): `E4 +1.3`, or the note alone for one too small to see (Wobble.words). So a bend is read on
## the finger playing it, by its number, not by a colour.
static func bent(note: String, semitones: float) -> String:
	var said := Wobble.words(semitones)
	return note if said == "" or note == "" else "%s %s" % [note, said]


## The fingertips' letters as shown now, index to little ("" for one hidden), and the chord's.
func letters() -> PackedStringArray:
	var out := PackedStringArray()
	for l in _tip_letters:
		out.append(l.text if l.visible else "")
	out.append(_chord_letter.text if _chord_letter != null and _chord_letter.visible else "")
	return out


## How far each finger is curled: index, middle, ring, little, thumb.
func curls() -> Array[float]:
	return _curls.duplicate()


## Where the thumb's tip is in the glove's own frame, at size 1 and unstretched: across from its
## root toward the fingers when it is tucked. For the suite.
func thumb_tip() -> Vector3:
	return _knuckles[4].transform * Vector3(0, 0, -_lengths[4])
