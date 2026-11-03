class_name GuestLive
extends Node

## A guest's audio input, heard live on the host, with the guest's offer and the host's say-so.
##
## The guest offers their input (Session.offer_share), the host allows it onto a track
## (Session.answer_share), and from then on the guest streams what their interface hears up
## (Session.send_live_audio), a few milliseconds at a time. Here the host queues each guest's sound
## in a `LiveSource` and tells the built-in engine's input monitor (InputMonitor.live) to play it
## through that track, so it goes through the track's chain, fader, sends and meters like any
## monitored input. The take is the guest's own recording (GuestAudio): the live sound is for
## hearing, and is not kept.
##
## What arrives is held to about LATE_FRAMES: sound that would queue past it is dropped, oldest
## first, so what is heard is what is being played now, a little late, never later and later.

## The sound a source holds back before it starts to give any: enough to ride over a network's
## jitter without a gap, no more.
const PREBUFFER_FRAMES := 960
## The most a source holds, frames: what is queued past this is the oldest, dropped.
const LATE_FRAMES := 4800
const RATE := 48000


## One guest's sound, queued. `push` from the network, `read` from the monitor's thread.
class LiveSource extends MixSource:
	var _queue := PackedVector2Array()
	var _lock := Mutex.new()
	var _primed := false
	var received := 0
	var dropped := 0

	func start() -> bool:
		return true

	func stop() -> void:
		pass

	func describe() -> String:
		return "a guest's live input"

	func push(pcm: PackedByteArray) -> void:
		var frames := PackedVector2Array()
		frames.resize(pcm.size() / 2)
		for i in frames.size():
			var v := pcm.decode_s16(i * 2) / 32768.0
			frames[i] = Vector2(v, v)
		_lock.lock()
		_queue.append_array(frames)
		received += frames.size()
		if _queue.size() > LATE_FRAMES:
			dropped += _queue.size() - LATE_FRAMES
			_queue = _queue.slice(_queue.size() - LATE_FRAMES)
		_lock.unlock()

	func read() -> PackedVector2Array:
		_lock.lock()
		var out := PackedVector2Array()
		if not _primed and _queue.size() >= PREBUFFER_FRAMES:
			_primed = true
		if _primed:
			out = _queue
			_queue = PackedVector2Array()
			if out.is_empty():
				# Dry: the next sound waits for its prebuffer again.
				_primed = false
		_lock.unlock()
		return out

	func queued() -> int:
		_lock.lock()
		var n := _queue.size()
		_lock.unlock()
		return n


## {peer: LiveSource}
var _sources: Dictionary = {}


func _ready() -> void:
	Session.live_audio_heard.connect(_on_audio)
	Session.shares_changed.connect(_sync)


func _exit_tree() -> void:
	_withdraw_all()


func _on_audio(from: int, pcm: PackedByteArray) -> void:
	if Session.role != Session.Role.HOST or not Session.share_allowed(from, &"audio"):
		return
	var source: LiveSource = _sources.get(from)
	if source == null:
		source = LiveSource.new()
		_sources[from] = source
	source.push(pcm)


## The track each allowed guest's sound plays through, and what is no longer allowed let go.
func _sync() -> void:
	for peer: int in _sources.keys():
		if not Session.share_allowed(peer, &"audio"):
			_sources.erase(peer)
	_publish()


func _process(_delta: float) -> void:
	_publish()


## Tell the input monitor what to play where, every frame: it forgets what it is not told.
func _publish() -> void:
	var monitors = monitors_of_backend()
	if monitors == null:
		return
	var live := {}
	var sources := {}
	for peer: int in _sources:
		var track := Session.share_track(peer)
		if track <= 0 or not Session.share_allowed(peer, &"audio"):
			continue
		var key := "live:%d" % peer
		live[track] = key
		sources[key] = _sources[peer]
	monitors.live = live
	monitors.live_sources = sources


static func monitors_of_backend() -> InputMonitor:
	if DAW.backend == null:
		return null
	return DAW.backend.get("monitors") as InputMonitor


func _withdraw_all() -> void:
	_sources.clear()
	var monitors := monitors_of_backend()
	if monitors != null and is_instance_valid(monitors):
		monitors.live = {}
		monitors.live_sources = {}


## The source for `peer`, for the suite.
func source_of(peer: int) -> LiveSource:
	return _sources.get(peer)
