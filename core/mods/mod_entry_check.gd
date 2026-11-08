class_name ModEntryCheck
extends RefCounted

## Validates one `provides[]` entry of a manifest by its kind (docs/mods.md section 3.2). The
## field tables there are the rules; mods/mod.schema.json is the machine form. Pure functions.

const KINDS: Array[String] = ["rack_module", "rack_preset", "plugin", "skin", "piece"]
const SOUND_KINDS: Array[String] = ["engine", "composite"]
const FACES: Array[String] = ["standard", "out", "scope", "seq"]
const REACTS: Array[String] = ["level", "hit", "none"]
const SIGNALS: Array[String] = ["gate", "audio", "cv"]
const PLUGIN_FORMATS: Array[String] = ["clap", "vst3", "lv2", "godot"]
const PIECE_CLASSES: Array[String] = ["single", "room_scale"]
const MOUNTS: Array[String] = ["floor", "wall", "zone", "surface", "venue", "shelf"]
const _HEX := "^#[0-9A-Fa-f]{6}$"


## The key a registry uses to tell entries apart: kind plus the field that names it.
static func entry_key(entry: Dictionary) -> String:
	match str(entry.get("kind", "")):
		"rack_module":
			return "rack_module:%s" % entry.get("type", "")
		"rack_preset":
			return "rack_preset:%s" % entry.get("name", "")
		"plugin":
			var p: Variant = entry.get("plugin")
			if p is Dictionary:
				return "plugin:%s:%s" % [p.get("format", ""), p.get("id", "")]
			return "plugin:"
		"skin":
			return "skin:%s" % entry.get("for", "")
		"piece":
			return "piece:%s" % entry.get("id", "")
	return str(entry.get("kind", ""))


## Problems for `entry` (index `i` in provides). `bad_schema` means the manifest is invalid;
## `unsupported_sound_kind` makes only this entry unavailable.
static func check(entry: Dictionary, i: int, mod_id: String) -> Array[ModProblem]:
	var out: Array[ModProblem] = []
	var where := "provides[%d]" % i
	var kind: Variant = entry.get("kind")
	if not kind is String or not str(kind) in KINDS:
		out.append(_bad(mod_id, "%s.kind must be one of %s" % [where, ", ".join(KINDS)], where))
		return out
	var errs: Array[String] = []
	match str(kind):
		"rack_module": _rack_module(entry, errs, out, mod_id, entry_key(entry))
		"rack_preset":
			_str(entry, "name", errs)
			_str(entry, "title", errs)
			var patch: Variant = entry.get("patch")
			if not patch is Dictionary:
				errs.append("patch must be an object")
			elif (patch as Dictionary).has("file") and not patch["file"] is String:
				errs.append("patch.file must be a string")
		"plugin":
			var p: Variant = entry.get("plugin")
			if not p is Dictionary:
				errs.append("plugin must be an object")
			else:
				if not str(p.get("format", "")) in PLUGIN_FORMATS:
					errs.append("plugin.format must be one of %s" % ", ".join(PLUGIN_FORMATS))
				_str(p, "id", errs, "plugin.")
			var d: Variant = entry.get("display")
			if d is Dictionary:
				if (d as Dictionary).has("title"):
					_str(d, "title", errs, "display.")
				if (d as Dictionary).has("skin"):
					_skin(d["skin"], errs, "display.skin")
			elif entry.has("display"):
				errs.append("display must be an object")
		"skin":
			_str(entry, "for", errs)
			_skin(entry.get("skin"), errs, "skin")
		"piece":
			_str(entry, "id", errs)
			_str(entry, "title", errs)
			_str(entry, "builder", errs)
			_enum(entry, "class", PIECE_CLASSES, errs)
			_enum(entry, "mount", MOUNTS, errs)
	for e in errs:
		out.append(_bad(mod_id, "%s: %s" % [where, e], entry_key(entry)))
	return out


static func _rack_module(entry: Dictionary, errs: Array[String], out: Array[ModProblem],
		mod_id: String, key: String) -> void:
	var t: Variant = entry.get("type")
	if not t is String or not _id_ok(str(t)):
		errs.append("type must be a dotted lower-case id")
	var sound: Variant = entry.get("sound")
	if not sound is Dictionary or not (sound as Dictionary).get("kind") is String:
		errs.append("sound must be an object with a kind")
		return
	var sk: String = sound["kind"]
	if not sk in SOUND_KINDS:
		# Includes the reserved "native_plugin" (docs/mods.md 4.2): recognised, never loaded.
		out.append(ModProblem.make(&"unsupported_sound_kind", mod_id,
				"sound kind '%s' is not supported" % sk, key))
		return
	if sk == "engine":
		_str(sound, "type", errs, "sound.")
		for forbidden in ["interface"]:
			if entry.has(forbidden):
				errs.append("%s is read from the engine and must not be given" % forbidden)
		for forbidden in ["ins", "outs", "knobs"]:
			if sound.has(forbidden):
				errs.append("sound.%s is read from the engine and must not be given" % forbidden)
	else:
		if not sound.get("modules") is Dictionary or (sound["modules"] as Dictionary).is_empty():
			errs.append("sound.modules must be a non-empty object")
		for need in ["ins", "outs"]:
			if not sound.get(need) is Dictionary:
				errs.append("sound.%s must be an object" % need)
	for f in ["title", "group", "blurb"]:
		if sk == "composite" or entry.has(f):
			_str(entry, f, errs)
	_skin(entry.get("skin"), errs, "skin")
	if entry.has("pad_knobs"):
		var pk: Variant = entry["pad_knobs"]
		if not pk is Array or (pk as Array).size() != 2 or not (pk as Array).all(func(s: Variant) -> bool: return s is String):
			errs.append("pad_knobs must be two knob ids")
	if entry.has("face"):
		if not entry["face"] is Dictionary or not str(entry["face"].get("kind", "")) in FACES:
			errs.append("face.kind must be one of %s" % ", ".join(FACES))
	if entry.has("model"):
		if not entry["model"] is Dictionary or not entry["model"].get("glb") is String:
			errs.append("model.glb must be a string")
	if entry.has("mood"):
		var m: Variant = entry["mood"]
		if not m is Dictionary:
			errs.append("mood must be an object")
		else:
			if m.has("accent") and not _hex(m["accent"]):
				errs.append("mood.accent must be #RRGGBB")
			if m.has("reacts_to") and not str(m["reacts_to"]) in REACTS:
				errs.append("mood.reacts_to must be one of %s" % ", ".join(REACTS))
	if entry.has("port_signals"):
		var ps: Variant = entry["port_signals"]
		if not ps is Dictionary or not (ps as Dictionary).values().all(func(v: Variant) -> bool: return str(v) in SIGNALS):
			errs.append("port_signals values must be one of %s" % ", ".join(SIGNALS))


static func _skin(skin: Variant, errs: Array[String], label: String) -> void:
	if not skin is Dictionary:
		errs.append("%s must be an object" % label)
		return
	for c in ["face", "accent"]:
		if not _hex(skin.get(c)):
			errs.append("%s.%s must be #RRGGBB" % [label, c])
	for s in ["pattern", "tagline"]:
		_str(skin, s, errs, label + ".")


## True for a dotted lower-case id: `plaits`, `builtin.plaits`, `dawlings.sample.pluck`.
static func _id_ok(s: String) -> bool:
	var re := RegEx.create_from_string("^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)*$")
	return re.search(s) != null


static func _hex(v: Variant) -> bool:
	return v is String and RegEx.create_from_string(_HEX).search(v) != null


static func _str(d: Dictionary, k: String, errs: Array[String], prefix: String = "") -> void:
	if not d.get(k) is String or str(d[k]).is_empty():
		errs.append("%s%s must be a non-empty string" % [prefix, k])


static func _enum(d: Dictionary, k: String, allowed: Array[String], errs: Array[String]) -> void:
	if not str(d.get(k, "")) in allowed:
		errs.append("%s must be one of %s" % [k, ", ".join(allowed)])


static func _bad(mod_id: String, msg: String, entry: String) -> ModProblem:
	return ModProblem.make(&"bad_schema", mod_id, msg, entry)
