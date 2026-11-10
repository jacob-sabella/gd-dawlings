class_name AssistantStream
extends RefCounted

## Claude Code's `--output-format stream-json` read for the assistant (docs/mcp_assistant.md): a line at a time into
## the events its panel shows. Like WorkshopStream, but the assistant has the game's tools and no files, so a tool
## row says what the game was asked (`track_set_volume  Pad -6`) and what came back, and its words are kept whole.
##
## An event is {kind, text} and for tools {tool, args, ok}. Kinds: init, say, tool, tool_result, result, error, raw.

const INIT := &"init"
const SAY := &"say"
const TOOL := &"tool"
const TOOL_RESULT := &"tool_result"
const RESULT := &"result"
const ERROR := &"error"
const RAW := &"raw"

const SAY_MAX := 1200
const ROW_MAX := 200
const SERVER := "mcp__dawlings__"

var session_id := ""
var model := ""
var result_text := ""
var is_error := false
var done := false
var cost_usd := 0.0
var turns := 0
var _pending := {}


func feed(line: String) -> Array:
	var s := line.strip_edges()
	if s == "":
		return []
	var json := JSON.new()
	if not s.begins_with("{") or json.parse(s) != OK or not (json.data is Dictionary):
		return [{"kind": RAW, "text": s.left(ROW_MAX)}]
	return event(json.data)


func event(e: Dictionary) -> Array:
	var out: Array = []
	match str(e.get("type", "")):
		"system":
			if str(e.get("subtype", "")) == "init":
				session_id = str(e.get("session_id", session_id))
				model = str(e.get("model", ""))
				out.append({"kind": INIT, "text": "started" + ((" on " + model) if model != "" else "")})
		"assistant":
			var msg: Dictionary = e.get("message", {}) if e.get("message") is Dictionary else {}
			for b in msg.get("content", []):
				if not (b is Dictionary):
					continue
				match str(b.get("type", "")):
					"text":
						var t := str(b.get("text", "")).strip_edges()
						if t != "":
							out.append({"kind": SAY, "text": t.left(SAY_MAX)})
					"tool_use":
						var name := short_name(str(b.get("name", "tool")))
						var input: Dictionary = b.get("input", {}) if b.get("input") is Dictionary else {}
						_pending[str(b.get("id", ""))] = name
						out.append({"kind": TOOL, "tool": name, "args": input, "text": row(name, input)})
		"user":
			var msg: Dictionary = e.get("message", {}) if e.get("message") is Dictionary else {}
			if msg.get("content") is Array:
				for b in msg["content"]:
					if b is Dictionary and str(b.get("type", "")) == "tool_result":
						var text := _text_of(b.get("content", ""))
						out.append({"kind": TOOL_RESULT, "tool": _pending.get(str(b.get("tool_use_id", "")), ""),
								"ok": not bool(b.get("is_error", false)), "text": text.left(ROW_MAX)})
		"result":
			done = true
			is_error = bool(e.get("is_error", false)) or str(e.get("subtype", "success")) != "success"
			result_text = str(e.get("result", ""))
			cost_usd = float(e.get("total_cost_usd", 0.0))
			turns = int(e.get("num_turns", 0))
			if is_error:
				out.append({"kind": ERROR, "text": "stopped: " + (result_text if result_text != "" else str(e.get("subtype", "error"))).split("\n")[0].left(ROW_MAX)})
			else:
				out.append({"kind": RESULT, "text": result_text.strip_edges().left(SAY_MAX)})
	return out


## `mcp__dawlings__track_set` is `track_set`.
static func short_name(n: String) -> String:
	return n.trim_prefix(SERVER)


## One tool row: the name and its arguments on a line.
static func row(name: String, args: Dictionary) -> String:
	var bits := PackedStringArray()
	for k in args:
		var v: Variant = args[k]
		var vs := JSON.stringify(v) if typeof(v) in [TYPE_ARRAY, TYPE_DICTIONARY] else str(v)
		bits.append("%s=%s" % [k, vs])
	var t := "%s  %s" % [name, " ".join(bits)]
	return t.left(ROW_MAX - 1) + "…" if t.length() > ROW_MAX else t


static func _text_of(content: Variant) -> String:
	if content is String:
		return content
	var parts := PackedStringArray()
	if content is Array:
		for c in content:
			if c is Dictionary and c.has("text"):
				parts.append(str(c["text"]))
	return "\n".join(parts)
