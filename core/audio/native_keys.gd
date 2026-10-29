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
##
## Things struck take the same road (docs/spatial_loop.md part two, slice 39): a helper of the
## studio's own, started with no MIDI (`start`'s `midi`) as "dawlings · hits", has Foley's sounds
## loaded into its slots once (`load_hits`: Foley.write_hits on a worker thread, then a `load`
## line each), and plays this player's own hits by a line each (`play_hit`, `hit`), a few
## milliseconds after the hand rather than Godot's tens.
##
## And the modular wall (docs/spatial_loop.md part two, slice 51): native/modular.c, built in, plays
## the wall's patch with this player's keys while they stand at it (`modular_on`), its cables and
## knobs told by `mod` lines (`modular_patch`, `modular_knob`), so the modular is on the fast path too.

const SOURCE := "res://native/keys.c"
## The modular's arithmetic, included by SOURCE: the helper is built again when either is newer.
const MODULAR_SOURCE := "res://native/modular.c"
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
## "velocity", "channel", "age": seconds since it arrived}, {"sustain": bool, "channel", "age"},
## or {"control": DawKitClip.PITCH_BEND, 1 or 11, "value", "channel", "age"}, a keyboard's wheels,
## which the helper passes on without playing (GuestMidi.control decides whether they are heard).
var pending: Array[Dictionary] = []

## The slots the helper has said it holds (`loaded SLOT FRAMES`), {slot: frames}: only these are
## hit here; a hit on any other plays through Godot.
var loaded := {}
## The loads it refused, {slot: why}: a file gone, or not the WAV it wants.
var refused := {}

var _pid := -1
var _io: FileAccess
var _partial := ""
## Foley's sounds being written for `load_hits`, on a worker thread: its task, or -1.
var _writing := -1
## What that thread wrote, [[slot, path], ...], taken by `poll` and loaded.
var _written: Array = []
var _written_lock := Mutex.new()


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
	var modular := ProjectSettings.globalize_path(MODULAR_SOURCE)
	var newest := maxi(FileAccess.get_modified_time(source),
			FileAccess.get_modified_time(modular) if FileAccess.file_exists(modular) else 0)
	if FileAccess.file_exists(built) and FileAccess.get_modified_time(built) >= newest:
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
## `midi` off makes no sequencer port: a node only for the app's hits, named `name`.
func start(device := "", midi := true, name := "") -> bool:
	var path := helper()
	if path == "":
		return false
	var told := OS.get_environment("R3D_KEYS_QUANTUM")
	var args := PackedStringArray(["--quantum", told if told.is_valid_int() else str(QUANTUM)])
	if device != "":
		args.append_array(["--device", device])
	if not midi:
		args.append("--no-midi")
	if name != "":
		args.append_array(["--name", name])
	var started := OS.execute_with_pipe(path, args, false)
	if started.is_empty():
		return false
	_pid = int(started["pid"])
	_io = started["stdio"]
	return true


func stop() -> void:
	if _writing >= 0:
		WorkerThreadPool.wait_for_task_completion(_writing)
		_writing = -1
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


## A control on the keys, as MonitorSynth.control has it: the pitch wheel (DawKitClip.PITCH_BEND)
## as `bend V`, a controller as `cc K V`.
func control(kind: int, value: int) -> void:
	_say(control_line(kind, value))


## The helper's line for a control (`control`).
static func control_line(kind: int, value: int) -> String:
	if kind == DawKitClip.PITCH_BEND:
		return "bend %d" % value
	return "cc %d %d" % [kind, value]


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


# --- the modular wall (docs/spatial_loop.md part two, slice 51) ---------------------------------

## The keys play the modular's patch (on) or the tine (off): the app's notes and the sequencer's.
func modular_on(on: bool) -> void:
	_say("mod on %d" % int(on))


## The whole of `patch` (Modular's {cables, knobs}) told to the helper: its cables cleared and put
## in again, and every knob.
func modular_patch(patch: Dictionary) -> void:
	for line in modular_lines(patch):
		_say(line)


## One knob as it turns.
func modular_knob(id: StringName, v: float) -> void:
	_say(modular_knob_line(id, v))


## A world socket's level now, and its gate opened (docs/spatial_loop.md part two, slice 53): what
## the world plays into the patch (ModularWorld), as it happens.
func modular_world(socket: StringName, level: float) -> void:
	_say(modular_world_line(socket, level))


func modular_trig(socket: StringName) -> void:
	_say("mod trig %s" % socket)


## The helper's line for world socket `socket` at `level`, with every digit, as a knob's.
static func modular_world_line(socket: StringName, level: float) -> String:
	return "mod world %s %s" % [socket, String.num(level, 17)]


## The helper's lines for the whole of `patch`: `mod clear`, a `mod cable` each, a `mod knob` each.
static func modular_lines(patch: Dictionary) -> PackedStringArray:
	var out := PackedStringArray(["mod clear"])
	for c: Array in patch.get("cables", []):
		out.append("mod cable %s %s" % [c[0], c[1]])
	var knobs: Dictionary = patch.get("knobs", {})
	for id: StringName in Modular.KNOBS:
		out.append(modular_knob_line(id, float(knobs.get(id, Modular.KNOB_REST[id]))))
	return out


## The helper's line for knob `id` at `v`, with all the digits a double has, so the helper's knob is
## the app's to the last bit (Modular.render, checked against `--render`).
static func modular_knob_line(id: StringName, v: float) -> String:
	return "mod knob %s %s" % [id, String.num(v, 17)]


# --- things struck (docs/spatial_loop.md part two, slice 39) ------------------------------------

## The sound in `path` (a 48 kHz 16-bit mono WAV, Foley.hit_wav) into slot `slot`, read by the
## helper now. It answers `loaded` or `refused` (`hear`).
func load_slot(slot: int, path: String) -> void:
	_say("load %d %s" % [slot, path])


## Slot `slot` played once: `gain` linear, `pan` -1 (left) to 1 (right), `speed` as an
## AudioStreamPlayer's pitch_scale.
func hit(slot: int, gain: float, pan := 0.0, speed := 1.0) -> void:
	_say(hit_line(slot, gain, pan, speed))


## The helper's line for a hit (`hit`).
static func hit_line(slot: int, gain: float, pan := 0.0, speed := 1.0) -> String:
	return "hit %d %.5f %.3f %.5f" % [slot, gain, clampf(pan, -1.0, 1.0), speed]


## Every one of Foley's struck sounds written to Foley.HITS_DIR on a worker thread and, as `poll`
## finds them written, loaded: once, as the hits' helper starts.
func load_hits() -> void:
	if _writing >= 0:
		return
	_writing = WorkerThreadPool.add_task(func() -> void:
		var wrote := Foley.write_hits()
		_written_lock.lock()
		_written = wrote
		_written_lock.unlock(), false, "hit sounds")


## Take `take` of Foley's `kind` played on the helper (`hit`), if it holds it: true when it did,
## false when it must be played through Godot (not started, or that sound not loaded yet).
func play_hit(kind: StringName, take: int, gain: float, pan := 0.0, speed := 1.0) -> bool:
	var slot := Foley.hit_slot(kind, take)
	if slot < 0 or not loaded.has(slot) or _io == null:
		return false
	hit(slot, gain, pan, speed)
	return true


## How late a hit on the helper is (s): as it last counted, or before its first, the two cycles
## it measures at.
func hit_latency() -> float:
	return latency if latency > 0.0 else 2.0 * QUANTUM / float(Foley.HIT_RATE)


func _say(line: String) -> void:
	if _io != null:
		_io.store_string(line + "\n")
		_io.flush()


## What the helper has said since last asked: its MIDI into `pending`, the rest kept here.
func poll() -> void:
	if _io == null:
		return
	if _writing >= 0 and WorkerThreadPool.is_task_completed(_writing):
		WorkerThreadPool.wait_for_task_completion(_writing)
		_writing = -1
		_written_lock.lock()
		var wrote := _written
		_written = []
		_written_lock.unlock()
		for row: Array in wrote:
			load_slot(int(row[0]), String(row[1]))
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
		"loaded":
			if w.size() >= 3:
				loaded[int(w[1])] = int(w[2])
				refused.erase(int(w[1]))
		"refused":
			if w.size() >= 2:
				refused[int(w[1])] = " ".join(w.slice(2))
				loaded.erase(int(w[1]))
		"note":
			if w.size() >= 6:
				pending.append({"on": w[1] == "1", "pitch": int(w[2]), "velocity": int(w[3]),
						"channel": int(w[4]), "age": _age(w[5], now_unix)})
		"sus":
			if w.size() >= 4:
				pending.append({"sustain": w[1] == "1", "channel": int(w[2]), "age": _age(w[3], now_unix)})
		"wheel":
			# The pitch wheel as the sequencer has it, -8192 to 8191: `wheel V channel when`.
			if w.size() >= 4:
				pending.append({"control": DawKitClip.PITCH_BEND, "value": clampi(int(w[1]), -8192, 8191),
						"channel": int(w[2]), "age": _age(w[3], now_unix)})
		"ctl":
			# The mod wheel or expression: `ctl K V channel when`. Any other controller is not passed.
			if w.size() >= 5 and int(w[1]) in [1, 11]:
				pending.append({"control": int(w[1]), "value": clampi(int(w[2]), 0, 127), "channel": int(w[3]),
						"age": _age(w[4], now_unix)})


## How long ago a stamp of the helper's was: both clocks are the system's wall clock.
static func _age(unix_us: String, now_unix: float) -> float:
	return maxf(0.0, now_unix - int(unix_us) / 1e6)


## The MIDI waiting, taken.
func take() -> Array[Dictionary]:
	var out := pending
	pending = []
	return out
