class_name PatchCable
extends Node3D

## A patch cable: two 1/4" TS plugs, two strain-relief boots, and a jacket hanging between them.
##
## WHY ANY OF THIS DETAIL. The patchbay is the one surface whose entire job is to be read at a
## glance -- how heavily patched the session is, which way signal flows, which return has four
## things landing on it. A straight tinted line conveys none of that, and in 3D two straight
## lines at different depths are indistinguishable. What makes a bundle legible is that each
## cable is a solid object that leaves its jack perpendicular, droops under its own weight, and
## catches the light along its length.
##
## Four things do the work, in rough order of how much they matter:
##
##   PLUGS      a cable that ends in a floating point reads as a wire. A sleeve, two insulating
##              rings and a tip read as something plugged in.
##   EXIT ANGLE real cables leave a jack along its axis for a few centimetres before gravity
##              takes over. Straight-from-the-hole is the single most artificial-looking thing a
##              patchbay can do, and it is also what made the old cables clip through the panel.
##   FRAMING    the tube is swept with parallel-transport frames rather than a fixed up vector.
##              A naive cross-product frame flips where the tangent passes vertical -- which on
##              a hanging cable is exactly at the bottom of the sag, in the middle, in view.
##   JACKET     clearcoat over a rough base, so a specular streak runs the length and follows
##              the curve. That streak is most of how the eye reads a cable as round.

## Sixteen sides, up from ten.
##
## Ten was plenty while the jacket had a broad middling gloss, because a wide highlight
## smears across several facets and hides every one of them. Narrowing the clearcoat to get
## the cable's round back immediately exposed the faceting: the specular line came back
## dashed, one bright dot per flat, which reads as a chain rather than a cable. Sheen width
## and tube resolution are the same decision and have to move together.
const RADIAL := 16
const SPINE := 32
const JACKET_RADIUS := 0.0022

## 1/4" TS. The sleeve really is 6.35mm across, and the jack bores it plugs into are modelled at
## 5.4mm radius, so this sits inside them rather than on top.
const PLUG_RADIUS := 0.00317
const TIP_LENGTH := 0.009
const RING_LENGTH := 0.0014
const SLEEVE_LENGTH := 0.019
const BOOT_LENGTH := 0.015
const BOOT_RADIUS := 0.0046
## How deep the plug sits in the jack. Everything in front of this -- a few millimetres of
## sleeve, then the boot -- is what you actually see, and getting it wrong is the difference
## between a seated plug and one resting on the panel.
const INSERT_DEPTH := 0.018
## Where the jacket starts, measured out from the panel face along the jack axis.
## The knurled band where the boot screws onto the plug body. Three millimetres of nothing much,
## and the thing that stops the metal-to-rubber joint looking like two primitives abutted.
const COLLAR_LENGTH := 0.0030
const JACKET_OFFSET := TIP_LENGTH + RING_LENGTH * 2.0 + SLEEVE_LENGTH + COLLAR_LENGTH \
		+ BOOT_LENGTH - INSERT_DEPTH

## How far the cable runs straight out of the boot before it starts to fall, and how far it
## drops. Sag is proportional to span with a floor: a short patch between neighbouring jacks
## that sagged 15cm would loop below the bay and read as a far longer cable than it is.
## How far the cable runs out along the jack axis before gravity takes over, as a base plus a
## share of the span. The span term is what keeps a long patch DRAPED IN FRONT of the bay
## instead of lying across its face: a fixed exit run leaves a cable to the far end of the row
## hugging the panel and hiding the jacks it passes over.
const EXIT_BASE := 0.030
const EXIT_PER_SPAN := 0.28
const EXIT_MAX := 0.17
## A Bezier reaches roughly three quarters of the way to its control points, so the visible
## droop ends up close to SAG_RATIO x span. Tuned against the furniture: anything past about
## 0.14 and a long patch across the bay hangs down over the rows below it.
const SAG_RATIO := 0.13
const MIN_SAG := 0.016

var from_xform: Transform3D = Transform3D.IDENTITY
var to_xform: Transform3D = Transform3D.IDENTITY
var colour: Color = Color(0.82, 0.74, 0.3)
## Seeds the per-cable variation. Two cables between adjacent jacks laid out identically read as
## one object drawn twice; real ones differ in how they were coiled.
var variation_seed: int = 0
## How far it droops, as a share of its span. A bay whose cables cross a gap sideways wants less
## than one whose cables loop between rows of the same panel.
var sag_ratio := SAG_RATIO
## Pushed back while something else on the bay is being looked at.
var dimmed := false:
	set(v):
		if dimmed != v:
			dimmed = v
			_paint()

var _jacket: MeshInstance3D
var _boots: Array[MeshInstance3D] = []


static func create(a: Transform3D, b: Transform3D, tint: Color, seed_value: int = 0) -> PatchCable:
	var c := PatchCable.new()
	c.from_xform = a
	c.to_xform = b
	c.colour = tint
	c.variation_seed = seed_value
	return c


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_jacket = null
	_boots.clear()

	# Built in LOCAL space from two GLOBAL transforms, so a cable survives its surface being
	# reparented from a monitor to the room -- the one operation this project does that would
	# otherwise leave every cable pointing at where the bay used to be.
	var inv := global_transform.affine_inverse()
	var a := inv * from_xform
	var b := inv * to_xform

	var a_axis := a.basis.z.normalized()
	var b_axis := b.basis.z.normalized()
	# Where the jacket actually begins: past the plug and past the boot.
	var a_start := a.origin + a_axis * JACKET_OFFSET
	var b_start := b.origin + b_axis * JACKET_OFFSET

	_build_plug(a, colour)
	_build_plug(b, colour)
	_build_jacket(_spine(a_start, a_axis, b_start, b_axis))
	_paint()


## A dimmed cable keeps its colour and loses most of its light, so the ones still lit are the
## ones the eye follows.
func _paint() -> void:
	var tint := colour.darkened(0.7) if dimmed else colour
	if _jacket != null:
		_jacket.material_override = Materials.cable(tint)
	for boot in _boots:
		boot.material_override = Materials.cable_boot(tint)


## A cubic Bézier whose control points lie along the two jack axes.
##
## That is what produces the perpendicular exit for free: the curve's tangent at an endpoint
## points at its neighbouring control point, so putting that control point along the jack axis
## makes the cable leave the panel square to it, with no special-casing of the first segment.
## Gravity is then applied to the two control points rather than to the curve, which keeps the
## whole thing a single smooth cubic instead of a curve with a sag bolted on.
func _spine(a: Vector3, a_axis: Vector3, b: Vector3, b_axis: Vector3) -> PackedVector3Array:
	var span := a.distance_to(b)
	var sag := maxf(span * sag_ratio, MIN_SAG)

	# Deterministic per cable: same jacks, same cable, every rebuild. A random() here would make
	# the bundle shimmer every time the patchbay was rebuilt.
	var rng := RandomNumberGenerator.new()
	rng.seed = variation_seed
	var slack := 1.0 + rng.randf_range(-0.12, 0.22)
	# A little lateral bow, so cables sharing a destination do not stack into one thick line.
	var sideways := a.direction_to(b).cross(Vector3.UP).normalized() * rng.randf_range(-0.035, 0.035) * span

	var p0 := a
	var p3 := b
	var exit_run := minf(EXIT_BASE + span * EXIT_PER_SPAN, EXIT_MAX) * slack
	var p1 := a + a_axis * exit_run + Vector3.DOWN * sag + sideways
	var p2 := b + b_axis * exit_run + Vector3.DOWN * sag + sideways

	var points := PackedVector3Array()
	for i in SPINE + 1:
		var t := float(i) / float(SPINE)
		var u := 1.0 - t
		points.append(p0 * (u * u * u) + p1 * (3.0 * u * u * t) + p2 * (3.0 * u * t * t) + p3 * (t * t * t))
	return points


## Hand the spine to the shared sweep and dress the result as a patch cable.
##
## The frame maths lives in CableSweep because the floor looms need exactly the same thing at a
## different scale. What is specific to a patch cable is only what it is made of.
func _build_jacket(spine: PackedVector3Array) -> void:
	var mesh := CableSweep.tube(spine, JACKET_RADIUS, RADIAL)
	if mesh == null:
		return
	var jacket := MeshInstance3D.new()
	jacket.name = "Jacket"
	jacket.mesh = mesh
	jacket.material_override = Materials.cable(colour)
	# A cable is 4mm across. Without this it disappears from its own shadow map as speckle, and
	# a patchbay full of shadow acne looks dirty rather than detailed.
	jacket.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(jacket)
	_jacket = jacket


## Tip, two insulating rings, sleeve, boot. Built from primitives rather than swept, because at
## 3mm across the segment count that matters is the radial one and a CylinderMesh already has it.
func _build_plug(at: Transform3D, tint: Color) -> void:
	var plug := Node3D.new()
	plug.name = "Plug"
	add_child(plug)
	# Cylinders stand along Y; the plug lies along the jack axis, which is the panel's +Z.
	plug.transform = Transform3D(at.basis * Basis(Vector3.RIGHT, PI * 0.5), at.origin)

	# Laid out from the tip outwards, starting behind the panel face: the tip, the rings and most
	# of the sleeve are inside the bore, which is what makes the plug look seated.
	var cursor := -INSERT_DEPTH
	cursor += _segment(plug, PLUG_RADIUS * 0.78, TIP_LENGTH, cursor, Materials.plug_metal(), true)
	cursor += _segment(plug, PLUG_RADIUS * 0.80, RING_LENGTH, cursor, Materials.plug_insulator(), false)
	cursor += _segment(plug, PLUG_RADIUS, SLEEVE_LENGTH, cursor, Materials.plug_metal(), false)
	cursor += _segment(plug, PLUG_RADIUS * 1.05, RING_LENGTH, cursor, Materials.plug_insulator(), false)
	cursor += _segment(plug, BOOT_RADIUS * 0.96, COLLAR_LENGTH, cursor, Materials.plug_metal(), false)

	# The boot tapers from a fat collar down to the jacket, so the joint between a 6mm boot and a
	# 4mm cable is not a visible step.
	var boot := MeshInstance3D.new()
	var boot_mesh := CylinderMesh.new()
	boot_mesh.top_radius = JACKET_RADIUS * 1.25
	boot_mesh.bottom_radius = BOOT_RADIUS
	boot_mesh.height = BOOT_LENGTH
	boot_mesh.radial_segments = RADIAL
	boot.mesh = boot_mesh
	boot.position = Vector3(0, cursor + BOOT_LENGTH * 0.5, 0)
	boot.material_override = Materials.cable_boot(tint)
	boot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plug.add_child(boot)
	_boots.append(boot)


func _segment(parent: Node3D, radius: float, length: float, offset: float,
		material: StandardMaterial3D, rounded: bool) -> float:
	var piece := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	# The tip is domed, which is both what a TS tip looks like and what stops it reading as a
	# cut-off pipe end when seen head-on from across the room.
	# A TS tip is domed. `rounded` tapers the DEEP end, the one that goes into the jack first.
	mesh.top_radius = radius
	mesh.bottom_radius = radius * (0.55 if rounded else 1.0)
	mesh.height = length
	mesh.radial_segments = RADIAL
	piece.mesh = mesh
	piece.position = Vector3(0, offset + length * 0.5, 0)
	piece.material_override = material
	piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(piece)
	return length
