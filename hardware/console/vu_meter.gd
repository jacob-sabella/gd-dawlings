class_name VUMeter
extends Node3D

## A segmented level ladder.
##
## Polls the state cache every frame rather than subscribing to a signal. Reaper streams meters
## at roughly 30Hz per channel, so on a 32-track project that is ~1000 updates a second; fanning
## those out as signals to every surface drawing that track costs more than simply reading two
## floats per meter per frame.
##
## PEAK HOLD AND DECAY LIVE HERE, not in Reaper's data. Reaper sends an instantaneous level; the
## ballistics that make a meter readable -- fast attack, slow release, a peak marker that sits
## for a moment -- are a property of the meter, and different meters in this scene legitimately
## have different ones.
##
## ONE DRAW CALL, NOT FOURTEEN
##
## The ladder is a MultiMesh rather than fourteen MeshInstance3Ds, and that is the single
## largest rendering decision in the project. tools/budget.sh measured a 90-track session at
## 3370 draw calls; 1260 of them -- thirty-seven percent of the entire studio -- were this one
## widget, because there is a meter per strip and each one was fourteen separate objects. As a
## MultiMesh it is ninety.
##
## The segment colour therefore has to travel as per-instance data rather than as a material,
## which is why this carries a shader at all. It is four lines and unshaded, which an LED should
## be anyway -- a little lamp does not take light from the room, it adds it -- and unshaded is
## identical under forward_plus and mobile, which the project requires of every material.

const SEGMENTS := 14
const SEG_HEIGHT := 0.0055
const SEG_GAP := 0.0015
const WIDTH := 0.008

## dB/s. 20 is roughly a PPM-style release: slow enough to read, fast enough to follow a vocal.
const DECAY_PER_SEC := 1.8
const PEAK_HOLD_SEC := 1.2

@export var track_index: int = 0
## Where the level comes from, when it is not a track. The master section sets this; an FX
## return or a monitor path would do the same. A Callable rather than a second meter class,
## because the ballistics, the colour boundaries and the segment count are the whole of what a
## meter IS and none of them change with the thing being metered.
var read_level: Callable = Callable()

var _multi: MultiMeshInstance3D
var _mesh: MultiMesh
var _level := 0.0
var _peak := 0.0
var _peak_age := 0.0
var _lit_shown := -1
var _peak_shown := -1

static var _shader: Shader


func total_height() -> float:
	return SEGMENTS * (SEG_HEIGHT + SEG_GAP)


func _ready() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(WIDTH, SEG_HEIGHT, 0.0015)

	_mesh = MultiMesh.new()
	_mesh.transform_format = MultiMesh.TRANSFORM_3D
	_mesh.use_colors = true
	_mesh.mesh = box
	_mesh.instance_count = SEGMENTS
	for i in SEGMENTS:
		_mesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(0, segment_y(i), 0.0)))

	_multi = MultiMeshInstance3D.new()
	_multi.multimesh = _mesh
	_multi.material_override = _lamp_material()
	add_child(_multi)
	_paint(0, -1)


## Unshaded, so a lamp adds light rather than taking it, and so it renders identically under
## forward_plus and mobile. Shared across every meter in the scene: a ShaderMaterial per meter
## would hand back in pipeline switches most of what the MultiMesh just saved.
static func _lamp_material() -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """
shader_type spatial;
render_mode unshaded, shadows_disabled;

void fragment() {
	// COLOR is the MultiMesh per-instance colour. Values above 1 are deliberate: that is what
	// the glow pass picks up, and it is how a lit segment reads as emitting rather than as
	// merely being a brighter shade of plastic.
	ALBEDO = COLOR.rgb;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _shader
	return m


## Green to about -9dB, amber to -3, red at the top two. The colour boundaries are the only
## calibration a meter at a glance actually conveys -- which is precisely why they cannot be
## only colour. Read through the reader's palette, so a deficiency that collapses green into
## amber gets a ramp that does not.
static func colour_at(index: int) -> Color:
	var f := float(index) / float(SEGMENTS - 1)
	if f > 0.92:
		return Ergonomics.current.signal_colour(&"over")
	if f > 0.76:
		return Ergonomics.current.signal_colour(&"warn")
	return Ergonomics.current.signal_colour(&"ok")


func _process(delta: float) -> void:
	var incoming := 0.0
	if read_level.is_valid():
		incoming = read_level.call()
	else:
		var t := DAW.state.track(track_index, false)
		if t != null:
			incoming = maxf(t.vu_l, t.vu_r)

	# Attack is instant, release is damped. The asymmetry is the whole of meter ballistics: a
	# symmetric filter either misses transients or looks like it is lagging.
	_level = incoming if incoming > _level else maxf(0.0, _level - DECAY_PER_SEC * delta)

	if _level >= _peak:
		_peak = _level
		_peak_age = 0.0
	else:
		_peak_age += delta
		if _peak_age > PEAK_HOLD_SEC:
			_peak = maxf(_level, _peak - DECAY_PER_SEC * delta)

	var lit_count := int(round(_level * SEGMENTS))
	var peak_seg := int(round(_peak * SEGMENTS)) - 1
	# Only when something actually changed. A meter spends most of its life on the same segment
	# count, and a ladder is fourteen writes -- across ninety strips that is 1,260 buffer writes
	# a frame to say nothing.
	if lit_count != _lit_shown or peak_seg != _peak_shown:
		_paint(lit_count, peak_seg)


## Where segment `index` sits up the ladder.
static func segment_y(index: int) -> float:
	return index * (SEG_HEIGHT + SEG_GAP)


## What colour segment `index` should be at this level. Lit segments are driven past 1.0 so the
## glow pass catches them; an unlit one keeps its tint rather than going black, because an off
## LED is not the absence of an LED.
##
## STATIC, AND THIS IS NOT TIDINESS. A MultiMesh's instance buffer lives in the rendering
## server, and the headless server is a stub -- set_instance_color writes into it quite happily
## and get_instance_color hands back black forever, so nothing the suite can reach can see what
## this meter decided. Converting a widget to a MultiMesh therefore makes it untestable unless
## the decision is lifted somewhere outside the buffer. Here it is, and _paint is the one line
## that cannot be checked.
static func segment_colour(index: int, lit_count: int, peak_seg: int) -> Color:
	var base := colour_at(index)
	var on := index < lit_count or index == peak_seg
	return Materials.lamp_colour(base, on)


func _paint(lit_count: int, peak_seg: int) -> void:
	_lit_shown = lit_count
	_peak_shown = peak_seg
	for i in SEGMENTS:
		_mesh.set_instance_color(i, segment_colour(i, lit_count, peak_seg))
