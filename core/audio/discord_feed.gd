class_name DiscordFeed
extends Node

## What this machine sends to its owner's Discord voice channel: whichever of its sounds they
## choose -- the master out, any tracks, the inputs being monitored, the room's gear -- mixed into
## one stream, played by a bot that follows them into whatever voice channel they are in.
##
## HOW. Each chosen source is tapped at the end of its bus (an AudioEffectCapture last in its
## chain), and its fader and mute are applied here, as Godot applies a bus's volume after its
## effects. A thread mixes the taps and writes them to a `pacat` that plays into a sink of its own,
## a null sink named SINK made for this, heard by nobody on this machine; the bot
## (tools/discord_bridge) reads that sink's monitor and plays it into the channel. Anything else
## can be routed into the sink too, from a patchbay. The bot is this process's child, its stdin
## held open: switched off, or the game gone, it leaves the channel.
##
## The built-in engine's buses only: with Reaper the mix is Reaper's, and the stand-in makes no
## sound. Linux with PipeWire or PulseAudio, as AudioPorts is. Never in an exported build: the
## bot is a node script in the source checkout. Settings are this player's own, kept in SAVE.

signal changed

const SINK := "dawlings_discord"
const SINK_TITLE := "dawlings to Discord"
const RATE := 48000
const PIPE_BUF := 4096
const LATENCY_MS := 20
const SAVE := "user://discord.cfg"
const BRIDGE := "res://tools/discord_bridge/bridge.mjs"
const PACKAGES := "res://tools/discord_bridge/node_modules/discord.js/package.json"
## Sources, by id: the master, the room, every monitored input; and "track:N" for a track.
const MASTER := "master"
const GEAR := "gear"
const MONITORED := "monitored"

## Whether the feed is on: the sink, the stream and the bot running.
var on := false
## What it sends: MASTER, GEAR, MONITORED and "track:N" ids.
var sources: Array = [MASTER]
## The send's own level, dB, over every source.
var level_db := 0.0
## What the bot said last ({state, say, channel, guild}), for the panel.
var bot := {}
## Why it is off, or could not go on; empty when nothing is wrong.
var why_not := ""
## How loud the stream is now, 0-1, for the panel's meter.
var meter := 0.0

## The suite gives its own: where the bus a source taps is, and the tools.
var player_tool := "pacat"
var bot_tool := "node"

## {bus name: AudioEffectCapture} on the buses tapped now.
var _taps := {}
## [[bus name, linear gain]] the thread mixes, set on the main thread under the lock.
var _mix: Array = []
var _gain := 1.0
var _lock := Mutex.new()
var _thread: Thread
var _running := false
var _pacat := {}
var _bot := {}
var _bot_spare := ""
var _module := -1
var _peak := 0.0


func _ready() -> void:
	_load()
	if on:
		on = false
		start()


func _exit_tree() -> void:
	stop(false)


## Whether it can run here at all, with `why_not` said when not.
func available() -> bool:
	if OS.get_name() != "Linux":
		why_not = "Sending to Discord needs PipeWire or PulseAudio (Linux)."
		return false
	if OS.has_feature("template"):
		why_not = "Sending to Discord runs from the source checkout, not an exported build."
		return false
	if not _has(player_tool) or not _has("pactl") or not _has("parec"):
		why_not = "Sending to Discord needs pactl, pacat and parec (PipeWire or PulseAudio's tools)."
		return false
	if not _has(bot_tool):
		why_not = "Sending to Discord needs Node.js for its bot (node on PATH)."
		return false
	if not FileAccess.file_exists(ProjectSettings.globalize_path(PACKAGES)):
		why_not = "The Discord bot's packages are not installed: run npm install in tools/discord_bridge."
		return false
	return true


func start() -> bool:
	if on:
		return true
	if not available():
		changed.emit()
		return false
	if not _make_sink():
		why_not = "Could not make the %s sink (pactl load-module failed)." % SINK
		changed.emit()
		return false
	var piped := OS.execute_with_pipe(player_tool, player_args(), false)
	if piped.is_empty():
		why_not = "Could not start %s for the Discord stream." % player_tool
		_unmake_sink()
		changed.emit()
		return false
	_pacat = piped
	_start_bot()
	on = true
	why_not = ""
	_running = true
	_thread = Thread.new()
	_thread.start(_pump)
	_save()
	changed.emit()
	return true


## Off: the bot leaves the channel, the stream and the sink go. `remember` keeps it off next time.
func stop(remember := true) -> void:
	_running = false
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	_untap_all()
	for p in [_bot, _pacat]:
		if not p.is_empty():
			(p["stdio"] as FileAccess).close()
			var pid: int = p["pid"]
			# The bot leaves the channel when its stdin closes; a moment, then it is made to.
			if p == _bot:
				for i in 20:
					if not OS.is_process_running(pid):
						break
					OS.delay_msec(25)
			if OS.is_process_running(pid):
				OS.kill(pid)
	_bot = {}
	_pacat = {}
	_unmake_sink()
	var was := on
	on = false
	bot = {}
	if remember and was:
		_save()
	changed.emit()


func set_sources(ids: Array) -> void:
	sources = ids.duplicate()
	_save()
	changed.emit()


func toggle_source(id: String) -> void:
	var now := sources.duplicate()
	if id in now:
		now.erase(id)
	else:
		now.append(id)
	set_sources(now)


func set_level(db: float) -> void:
	level_db = clampf(db, -40.0, 12.0)
	_save()
	changed.emit()


## In words, for the panel: what it is doing.
func status() -> String:
	if not on:
		return why_not if why_not != "" else "Off."
	var said: String = bot.get("say", "starting the bot")
	return said


## The pacat's arguments: raw stereo float into SINK, named for a patchbay.
func player_args() -> PackedStringArray:
	var title := "dawlings · discord"
	return PackedStringArray(["--playback", "--raw", "--format=float32le", "--rate=%d" % RATE,
			"--channels=2", "--latency-msec=%d" % LATENCY_MS, "--device=" + SINK,
			"--client-name=" + title, "--stream-name=" + title,
			"--property=node.name=dawlings_discord_out", "--property=node.description=" + title,
			"--property=application.name=" + title, "--property=media.role=Music"])


## The buses the chosen sources are on now, [bus, linear gain]: the master and tracks through
## their faders and mutes, the inputs being monitored as their tracks, the room's own bus.
static func buses_for(ids: Array, backend: Object, state: MixState) -> Array:
	var out := {}
	var engine := backend as GodotBackend
	if engine != null and state != null:
		if MASTER in ids and AudioServer.get_bus_index(GodotBackend.MASTER_BUS) >= 0:
			var m := AudioServer.get_bus_index(GodotBackend.MASTER_BUS)
			out[GodotBackend.MASTER_BUS] = 0.0 if AudioServer.is_bus_mute(m) else db_to_linear(AudioServer.get_bus_volume_db(m))
		var tracks: Array = []
		for id in ids:
			if String(id).begins_with("track:"):
				tracks.append(String(id).trim_prefix("track:").to_int())
		if MONITORED in ids:
			for index in InputMonitor.plan(state):
				if index not in tracks:
					tracks.append(index)
		for index in tracks:
			var bus := String(engine.monitor_bus(index))
			var b := AudioServer.get_bus_index(bus)
			if b >= 0:
				out[bus] = 0.0 if AudioServer.is_bus_mute(b) else db_to_linear(AudioServer.get_bus_volume_db(b))
	if GEAR in ids and AudioServer.get_bus_index(AudioPorts.GEAR) >= 0:
		out[String(AudioPorts.GEAR)] = 1.0
	var rows: Array = []
	for bus in out:
		rows.append([bus, out[bus]])
	return rows


func _process(delta: float) -> void:
	if not on:
		return
	_read_bot()
	if not _pacat.is_empty() and not OS.is_process_running(_pacat["pid"]):
		why_not = "The Discord stream stopped."
		stop(false)
		return
	var rows := buses_for(sources, DAW.backend, DAW.state)
	_retap(rows)
	_lock.lock()
	_mix = rows
	_gain = db_to_linear(level_db)
	meter = maxf(_peak, meter - delta * 1.5)
	_peak = 0.0
	_lock.unlock()


## A capture last on each bus a source is on, put back when a rebuild took it off; and off the
## buses no longer sent.
func _retap(rows: Array) -> void:
	var wanted := {}
	for row in rows:
		wanted[row[0]] = true
	_lock.lock()
	for bus in _taps.keys():
		if not wanted.has(bus):
			_untap(bus)
	for bus in wanted:
		var b := AudioServer.get_bus_index(bus)
		var cap: AudioEffectCapture = _taps.get(bus)
		var placed := false
		if cap != null:
			for i in AudioServer.get_bus_effect_count(b):
				if AudioServer.get_bus_effect(b, i) == cap:
					placed = true
					break
		if not placed:
			cap = AudioEffectCapture.new()
			cap.buffer_length = 0.2
			AudioServer.add_bus_effect(b, cap)
			_taps[bus] = cap
	_lock.unlock()


func _untap(bus: String) -> void:
	var cap: AudioEffectCapture = _taps.get(bus)
	_taps.erase(bus)
	var b := AudioServer.get_bus_index(bus)
	if cap == null or b < 0:
		return
	for i in range(AudioServer.get_bus_effect_count(b) - 1, -1, -1):
		if AudioServer.get_bus_effect(b, i) == cap:
			AudioServer.remove_bus_effect(b, i)


func _untap_all() -> void:
	_lock.lock()
	for bus in _taps.keys():
		_untap(bus)
	_mix = []
	_lock.unlock()


## The taps, mixed, into the pipe in pieces no bigger than PIPE_BUF. As many frames as every tap
## has: they fill on the same mix, so they keep in step.
func _pump() -> void:
	var piece := PIPE_BUF / 8
	while _running:
		_lock.lock()
		var rows := _mix
		var gain := _gain
		var caps: Array = []
		var gains: Array = []
		for row in rows:
			var cap: AudioEffectCapture = _taps.get(row[0])
			if cap != null:
				caps.append(cap)
				gains.append(float(row[1]) * gain)
		var n := 1 << 30
		for cap in caps:
			n = mini(n, (cap as AudioEffectCapture).get_frames_available())
		if caps.is_empty():
			n = 0
		var pipe: FileAccess = _pacat.get("stdio")
		while n > 0 and pipe != null:
			var take := mini(n, piece)
			n -= take
			var mixed := PackedVector2Array()
			mixed.resize(take)
			for c in caps.size():
				var got: PackedVector2Array = (caps[c] as AudioEffectCapture).get_buffer(take)
				var g: float = gains[c]
				for i in got.size():
					mixed[i] += got[i] * g
			var peak := 0.0
			for i in take:
				var f := mixed[i]
				# Clipped here rather than wrapped by the encoder: a hot master stays a hot master.
				f = Vector2(clampf(f.x, -1.0, 1.0), clampf(f.y, -1.0, 1.0))
				mixed[i] = f
				peak = maxf(peak, maxf(absf(f.x), absf(f.y)))
			_peak = maxf(_peak, peak)
			pipe.store_buffer(mixed.to_byte_array())
		_lock.unlock()
		OS.delay_usec(2000)


func _start_bot() -> void:
	var script := ProjectSettings.globalize_path(BRIDGE)
	_bot = OS.execute_with_pipe(bot_tool, PackedStringArray([script, "--source=%s.monitor" % SINK]), false)
	_bot_spare = ""
	if _bot.is_empty():
		bot = {"state": "error", "say": "could not start the bot (%s)" % bot_tool}
	else:
		bot = {"state": "starting", "say": "starting the bot"}


## The bot's news: a JSON object a line on its stdout.
func _read_bot() -> void:
	if _bot.is_empty():
		return
	var pipe: FileAccess = _bot["stdio"]
	var got := pipe.get_buffer(1 << 14)
	if got.is_empty():
		if not OS.is_process_running(_bot["pid"]) and bot.get("state", "") != "error":
			bot = {"state": "error", "say": "the bot stopped"}
			changed.emit()
		return
	_bot_spare += got.get_string_from_utf8()
	var lines := _bot_spare.split("\n")
	_bot_spare = lines[lines.size() - 1]
	for i in lines.size() - 1:
		var said = JSON.parse_string(lines[i])
		if typeof(said) == TYPE_DICTIONARY:
			bot = said
			changed.emit()


func _make_sink() -> bool:
	var listed: Array = []
	OS.execute("pactl", ["list", "short", "sinks"], listed)
	if listed.size() > 0 and String(listed[0]).contains(SINK + "\t"):
		return true
	var out: Array = []
	var code := OS.execute("pactl", ["load-module", "module-null-sink", "sink_name=" + SINK,
			"sink_properties=device.description=\"%s\"" % SINK_TITLE.replace(" ", "\\ ")], out)
	if code != 0 or out.is_empty() or not String(out[0]).strip_edges().is_valid_int():
		return false
	_module = String(out[0]).strip_edges().to_int()
	return true


func _unmake_sink() -> void:
	if _module >= 0:
		OS.execute("pactl", ["unload-module", str(_module)])
		_module = -1


func _has(tool: String) -> bool:
	return OS.execute("sh", ["-c", "command -v " + tool], [], false) == 0


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE) != OK:
		return
	on = bool(cfg.get_value("discord", "on", false))
	sources = cfg.get_value("discord", "sources", [MASTER])
	level_db = float(cfg.get_value("discord", "level_db", 0.0))


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("discord", "on", on)
	cfg.set_value("discord", "sources", sources)
	cfg.set_value("discord", "level_db", level_db)
	cfg.save(SAVE)
