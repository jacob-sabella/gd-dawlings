class_name RackSkin
extends RefCounted

## How each kind of module looks in the case: its own faceplate colour, an accent (its band, its
## cables, its trace), a pattern printed under the title and a cheeky tagline along the foot, so a
## wall of thirty modules reads at a glance, like a shelf of records: the clock is a hazard-striped
## metronome, the ladder filter a squelchy purple, the reverb a deep cavern blue.
## Faces are kept dark enough for the cream lettering; the accents carry the colour.

const PATTERN_NONE := &"none"
const PATTERN_STRIPES := &"stripes"
const PATTERN_CHECKER := &"checker"
const PATTERN_DOTS := &"dots"
const PATTERN_WAVE := &"wave"
const PATTERN_BARS := &"bars"
const PATTERN_ZIGZAG := &"zigzag"

# type: [face, accent, pattern, tagline]
const SKINS := {
	"keys": [Color(0.30, 0.10, 0.12), Color(1.00, 0.35, 0.30), &"checker", "PLAY ME"],
	"clock": [Color(0.22, 0.17, 0.05), Color(1.00, 0.78, 0.15), &"stripes", "TICK TOCK"],
	"seq": [Color(0.06, 0.20, 0.26), Color(0.25, 0.90, 0.95), &"bars", "STEP UP"],
	"lfo": [Color(0.07, 0.24, 0.17), Color(0.35, 1.00, 0.60), &"wave", "WOBBLE"],
	"noise": [Color(0.20, 0.20, 0.22), Color(0.85, 0.85, 0.90), &"dots", "SSSHHH"],
	"sh": [Color(0.18, 0.16, 0.26), Color(0.70, 0.60, 1.00), &"bars", "DICE ROLL"],
	"slew": [Color(0.08, 0.20, 0.22), Color(0.40, 0.95, 0.85), &"wave", "GLIDE"],
	"att": [Color(0.20, 0.20, 0.13), Color(0.90, 0.90, 0.50), &"stripes", "EASY NOW"],
	"quant": [Color(0.26, 0.12, 0.22), Color(1.00, 0.50, 0.85), &"checker", "IN TUNE"],
	"env": [Color(0.28, 0.14, 0.06), Color(1.00, 0.55, 0.20), &"zigzag", "SHAPE IT"],
	"vco": [Color(0.30, 0.07, 0.07), Color(1.00, 0.30, 0.25), &"wave", "BUZZ"],
	"drum": [Color(0.27, 0.10, 0.03), Color(1.00, 0.62, 0.10), &"dots", "BOOM TSS"],
	"svf": [Color(0.05, 0.17, 0.28), Color(0.30, 0.70, 1.00), &"zigzag", "SWEEP"],
	"ladder": [Color(0.18, 0.07, 0.28), Color(0.80, 0.35, 1.00), &"stripes", "SQUELCH"],
	"vca": [Color(0.12, 0.22, 0.10), Color(0.60, 0.95, 0.35), &"bars", "VOLUME"],
	"mix": [Color(0.22, 0.20, 0.10), Color(0.95, 0.85, 0.40), &"bars", "ALL TOGETHER"],
	"fold": [Color(0.28, 0.07, 0.17), Color(1.00, 0.35, 0.65), &"zigzag", "ORIGAMI"],
	"drive": [Color(0.30, 0.09, 0.04), Color(1.00, 0.45, 0.15), &"stripes", "HOT HOT HOT"],
	"crush": [Color(0.10, 0.12, 0.26), Color(0.45, 0.55, 1.00), &"checker", "CRUNCH"],
	"scope": [Color(0.04, 0.12, 0.10), Color(0.40, 1.00, 0.70), &"wave", "WHAT DO YOU SEE"],
	"delay": [Color(0.05, 0.20, 0.24), Color(0.35, 0.95, 1.00), &"dots", "ECHO ECHO"],
	"chorus": [Color(0.07, 0.23, 0.24), Color(0.45, 1.00, 0.85), &"wave", "SHIMMER"],
	"out": [Color(0.10, 0.10, 0.11), Color(1.00, 1.00, 1.00), &"stripes", "TO THE DAW"],
	"world": [Color(0.07, 0.22, 0.09), Color(0.50, 1.00, 0.40), &"dots", "LISTEN OUT"],
	"hand": [Color(0.24, 0.13, 0.04), Color(1.00, 0.72, 0.25), &"dots", "HANDS ON"],
	"plaits": [Color(0.26, 0.12, 0.28), Color(1.00, 0.55, 1.00), &"checker", "ONE OF 16"],
	"rings": [Color(0.24, 0.17, 0.05), Color(1.00, 0.80, 0.30), &"dots", "DING"],
	"reverb": [Color(0.05, 0.08, 0.26), Color(0.40, 0.45, 1.00), &"dots", "CAVERN"],
	"clouds": [Color(0.14, 0.16, 0.24), Color(0.70, 0.85, 1.00), &"dots", "GRAINY"],
}
const DEFAULT := [Color(0.16, 0.16, 0.17), Color(0.8, 0.8, 0.8), &"none", ""]


static var _from_mods := {}
static var _watching: ModRegistry


## The registry rescanned: read the skins again.
static func _forget() -> void:
	_from_mods.clear()


## The skin of a module type as `[face, accent, pattern, tagline]`: the mod that provides the type
## decides, then the table above, then DEFAULT.
static func of(type: String) -> Array:
	var reg := ModRegistry.ensure_current()
	if reg != _watching:
		_watching = reg
		_from_mods.clear()
		reg.changed.connect(_forget)
	if _from_mods.has(type):
		return _from_mods[type]
	var skin: Array = SKINS.get(type, DEFAULT)
	var e := reg.rack_module_entry(type)
	if not e.is_empty():
		var s: Dictionary = e["skin"]
		skin = [Color.html(s["face"]), Color.html(s["accent"]), StringName(s["pattern"]), s["tagline"]]
	_from_mods[type] = skin
	return skin


static func face(type: String, alt := false) -> Color:
	var c: Color = of(type)[0]
	return c.lightened(0.05) if alt else c


static func accent(type: String) -> Color:
	return of(type)[1]


static func pattern(type: String) -> StringName:
	return of(type)[2]


static func tagline(type: String) -> String:
	return of(type)[3]


## The printed pattern: a strip of small accent marks `wide` metres across and `tall` high, as one
## MultiMesh so a wall of them is one draw each. Centred on the node's origin.
static func print_pattern(type: String, wide: float, tall: float) -> MultiMeshInstance3D:
	var kind := pattern(type)
	if kind == PATTERN_NONE:
		return null
	var acc := accent(type)
	var marks: Array[Transform3D] = []
	var step := 0.012
	var n := maxi(3, int(wide / step))
	for i in n:
		var x := -wide * 0.5 + wide * (i + 0.5) / float(n)
		match kind:
			PATTERN_STRIPES:
				marks.append(Transform3D(Basis(Vector3.BACK, 0.7).scaled(Vector3(0.35, 1.0, 1.0)), Vector3(x, 0, 0)))
			PATTERN_CHECKER:
				marks.append(Transform3D(Basis().scaled(Vector3(0.8, 0.5, 1.0)), Vector3(x, tall * 0.25 * (1.0 if i % 2 == 0 else -1.0), 0)))
			PATTERN_DOTS:
				marks.append(Transform3D(Basis().scaled(Vector3(0.45, 0.45, 1.0)), Vector3(x, 0, 0)))
			PATTERN_WAVE:
				marks.append(Transform3D(Basis().scaled(Vector3(0.5, 0.5, 1.0)), Vector3(x, sin(float(i) * 0.9) * tall * 0.4, 0)))
			PATTERN_BARS:
				var h := 0.25 + 0.75 * absf(sin(float(i) * 1.7 + 0.6))
				marks.append(Transform3D(Basis().scaled(Vector3(0.6, h, 1.0)), Vector3(x, (h - 1.0) * tall * 0.5, 0)))
			PATTERN_ZIGZAG:
				marks.append(Transform3D(Basis(Vector3.BACK, 0.9 if i % 2 == 0 else -0.9).scaled(Vector3(0.3, 1.0, 1.0)), Vector3(x, 0, 0)))
	var mesh := BoxMesh.new()
	mesh.size = Vector3(step * 0.8, tall, 0.001)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = marks.size()
	for i in marks.size():
		mm.set_instance_transform(i, marks[i])
	var inst := MultiMeshInstance3D.new()
	inst.name = "Print"
	inst.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = acc * 0.75
	mat.roughness = 0.7
	inst.material_override = mat
	return inst


## What a cable carries, from the output it leaves: audio is amber, pitch green, a gate or clock pink,
## any other control voltage blue. The same colours everywhere, so a patch reads by its cables.
const SIGNAL_AUDIO := Color(1.0, 0.72, 0.2)
const SIGNAL_PITCH := Color(0.4, 0.95, 0.5)
const SIGNAL_GATE := Color(1.0, 0.4, 0.62)
const SIGNAL_CV := Color(0.4, 0.75, 1.0)
const _GATES := ["gate", "trig", "16th", "8th", "beat", "bar", "reset", "step", "strum"]
const _AUDIO := ["out", "sub", "aux", "l", "r", "lp", "bp", "hp", "notch", "odd", "even", "white", "pink",
		"weather", "drips", "venue", "marbles"]


static func signal_of(port: String) -> Color:
	if port == "pitch":
		return SIGNAL_PITCH
	if port in _GATES or port.ends_with("_g"):
		return SIGNAL_GATE
	if port in _AUDIO or port.begins_with("ring"):
		return SIGNAL_AUDIO
	return SIGNAL_CV
