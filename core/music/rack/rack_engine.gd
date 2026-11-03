class_name RackEngine
extends RefCounted

## The modular room's engine, native/rack, as a process: built on demand from the pinned submodules
## (tools/rack_build.sh), told the patch and the player's notes as text lines, heard back as float32
## stereo on its stdout (live) or as a WAV (offline). Its stderr says how loud each module is, for the
## room's lights.

const SCRIPT := "res://tools/rack_build.sh"
const RATE := 48000

static var _binary := ""
static var _tried := false
static var _lock := Mutex.new()


## The built engine's path, building it if need be; "" when this machine cannot (no compiler, or the
## submodules not fetched).
static func binary() -> String:
	_lock.lock()
	if not _tried:
		_tried = true
		var told := OS.get_environment("DAWLINGS_RACK")
		if told != "" and FileAccess.file_exists(told):
			_binary = told
		elif OS.get_name() == "Linux" or OS.get_name() == "macOS":
			var out: Array = []
			var code := OS.execute("bash", [ProjectSettings.globalize_path(SCRIPT)], out, true)
			if code == 0:
				_binary = String(out[0]).strip_edges().get_slice("\n", String(out[0]).strip_edges().count("\n"))
				if not _binary.is_absolute_path():
					_binary = ProjectSettings.globalize_path("res://").path_join(_binary)
			else:
				push_warning("rack: could not build the engine: %s" % str(out))
	_lock.unlock()
	return _binary


static func available() -> bool:
	return binary() != ""


## What the engine says its modules are (--describe), for the catalogue test.
static func describe() -> Dictionary:
	if not available():
		return {}
	var out: Array = []
	if OS.execute(binary(), ["--describe"], out, true) != 0:
		return {}
	var data: Variant = JSON.parse_string(out[0])
	return data if data is Dictionary else {}


## A patch rendered to stereo frames, offline. `play` is lines run in order after the patch, where
## `run S` renders S seconds: e.g. ["note_on 60 100", "run 1", "note_off 60", "run 0.5"].
static func render(patch: Dictionary, play: PackedStringArray, bpm := 120.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	if not available():
		return out
	var dir := OS.get_user_data_dir().path_join("rack")
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := str(Time.get_ticks_usec())
	var script := dir.path_join("script_%s.txt" % stamp)
	var wav := dir.path_join("render_%s.wav" % stamp)
	var f := FileAccess.open(script, FileAccess.WRITE)
	if f == null:
		return out
	f.store_line("bpm %f" % bpm)
	for line in RackPatch.lines(patch):
		f.store_line(line)
	for line in play:
		f.store_line(line)
	f.close()
	var log: Array = []
	var code := OS.execute(binary(), ["--render", wav, script], log, true)
	DirAccess.remove_absolute(script)
	if code == 0:
		out = read_wav(wav)
	DirAccess.remove_absolute(wav)
	return out


## The 16-bit stereo WAV the engine writes, as frames.
static func read_wav(path: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 44:
		return out
	f.seek(44)
	var bytes := f.get_buffer(f.get_length() - 44)
	var n := bytes.size() / 4
	out.resize(n)
	for i in n:
		out[i] = Vector2(bytes.decode_s16(i * 4) / 32768.0, bytes.decode_s16(i * 4 + 2) / 32768.0)
	return out


# --- live -----------------------------------------------------------------------------------

var _pid := -1
var _io: FileAccess
var _err: FileAccess
var _spare := PackedByteArray()
## {module id: peak 0..1+} as last told, and the song's beat the engine thinks it is at.
var meters := {}
var running_beat := 0.0
var _err_buf := ""


func start() -> bool:
	if running():
		return true
	var path := binary()
	if path == "":
		return false
	var started := OS.execute_with_pipe(path, PackedStringArray(["--live", "240"]), false)
	if started.is_empty():
		return false
	_pid = int(started["pid"])
	_io = started["stdio"]
	_err = started["stderr"]
	return true


func stop() -> void:
	if _io != null:
		_io.store_line("quit")
		_io.close()
		_io = null
	_err = null
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_pid = -1
	_spare.clear()
	meters = {}


func running() -> bool:
	return _pid > 0 and _io != null and OS.is_process_running(_pid)


func say(line: String) -> void:
	if _io != null:
		_io.store_line(line)


func say_all(lines: PackedStringArray) -> void:
	for line in lines:
		say(line)


## Everything the engine has played since last asked. Safe off the main thread (read only).
func read() -> PackedVector2Array:
	var out := PackedVector2Array()
	if _io == null:
		return out
	var bytes := _spare + _io.get_buffer(1 << 15)
	var whole := bytes.size() / 8 * 8
	_spare = bytes.slice(whole)
	var samples := bytes.slice(0, whole).to_float32_array()
	out.resize(samples.size() / 2)
	for i in out.size():
		out[i] = Vector2(samples[i * 2], samples[i * 2 + 1])
	return out


## Reads the engine's meter lines, once a frame, on the main thread.
func poll() -> void:
	if _err == null:
		return
	_err_buf += _err.get_buffer(4096).get_string_from_utf8()
	var nl := _err_buf.rfind("\n")
	if nl < 0:
		return
	var last := _err_buf.substr(0, nl).get_slice("\n", _err_buf.substr(0, nl).count("\n"))
	_err_buf = _err_buf.substr(nl + 1)
	var parts := last.split(" ", false)
	if parts.size() < 2 or parts[0] != "meter":
		return
	var m := {}
	var i := 1
	while i + 1 < parts.size():
		if parts[i] == "@beat":
			running_beat = float(parts[i + 1])
		else:
			m[parts[i]] = float(parts[i + 1])
		i += 2
	meters = m


## The engine's sound as a source a track can monitor (InputMonitor.live_sources).
class Source extends MixSource:
	var engine: RackEngine

	func _init(e: RackEngine) -> void:
		engine = e

	func start() -> bool:
		return engine.running()

	func read() -> PackedVector2Array:
		return engine.read()

	func describe() -> String:
		return "the modular room"

	func latency_ms() -> float:
		return 6.0
