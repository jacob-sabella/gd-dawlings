class_name AudioPorts
extends Node
## Every sound this process makes leaves it on its own named stream, and every sound it takes in
## arrives on one, so a patchbay can route each of them anywhere -- the mix to the monitors, the
## gear's clicks to a headphone feed or nowhere, a guest's own keys to a recorder.
##
##   dawlings · mix       the built-in DAW's master, or on a guest the host's mix it hears
##   dawlings · monitor   a guest's own keys, played here the instant they are pressed
##   dawlings · hits      this player's own strikes and shakes, on a second NativeKeys helper
##   dawlings · gear      the room: buttons, faders, tape motors, castors
##   dawlings · mic       what a guest records (MixSource.Piped)
##   dawlings · mix tap   what a host passes on to its guests, tapped from the DAW (MixTap)
##
## Each is a PipeWire node of its own, so the session manager puts it on the default device
## like any app's sound and remembers wherever it is moved to after that.
##
## HOW. Godot opens one output, and that is not changed: it is what keeps time. Each kind of
## sound plays on a bus of its own (MIX, MONITOR, GEAR); there an AudioEffectCapture takes it,
## and the bus goes on into a muted one, so the sound does not ALSO come out of Godot's own
## stream. A thread moves what the captures hold into a `pacat` per bus a millisecond at a time.
## Godot's mixer is paced by its own stream, which runs on the device's clock, and the pacats
## are drained on that same clock, so the pipes neither fill nor run dry.
##
## Writes are non-blocking and never more than PIPE_BUF bytes: a pipe takes a write that size
## whole or not at all, so when a pacat falls behind a block is dropped and the stream stays
## aligned, rather than a half-written block shifting every sample after it by one channel.
##
## Where there is no pacat (not Linux, no PipeWire or Pulse tools), or with --direct-audio, the
## buses go straight to Master and everything plays out of Godot's one stream, as it always did.

const MIX := &"Mix"
const MONITOR := &"Monitor"
const GEAR := &"Gear"
## Where the port buses go once captured: muted, so nothing is heard twice. Made before them.
const SPENT := &"Ported"
const KINDS: Array[StringName] = [MIX, MONITOR, GEAR]
## What each is called in a patchbay.
const NAMES := {MIX: "mix", MONITOR: "monitor", GEAR: "gear"}
const RATE := 48000
## The most bytes a pipe takes in one piece: 512 stereo float frames.
const PIPE_BUF := 4096
## How much the far side buffers, in msec. Low: this is a second hop after Godot's own output,
## and every millisecond here is one the player hears late. R3D_PORT_LATENCY_MS overrides it.
const LATENCY_MS := 8

## Whether sound is leaving through the ports. False before `open`, after `close`, and where
## they could not be made.
static var active := false
## Why not, for the session panel. Empty when they are open.
static var why_not := ""
## Where every stream of the app's starts, by sink name; empty for the session manager's choice.
## --audio-out. The ports and the monitor keys' helper both play there.
static var target := ""
## --direct-audio: one stream out of this process, nothing else -- not even the keys' own node.
static var direct := false

## The program that plays a stream from a pipe: `pacat`, or a stand-in the suite gives.
var player_tool := "pacat"
## Extra arguments in front of the player's own, for a stand-in that is a shell.
var player_prefix: PackedStringArray = []
## Where the ports play to, by sink name; empty for `target`.
var device := ""
## Kinds that are not to be ported: MONITOR where the keys are their own node (NativeKeys), so
## there are not two streams by one name.
var skip: Array[StringName] = []
## {kind: {"pid", "pipe": FileAccess, "capture": AudioEffectCapture, "dropped": int, "sent": int}}
var ports := {}

var _thread: Thread
var _running := false
var _lock := Mutex.new()


## The three buses, each with nowhere to go but Master yet. Made at startup whether or not the
## ports open, so every player can name its bus without asking.
static func ensure_buses() -> void:
	# Spent first: a bus can only send to one before it, and the three send here when ported.
	if AudioServer.get_bus_index(SPENT) < 0:
		var spent := AudioServer.bus_count
		AudioServer.add_bus(spent)
		AudioServer.set_bus_name(spent, SPENT)
		AudioServer.set_bus_mute(spent, true)
		AudioServer.set_bus_send(spent, &"Master")
	for kind in KINDS:
		if AudioServer.get_bus_index(kind) < 0:
			var at := AudioServer.bus_count
			AudioServer.add_bus(at)
			AudioServer.set_bus_name(at, kind)
			AudioServer.set_bus_send(at, &"Master")


## The bus a player of `kind` plays on: its own where it has been made, Master where not (a
## test building one piece of gear by itself).
static func bus(kind: StringName) -> StringName:
	return kind if AudioServer.get_bus_index(kind) >= 0 else &"Master"


## Whether this machine can make the ports at all.
static func supported(tool := "pacat") -> bool:
	return OS.get_name() == "Linux" and OS.execute("sh", ["-c", "command -v " + tool], [], false) == 0


## Start a stream per kind, and move each bus's sound out through it. False, with `why_not`
## set, where they could not be made; the buses then go on playing to Master.
func open() -> bool:
	ensure_buses()
	if not ports.is_empty():
		return true
	if not supported(player_tool):
		why_not = "Separate audio outputs need PipeWire (or PulseAudio) and its pacat tool."
		return false
	for kind in KINDS:
		if kind in skip:
			continue
		var piped := OS.execute_with_pipe(player_tool, player_prefix + player_args(kind), false)
		if piped.is_empty():
			close()
			why_not = "Could not start %s for the %s output." % [player_tool, NAMES[kind]]
			return false
		var capture := AudioEffectCapture.new()
		capture.buffer_length = 0.1
		var b := AudioServer.get_bus_index(kind)
		AudioServer.add_bus_effect(b, capture)
		AudioServer.set_bus_send(b, SPENT)
		ports[kind] = {"pid": piped["pid"], "pipe": piped["stdio"], "capture": capture, "dropped": 0, "sent": 0}
	active = true
	why_not = ""
	_running = true
	_thread = Thread.new()
	_thread.start(_pump)
	return true


## The player's arguments for one kind: raw stereo float at the mix rate, named for a patchbay.
func player_args(kind: StringName) -> PackedStringArray:
	var title := "dawlings · %s" % NAMES[kind]
	var latency := OS.get_environment("R3D_PORT_LATENCY_MS")
	var args := PackedStringArray(["--playback", "--raw", "--format=float32le", "--rate=%d" % RATE,
			"--channels=2", "--latency-msec=%s" % (latency if latency.is_valid_int() else str(LATENCY_MS)),
			"--client-name=" + title, "--stream-name=" + title,
			"--property=node.name=dawlings_" + NAMES[kind], "--property=node.description=" + title,
			"--property=application.name=" + title, "--property=media.role=Music"])
	var to := device if not device.is_empty() else target
	if not to.is_empty():
		args.append("--device=" + to)
	return args


## Stop every stream and put the buses back on Master, where Godot's own output plays them.
func close() -> void:
	_running = false
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	for kind in ports:
		_unport(kind, ports[kind])
	ports.clear()
	active = false


## One port taken down: its capture off the bus, the bus back on Master, its player stopped.
static func _unport(kind: StringName, port: Dictionary) -> void:
	var b := AudioServer.get_bus_index(kind)
	if b >= 0:
		for i in range(AudioServer.get_bus_effect_count(b) - 1, -1, -1):
			if AudioServer.get_bus_effect(b, i) == port["capture"]:
				AudioServer.remove_bus_effect(b, i)
		AudioServer.set_bus_send(b, &"Master")
	(port["pipe"] as FileAccess).close()
	if OS.is_process_running(port["pid"]):
		OS.kill(port["pid"])


## A port whose player has gone (killed, or its server restarted) is closed, and its bus goes
## back to Master: heard from Godot's own stream rather than not at all.
func _process(_delta: float) -> void:
	for kind in ports.keys():
		if not OS.is_process_running(ports[kind]["pid"]):
			_lock.lock()
			var port: Dictionary = ports[kind]
			ports.erase(kind)
			_lock.unlock()
			_unport(kind, port)
			why_not = "The %s output stopped; it plays through the app's own output now." % NAMES[kind]
			push_warning(why_not)
	if active and ports.is_empty():
		active = false


func _exit_tree() -> void:
	close()


## What the captures hold, into the pipes, in pieces no bigger than PIPE_BUF.
func _pump() -> void:
	var piece := PIPE_BUF / 8
	while _running:
		_lock.lock()
		for kind in ports:
			var port: Dictionary = ports[kind]
			var capture: AudioEffectCapture = port["capture"]
			var pipe: FileAccess = port["pipe"]
			var n := capture.get_frames_available()
			while n > 0:
				var take := mini(n, piece)
				var bytes := capture.get_buffer(take).to_byte_array()
				n -= take
				if not pipe.store_buffer(bytes):
					port["dropped"] += take
				else:
					port["sent"] += take
		_lock.unlock()
		OS.delay_usec(1000)
