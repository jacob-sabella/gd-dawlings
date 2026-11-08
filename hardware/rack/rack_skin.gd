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

## The skin of a module no mod gives one: `[face, accent, pattern, tagline]`. Every skin is that
## four-tuple; the real ones are the `skin` of each `rack_module` entry in `res://mods/builtin/`.
const DEFAULT := [Color(0.16, 0.16, 0.17), Color(0.8, 0.8, 0.8), &"none", ""]


static var _from_mods := {}
static var _watching: ModRegistry


## The registry rescanned: read the skins again.
static func _forget() -> void:
	_from_mods.clear()


## The skin of a module type as `[face, accent, pattern, tagline]`: the mod that provides the type
## decides, else DEFAULT.
static func of(type: String) -> Array:
	var reg := ModRegistry.ensure_current()
	if reg != _watching:
		_watching = reg
		_from_mods.clear()
		reg.changed.connect(_forget)
	if _from_mods.has(type):
		return _from_mods[type]
	var skin: Array = DEFAULT
	var e := reg.rack_module_entry(type)
	if not e.is_empty():
		var s: Dictionary = e["skin"]
		skin = [Color.html(s["face"]), Color.html(s["accent"]), StringName(s["pattern"]), s["tagline"]]
	_from_mods[type] = skin
	return skin


## The skin a mod gives a plugin (`display.skin` of its `plugin` entry, docs/mods.md 4.3) as `[face, accent,
## pattern, tagline]`, or an empty Array when no available mod dresses `(format, id)`.
static func of_plugin(format: String, id: String) -> Array:
	var skin: Variant = ModRegistry.ensure_current().plugin_display(format.to_lower(), id).get("skin")
	if not skin is Dictionary:
		return []
	return [Color.html(skin["face"]), Color.html(skin["accent"]), StringName(skin["pattern"]), skin["tagline"]]


## The face colour of module `type`, a shade lighter for the alternate.
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
	return print_marks(pattern(type), accent(type), wide, tall)


## The same strip for a pattern and accent given outright (a plugin's skin has no module type).
static func print_marks(kind: StringName, acc: Color, wide: float, tall: float) -> MultiMeshInstance3D:
	if kind == PATTERN_NONE:
		return null
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


## The colour of a signal on `port`: pitch, gate, audio or (by default) CV.
static func signal_of(port: String) -> Color:
	if port == "pitch":
		return SIGNAL_PITCH
	if port in _GATES or port.ends_with("_g"):
		return SIGNAL_GATE
	if port in _AUDIO or port.begins_with("ring"):
		return SIGNAL_AUDIO
	return SIGNAL_CV
