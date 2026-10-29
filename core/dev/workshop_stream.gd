class_name WorkshopStream
extends RefCounted

## Claude Code's `--output-format stream-json` read a line at a time into what the Workshop panel
## says while a request runs (docs/workshop.md).
##
## Each line of the stream is one JSON event: `system` (init: the session id, the model, the tools),
## `assistant` (a message whose content is text and tool_use blocks: Read, Edit, Write, Bash...),
## `user` (the tool_result blocks answering them) and, last, `result` (the final text, whether it
## is an error, the turns and the cost). `feed` takes one line and answers the progress lines it
## makes ({kind, text}), and keeps what the Workshop needs afterwards: the session id (for "ask
## Claude to fix it", which resumes it), the files edited, the test summary lines seen, the final
## text and its SUMMARY and TESTS lines.
##
## A line that is not JSON (a warning on stdout, a partial line) is kept as a `raw` line rather
## than dropped: when something goes wrong it is usually the only clue.

## The kinds of progress line.
const INIT := &"init"
const SAY := &"say"
const TOOL := &"tool"
const EDIT := &"edit"
const TESTS := &"tests"
const FAILED := &"failed"
const RESULT := &"result"
const ERROR := &"error"
const RAW := &"raw"

## The most a progress line says (characters): the panel is a wall, not a terminal.
const LINE_MAX := 160

var session_id := ""
var model := ""
## Repo-relative paths written by Edit / Write / NotebookEdit, in the order first touched.
var files: PackedStringArray = []
## "N checks, M failed" lines and FAIL lines seen in tool results.
var test_lines: PackedStringArray = []
## The final text, and whether the run ended in an error; `done` once a result event arrived.
var result_text := ""
var is_error := false
var done := false
var cost_usd := 0.0
var turns := 0
## The repo's absolute path, so a tool's file_path is said relative to it.
var repo := ""

## tool_use id -> tool name, so a tool_result can say what it answers.
var _pending := {}


func _init(repo_path := "") -> void:
	repo = repo_path.trim_suffix("/")


## One line of the stream in; the progress lines it makes out (Array of {kind, text}).
func feed(line: String) -> Array:
	var s := line.strip_edges()
	if s.is_empty():
		return []
	# An instance's parse, which says nothing in the log about a line that is not JSON.
	var json := JSON.new()
	if not s.begins_with("{") or json.parse(s) != OK or not (json.data is Dictionary):
		return [_line(RAW, s)]
	return event(json.data)


## One parsed event in; the progress lines it makes.
func event(e: Dictionary) -> Array:
	var out: Array = []
	match str(e.get("type", "")):
		"system":
			if str(e.get("subtype", "")) == "init":
				session_id = str(e.get("session_id", session_id))
				model = str(e.get("model", ""))
				out.append(_line(INIT, "started%s" % ((" on " + model) if model != "" else "")))
		"assistant":
			var msg: Dictionary = e.get("message", {}) if e.get("message") is Dictionary else {}
			for block in msg.get("content", []):
				if not (block is Dictionary):
					continue
				match str(block.get("type", "")):
					"text":
						var t := str(block.get("text", "")).strip_edges()
						if t != "":
							out.append(_line(SAY, t.split("\n")[0]))
					"tool_use":
						out.append(_tool_use(block))
		"user":
			var msg: Dictionary = e.get("message", {}) if e.get("message") is Dictionary else {}
			var content: Variant = msg.get("content", [])
			if content is Array:
				for block in content:
					if block is Dictionary and str(block.get("type", "")) == "tool_result":
						out.append_array(_tool_result(block))
		"result":
			done = true
			is_error = bool(e.get("is_error", false)) or str(e.get("subtype", "success")) != "success"
			result_text = str(e.get("result", ""))
			cost_usd = float(e.get("total_cost_usd", 0.0))
			turns = int(e.get("num_turns", 0))
			if is_error:
				var why := result_text if result_text != "" else str(e.get("subtype", "error"))
				out.append(_line(ERROR, "stopped: " + why.split("\n")[0]))
			else:
				out.append(_line(RESULT, summary() if summary() != "" else result_text.split("\n")[0]))
	return out


## The final text's `SUMMARY:` line (the prompt asks for one), or its first line.
func summary() -> String:
	for l in result_text.split("\n"):
		var t := l.strip_edges()
		if t.to_upper().begins_with("SUMMARY:"):
			return t.substr(8).strip_edges()
	return result_text.strip_edges().split("\n")[0] if result_text.strip_edges() != "" else ""


## The tests the final text names on its `TESTS:` line (`_test_a, _test_b`), or none.
func tests() -> PackedStringArray:
	var out := PackedStringArray()
	for l in result_text.split("\n"):
		var t := l.strip_edges()
		if t.to_upper().begins_with("TESTS:"):
			for name in t.substr(6).replace(" ", ",").split(",", false):
				var n := name.strip_edges().trim_prefix("`").trim_suffix("`")
				if n.begins_with("_test_") and not out.has(n):
					out.append(n)
	return out


func _tool_use(block: Dictionary) -> Dictionary:
	var name := str(block.get("name", "tool"))
	var input: Dictionary = block.get("input", {}) if block.get("input") is Dictionary else {}
	_pending[str(block.get("id", ""))] = name
	match name:
		"Edit", "Write", "NotebookEdit", "MultiEdit":
			var path := _relative(str(input.get("file_path", input.get("notebook_path", ""))))
			if path != "" and not files.has(path):
				files.append(path)
			return _line(EDIT, "%s %s" % ["wrote" if name == "Write" else "edited", path])
		"Read":
			return _line(TOOL, "read " + _relative(str(input.get("file_path", ""))))
		"Bash":
			var cmd := str(input.get("command", "")).replace(repo, ".")
			return _line(TOOL, "$ " + cmd.split("\n")[0])
		"Grep", "Glob":
			return _line(TOOL, "%s %s" % [name.to_lower(), str(input.get("pattern", ""))])
	return _line(TOOL, name)


func _tool_result(block: Dictionary) -> Array:
	var out: Array = []
	var text := _text_of(block.get("content", ""))
	var tool: String = _pending.get(str(block.get("tool_use_id", "")), "")
	for l in text.split("\n"):
		var t := l.strip_edges()
		if t.contains(" checks, ") and t.ends_with("failed"):
			test_lines.append(t)
			out.append(_line(TESTS, t))
		elif t.begins_with("FAIL"):
			test_lines.append(t)
			out.append(_line(FAILED, t))
		elif t.contains("SCRIPT ERROR") or t.contains("Parse Error"):
			out.append(_line(FAILED, t))
	if bool(block.get("is_error", false)) and out.is_empty():
		out.append(_line(FAILED, "%s refused: %s" % [tool if tool != "" else "tool", text.split("\n")[0]]))
	return out


static func _text_of(content: Variant) -> String:
	if content is String:
		return content
	var parts := PackedStringArray()
	if content is Array:
		for c in content:
			if c is Dictionary and c.has("text"):
				parts.append(str(c["text"]))
	return "\n".join(parts)


func _relative(path: String) -> String:
	if repo != "" and path.begins_with(repo + "/"):
		return path.substr(repo.length() + 1)
	return path


static func _line(kind: StringName, text: String) -> Dictionary:
	var t := text.strip_edges()
	if t.length() > LINE_MAX:
		t = t.left(LINE_MAX - 1) + "…"
	return {"kind": kind, "text": t}
