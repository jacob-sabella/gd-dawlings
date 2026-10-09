class_name NativeKeys
extends RefCounted
## The monitor synth as a PipeWire node of its own -- native/keys.c -- so a guest's keys are heard
## a few milliseconds after they go down rather than tens.
##
## Through Godot, a key waits for the next frame to be read, then behind a generator queue deep
## enough for Godot's mixer, then behind an output: 30-50ms. The helper renders in the graph's
## realtime callback at a 128-frame quantum and reads MIDI from the ALSA sequencer itself, the
## moment it arrives: tools/keys_latency.sh measures key to sink at about 4.5ms.
##
## The app still hears every MIDI note -- the helper passes each on, stamped with when it
## arrived -- because a take is made here. Notes from the app's own keys (computer keyboard, the
## panel) go the other way, as commands.
##
## Linux with PipeWire, a C compiler, and the PipeWire and ALSA headers; elsewhere MonitorSynth
## plays through Godot as before.

const SOURCE := "res://native/keys.c"
const BUILT := "user://bin/keys"
## Frames per graph cycle asked for: 2.7ms at 48kHz. The graph runs at the smallest any of its
## nodes asks for, so while a guest session is open everything on that card runs at this.
## R3D_KEYS_QUANTUM overrides it.
const QUANTUM := 128

static var _helper := ""
static var _helper_checked := false
static var _build_lock := Mutex.new()

## Hardware MIDI sources the helper has linked in, by name.
var devices: PackedStringArray = []
## Key to sink, in seconds, as the helper last counted it; 0 until a note has been played.
var latency := 0.0
var ready := false
## MIDI the helper has passed on and the app has not yet taken: {"on": bool, "pitch",
## "velocity", "channel", "age": seconds since it arrived} or {"sustain": bool, "channel", "age"}.
var pending: Array[Dictionary] = []

var _pid := -1
var _io: FileAccess
var _partial := ""


## Whether the helper can run here: Linux, and built (or buildable) from its source.
static func available() -> bool:
	return OS.get_name() == "Linux" and helper() != ""


## The helper's path, built from source the first time it is wanted and again whenever the
## source is newer, or "" when it cannot be: no compiler, or no PipeWire or ALSA headers.
static func helper() -> String:
	_build_lock.lock()
	if not _helper_checked:
		_helper_checked = true
		_helper = _build()
	_build_lock.unlock()
	return _helper


static func _build() -> String:
	var source := ProjectSettings.globalize_path(SOURCE)
	var built := ProjectSettings.globalize_path(BUILT)
	if not FileAccess.file_exists(source):
		return ""
	if FileAccess.file_exists(built) \
			and FileAccess.get_modified_time(built) >= FileAccess.get_modified_time(source):
		return built
	var flags: Array = []
	if OS.execute("pkg-config", ["--cflags", "--libs", "libpipewire-0.3", "alsa"], flags, true) != 0:
		return ""
	DirAccess.make_dir_recursive_absolute(built.get_base_dir())
	var args := PackedStringArray(["-O2", "-o", built, source])
	args.append_array((flags[0] as String).strip_edges().split(" ", false))
	args.append("-lm")
	var out: Array = []
	if OS.execute("cc", args, out, true) != 0:
		push_warning("monitor keys: could not build the helper: %s" % str(out))
		return ""
	return built


## Start the node, playing to `device` (a sink's name; empty for the session manager's choice).
func start(device := "") -> bool:
	var path := helper()
	if path == "":
		return false
	var told := OS.get_environment("R3D_KEYS_QUANTUM")
	var args := PackedStringArray(["--quantum", told if told.is_valid_int() else str(QUANTUM)])
	if device != "":
		args.append_array(["--device", device])
	var started := OS.execute_with_pipe(path, args, false)
	if started.is_empty():
		return false
	_pid = int(started["pid"])
	_io = started["stdio"]
	return true


func stop() -> void:
	if _io != null:
		_io.close()
		_io = null
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_pid = -1
	ready = false


func running() -> bool:
	return _pid > 0 and OS.is_process_running(_pid)


func note_on(pitch: int, velocity: int) -> void:
	_say("on %d %d" % [pitch, velocity])


func note_off(pitch: int) -> void:
	_say("off %d" % pitch)


func sustain(down: bool) -> void:
	_say("sus %d" % int(down))


func volume(db: float) -> void:
	_say("vol %.2f" % db)


func enable(on: bool) -> void:
	_say("enable %d" % int(on))


func panic() -> void:
	_say("panic")


## Take every hardware MIDI source's notes, or let them go.
func take_midi(on: bool) -> void:
	if not on:
		devices = PackedStringArray()
	_say("midi %d" % int(on))


func _say(line: String) -> void:
	if _io != null:
		_io.store_string(line + "\n")
		_io.flush()


## What the helper has said since last asked: its MIDI into `pending`, the rest kept here.
func poll() -> void:
	if _io == null:
		return
	var bytes := _io.get_buffer(65536)
	if bytes.is_empty():
		return
	var text := _partial + bytes.get_string_from_utf8()
	var lines := text.split("\n")
	_partial = lines[lines.size() - 1]
	for i in lines.size() - 1:
		hear(lines[i])


## One line of the helper's, understood.
func hear(line: String, now_unix := Time.get_unix_time_from_system()) -> void:
	var w := line.split(" ", false)
	if w.is_empty():
		return
	match w[0]:
		"ready":
			ready = true
		"midi-from":
			var name := line.substr(10)
			if not name in devices:
				devices.append(name)
		"latency":
			if w.size() >= 2:
				latency = int(w[1]) / 1e6
		"note":
			if w.size() >= 6:
				pending.append({"on": w[1] == "1", "pitch": int(w[2]), "velocity": int(w[3]),
						"channel": int(w[4]), "age": _age(w[5], now_unix)})
		"sus":
			if w.size() >= 4:
				pending.append({"sustain": w[1] == "1", "channel": int(w[2]), "age": _age(w[3], now_unix)})


## How long ago a stamp of the helper's was: both clocks are the system's wall clock.
static func _age(unix_us: String, now_unix: float) -> float:
	return maxf(0.0, now_unix - int(unix_us) / 1e6)


## The MIDI waiting, taken.
func take() -> Array[Dictionary]:
	var out := pending
	pending = []
	return out
