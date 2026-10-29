class_name WorkshopRunner
extends RefCounted

## One Claude Code run for the Workshop (docs/workshop.md): the command line, the process, and its
## stream read as it is written, never waited on.
##
## The CLI is started as its own process through `/bin/sh -c` (OS.create_process), with the prompt
## on its stdin from a file and its stdout (stream-json, a JSON event a line) into a file this tails
## a little each frame (`poll`), so a long run never holds up a frame. OS.create_process makes it the
## head of a process group of its own, so Cancel (`cancel`) stops it and whatever it started (a test
## run, a screenshot) with one signal to the group.
##
## What it may do is said on the command line (`claude_args`), not trusted to the prompt:
## `--restricted` (no settings files, the file tools confined to the repo, git and settings files
## not writable without a person), only the tools named in `TOOLS`, Bash only for the commands in
## `ALLOWED_BASH`, everything in `DENIED` refused, and `--permission-mode dontAsk` with nobody to
## answer a prompt (`--permission-prompts none`), so anything not allowed is refused rather than
## waited on. No MCP servers (`--strict-mcp-config`), a spending cap (`--max-budget-usd`).

const TOOLS := "Read,Edit,Write,Glob,Grep,Bash"
## Bash commands the run may use: the targeted tests, a parse check, a reimport, a screenshot, the
## layout tools, and git's read-only verbs. Every other command is refused (dontAsk).
const ALLOWED_BASH := [
	"Bash(godot --headless --path . *)",
	"Bash(timeout * godot --headless --path . *)",
	"Bash(DAWLINGS_TESTS=* timeout * godot --headless --path . *)",
	"Bash(DAWLINGS_TESTS=* godot --headless --path . *)",
	"Bash(tools/shot.sh *)",
	"Bash(SHOT_* tools/shot.sh *)",
	"Bash(python3 tools/layout_map.py *)",
	"Bash(LAYOUT_* godot --headless --path . tools/layout_dump.tscn*)",
	"Bash(git status*)", "Bash(git diff*)", "Bash(git log*)", "Bash(git show*)",
	"Bash(ls *)", "Bash(wc *)", "Bash(head *)", "Bash(tail *)",
]
## Refused outright, whatever else would allow them.
const DENIED := [
	"Bash(git push*)", "Bash(git commit*)", "Bash(git reset*)", "Bash(git checkout*)",
	"Bash(git restore*)", "Bash(git stash*)", "Bash(git clean*)", "Bash(git rebase*)",
	"Bash(git merge*)", "Bash(git branch*)", "Bash(git remote*)", "Bash(git add*)",
	"Bash(rm *)", "Bash(curl *)", "Bash(wget *)", "Bash(ssh *)", "Bash(scp *)", "Bash(rsync *)",
	"Bash(pkill *)", "Bash(kill *)", "Bash(sudo *)", "Bash(deploy/*)",
	"Edit(vendor/**)", "Write(vendor/**)", "Edit(shots/workshop/**)", "Write(shots/workshop/**)",
	"Edit(deploy/**)", "Write(deploy/**)", "Edit(.git/**)", "Write(.git/**)",
	"WebFetch", "WebSearch",
]
## The most one request may spend (USD), unless the settings say otherwise.
const BUDGET := 5.0

var pid := -1
var stream: WorkshopStream
var events_path := ""
var stderr_path := ""
## The progress lines made so far, oldest first.
var lines: Array = []
var _offset := 0
var _partial := ""
var _finished := false


## The CLI's arguments (after the executable) for a run in `repo` whose prompt is on stdin: a fresh
## one, or one that resumes `resume_session` (Ask Claude to fix it).
static func claude_args(repo: String, resume_session := "", budget := BUDGET) -> PackedStringArray:
	var a := PackedStringArray(["-p", "--output-format", "stream-json", "--verbose",
			"--restricted", "--tools", TOOLS,
			"--permission-mode", "dontAsk", "--permission-prompts", "none",
			"--strict-mcp-config", "--max-budget-usd", "%.2f" % budget,
			"--append-system-prompt", "You are running inside the dawlings Workshop, started from the game itself. Nobody is watching the terminal: never ask a question, decide and say what you decided in the summary. Work only in %s." % repo])
	a.append("--allowedTools")
	a.append_array(PackedStringArray(["Read", "Glob", "Grep", "Edit(./**)", "Write(./**)"] + ALLOWED_BASH))
	a.append("--disallowedTools")
	a.append_array(PackedStringArray(DENIED))
	if resume_session != "":
		a.append("--resume")
		a.append(resume_session)
	return a


## The whole shell line: into `repo`, the CLI in a process group of its own, the prompt from
## `prompt_path` on stdin, its stream into `events`, its complaints into `errors`.
static func shell_line(claude: String, repo: String, prompt_path: String, events: String, errors: String,
		resume_session := "", budget := BUDGET) -> String:
	# No setsid: OS.create_process already makes the child the head of a session and a process group
	# of its own (setsid would fork again, and the pid followed would be gone at once).
	var words := PackedStringArray(["exec", quote(claude)])
	for a in claude_args(repo, resume_session, budget):
		words.append(quote(a))
	return "cd %s && %s < %s > %s 2> %s" % [quote(repo), " ".join(words), quote(prompt_path), quote(events), quote(errors)]


## `s` as one word for /bin/sh.
static func quote(s: String) -> String:
	return "'" + s.replace("'", "'\\''") + "'"


## Start the run. False if the process could not be started.
func start(claude: String, repo: String, prompt_path: String, dir: String, resume_session := "",
		budget := BUDGET) -> bool:
	events_path = dir.path_join("events.jsonl")
	stderr_path = dir.path_join("stderr.log")
	stream = WorkshopStream.new(repo)
	lines.clear()
	_offset = 0
	_partial = ""
	_finished = false
	# The file exists from the start, so the first poll finds it whatever the CLI is doing.
	FileAccess.open(events_path, FileAccess.WRITE).close()
	pid = OS.create_process("/bin/sh", ["-c", shell_line(claude, repo, prompt_path, events_path, stderr_path,
			resume_session, budget)])
	return pid > 0


func running() -> bool:
	return pid > 0 and OS.is_process_running(pid)


## What has been written since the last poll, as progress lines; and once the process has gone, the
## rest. Cheap: one open and one read of what is new.
func poll() -> Array:
	var out: Array = []
	if events_path == "" or _finished:
		return out
	var alive := running()
	var f := FileAccess.open(events_path, FileAccess.READ)
	if f != null:
		var size := f.get_length()
		if size > _offset:
			f.seek(_offset)
			var chunk := f.get_buffer(size - _offset).get_string_from_utf8()
			_offset = size
			var text := _partial + chunk
			var parts := text.split("\n")
			_partial = parts[parts.size() - 1]
			for i in parts.size() - 1:
				out.append_array(stream.feed(parts[i]))
		f.close()
	if not alive:
		if _partial.strip_edges() != "":
			out.append_array(stream.feed(_partial))
		_partial = ""
		_finished = true
		if not stream.done:
			var why := _stderr_tail()
			stream.is_error = true
			out.append(WorkshopStream._line(WorkshopStream.ERROR, "the CLI ended without a result" + (": " + why if why != "" else "")))
	lines.append_array(out)
	return out


## Whether the run is over and its stream read to the end.
func finished() -> bool:
	return _finished


## Stop the run and everything it started.
func cancel() -> void:
	# The group, by its head's pid: TERM, which the CLI and godot both stop on. Asked once: asking
	# again about a pid that has been reaped is an error in the log.
	if not _finished and running():
		OS.execute("/bin/kill", ["-TERM", "--", "-%d" % pid])


func _stderr_tail() -> String:
	if stderr_path == "" or not FileAccess.file_exists(stderr_path):
		return ""
	var t := FileAccess.get_file_as_string(stderr_path).strip_edges()
	return t.split("\n")[-1].left(WorkshopStream.LINE_MAX) if t != "" else ""
