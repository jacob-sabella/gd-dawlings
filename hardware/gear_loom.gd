class_name GearLoom
extends Node3D

## A multicore loom: the thick cable run between one piece of gear and the patchbay.
##
## WHY THIS EXISTS, which is not decoration. The patchbay draws a cable for every send in the
## session, and that is the one surface in the room whose job is to show signal going somewhere.
## But for the first several versions those cables were the ONLY thing connecting anything. The
## console, the rack and the tape deck sat in the same room as the bay and had no physical
## relationship to it at all -- so the bay's jacks were labelled with the names of gear they were
## visibly not attached to. A patchbay wired to nothing is a prop of a patchbay.
##
## That is what a loom fixes. It is the normalling: the permanent run from the back of each
## machine up to the bay, which is the thing that makes a jack on the bay mean that machine. The
## per-send cables on the front are then patches over the top of it, which is the correct reading
## and was previously unavailable.
##
## It is still scenery in the sense that nothing in the DAW state decides where it goes. The
## honest claim is narrower than the patch cables': a loom says THIS MACHINE IS WIRED TO THE BAY,
## which is true of every machine here, rather than claiming any particular signal.
##
## HOW IT IS SHAPED. Not a sag between two points. A real floor loom leaves the chassis through a
## gland, falls to the floor, runs along it to wherever the trunking is, and climbs back out --
## and the floor part is most of its length. So the route is a list of places the cable has to BE
## rather than lean towards, which is why CableSweep.smooth is a Catmull-Rom and not a Bezier.

## Each conductor in the bundle. Three of them, because a single tube that thick reads as a pipe:
## what says "cable" is the parting lines between cores and the way they converge at the ties.
const CORE_RADIUS := 0.0062
const CORES := 3
## Eight-sided. A loom is three times the diameter of a patch cable but is seen from across the
## room rather than leant over, and most of its length is in shadow under the furniture.
const RADIAL := 8
const PER_SPAN := 8
## How far it runs out of the gland before the fall starts, and how far along the floor route the
## drop lands. Both exist for the same reason as a patch cable's exit run: a cable that turns the
## instant it leaves the chassis reads as drawn rather than plugged.
const EXIT_RUN := 0.085
## How far along the floor route the fall lands, as a share of the way there. Raised from a third
## after the first render: at a third, a loom from gear standing directly over its floor route
## fell almost vertically, and a vertical cable with no bend in it is indistinguishable from a
## pole. The lead is what turns the drop into an arc.
const DROP_LEAD := 0.46
const GLAND_LENGTH := 0.030
const GLAND_RADIUS := 0.0145
## Velcro wraps along the floor run. Two, at these fractions of the route.
const TIE_FRACTIONS: Array[float] = [0.34, 0.66]
const DIRECT_TIE_FRACTIONS: Array[float] = [0.5]
const TIE_LENGTH := 0.016
## How far either side of the floor the contact is rounded off. Three centimetres: enough that
## the cable visibly flattens into the floor rather than meeting it at an angle, short enough
## that the fall above it is still a fall.
const FLOOR_BLEND := 0.030

var from_point: Vector3 = Vector3.ZERO
var from_axis: Vector3 = Vector3.BACK
var to_point: Vector3 = Vector3.ZERO
var to_axis: Vector3 = Vector3.BACK
## The one place in the middle the run has to pass through. On a floor run only its x and z are
## used -- the height is the bundle lying on the floor, which the loom works out, because a loom
## that hovers and one that sinks are both worse than one obviously lying down. On a direct run
## it is taken as given, and it is how a short drop is told to go round something solid.
var via: Vector3 = Vector3.ZERO
## Whether the via is on the floor. False for a run that never reaches it: gear stacked over its
## own destination, where a trunk route down and back up would be a longer cable than the one
## that fits.
var on_floor := true
var floor_y := 0.0
## Mid-dark rather than near-black. The floor under this desk is the least-lit part of the room,
## and the first pass at 0.085 rendered as a silhouette with no highlight anywhere along it --
## which is exactly the thing the sweep's round frame exists to produce.
var jacket_colour: Color = Color(0.148, 0.152, 0.165)
## The heat-shrink at each gland, which is how a real machine room tells two identical black
## trunks apart. It is also the only part of a loom that catches any light at this distance.
var band_colour: Color = DEFAULT_BAND
## Left at this, the band takes the venue's own (`Materials.loom_band`, a GearStyle finish).
const DEFAULT_BAND := Color(0.70, 0.56, 0.22)
var variation_seed := 0
## () -> float: how loud what the loom carries is now, 0..1 on the fader law, for its beads
## (SignalBeads). The studio says, per machine: the console's carries every heard track, so a desk
## of muted strips sends nothing down it. Unset, it carries nothing.
var level_source: Callable = Callable()

var _spines: Array[PackedVector3Array] = []
## The middle core's length, and its spine in world space as last asked.
var _length := 0.0
var _world := PackedVector3Array()
var _world_at := Transform3D()


static func create(from_at: Vector3, from_dir: Vector3, to_at: Vector3, to_dir: Vector3,
		via_point: Vector3, seed_value: int = 0) -> GearLoom:
	var loom := GearLoom.new()
	loom.from_point = from_at
	loom.from_axis = from_dir.normalized()
	loom.to_point = to_at
	loom.to_axis = to_dir.normalized()
	loom.via = via_point
	loom.variation_seed = seed_value
	return loom


## The height the centre of a core sits at when the bundle is resting on the floor.
##
## A core is not the whole bundle: the lowest core in a spread bundle is CORE_RADIUS above the
## floor, and the spines are built per core, so this is the height of the core being routed plus
## however far that core is pushed down from the bundle's axis.
static func rest_height(floor_level: float, spread_down: float) -> float:
	return floor_level + CORE_RADIUS + spread_down


func bundle_radius() -> float:
	return CORE_RADIUS * 2.1


func spine(core: int) -> PackedVector3Array:
	if core < 0 or core >= _spines.size():
		return PackedVector3Array()
	return _spines[core]


func _enter_tree() -> void:
	add_to_group(SignalBeads.CARRIERS)


func _ready() -> void:
	rebuild()


# --- what its beads ride (SignalBeads): the middle core, from the machine to the bay ----------

func signal_spine() -> PackedVector3Array:
	var middle := spine(CORES / 2)
	if _world.size() != middle.size() or global_transform != _world_at:
		_world_at = global_transform
		_world = _world_at * middle
	return _world


func signal_length() -> float:
	return _length


func signal_level() -> float:
	return float(level_source.call()) if level_source.is_valid() else 0.0


func signal_radius() -> float:
	return CORE_RADIUS


func rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_spines.clear()

	var rng := RandomNumberGenerator.new()
	rng.seed = variation_seed

	# The plane the cores spread in: across the run, horizontally. Spreading them vertically would
	# stack the bundle into a column, and a column resting on the floor touches it at one core.
	var straight := to_point - from_point
	straight.y = 0.0
	var across := straight.cross(Vector3.UP)
	across = across.normalized() if across.length_squared() > 1e-8 else Vector3.RIGHT

	for core in CORES:
		# Centred: -1, 0, +1 for three cores, so the bundle's axis is the route it was given
		# rather than one core's edge.
		var lane := float(core) - float(CORES - 1) * 0.5
		var sideways := across * lane * CORE_RADIUS * 1.75
		var sag := rng.randf_range(0.0, CORE_RADIUS * 0.6)
		var points := CableSweep.smooth(_route(sideways, sag), PER_SPAN)
		if on_floor:
			points = CableSweep.rest_on(points, rest_height(floor_y, sag), FLOOR_BLEND)
		_spines.append(points)
		var mesh := CableSweep.tube(points, CORE_RADIUS, RADIAL, 14.0)
		if mesh == null:
			continue
		var core_mesh := MeshInstance3D.new()
		core_mesh.name = "Core%d" % core
		core_mesh.mesh = mesh
		core_mesh.material_override = Materials.cable(jacket_colour)
		# Same reason as the patch cables: at 12mm across, a self-shadowing cable two metres long
		# is speckle rather than shading, and the floor under the desk is the darkest part of the
		# room already.
		core_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(core_mesh)

	_length = SignalBeads.length_of(spine(CORES / 2))
	_world = PackedVector3Array()
	_build_gland(from_point, from_axis, "FromGland")
	_build_gland(to_point, to_axis, "ToGland")
	_build_ties()


## Out of the gland, down to the floor, along it, and back out -- or, for a short run, straight
## across with slack in it.
##
## `sideways` and `extra_sag` are the per-core variation. The endpoints take only a quarter of the
## sideways offset, because all three cores leave through one gland and fan out afterwards.
func _route(sideways: Vector3, extra_sag: float) -> PackedVector3Array:
	var a := from_point + sideways * 0.25
	var b := to_point + sideways * 0.25
	var a_out := a + from_axis * EXIT_RUN
	var b_out := b + to_axis * EXIT_RUN

	if not on_floor:
		var middle := via + sideways
		middle.y -= extra_sag
		return PackedVector3Array([a, a_out, middle, b_out, b])

	var rest := rest_height(floor_y, extra_sag)
	var floor_point := Vector3(via.x, rest, via.z) + sideways

	# Where the fall lands: under the exit, lead-distance along the way to the floor route. A drop
	# straight down would put a right angle in the cable where it meets the floor.
	var down := Vector3(a_out.x, rest, a_out.z)
	down += (floor_point - down) * DROP_LEAD
	var up := Vector3(b_out.x, rest, b_out.z)
	up += (floor_point - up) * DROP_LEAD

	return PackedVector3Array([a, a_out, down, floor_point, up, b_out, b])


## The strain-relief gland where the loom enters the chassis. A loom that stops at a flat surface
## reads as passing through it; a collar reads as entering it.
func _build_gland(at: Vector3, axis: Vector3, label: String) -> void:
	var gland := MeshInstance3D.new()
	gland.name = label
	var mesh := CylinderMesh.new()
	mesh.top_radius = bundle_radius() * 1.05
	mesh.bottom_radius = GLAND_RADIUS
	mesh.height = GLAND_LENGTH
	mesh.radial_segments = RADIAL + 4
	gland.mesh = mesh
	# Cylinders stand along Y; the gland lies along the axis it leaves on.
	var up := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.98 else Vector3.BACK
	var side := up.cross(axis).normalized()
	gland.transform = Transform3D(Basis(side, axis, side.cross(axis).normalized()),
			at + axis * (GLAND_LENGTH * 0.5 - 0.004))
	gland.material_override = Materials.brushed_metal()
	# Off, like the rest of the loom. It was left on by oversight and showed up as six extra
	# shadow-pass draws in the budget: the only part of a cable that cast a shadow was the
	# 30mm collar at each end, which is both a cost and a lie about where the cable is.
	gland.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(gland)

	var band := MeshInstance3D.new()
	band.name = label + "Band"
	var band_mesh := CylinderMesh.new()
	band_mesh.top_radius = bundle_radius() * 1.18
	band_mesh.bottom_radius = bundle_radius() * 1.18
	band_mesh.height = 0.012
	band_mesh.radial_segments = RADIAL + 2
	band.mesh = band_mesh
	band.transform = Transform3D(gland.transform.basis,
			at + axis * (GLAND_LENGTH + 0.016))
	band.material_override = Materials.loom_band() if band_colour == DEFAULT_BAND else Materials.cap_plastic(band_colour)
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(band)


## Velcro wraps holding the bundle together. Taken from the MIDDLE core's spine, so a tie sits
## on the bundle's axis rather than on an outside core.
##
## A hanging run gets one in the middle and a floor run gets two, and that is not only dressing:
## without a tie the three cores hang as three evenly spaced parallel lines, which from across
## the room reads as a ribbon cable or a ladder. One wrap gathering them in the middle is what
## makes the splay either side of it read as slack in one bundle.
func _build_ties() -> void:
	var middle := spine(CORES / 2)
	if middle.size() < 2:
		return
	for fraction in (TIE_FRACTIONS if on_floor else DIRECT_TIE_FRACTIONS):
		var index := int(round(fraction * float(middle.size() - 1)))
		var tie := MeshInstance3D.new()
		tie.name = "Tie"
		var mesh := CylinderMesh.new()
		mesh.top_radius = bundle_radius() * 1.12
		mesh.bottom_radius = bundle_radius() * 1.12
		mesh.height = TIE_LENGTH
		mesh.radial_segments = RADIAL + 2
		tie.mesh = mesh
		tie.transform = Transform3D(CableSweep.frame_at(middle, index), middle[index])
		tie.material_override = Materials.cap_plastic(Color(0.13, 0.135, 0.15))
		tie.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(tie)
