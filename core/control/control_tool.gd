class_name ControlTool
extends RefCounted

## One tool of the control API (docs/mcp_assistant.md): a name, a JSON schema for its arguments, a tier
## that says what may be done without a person, and the handler that does it through the verb the
## game's own controls use.
##
## Names are `<domain>_<op>`, the ops being list, get, add, set and remove (and a few actions of a
## domain: transport_play, rack_tidy). A handler takes the arguments Dictionary and returns either
## `ControlTool.ok(data)` or `ControlTool.fail("why")`; the why is the game's own refusal text where it has one.

## Anything that only reads.
const READ := 0
## Changes something, and a change set can take it back.
const EDIT := 1
## Throws something away or replaces a whole: a person confirms it first (ControlApi.confirm).
const DESTRUCTIVE := 2

var name := ""
var domain := ""
var summary := ""
var schema: Dictionary = {}
var tier := READ
var handler := Callable()


static func make(tool_name: String, tool_summary: String, props: Dictionary, required: Array, tool_tier: int,
		fn: Callable) -> ControlTool:
	var t := ControlTool.new()
	t.name = tool_name
	t.domain = tool_name.get_slice("_", 0)
	t.summary = tool_summary
	t.schema = {"type": "object", "properties": props, "required": required, "additionalProperties": false}
	t.tier = tool_tier
	t.handler = fn
	return t


static func ok(data: Variant = null) -> Dictionary:
	return {"ok": true, "data": data}


static func fail(why: String) -> Dictionary:
	return {"ok": false, "error": why}


# --- schema property helpers -------------------------------------------------------------------

static func str_p(desc: String, choices: Array = []) -> Dictionary:
	var p := {"type": "string", "description": desc}
	if not choices.is_empty():
		p["enum"] = choices
	return p


static func num_p(desc: String, lo: Variant = null, hi: Variant = null) -> Dictionary:
	var p := {"type": "number", "description": desc}
	if lo != null:
		p["minimum"] = lo
	if hi != null:
		p["maximum"] = hi
	return p


static func int_p(desc: String, lo: Variant = null, hi: Variant = null) -> Dictionary:
	var p := num_p(desc, lo, hi)
	p["type"] = "integer"
	return p


## A reference to a thing by name or by its number, as the list tools show them: a string ("Kick", "#3") or an integer.
static func ref_p(desc: String) -> Dictionary:
	return {"type": ["string", "integer"], "description": desc}


static func bool_p(desc: String) -> Dictionary:
	return {"type": "boolean", "description": desc}


static func arr_p(desc: String, items: Dictionary = {}) -> Dictionary:
	var p := {"type": "array", "description": desc}
	if not items.is_empty():
		p["items"] = items
	return p


static func obj_p(desc: String) -> Dictionary:
	return {"type": "object", "description": desc}


## The MCP `tools/list` row for this tool.
func describe() -> Dictionary:
	var suffix := ""
	if tier == DESTRUCTIVE:
		suffix = " (destructive: the player is asked to confirm)"
	return {"name": name, "description": summary + suffix, "inputSchema": schema,
			"annotations": {"readOnlyHint": tier == READ, "destructiveHint": tier == DESTRUCTIVE}}


## The reasons `args` do not fit the schema, empty when they do. Also converts whole floats to ints where the
## schema says integer (JSON has one number type).
func check(args: Dictionary) -> Array[String]:
	var bad: Array[String] = []
	var props: Dictionary = schema.get("properties", {})
	for r in schema.get("required", []):
		if not args.has(r):
			bad.append("missing '%s'" % r)
	for k in args.keys():
		if not props.has(k):
			bad.append("unknown argument '%s'" % k)
			continue
		var p: Dictionary = props[k]
		var v: Variant = args[k]
		var kind: Variant = p.get("type", "")
		if typeof(kind) == TYPE_ARRAY:
			# A reference: a name or a number.
			var fits := false
			for one in kind:
				if (one == "string" and typeof(v) in [TYPE_STRING, TYPE_STRING_NAME]) \
						or (one == "integer" and typeof(v) in [TYPE_INT, TYPE_FLOAT] and float(v) == floorf(float(v))) \
						or (one == "number" and typeof(v) in [TYPE_INT, TYPE_FLOAT]):
					fits = true
			if not fits:
				bad.append("'%s' must be a %s" % [k, " or ".join(PackedStringArray(kind))])
			elif typeof(v) == TYPE_FLOAT:
				args[k] = int(v)
			continue
		match kind:
			"string":
				if typeof(v) != TYPE_STRING and typeof(v) != TYPE_STRING_NAME:
					bad.append("'%s' must be a string" % k)
				elif p.has("enum") and not (str(v) in p["enum"]):
					bad.append("'%s' must be one of %s" % [k, ", ".join(PackedStringArray(p["enum"]))])
			"number", "integer":
				if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
					bad.append("'%s' must be a number" % k)
				else:
					if p["type"] == "integer":
						if float(v) != floorf(float(v)):
							bad.append("'%s' must be a whole number" % k)
						else:
							args[k] = int(v)
					if p.has("minimum") and float(v) < float(p["minimum"]):
						bad.append("'%s' is below %s" % [k, p["minimum"]])
					if p.has("maximum") and float(v) > float(p["maximum"]):
						bad.append("'%s' is above %s" % [k, p["maximum"]])
			"boolean":
				if typeof(v) != TYPE_BOOL:
					bad.append("'%s' must be true or false" % k)
			"array":
				if typeof(v) != TYPE_ARRAY:
					bad.append("'%s' must be a list" % k)
			"object":
				if typeof(v) != TYPE_DICTIONARY:
					bad.append("'%s' must be an object" % k)
	return bad
