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
## What each SCOPE module saw lately: id -> PackedFloat32Array of points, -1..1.
var scopes := {}
var steps := {}
## When something last took the sound (msec): the engine stalls on a full pipe, so a rack nobody is
## listening to is drained by its voice to keep its meters and scopes alive.
var last_read := 0
var running_beat := 0.0
var _err_lines := PackedStringArray()
var _err_mutex := Mutex.new()
var _err_thread: Thread
var _drain_thread: Thread
var _io_mutex := Mutex.new()
var _alive := false


## Start the engine process in live mode; true if it is running afterwards, false if the binary is missing or will not start.
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
	# The engine's meter and scope lines are read on a thread of their own: a read on a pipe waits
	# for its bytes, and the main thread must never wait on the engine (a frame is 16 ms).
	_err_lines = PackedStringArray()
	_err_thread = Thread.new()
	_err_thread.start(_read_lines.bind(_err, _pid))
	_alive = true
	_drain_thread = Thread.new()
	_drain_thread.start(_drain.bind(_io))
	return true


## Keeps the engine's sound moving when nothing is taking it (no track plays the rack): the engine
## stalls on a full pipe, and its meters and scopes with it. Off the main thread, which must not wait.
func _drain(io: FileAccess) -> void:
	while _alive:
		if Time.get_ticks_msec() - last_read > 60:
			_io_mutex.lock()
			if Time.get_ticks_msec() - last_read > 60:
				io.get_buffer(4096)
			_io_mutex.unlock()
		else:
			OS.delay_msec(20)


func _read_lines(err: FileAccess, pid: int) -> void:
	while true:
		var line := err.get_line()
		if line == "" and (err.eof_reached() or not OS.is_process_running(pid)):
			break
		if line == "":
			continue
		_err_mutex.lock()
		_err_lines.append(line)
		_err_mutex.unlock()


## Tell the engine to quit, close its pipes and join the drain thread.
func stop() -> void:
	_alive = false
	if _drain_thread != null:
		_drain_thread.wait_to_finish()
		_drain_thread = null
	if _io != null:
		_io.store_line("quit")
		_io.close()
		_io = null
	_err = null
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_pid = -1
	if _err_thread != null:
		_err_thread.wait_to_finish()
		_err_thread = null
	_spare.clear()
	meters = {}
	scopes = {}


func running() -> bool:
	return _pid > 0 and _io != null and OS.is_process_running(_pid)


## Send the engine one command line; dropped if it is not running.
func say(line: String) -> void:
	if _io != null:
		_io.store_line(line)


## Send the engine each of `lines` in order.
func say_all(lines: PackedStringArray) -> void:
	for line in lines:
		say(line)


## Everything the engine has played since last asked. Safe off the main thread (read only).
func read() -> PackedVector2Array:
	last_read = Time.get_ticks_msec()
	var out := PackedVector2Array()
	if _io == null:
		return out
	_io_mutex.lock()
	var chunk := _io.get_buffer(1 << 15)
	_io_mutex.unlock()
	var bytes := _spare + chunk
	var whole := bytes.size() / 8 * 8
	_spare = bytes.slice(whole)
	var samples := bytes.slice(0, whole).to_float32_array()
	out.resize(samples.size() / 2)
	for i in out.size():
		out[i] = Vector2(samples[i * 2], samples[i * 2 + 1])
	return out


## Reads the engine's meter lines, once a frame, on the main thread.
func poll() -> void:
	if _err_thread == null:
		return
	_err_mutex.lock()
	var lines := _err_lines
	_err_lines = PackedStringArray()
	_err_mutex.unlock()
	if lines.is_empty():
		return
	var last_meter := ""
	for line in lines:
		if line.begins_with("scope "):
			var q := line.split(" ", false)
			if q.size() > 2:
				var w := PackedFloat32Array()
				w.resize(q.size() - 2)
				for k in w.size():
					w[k] = float(q[k + 2])
				scopes[q[1]] = w
		elif line.begins_with("step "):
			var sq := line.split(" ", false)
			if sq.size() == 3:
				steps[sq[1]] = int(sq[2])
		elif line.begins_with("meter "):
			last_meter = line
	var parts := last_meter.split(" ", false)
	if parts.size() < 2:
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
	for id in scopes.keys():
		if not m.has(id):
			scopes.erase(id)
	for id in steps.keys():
		if not m.has(id):
			steps.erase(id)


## The engine's sound as a source a track can monitor (InputMonitor.feeds), with a tape that can be
## kept running to catch what is played, for a take.
class Source extends MixSource:
	var engine: RackEngine
	var _tape := PackedVector2Array()
	var _taping := false
	var _lock := Mutex.new()

	func _init(e: RackEngine) -> void:
		engine = e

	func start() -> bool:
		return engine.running()

	func stop() -> void:
		pass

	func read() -> PackedVector2Array:
		var got := engine.read()
		if _taping and not got.is_empty():
			_lock.lock()
			_tape.append_array(got)
			_lock.unlock()
		return got

	func tape(on: bool) -> void:
		_lock.lock()
		if on and not _taping:
			_tape = PackedVector2Array()
		_taping = on
		_lock.unlock()

	func taking() -> bool:
		return _taping

	func take_tape() -> PackedVector2Array:
		_lock.lock()
		var out := _tape
		_tape = PackedVector2Array()
		_lock.unlock()
		return out

	func describe() -> String:
		return "the modular room"

	func latency_ms() -> float:
		return 6.0


## Frames as a 16-bit stereo WAV file.
static func write_wav(path: String, frames: PackedVector2Array) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	var bytes := frames.size() * 4
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + bytes)
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)
	f.store_16(2)
	f.store_32(RATE)
	f.store_32(RATE * 4)
	f.store_16(4)
	f.store_16(16)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(bytes)
	var pcm := PackedByteArray()
	pcm.resize(bytes)
	for i in frames.size():
		pcm.encode_s16(i * 4, int(clampf(frames[i].x, -1.0, 1.0) * 32767.0))
		pcm.encode_s16(i * 4 + 2, int(clampf(frames[i].y, -1.0, 1.0) * 32767.0))
	f.store_buffer(pcm)
	f.close()
	return true
