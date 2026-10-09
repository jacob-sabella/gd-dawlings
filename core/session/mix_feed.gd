class_name MixFeed
extends Node

## The host's programme audio, to every guest who is listening.
##
## Its own UDP socket and its own threads, apart from everything else the session sends, and
## both for the same reason: latency. The session's ENet traffic is serviced once a frame on
## the main thread, so anything sent through it waits for the next frame -- up to sixteen
## milliseconds of jitter on every packet, which a guest's buffer then has to be sixteen
## milliseconds deeper to hide. Audio here is read and sent from a thread that wakes every half
## millisecond, so a packet leaves within a fraction of a millisecond of being captured.
##
## The wire is deliberately plain: 128 frames of 16-bit stereo, 2.7ms of sound, 528 bytes, well
## under any MTU. 1.5Mbit/s per listener -- nothing on a LAN, too much for a phone tether, and
## the reason there is no compression yet is that Godot has no low-latency codec to compress
## with. Opus would cut it to a tenth.
##
## Admission rides on the session's: the host hands each admitted guest a random ticket over the
## reliable channel, and the audio socket only answers packets that carry one. The guest speaks
## first, so the reply finds its way back through the guest's own NAT and firewall.

signal changed()

## "RD3P" little-endian: audio with the song position in its header. Changed from "RD3A" when
## the header grew, so a mismatched pair of builds hears silence rather than garbage.
const MAGIC_AUDIO := 0x50334452
const MAGIC_LISTEN := 0x4C334452 # "RD3L"
const HEADER := 24
## The header's flags. VALID: the host knew its song position. PLAYING and RECORDING: its
## transport, as of the packet's first frame.
const FLAG_VALID := 1
const FLAG_PLAYING := 2
const FLAG_RECORDING := 4
const FRAMES := 128
const RATE := 48000.0
## A listener not heard from for this long is taken to have gone.
const LISTENER_TIMEOUT_MSEC := 3000
const KEEPALIVE_MSEC := 250
## Godot's mixer takes this many frames from a playing stream at once.
const MIX_STEP := 512
## The most the guest lets sit in Godot's generator. Not a target -- the jitter buffer's steering
## sets how much is buffered in all -- just a ceiling well above it.
const QUEUE_FRAMES := 4096

var port := 0
var sending := false
var listening := false
## Host: what it is sharing, in a sentence.
var source_label := ""
## Guest: what it last heard, for the panel.
var volume_db := 0.0:
	set(v):
		volume_db = v
		if _player != null:
			_player.volume_db = v

var _socket: PacketPeerUDP = null
var _thread: Thread = null
var _running := false
var _mutex := Mutex.new()

# host
var _source: MixSource = null
var _tickets: Dictionary = {} # ticket -> peer_id
var _listeners: Dictionary = {} # ticket -> {ip, port, heard, echo}
var _seq := 0
## The host's song position, running between the DAW's reports, for stamping packets.
var song_clock := SongClock.new()

# guest
var _jitter: JitterBuffer = null
var _player: AudioStreamPlayer = null
var _playback: AudioStreamGeneratorPlayback = null
var _queue_capacity := 0
var _skips := 0
## The loudest sample handed to the speakers lately, decaying: proof of sound, not just packets.
var _level := 0.0
var _ticket := 0
var _host_ip := ""
var _rtt_ms := -1.0
var _last_heard_msec := 0
## Headless or told not to play: frames are pulled by the clock and measured instead of heard.
var drain := false
var _drain_start_usec := 0
var _drained := 0
## What a drain heard, for the probe: the loudest frame and when each click arrived.
var heard_peak := 0.0
var heard_clicks: Array = []
var _clicks_mutex := Mutex.new()
## Guest: which song position is at the speaker. See heard_position().
var heard := HeardClock.new()


var _report_msec := 0
## Print the guest's account of its delay once a second (--audio-stats, and the latency tool).
var report := false


func _exit_tree() -> void:
	stop()


func _process(_delta: float) -> void:
	# The song clock is fed from the main thread, where DAW.state lives, and read from the send
	# thread. Every frame: repeats are ignored by the clock itself.
	if sending and DAW.state != null:
		song_clock.observe(DAW.state.position_seconds, DAW.state.playing, DAW.state.recording,
				Time.get_ticks_usec())
	_report_stats()


## For tools/audio_latency.sh: the guest's own account of where its delay is, once a second.
func _report_stats() -> void:
	if not listening or not (report or OS.get_environment("R3D_AUDIO_STATS") != ""):
		return
	if Time.get_ticks_msec() - _report_msec < 1000:
		return
	_report_msec = Time.get_ticks_msec()
	var s := stats()
	print("MIXFEED latency %.1f = buffer %.1f (jitter target %d) + output %.1f + rtt %.2f; lost %d late %d underruns %d level %.3f" % [
			s["latency_ms"], s["buffer_ms"], _jitter.target, s["output_ms"], s["rtt_ms"],
			s["lost"], s["late"], s["underruns"], s["level"]])


# --- host ---------------------------------------------------------------------------------

func start_sending(at_port: int, source: MixSource) -> bool:
	stop()
	_socket = PacketPeerUDP.new()
	if _socket.bind(at_port) != OK:
		push_warning("MixFeed: cannot bind audio port %d" % at_port)
		_socket = null
		return false
	port = at_port
	_source = source if source != null else MixSource.new()
	if not _source.start():
		_source = MixSource.new()
	source_label = _source.describe()
	sending = true
	_seq = 0
	song_clock.reset()
	if _source is MixSource.Tone:
		(_source as MixSource.Tone).clock = song_clock
	_running = true
	_thread = Thread.new()
	_thread.start(_send_loop)
	changed.emit()
	return true


## A ticket for one admitted guest. Random, so a guest that has left cannot be impersonated by
## guessing the next number.
func grant(peer_id: int) -> int:
	var ticket := (randi() << 31) ^ randi()
	_mutex.lock()
	_tickets[ticket] = peer_id
	_mutex.unlock()
	return ticket


func revoke(peer_id: int) -> void:
	_mutex.lock()
	for ticket in _tickets.keys():
		if _tickets[ticket] == peer_id:
			_tickets.erase(ticket)
			_listeners.erase(ticket)
	_mutex.unlock()


func listener_count() -> int:
	_mutex.lock()
	var n := _listeners.size()
	_mutex.unlock()
	return n


func _send_loop() -> void:
	var pending := PackedVector2Array()
	# The song position of pending[0], and the transport it was under.
	var pending_seconds := 0.0
	var pending_flags := 0
	while _running:
		_hear_listeners()
		var got := _source.read()
		if not got.is_empty():
			pending.append_array(got)
			# The newest frame was the song's "now" a source-specific moment ago; the frames
			# before it, one sample each earlier. Re-derived on every read rather than counted
			# forward, so the stamps follow the DAW's clock and not this machine's sound card.
			var song := song_clock.at(Time.get_ticks_usec() - int(_source.song_offset_ms() * 1000.0))
			pending_flags = flags_of(song)
			pending_seconds = float(song["seconds"])
			if song["playing"]:
				pending_seconds -= (pending.size() - 1) / RATE
		while pending.size() >= FRAMES:
			var packet := encode(_seq, pending.slice(0, FRAMES), pending_seconds, pending_flags)
			pending = pending.slice(FRAMES)
			if pending_flags & FLAG_PLAYING:
				pending_seconds += FRAMES / RATE
			_seq += 1
			_mutex.lock()
			var now := Time.get_ticks_msec()
			for ticket in _listeners.keys():
				var l: Dictionary = _listeners[ticket]
				if now - int(l["heard"]) > LISTENER_TIMEOUT_MSEC:
					_listeners.erase(ticket)
					continue
				# The guest's last timestamp, echoed, so it can time the round trip on the path
				# the sound actually takes.
				packet.encode_u32(8, int(l["echo"]) + (now - int(l["echo_at"])))
				_socket.set_dest_address(l["ip"], l["port"])
				_socket.put_packet(packet)
			_mutex.unlock()
		OS.delay_usec(500)


func _hear_listeners() -> void:
	while _socket.get_available_packet_count() > 0:
		var packet := _socket.get_packet()
		if packet.size() < 16 or packet.decode_u32(0) != MAGIC_LISTEN:
			continue
		var ticket := packet.decode_s64(4)
		_mutex.lock()
		if _tickets.has(ticket):
			var fresh := not _listeners.has(ticket)
			_listeners[ticket] = {"ip": _socket.get_packet_ip(), "port": _socket.get_packet_port(),
					"heard": Time.get_ticks_msec(), "echo": packet.decode_u32(12),
					"echo_at": Time.get_ticks_msec()}
			if fresh:
				changed.emit.call_deferred()
		_mutex.unlock()


# --- guest --------------------------------------------------------------------------------

func listen(address: String, at_port: int, ticket: int) -> bool:
	stop()
	_host_ip = address if address.is_valid_ip_address() else IP.resolve_hostname(address, IP.TYPE_IPV4)
	if _host_ip.is_empty():
		return false
	_socket = PacketPeerUDP.new()
	if _socket.connect_to_host(_host_ip, at_port) != OK:
		_socket = null
		return false
	port = at_port
	_ticket = ticket
	_jitter = JitterBuffer.new()
	_jitter.sample_rate = RATE
	_jitter.step_frames = MIX_STEP
	_rtt_ms = -1.0
	_last_heard_msec = 0
	heard_peak = 0.0
	heard_clicks.clear()
	heard.reset()
	heard.frames_per_packet = FRAMES
	# No sound card at all (--headless implies the Dummy driver): nothing would ever ask for the
	# frames, so the clock asks instead. A headless display with a real audio driver -- the
	# latency tool's guest -- still plays.
	drain = drain or AudioServer.get_driver_name() == "Dummy"
	if not drain:
		_open_player()
	_drain_start_usec = Time.get_ticks_usec()
	_drained = 0
	listening = true
	_running = true
	_thread = Thread.new()
	_thread.start(_listen_loop)
	changed.emit()
	return true


func _open_player() -> void:
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = RATE
	# The generator's ring, not its fill: how full it is kept is QUEUE_FRAMES, below.
	stream.buffer_length = QUEUE_FRAMES / RATE
	_player = AudioStreamPlayer.new()
	_player.name = "SessionMix"
	_player.bus = AudioPorts.bus(AudioPorts.MIX)
	_player.stream = stream
	_player.volume_db = volume_db
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback()
	_queue_capacity = _playback.get_frames_available()
	_skips = _playback.get_skips()


func _listen_loop() -> void:
	var last_keepalive := -KEEPALIVE_MSEC
	while _running:
		var now := Time.get_ticks_msec()
		if now - last_keepalive >= KEEPALIVE_MSEC:
			last_keepalive = now
			_socket.put_packet(listen_packet(_ticket, now))
		while _socket.get_available_packet_count() > 0:
			var packet := _socket.get_packet()
			var decoded := decode(packet)
			if decoded.is_empty():
				continue
			var arrived := Time.get_ticks_usec() / 1000.0
			_jitter.push(decoded["seq"], decoded["frames"], arrived)
			heard.stamp(decoded["seq"], decoded["position"], decoded["flags"])
			_last_heard_msec = Time.get_ticks_msec()
			var rtt := float(Time.get_ticks_msec() - int(decoded["echo"]))
			if rtt >= 0.0 and rtt < 5000.0:
				_rtt_ms = rtt if _rtt_ms < 0.0 else lerpf(_rtt_ms, rtt, 0.05)
		if drain:
			_drain_by_clock()
		elif _playback != null:
			# Everything that has arrived goes straight on to the generator, a packet at a time:
			# one buffer, not two in a row. The jitter buffer's job here is the steering --
			# order, gaps, drift, and how deep the two together should be -- not holding audio.
			var queued := _queue_capacity - _playback.get_frames_available()
			if _playback.get_skips() != _skips:
				_skips = _playback.get_skips()
				_jitter.reprime()
			while queued + FRAMES <= QUEUE_FRAMES:
				var frames := _jitter.take(FRAMES, queued)
				if frames.is_empty():
					break
				_playback.push_buffer(frames)
				queued += FRAMES
				_level *= 0.97
				for f in frames:
					_level = maxf(_level, absf(f.x))
			# At the speaker: the read head, less the generator's queue, less the card. Less half a
			# mixer gulp as well: the mixer takes 512 frames at once and plays them out over the
			# next 10.7ms, so on average the frame being heard is half a gulp behind the last
			# frame it took.
			heard.observe(_jitter.read_frame() - queued - MIX_STEP * 0.5
					- AudioServer.get_output_latency() * RATE, Time.get_ticks_usec())
		OS.delay_usec(500)


## No sound card to pace the reads, so the wall clock does: the same demand a card would make,
## and the frames measured instead of heard.
func _drain_by_clock() -> void:
	var due := int((Time.get_ticks_usec() - _drain_start_usec) * RATE / 1000000.0)
	var count := due - _drained
	if count < FRAMES:
		return
	var frames := _jitter.pull(count)
	# Pulled is heard, in a drain: the frame just taken is the one at the "speaker" now.
	heard.observe(_jitter.read_frame(), Time.get_ticks_usec())
	for i in frames.size():
		var v := absf(frames[i].x)
		if v > heard_peak:
			heard_peak = v
		if v > 0.6 and (heard_clicks.is_empty() or _drained + i - int(heard_clicks[-1]) > int(RATE / 2.0)):
			_clicks_mutex.lock()
			heard_clicks.append(_drained + i)
			_clicks_mutex.unlock()
	_drained += count


## The clicks a drain has heard so far, each as [frame, Time.get_ticks_usec() it was "heard"]:
## a drain hears frame n exactly n/RATE after it started. Safe from the main thread while the
## feed's thread is still adding to them. For the probe, which plays notes against them.
func clicks_heard() -> Array:
	_clicks_mutex.lock()
	var out: Array = []
	for frame in heard_clicks:
		out.append([int(frame), _drain_start_usec + int(int(frame) * 1000000.0 / RATE)])
	_clicks_mutex.unlock()
	return out


## The song position coming out of this guest's speakers right now:
## {seconds, playing, recording, valid}. Invalid when not listening, or before the stream says.
func heard_position() -> Dictionary:
	if not listening:
		return {"seconds": 0.0, "playing": false, "recording": false, "valid": false}
	return heard.at(Time.get_ticks_usec())


func stats() -> Dictionary:
	var out := {"sending": sending, "listening": listening, "listeners": listener_count(),
			"source": source_label}
	if listening and _jitter != null:
		var depth_ms := _jitter.depth() * 1000.0 / RATE
		var queue_ms := 0.0
		if _playback != null:
			queue_ms = (_queue_capacity - _playback.get_frames_available()) * 1000.0 / RATE
		var output_ms := 0.0 if drain else AudioServer.get_output_latency() * 1000.0
		var one_way := maxf(0.0, _rtt_ms) * 0.5
		out["rtt_ms"] = _rtt_ms
		out["jitter_ms"] = _jitter.jitter_ms()
		out["buffer_ms"] = depth_ms + queue_ms
		out["output_ms"] = output_ms
		# Capture fragment on the host + one packet + the network + the buffer + the card.
		out["latency_ms"] = 5.3 + FRAMES * 1000.0 / RATE + one_way + depth_ms + queue_ms + output_ms
		out["lost"] = _jitter.lost
		out["late"] = _jitter.late
		out["underruns"] = _jitter.underruns
		out["packets"] = _jitter.packets
		out["level"] = _level if not drain else heard_peak
		out["hearing"] = _last_heard_msec > 0 and Time.get_ticks_msec() - _last_heard_msec < 1000
	return out


# --- both ---------------------------------------------------------------------------------

func stop() -> void:
	_running = false
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null
	if _socket != null:
		_socket.close()
	_socket = null
	if _source != null:
		_source.stop()
	_source = null
	if _player != null:
		_player.stop()
		_player.queue_free()
	_player = null
	_playback = null
	_mutex.lock()
	_tickets.clear()
	_listeners.clear()
	_mutex.unlock()
	var was := sending or listening
	sending = false
	listening = false
	source_label = ""
	if was:
		changed.emit()


# --- the wire -----------------------------------------------------------------------------

## [magic u32][seq u32][echo u32][frames u16][flags u16][song seconds f64][frames × L,R s16]
##
## The song position is of the packet's FIRST frame, in seconds from the project start, as a
## double: a float would be a tenth of a millisecond out by the end of a long song.
static func encode(seq: int, frames: PackedVector2Array, song_seconds := 0.0,
		flags := 0) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(HEADER + frames.size() * 4)
	out.encode_u32(0, MAGIC_AUDIO)
	out.encode_u32(4, seq)
	out.encode_u32(8, 0)
	out.encode_u16(12, frames.size())
	out.encode_u16(14, flags)
	out.encode_double(16, song_seconds)
	var at := HEADER
	for f in frames:
		out.encode_s16(at, int(clampf(f.x, -1.0, 1.0) * 32767.0))
		out.encode_s16(at + 2, int(clampf(f.y, -1.0, 1.0) * 32767.0))
		at += 4
	return out


static func decode(packet: PackedByteArray) -> Dictionary:
	if packet.size() < HEADER or packet.decode_u32(0) != MAGIC_AUDIO:
		return {}
	var count := packet.decode_u16(12)
	if packet.size() < HEADER + count * 4:
		return {}
	var frames := PackedVector2Array()
	frames.resize(count)
	var at := HEADER
	for i in count:
		frames[i] = Vector2(packet.decode_s16(at) / 32767.0, packet.decode_s16(at + 2) / 32767.0)
		at += 4
	var flags := packet.decode_u16(14)
	return {"seq": packet.decode_u32(4), "echo": packet.decode_u32(8), "frames": frames,
			"position": packet.decode_double(16), "flags": flags,
			"valid": (flags & FLAG_VALID) != 0, "playing": (flags & FLAG_PLAYING) != 0,
			"recording": (flags & FLAG_RECORDING) != 0}


## The header's flags for a song clock's reading.
static func flags_of(song: Dictionary) -> int:
	var out := 0
	if song.get("valid", false):
		out |= FLAG_VALID
	if song.get("playing", false):
		out |= FLAG_PLAYING
	if song.get("recording", false):
		out |= FLAG_RECORDING
	return out


static func listen_packet(ticket: int, now_msec: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(16)
	out.encode_u32(0, MAGIC_LISTEN)
	out.encode_s64(4, ticket)
	out.encode_u32(12, now_msec & 0xFFFFFFFF)
	return out
