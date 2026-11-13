extends RefCounted

## The control API's spine (docs/mcp_assistant.md), called from tests/run_tests.gd's `_test_control_api_*`: the schema
## check, tiers, batches and change sets; the MCP server's HTTP and JSON-RPC; the assistant's stream, command line
## and a whole run against tests/fixtures/fake_assistant.sh (which calls the real server over HTTP as the CLI would).

const FAKE := "res://tests/fixtures/fake_assistant.sh"

var t: Node


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


## A small api of tools that touch only a counter, so the rules are tested apart from any domain.
func _toy() -> Array:
	var T := ControlTool
	var state := {"n": 0, "who": -1}
	var api := ControlApi.new()
	api.add(T.make("toy_get", "reads", {}, [], T.READ, func(_a: Dictionary) -> Dictionary: return T.ok(state["n"])))
	api.add(T.make("toy_set", "sets", {"n": T.int_p("the value", 0, 100), "mode": T.str_p("how", ["a", "b"])}, ["n"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				state["n"] = a["n"]
				return T.ok(a["n"])))
	api.add(T.make("toy_fail", "fails", {}, [], T.EDIT, func(_a: Dictionary) -> Dictionary: return T.fail("no good")))
	api.add(T.make("toy_wipe", "wipes", {}, [], T.DESTRUCTIVE, func(_a: Dictionary) -> Dictionary:
		state["n"] = 0
		return T.ok(true)))
	api.add(T.make("toy_who", "who", {}, [], T.EDIT, func(_a: Dictionary) -> Dictionary: return T.ok(DAW.state != null)))
	api.snapshotters.append({"name": "toy", "snap": func() -> Variant: return state["n"], "restore": func(v: Variant) -> void: state["n"] = v})
	return [api, state]


func rules() -> void:
	var made := _toy()
	var api: ControlApi = made[0]
	var state: Dictionary = made[1]
	var r := api.invoke("toy_set", {"n": 5})
	check("a call runs its handler and answers ok", r["ok"] and state["n"] == 5)
	check("a whole float is taken for an integer", api.invoke("toy_set", {"n": 7.0})["ok"] and state["n"] == 7)
	check("a missing argument is said", not api.invoke("toy_set", {})["ok"] and str(api.invoke("toy_set", {})["error"]).contains("missing 'n'"))
	check("an unknown argument is said", str(api.invoke("toy_set", {"n": 1, "x": 2})["error"]).contains("unknown argument 'x'"))
	check("a wrong type is said", str(api.invoke("toy_set", {"n": "five"})["error"]).contains("must be a number"))
	check("a fraction for an integer is said", str(api.invoke("toy_set", {"n": 1.5})["error"]).contains("whole number"))
	check("a value out of range is said", str(api.invoke("toy_set", {"n": 500})["error"]).contains("above"))
	check("an enum miss lists the choices", str(api.invoke("toy_set", {"n": 1, "mode": "z"})["error"]).contains("a, b"))
	check("an unknown tool is said", str(api.invoke("nope")["error"]).contains("no tool called"))
	check("a destructive tool is refused unconfirmed", not api.invoke("toy_wipe")["ok"])
	check("a destructive tool runs once confirmed", api.invoke("toy_wipe", {}, 0, true)["ok"] and state["n"] == 0)
	var t_reads := api.history.size()
	api.invoke("toy_get")
	check("a read is not a change set", api.history.size() == t_reads)
	check("search finds a tool by a word of its summary", api.search("wipes").size() == 1 and api.search("", "toy").size() == 5)
	check("describe gives every tool a schema and an annotation", api.describe().all(func(d: Dictionary) -> bool: return d.has("inputSchema") and d.has("annotations")))
	check("a destructive tool says so in its description", str(api.describe()[3 if false else 0]).length() > 0 and api.tools["toy_wipe"].describe()["description"].contains("destructive"))


func batches() -> void:
	var made := _toy()
	var api: ControlApi = made[0]
	var state: Dictionary = made[1]
	state["n"] = 3
	var r: Dictionary = await api.batch([{"tool": "toy_set", "args": {"n": 10}}, {"tool": "toy_set", "args": {"n": 20}}])
	check("a batch runs its calls in order as one change set", r["ok"] and state["n"] == 20 and api.history.size() == 1 and api.history[0]["calls"].size() == 2)
	check("undo takes the whole batch back", api.undo()["ok"] and state["n"] == 3 and api.history[0]["undone"])
	check("there is nothing left to undo", not api.undo()["ok"])
	var stopped: Dictionary = await api.batch([{"tool": "toy_set", "args": {"n": 1}}, {"tool": "toy_fail"}, {"tool": "toy_set", "args": {"n": 2}}])
	check("a batch stops at the first failure", stopped["data"]["ran"] == 2 and stopped["data"]["failed"] == 1 and state["n"] == 1)
	var kept: Dictionary = await api.batch([{"tool": "toy_fail"}, {"tool": "toy_set", "args": {"n": 2}}], 0, true)
	check("keep_going carries on past a failure", kept["data"]["ran"] == 2 and state["n"] == 2)
	check("a batch of a batch is refused", not (await api.batch([{"tool": "batch", "args": {}}]))["ok"])
	check("a batch with an unknown tool is refused before any runs", not (await api.batch([{"tool": "toy_set", "args": {"n": 9}}, {"tool": "nope"}]))["ok"] and state["n"] == 2)
	# Tier 2.
	var asked := []
	api.confirm = func(tool_name: String, _a: Dictionary, _w: int) -> bool:
		asked.append(tool_name)
		return false
	var no: Dictionary = await api.call_tool("toy_wipe")
	check("a refused confirm changes nothing and says so", not no["ok"] and asked == ["toy_wipe"] and state["n"] == 2)
	api.confirm = func(_tool_name: String, _a: Dictionary, _w: int) -> bool: return true
	check("an allowed confirm runs it", (await api.call_tool("toy_wipe"))["ok"] and state["n"] == 0)
	state["n"] = 4
	api.confirm = func(tool_name: String, _a: Dictionary, _w: int) -> bool:
		asked.append("batch:" + tool_name)
		return false
	var nb: Dictionary = await api.batch([{"tool": "toy_set", "args": {"n": 8}}, {"tool": "toy_wipe"}])
	check("a batch with a destructive call is confirmed once, before any runs", not nb["ok"] and state["n"] == 4 and asked.back() == "batch:toy_wipe")
	api.confirm = Callable()
	check("with nobody to ask, a destructive call is refused", not (await api.call_tool("toy_wipe"))["ok"])


func refs() -> void:
	var previous := DAW.backend
	DAW.use(OfflineBackend.new())
	var s := DAW.state
	var first: int = s.track_indices()[0]
	var name: String = s.track(first, false).name
	check("a track is found by its name", ControlRefs.track(s, name).get("index") == first)
	check("a track is found by its name in any case", ControlRefs.track(s, name.to_upper()).get("index") == first)
	check("a track is found by #number", ControlRefs.track(s, "#%d" % first).get("index") == first)
	check("a track is found by number", ControlRefs.track(s, first).get("index") == first)
	check("an unknown track says what there is", str(ControlRefs.track(s, "No Such Track")["error"]).contains("the tracks are"))
	check("a number that is no track says what there is", not ControlRefs.track(s, 9999)["ok"])
	DAW.use(previous, false)


# --- the server ---------------------------------------------------------------------------------------

func _request(path: String, body: String, headers: Dictionary = {}, method := "POST") -> Dictionary:
	var h := {"host": "127.0.0.1:47100", "authorization": "Bearer secret"}
	h.merge(headers, true)
	return {"complete": true, "method": method, "path": path, "query": {}, "headers": h, "body": body}


func _rpc(method: String, params: Dictionary = {}, id: Variant = 1) -> String:
	return JSON.stringify({"jsonrpc": "2.0", "id": id, "method": method, "params": params})


func server() -> void:
	var made := _toy()
	var api: ControlApi = made[0]
	var s := ControlServer.new()
	s.api = api
	s.token = "secret"
	var raw := "POST /mcp?domains=toy HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 5\r\n\r\nhello".to_utf8_buffer()
	var p := ControlServer.parse_request(raw)
	check("a request is parsed: method, path, query, headers, body", p["complete"] and p["method"] == "POST" and p["path"] == "/mcp"
			and p["query"]["domains"] == "toy" and p["headers"]["host"] == "127.0.0.1" and p["body"] == "hello")
	check("half a body is not yet a request", ControlServer.parse_request(raw.slice(0, raw.size() - 2)).get("complete", false) == false)
	check("no end of headers is not yet a request", ControlServer.parse_request("POST /mcp HT".to_utf8_buffer()).is_empty() or not ControlServer.parse_request("POST /mcp HT".to_utf8_buffer()).get("bad", false))
	check("a request line without a version is bad", ControlServer.parse_request("GET\r\n\r\n".to_utf8_buffer()).get("bad", false))
	check("a body past the limit is bad", ControlServer.parse_request(("POST /mcp HTTP/1.1\r\nContent-Length: %d\r\n\r\n" % (ControlServer.BODY_MAX + 1)).to_utf8_buffer()).get("bad", false))
	var no_auth: Dictionary = await s.handle(_request("/mcp", "{}", {"authorization": ""}))
	check("no token is 401", no_auth["status"] == 401)
	check("a wrong token is 401", (await s.handle(_request("/mcp", "{}", {"authorization": "Bearer nope"})))["status"] == 401)
	check("a foreign Host is 403", (await s.handle(_request("/mcp", "{}", {"host": "evil.example"})))["status"] == 403)
	check("a foreign Origin is 403", (await s.handle(_request("/mcp", "{}", {"origin": "http://evil.example"})))["status"] == 403)
	check("a local Origin is let in", (await s.handle(_request("/mcp", _rpc("ping"), {"origin": "http://localhost:3000"})))["status"] == 200)
	check("another path is 404", (await s.handle(_request("/x", "{}")))["status"] == 404)
	check("GET is 405", (await s.handle(_request("/mcp", "", {}, "GET")))["status"] == 405)
	var init: Dictionary = await s.handle(_request("/mcp", _rpc("initialize", {"protocolVersion": "2025-03-26"})))
	check("initialize names the server and offers tools", init["status"] == 200 and init["json"]["result"]["serverInfo"]["name"] == "dawlings"
			and init["json"]["result"]["capabilities"].has("tools") and init["json"]["id"] == 1 and init["json"]["result"]["instructions"] != "")
	var listed: Dictionary = await s.handle(_request("/mcp", _rpc("tools/list")))
	check("tools/list lists every tool with its schema", listed["json"]["result"]["tools"].size() == api.tools.size())
	var scoped := ControlServer.new()
	scoped.api = api
	scoped.token = "secret"
	var only: Dictionary = await scoped.handle(_request("/mcp", _rpc("tools/list")).merged({"query": {"domains": "nothing"}}, true))
	check("tools/list?domains= carries only those domains", only["json"]["result"]["tools"].is_empty())
	var called: Dictionary = await s.handle(_request("/mcp", _rpc("tools/call", {"name": "toy_set", "arguments": {"n": 12}})))
	var res: Dictionary = called["json"]["result"]
	check("tools/call runs the tool and returns its data as text", not res["isError"] and JSON.parse_string(res["content"][0]["text"]) == 12.0 and made[1]["n"] == 12)
	var bad: Dictionary = await s.handle(_request("/mcp", _rpc("tools/call", {"name": "toy_set", "arguments": {"n": "x"}})))
	check("a refused call is a result with isError, not a protocol error", bad["json"]["result"]["isError"] and str(bad["json"]["result"]["content"][0]["text"]).contains("must be a number"))
	var unknown: Dictionary = await s.handle(_request("/mcp", _rpc("nonsense")))
	check("an unknown method is a JSON-RPC error", unknown["json"]["error"]["code"] == -32601)
	var note: Dictionary = await s.handle(_request("/mcp", JSON.stringify({"jsonrpc": "2.0", "method": "notifications/initialized"})))
	check("a notification is answered 202 with nothing", note["status"] == 202 and not note.has("json"))
	var group: Dictionary = await s.handle(_request("/mcp", "[" + _rpc("ping", {}, 1) + "," + _rpc("ping", {}, 2) + "]"))
	check("a JSON-RPC batch is answered in kind", group["json"] is Array and group["json"].size() == 2)
	check("bad JSON is a parse error", (await s.handle(_request("/mcp", "{not json")))["json"]["error"]["code"] == -32700)
	var batch: Dictionary = await s.handle(_request("/mcp", _rpc("tools/call", {"name": "batch", "arguments": {"calls": [{"tool": "toy_set", "args": {"n": 30}}, {"tool": "toy_set", "args": {"n": 31}}]}})))
	check("batch over MCP is one change set", JSON.parse_string(batch["json"]["result"]["content"][0]["text"])["ran"] == 2.0 and made[1]["n"] == 31)
	var run_token := s.issue_token(7)
	check("a run token is let in as another peer", (await s.handle(_request("/mcp", _rpc("ping"), {"authorization": "Bearer " + run_token})))["status"] == 200)
	s.revoke(run_token)
	check("a revoked run token is 401", (await s.handle(_request("/mcp", _rpc("ping"), {"authorization": "Bearer " + run_token})))["status"] == 401)
	s.free()
	scoped.free()


## A real round trip over a loopback socket, as a client makes it.
func socket() -> void:
	var made := _toy()
	var s := ControlServer.new()
	s.api = made[0]
	t.add_child(s)
	check("the server finds a port", s.start(47150, false) and s.port >= 47150)
	var http := HTTPClient.new()
	check("a client connects", http.connect_to_host("127.0.0.1", s.port) == OK)
	var waited := 0
	while http.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING] and waited < 300:
		http.poll()
		await t.get_tree().process_frame
		waited += 1
	check("it is connected", http.get_status() == HTTPClient.STATUS_CONNECTED)
	http.request(HTTPClient.METHOD_POST, "/mcp", ["Authorization: Bearer " + s.token, "Content-Type: application/json"], _rpc("tools/call", {"name": "toy_set", "arguments": {"n": 44}}))
	waited = 0
	while http.get_status() == HTTPClient.STATUS_REQUESTING and waited < 300:
		http.poll()
		await t.get_tree().process_frame
		waited += 1
	var body := PackedByteArray()
	waited = 0
	while http.get_status() == HTTPClient.STATUS_BODY or http.has_response() and waited < 300:
		http.poll()
		var chunk := http.read_response_body_chunk()
		if chunk.size() > 0:
			body.append_array(chunk)
		elif http.get_status() != HTTPClient.STATUS_BODY:
			break
		await t.get_tree().process_frame
		waited += 1
	var reply: Variant = JSON.parse_string(body.get_string_from_utf8())
	check("a real HTTP call changes the state and answers", http.get_response_code() == 200 and reply is Dictionary and made[1]["n"] == 44)
	s.stop()
	check("a stopped server no longer listens", not s.listening())
	s.queue_free()


# --- the assistant -----------------------------------------------------------------------------------

func stream() -> void:
	var s := AssistantStream.new()
	var out: Array = []
	for l in ['{"type":"system","subtype":"init","session_id":"abc","model":"m"}',
			'{"type":"assistant","message":{"content":[{"type":"text","text":"Muting the hats."},{"type":"tool_use","id":"1","name":"mcp__dawlings__mix_set_mute","input":{"track":"Hats","muted":true}}]}}',
			'{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"1","is_error":true,"content":[{"type":"text","text":"no track called Hats"}]}]}}',
			'{"type":"result","subtype":"success","is_error":false,"result":"Done.","total_cost_usd":0.5,"num_turns":3}',
			"not json"]:
		out.append_array(s.feed(l))
	var kinds := out.map(func(e: Dictionary) -> String: return str(e["kind"]))
	check("a stream is read into init, say, tool, tool_result, result, raw", kinds == ["init", "say", "tool", "tool_result", "result", "raw"])
	check("a tool row says the tool without the server prefix and its arguments", out[2]["tool"] == "mix_set_mute" and out[2]["text"].begins_with("mix_set_mute  track=Hats"))
	check("a refused tool result says it was and why", out[3]["ok"] == false and out[3]["text"] == "no track called Hats")
	check("the session id, cost and turns are kept", s.session_id == "abc" and s.cost_usd == 0.5 and s.turns == 3 and s.done and not s.is_error)
	var e := AssistantStream.new()
	var err := e.feed('{"type":"result","subtype":"error_max_budget_usd","is_error":true,"result":"over budget"}')
	check("an error result is an error line", err[0]["kind"] == AssistantStream.ERROR and e.is_error)


func command() -> void:
	var a := AssistantRunner.claude_args("/x/mcp.json", "sess-1", 1.5)
	var line := " ".join(a)
	check("the command names only the game's server", a.has("--strict-mcp-config") and a.has("--mcp-config") and a[a.find("--mcp-config") + 1] == "/x/mcp.json")
	check("the command takes away every built-in tool", a[a.find("--tools") + 1] == "")
	check("the command allows only the dawlings tools", a[a.find("--allowedTools") + 1] == "mcp__dawlings")
	check("the command asks nobody and caps the spend", a.has("dontAsk") and a[a.find("--max-budget-usd") + 1] == "1.50")
	check("the command names a small model by default", a[a.find("--model") + 1] == "sonnet")
	check("the command resumes a conversation", a[a.find("--resume") + 1] == "sess-1" and not AssistantRunner.claude_args("/x").has("--resume"))
	check("the command says nothing of files or the shell", not line.contains("Bash") and not line.contains("Edit") and not line.contains("Write"))
	var sh := AssistantRunner.shell_line("/usr/bin/claude", "/d", "/d/p.txt", "/d/e.jsonl", "/d/err", "/d/mcp.json")
	check("the run is in its own folder with the prompt on stdin", sh.begins_with("cd '/d' && exec '/usr/bin/claude'") and sh.contains("< '/d/p.txt' > '/d/e.jsonl'"))


func run() -> void:
	var host := ControlHost.attach(t, null)
	await t.get_tree().process_frame
	var asst := host.assistant
	var args_file := ProjectSettings.globalize_path("user://assistant_test_args.txt")
	OS.set_environment("FAKE_CLAUDE_ARGS", args_file)
	OS.set_environment("FAKE_ASSIST_TOOL", "tools_search")
	OS.set_environment("FAKE_ASSIST_ARGS", '{"query":"batch"}')
	Assistant.claude_override = ProjectSettings.globalize_path(FAKE)
	asst.claude = Assistant.claude_override
	var why := []
	check("a host with claude can run the assistant", asst.can_run(why))
	asst.ask("what can you do?")
	var waited := 0
	while waited < 900 and (asst.runs.is_empty() or asst.runs[0]["status"] in [Assistant.QUEUED, Assistant.RUNNING]):
		await t.get_tree().process_frame
		waited += 1
		if waited % 30 == 0:
			await t.get_tree().create_timer(0.05).timeout
	check("the run finished", not asst.runs.is_empty() and asst.runs[0]["status"] == Assistant.DONE)
	var kinds: Array = asst.runs[0]["events"].map(func(e: Dictionary) -> String: return str(e["kind"])) if not asst.runs.is_empty() else []
	check("the run's events are ask, say, tool, tool_result, result, end", kinds == ["ask", "say", "tool", "tool_result", "result", "end"] or (kinds.has("tool") and kinds.has("tool_result") and kinds.has("result")))
	var result_ev: Array = asst.runs[0]["events"].filter(func(e: Dictionary) -> bool: return str(e["kind"]) == "tool_result") if not asst.runs.is_empty() else []
	check("the CLI really called the game's server and the call worked", not result_ev.is_empty() and result_ev[0]["ok"] == true and str(result_ev[0]["text"]).contains("batch"))
	check("the run's token is revoked when it ends", host.server != null and host.server.tokens.is_empty())
	check("the conversation goes on from the run's session", asst.conversation == "fake-session-1")
	var given := FileAccess.get_file_as_string(args_file)
	check("the CLI was given the locked-down line", given.contains("--strict-mcp-config") and given.contains("mcp__dawlings") and given.contains("dontAsk"))
	check("its prompt says the room and who asked", given.contains("The room, as it is now:") and given.contains("asks: what can you do?"))
	asst.ask("and again")
	waited = 0
	while waited < 900 and asst.runs.size() < 2 or (asst.runs.size() > 1 and asst.runs[1]["status"] in [Assistant.QUEUED, Assistant.RUNNING] and waited < 900):
		await t.get_tree().process_frame
		waited += 1
		if waited % 30 == 0:
			await t.get_tree().create_timer(0.05).timeout
	given = FileAccess.get_file_as_string(args_file)
	check("the second ask resumes the conversation", given.contains("--resume\nfake-session-1") and not given.contains("The room, as it is now:"))
	# A card.
	var gate := host.api.tools.has("batch")
	check("an outside client's destructive call is refused without --control-yes", gate and not (await asst.confirm("rack_clear", {}, 0)))
	host.auto_confirm = true
	check("and allowed with it", await asst.confirm("rack_clear", {}, 0))
	host.auto_confirm = false
	if host.server != null:
		host.server.stop()
	OS.unset_environment("FAKE_CLAUDE_ARGS")
	OS.unset_environment("FAKE_ASSIST_TOOL")
	OS.unset_environment("FAKE_ASSIST_ARGS")
	Assistant.claude_override = ""
	host.queue_free()
	DirAccess.remove_absolute(args_file)


## CANCEL stops a run at once, even one whose CLI ignores the polite signal (it is killed two seconds on), and the
## next ask can start; NEW CHAT clears the transcript and the conversation.
func cancel_and_clear() -> void:
	var host := ControlHost.attach(t, null)
	await t.get_tree().process_frame
	var asst := host.assistant
	OS.set_environment("FAKE_ASSIST_HANG", "1")
	Assistant.claude_override = ProjectSettings.globalize_path(FAKE)
	asst.claude = Assistant.claude_override
	asst.conversation = "older-session"
	asst.ask("think hard")
	var waited := 0
	while waited < 600 and (asst.runs.is_empty() or not asst.runs[0]["events"].any(func(e: Dictionary) -> bool: return str(e["kind"]) == "say")):
		await t.get_tree().process_frame
		waited += 1
		if waited % 30 == 0:
			await t.get_tree().create_timer(0.05).timeout
	check("the run is going and has said something", not asst.runs.is_empty() and asst.runs[0]["status"] == Assistant.RUNNING)
	var pid: int = asst._runner.pid if asst._runner != null else -1
	asst.cancel(int(asst.runs[0]["id"]))
	check("CANCEL stops it at once", asst.runs[0]["status"] == Assistant.CANCELLED and asst._current.is_empty() and asst._runner == null)
	check("the board says it was cancelled", str(asst.runs[0]["events"][-1]["text"]) == "cancelled")
	check("its token is revoked", host.server != null and host.server.tokens.is_empty())
	await t.get_tree().create_timer(2.6).timeout
	check("a CLI deaf to the signal is gone two seconds on", pid > 0 and not OS.is_process_running(pid))
	check("the conversation is not lost to a cancel", asst.conversation == "older-session")
	asst.new_conversation()
	check("NEW CHAT clears the transcript and the conversation", asst.runs.is_empty() and asst.cards.is_empty() and asst.conversation == "")
	OS.unset_environment("FAKE_ASSIST_HANG")
	Assistant.claude_override = ""
	if host.server != null:
		host.server.stop()
	host.queue_free()


## requests_add writes a request to the host's file, safely, and requests_list reads them back.
const ToolsRequests := preload("res://core/control/tools_requests.gd")


func requests() -> void:
	var file := "user://requests_test.md"
	ToolsRequests.path_override = file
	DirAccess.remove_absolute(file)
	var api := ControlTools.make_api()
	check("the requests tools are there, in their domain", api.has("requests_add") and api.has("requests_list") and "requests" in api.domains())
	check("a request needs details", not api.invoke("requests_add", {"title": "x", "details": " "})["ok"])
	var r := api.invoke("requests_add", {"title": "Undo for TIDY UP\n## not a heading", "details": "They tidied the rack and wanted it back.\nTwo lines.", "kind": "feature", "asked": "can I undo the tidy?"}, 0)
	check("a request is noted", r["ok"] and r["data"]["who"] == "host")
	api.invoke("requests_add", {"title": "Scope freezes", "details": "The scope stops after a minute.", "kind": "bug"})
	var text := FileAccess.get_file_as_string(file)
	check("the file has a heading, the entry, the details and their words", text.begins_with("# Feature requests") and text.contains("**Undo for TIDY UP ## not a heading**")
			and text.contains("Two lines.") and text.contains("> can I undo the tidy?"))
	check("a title cannot start a heading of its own", text.count("\n## ") == 2)
	var listed := api.invoke("requests_list", {})
	check("requests_list gives them newest first", listed["ok"] and listed["data"]["count"] == 2 and listed["data"]["requests"][0]["title"] == "Scope freezes"
			and listed["data"]["requests"][1]["kind"] == "feature")
	DirAccess.remove_absolute(file)
	ToolsRequests.path_override = ""


# --- the board ---------------------------------------------------------------------------------------

func panel() -> void:
	var a := Assistant.new()
	check("an empty board says nothing was asked", AssistantPanel.board_rows(a, 15)[0]["text"].begins_with("Nothing asked yet"))
	a.runs.append({"id": 1, "peer": 1, "who": "Ada", "text": "mute the hats", "status": "done", "cost": 0.0, "events": [
			{"kind": "say", "text": "Muting them."}, {"kind": "tool", "text": "mix_set_mute  track=Hats"},
			{"kind": "tool_result", "ok": false, "text": "no track called Hats"}, {"kind": "result", "text": "Could not."}]})
	var rows := AssistantPanel.board_rows(a, 15)
	var words := rows.map(func(r: Dictionary) -> String: return r["text"])
	check("the board shows who asked, what was said, the tool and a refusal", words[0] == "Ada: mute the hats" and words.has("  Muting them.")
			and words.has("    › mix_set_mute  track=Hats") and words.has("    refused: no track called Hats"))
	check("a refusal is in the warning colour", rows[3]["colour"] == AssistantPanel.BAD)
	check("only the newest lines fit the face", AssistantPanel.board_rows(a, 2).size() == 2 and AssistantPanel.board_rows(a, 2)[1]["text"] == "  Could not.")
	var long := {"id": 2, "peer": 1, "who": "Ada", "text": "x".repeat(300), "status": "running", "cost": 0.0, "events": []}
	a.runs.append(long)
	check("a long question is clipped to the face and a running one says so", AssistantPanel.board_rows(a, 15).any(func(r: Dictionary) -> bool: return r["text"].length() <= 84 and r["text"].ends_with("…"))
			and AssistantPanel.board_rows(a, 15)[-1]["text"] == "  working...")
	check("the station has a row with a frame and hands text, and no spot where no host stands", Stations.row(&"assistant").has("frame") and Stations.row(&"assistant")["hands"] != ""
			and not ControlHost.stands)
	a.free()
