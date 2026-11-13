class_name MilkFile
extends RefCounted

## A MilkDrop preset file (`.milk`) read into its parts (docs/visuals.md); MilkPlayer plays one. Read
## for this project from the format's published description: an INI-like `[preset00]` section of
## `key=value` lines.
##
## The parts:
##  - `values`: every number in the file by its key in lower case (`fdecay`, `zoom`, `nwavemode`...);
##    `base()` turns them into the per-frame variables' starting values, MilkDrop's defaults filling
##    the gaps;
##  - `per_frame_init`, `per_frame`, `per_pixel`: the equations, the numbered lines joined in order;
##  - `waves` and `shapes`: the custom waves and shapes, each {index, cfg (its `wavecode_N_*` or
##    `shapecode_N_*` numbers, without the prefix), init, per_frame, per_point};
##  - `warp_shader`, `comp_shader`: a MilkDrop 2 preset's HLSL, as text (MilkHlsl translates it).
## Tolerant by design: unknown keys are kept and ignored, CRLF and odd spacing are fine, a line
## without `=` is skipped.

var name := ""
var path := ""
var values := {}
var per_frame_init := ""
var per_frame := ""
var per_pixel := ""
var waves: Array[Dictionary] = []
var shapes: Array[Dictionary] = []
var warp_shader := ""
var comp_shader := ""

## Where a per-frame variable's starting value is kept in the file, when it is under another name.
const FILE_KEYS := {
	"decay": "fdecay", "zoomexp": "fzoomexponent", "gamma": "fgammaadj", "echo_zoom": "fvideoechozoom",
	"echo_alpha": "fvideoechoalpha", "echo_orient": "nvideoechoorientation", "wave_mode": "nwavemode",
	"wave_a": "fwavealpha", "wave_scale": "fwavescale", "wave_smoothing": "fwavesmoothing",
	"wave_mystery": "fwaveparam", "wave_usedots": "bwavedots", "wave_thick": "bwavethick",
	"wave_additive": "badditivewaves", "wave_brighten": "bmaximizewavecolor",
	"modwavealphabyvolume": "bmodwavealphabyvolume", "modwavealphastart": "fmodwavealphastart",
	"modwavealphaend": "fmodwavealphaend", "warpanimspeed": "fwarpanimspeed", "warpscale": "fwarpscale",
	"darken_center": "bdarkencenter", "wrap": "btexwrap", "invert": "binvert", "brighten": "bbrighten",
	"darken": "bdarken", "solarize": "bsolarize", "mv_x": "nmotionvectorsx", "mv_y": "nmotionvectorsy",
	"red_blue": "bredbluestereo",
}

## MilkDrop's starting values for what a file leaves out.
const DEFAULTS := {
	"decay": 0.98, "zoom": 1.0, "zoomexp": 1.0, "rot": 0.0, "warp": 1.0, "cx": 0.5, "cy": 0.5, "dx": 0.0,
	"dy": 0.0, "sx": 1.0, "sy": 1.0, "gamma": 2.0, "echo_zoom": 2.0, "echo_alpha": 0.0, "echo_orient": 0.0,
	"wave_mode": 0.0, "wave_r": 1.0, "wave_g": 1.0, "wave_b": 1.0, "wave_a": 0.8, "wave_x": 0.5,
	"wave_y": 0.5, "wave_scale": 1.0, "wave_smoothing": 0.75, "wave_mystery": 0.0, "wave_usedots": 0.0,
	"wave_thick": 0.0, "wave_additive": 0.0, "wave_brighten": 1.0, "modwavealphabyvolume": 0.0,
	"modwavealphastart": 0.75, "modwavealphaend": 0.95, "warpanimspeed": 1.0, "warpscale": 1.0,
	"darken_center": 0.0, "wrap": 1.0, "invert": 0.0, "brighten": 0.0, "darken": 0.0, "solarize": 0.0,
	"ob_size": 0.01, "ob_r": 0.0, "ob_g": 0.0, "ob_b": 0.0, "ob_a": 0.0,
	"ib_size": 0.01, "ib_r": 0.25, "ib_g": 0.25, "ib_b": 0.25, "ib_a": 0.0,
	"mv_x": 12.0, "mv_y": 9.0, "mv_dx": 0.0, "mv_dy": 0.0, "mv_l": 0.9,
	"mv_r": 1.0, "mv_g": 1.0, "mv_b": 1.0, "mv_a": 0.0,
}

## A custom wave's and a custom shape's settings, MilkDrop's defaults.
const WAVE_DEFAULTS := {
	"enabled": 0.0, "samples": 512.0, "sep": 0.0, "bspectrum": 0.0, "busedots": 0.0, "bdrawthick": 0.0,
	"badditive": 0.0, "scaling": 1.0, "smoothing": 0.5, "r": 1.0, "g": 1.0, "b": 1.0, "a": 1.0,
}
const SHAPE_DEFAULTS := {
	"enabled": 0.0, "sides": 4.0, "additive": 0.0, "thickoutline": 0.0, "textured": 0.0, "num_inst": 1.0,
	"x": 0.5, "y": 0.5, "rad": 0.1, "ang": 0.0, "tex_ang": 0.0, "tex_zoom": 1.0,
	"r": 1.0, "g": 0.0, "b": 0.0, "a": 1.0, "r2": 0.0, "g2": 1.0, "b2": 0.0, "a2": 0.0,
	"border_r": 1.0, "border_g": 1.0, "border_b": 1.0, "border_a": 0.1,
}


## Reads a preset from disk; null if it cannot be read.
static func load_path(p: String) -> MilkFile:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return null
	# Read as plain bytes: the code is ASCII, and many files carry old code-page text in their comments,
	# which a UTF-8 read would complain about line by line.
	var text := f.get_buffer(f.get_length()).get_string_from_ascii()
	var m := parse_text(text, p.get_file().get_basename())
	m.path = p
	return m


static func parse_text(text: String, preset_name := "") -> MilkFile:
	var m := MilkFile.new()
	m.name = preset_name
	var code := {}
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with("[") or line.begins_with("//"):
			continue
		var eq := line.find("=")
		if eq <= 0:
			continue
		var key := line.left(eq).strip_edges().to_lower()
		var val := line.substr(eq + 1)
		var slot := _code_slot(key)
		if slot.is_empty():
			var t := val.strip_edges()
			if t.is_valid_float() or t.is_valid_int():
				m.values[key] = t.to_float()
			continue
		var bucket: Dictionary = code.get(slot[0], {})
		bucket[int(slot[1])] = val
		code[slot[0]] = bucket
	m.per_frame_init = _joined(code.get("per_frame_init", {}))
	m.per_frame = _joined(code.get("per_frame", {}))
	m.per_pixel = _joined(code.get("per_pixel", {}))
	m.warp_shader = _joined(code.get("warp", {}))
	m.comp_shader = _joined(code.get("comp", {}))
	for i in 4:
		var w := {"index": i, "cfg": _cfg(m.values, "wavecode_%d_" % i, WAVE_DEFAULTS),
				"init": _joined(code.get("wave_%d_init" % i, {})),
				"per_frame": _joined(code.get("wave_%d_per_frame" % i, {})),
				"per_point": _joined(code.get("wave_%d_per_point" % i, {}))}
		if float(w.cfg.enabled) != 0.0:
			m.waves.append(w)
		var s := {"index": i, "cfg": _cfg(m.values, "shapecode_%d_" % i, SHAPE_DEFAULTS),
				"init": _joined(code.get("shape_%d_init" % i, {})),
				"per_frame": _joined(code.get("shape_%d_per_frame" % i, {}))}
		if float(s.cfg.enabled) != 0.0:
			m.shapes.append(s)
	return m


## Which block of code a key is a numbered line of: [block, line number], or [] for a plain value.
static func _code_slot(key: String) -> Array:
	for prefix in ["per_frame_init_", "per_frame_", "per_pixel_", "warp_", "comp_"]:
		if key.begins_with(prefix) and key.substr(prefix.length()).is_valid_int():
			return [prefix.trim_suffix("_"), key.substr(prefix.length()).to_int()]
	# wave_0_per_point12, shape_1_per_frame3, wave_2_init1 (and the per_pixel-less "_per_frame_init" spelling)
	for kind in ["wave_", "shape_"]:
		if not key.begins_with(kind):
			continue
		var rest := key.substr(kind.length())
		var us := rest.find("_")
		if us <= 0 or not rest.left(us).is_valid_int():
			continue
		var idx := rest.left(us)
		var tail := rest.substr(us + 1)
		for part in ["per_frame_init", "per_frame", "per_point", "init"]:
			if tail.begins_with(part):
				var num := tail.substr(part.length())
				if num.is_valid_int():
					var block: String = "init" if part == "per_frame_init" else part
					return ["%s%s_%s" % [kind, idx, block], num.to_int()]
	return []


static func _joined(lines: Dictionary) -> String:
	var keys := lines.keys()
	keys.sort()
	var out := PackedStringArray()
	for k in keys:
		var l := String(lines[k])
		# A MilkDrop 2 shader line starts with a backtick.
		out.append(l.substr(1) if l.begins_with("`") else l)
	return "\n".join(out)


static func _cfg(values: Dictionary, prefix: String, defaults: Dictionary) -> Dictionary:
	var out := defaults.duplicate()
	for k in values:
		if String(k).begins_with(prefix):
			out[String(k).substr(prefix.length())] = values[k]
	return out


## The per-frame variables' starting values: the file's, under their equation names, over MilkDrop's
## defaults.
func base() -> Dictionary:
	var out := DEFAULTS.duplicate()
	for k in DEFAULTS:
		var fk: String = FILE_KEYS.get(k, k)
		if values.has(fk):
			out[k] = float(values[fk])
		elif values.has(k):
			out[k] = float(values[k])
	# Older presets spell the wave's look as flags only; wave_a may also be stored as "wave_a".
	return out


## Whether this preset carries MilkDrop 2 shaders.
func has_shaders() -> bool:
	return warp_shader.strip_edges() != "" or comp_shader.strip_edges() != ""
