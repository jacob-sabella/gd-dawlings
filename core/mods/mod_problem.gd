class_name ModProblem
extends RefCounted

## One thing that is wrong with a mod, a manifest or one of its entries (docs/mods.md section 5).
## The loader never throws: it collects these, and the game decides what to show. A problem with
## severity `error` makes its mod or entry unavailable; a `warning` is only reported.

const ERROR := &"error"
const WARNING := &"warning"

## Codes raised by the parser, the folder loader and the registry (migration steps 1 and 2).
const CODES: Array[StringName] = [
	&"no_manifest", &"bad_json", &"bad_schema", &"unknown_key",
	&"api_version_unsupported", &"game_too_old",
	&"id_collision", &"type_collision", &"reserved_id",
	&"missing_dependency", &"dependency_cycle",
	&"missing_file", &"bad_model", &"unsupported_sound_kind", &"unknown_group",
]

## Codes from docs/mods.md section 5 that need machinery not built yet, so nothing raises them
## today: the engine snapshot (3), composite expansion (7), plugin scan (8), source pins (10).
const LATER_CODES: Array[StringName] = [
	&"engine_type_missing", &"engine_unavailable", &"snapshot_stale", &"binary_hash_mismatch",
	&"unsupported_platform", &"composite_invalid", &"plugin_not_found",
]

## One of CODES (or LATER_CODES).
var code: StringName = &""
## The id of the mod it is about, or the folder name when the mod has no usable id.
var mod := ""
## The entry it is about (see ModManifest.entry_key), empty when it is about the whole mod.
var entry := ""
## A sentence a person can read, naming what is wrong.
var message := ""
## ERROR or WARNING.
var severity: StringName = ERROR


## Builds a problem in one call.
static func make(code_: StringName, mod_: String, message_: String, entry_: String = "",
		severity_: StringName = ERROR) -> ModProblem:
	var p := ModProblem.new()
	p.code = code_
	p.mod = mod_
	p.message = message_
	p.entry = entry_
	p.severity = severity_
	return p


## True when the problem makes its mod or entry unavailable.
func is_error() -> bool:
	return severity == ERROR


func _to_string() -> String:
	var where := mod if entry.is_empty() else "%s/%s" % [mod, entry]
	return "[%s] %s %s: %s" % [severity, code, where, message]
