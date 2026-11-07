class_name LayoutProblem
extends RefCounted

## One thing that is wrong with a layout file, a fragment it extends or one of its entries
## (docs/layouts.md section 5). Parsing and merging never throw: they collect these and the caller
## decides what to show. An `error` makes the layout (or the entry) unusable; a `warning` is only
## reported. These are file-level problems; the placement issues of section 6 (`off_floor`,
## `too_close`, ...) are `LayoutIssue`s of the validator, a later step.

const ERROR := &"error"
const WARNING := &"warning"

## Every code the parser, the merge and the loader raise.
const CODES: Array[StringName] = [
	&"no_file", &"bad_json", &"bad_schema", &"unknown_key", &"version_unsupported",
	&"duplicate_id", &"unknown_anchor", &"unknown_piece", &"cycle",
	&"extends_missing", &"extends_cycle", &"id_collision", &"bad_variant", &"over_limit",
]

## One of CODES.
var code: StringName = &""
## The id of the layout it is about, or the file name when the layout has no usable id.
var layout := ""
## Where in the layout, as a path such as `pieces[2].at.pos`; empty for the whole layout.
var where := ""
## A sentence a person can read, naming what is wrong.
var message := ""
## ERROR or WARNING.
var severity: StringName = ERROR


## Builds a problem in one call.
static func make(code_: StringName, layout_: String, message_: String, where_: String = "",
		severity_: StringName = ERROR) -> LayoutProblem:
	var p := LayoutProblem.new()
	p.code = code_
	p.layout = layout_
	p.message = message_
	p.where = where_
	p.severity = severity_
	return p


## True when the problem makes its layout or entry unusable.
func is_error() -> bool:
	return severity == ERROR


func _to_string() -> String:
	var at := layout if where.is_empty() else "%s:%s" % [layout, where]
	return "[%s] %s %s: %s" % [severity, code, at, message]
