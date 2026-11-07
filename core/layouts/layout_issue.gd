class_name LayoutIssue
extends RefCounted

## One thing the validator found wrong with where a room's pieces stand (docs/layouts.md section 6).
## Unlike a LayoutProblem, which is about a file, an issue needs a shell: it names the piece at fault,
## the one it clashes with, a point to mark it at, and a sentence a player can read.

const ERROR := 0
const WARNING := 1

## Every code the validator raises. Structure first (the parser's own problems, passed through),
## then placement, then room-scale claims, then what is missing.
const CODES: Array[StringName] = [
	&"schema", &"duplicate_id", &"unknown_piece", &"unknown_anchor", &"cycle", &"over_limit",
	&"off_floor", &"hits_solid", &"too_close", &"unreachable", &"no_seat", &"group_spread",
	&"needs_missing", &"door_blocked", &"site_taken", &"wall_uncuttable", &"unavailable_mod",
]

## One of CODES.
var code: StringName = &""
## ERROR (blocks saving) or WARNING (reported only).
var severity := ERROR
## The piece at fault; empty when the layout as a whole is.
var piece: StringName = &""
## What it clashes with, if anything: another piece, a zone (`zone.synth`), `control_room`, `solid`.
var other: StringName = &""
## Where, on the floor, for a marker in edit mode.
var at := Vector2.ZERO
## A sentence for the player.
var message := ""
## Optional `{"pos": [x, z]}`: the nearest floor point the piece's origin could stand at without
## this issue (only when asked for: opts `fix`).
var fix: Dictionary = {}


## Builds an issue in one call.
static func make(code_: StringName, severity_: int, piece_: StringName, other_: StringName, at_: Vector2,
		message_: String) -> LayoutIssue:
	var i := LayoutIssue.new()
	i.code = code_
	i.severity = severity_
	i.piece = piece_
	i.other = other_
	i.at = at_
	i.message = message_
	return i


## True for an issue that blocks saving.
func is_error() -> bool:
	return severity == ERROR


func _to_string() -> String:
	return "[%s] %s %s%s: %s" % ["error" if is_error() else "warning", code, piece,
			"~" + String(other) if other != &"" else "", message]
