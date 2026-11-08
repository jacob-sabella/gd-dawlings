class_name RackUnitDress
extends RefCounted

## What a mod and a missing plugin do to a RackUnit's faceplate (docs/mods.md 4.3): a plugin entry's
## `display.skin` gives it a face colour, an accent band, a printed pattern and a tagline; a slot whose
## plugin this machine lacks gets the unavailable plate, naming the plugin, in the slot's place with its
## power and remove keys, so the project still saves it as it came. A unit no mod dresses is untouched.

const MISSING_FACE := Color(0.20, 0.11, 0.11)
const MISSING_ACCENT := Color(0.95, 0.35, 0.3)


## The skin `[face, accent, pattern, tagline]` the slot shows, or an empty Array for none: the unavailable
## plate's for a missing plugin, else the mod's `display.skin` for the plugin it holds.
static func skin_of(ref: Dictionary) -> Array:
	if ref.is_empty():
		return []
	if ref["missing"]:
		return [MISSING_FACE, MISSING_ACCENT, RackSkin.PATTERN_NONE, ""]
	return RackSkin.of_plugin(ref["format"], ref["id"])


## What the unavailable plate says, in two lines: the plugin and the reason.
static func missing_words(ref: Dictionary) -> PackedStringArray:
	var title := ModRegistry.ensure_current().plugin_title(ref["format"], ref["id"], str(ref["name"]))
	return PackedStringArray(["UNAVAILABLE", "%s %s is not installed here" % [str(ref["format"]).to_upper(), title.to_upper()]])


## Adds the pattern, band and tagline of `skin` to `unit` (whose faceplate is `h` tall), and, for a
## missing plugin, the words of the unavailable plate across the knob row.
static func add_to(unit: RackUnit, ref: Dictionary, skin: Array, h: float) -> void:
	var accent: Color = skin[1]
	var strip := RackSkin.print_marks(skin[2], accent, RackUnit.RACK_WIDTH - 0.07, 0.006)
	if strip != null:
		strip.name = "SkinPrint"
		strip.position = Vector3(0, RackUnit.RULE_Y - 0.0075, 0.0012)
		unit.add_child(strip)
	var band := MeshInstance3D.new()
	band.name = "SkinBand"
	var box := BoxMesh.new()
	box.size = Vector3(RackUnit.RACK_WIDTH - 0.056, 0.0016, 0.001)
	band.mesh = box
	band.position = Vector3(0, -h * 0.5 + 0.0022, 0.0015)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = accent
	paint.emission_enabled = true
	paint.emission = accent
	band.material_override = paint
	unit.add_child(band)
	if str(skin[3]) != "":
		unit.add_child(_label("SkinTagline", skin[3], 34, accent.lerp(Color.WHITE, 0.5), Vector3(0, -h * 0.5 + 0.0068, 0.002)))
	if ref.get("missing", false):
		var words := missing_words(ref)
		unit.add_child(_label("UnavailableTitle", words[0], 96, Color(1.0, 0.62, 0.55), Vector3(0, 0.002, 0.002)))
		unit.add_child(_label("UnavailableWhy", words[1], 52, Color(0.85, 0.78, 0.76), Vector3(0, -0.0125, 0.002)))


static func _label(label_name: String, text: String, size: int, colour: Color, at: Vector3) -> Label3D:
	var l := Label3D.new()
	l.name = label_name
	l.text = text
	l.font_size = size
	l.pixel_size = 0.00019
	l.modulate = colour
	l.position = at
	Lettering.range_to_legibility(l)
	return l
