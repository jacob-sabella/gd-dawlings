class_name TubeFrames
extends RefCounted

## A fetched video's picture, for the TV (docs/sampling_station.md): ffmpeg decodes it from a time
## on, through a pipe, a frame at a time, on a thread, and `frame_at(t)` hands over the frame for the
## sound's position t. The sound is the clock: frames are never shown by a clock of their own, so a
## TV that stutters drops a frame rather than drifting from what is heard.
##
## The reader keeps no more than AHEAD frames decoded past the one shown, so a paused TV holds
## a still and a quarter of a megabyte a frame, not a video's worth. A time before the first frame
## held, or further ahead than LEAP, restarts the pipe there (a seek).

const W := 384
const H := 216
const FPS := 24.0
const FRAME := W * H * 3
const AHEAD := 12
## How far past the newest frame a time may be before it is a seek rather than a wait (s).
const LEAP := 1.0

var id := ""
## The time of the pipe's first frame (s).
var _from := 0.0
## [index, Image] in order, index counting frames from `_from`.
var _queue: Array = []
## The frame handed over last and its index, kept for a time between two frames.
var _shown: Image
var _shown_at := -1
var _mutex := Mutex.new()
var _thread: Thread
var _pipe: FileAccess
var _pid := -1
var _stop := false
var _ended := false


func _init(video_id: String) -> void:
	id = video_id


## The frame for time `t` (s) into the video; null until the first is decoded.
func frame_at(t: float) -> Image:
	var back := t < _from - 0.001 or (_shown_at >= 0 and t < _time_of(_shown_at) - 0.5 / FPS)
	var leap := t > _newest_time() + LEAP and not _ended
	if (_thread == null and not _ended) or back or leap:
		_open(maxf(t, 0.0))
	var want := int(floor((t - _from) * FPS + 0.001))
	_mutex.lock()
	while not _queue.is_empty() and _queue[0][0] <= want:
		var head: Array = _queue.pop_front()
		_shown_at = head[0]
		_shown = head[1]
	_mutex.unlock()
	return _shown


## Whether the pipe has given its last frame (the video's end).
func ended() -> bool:
	_mutex.lock()
	var done := _ended and _queue.is_empty()
	_mutex.unlock()
	return done


func _time_of(index: int) -> float:
	return _from + index / FPS


func _newest_time() -> float:
	_mutex.lock()
	var newest: int = _queue.back()[0] if not _queue.is_empty() else _shown_at
	_mutex.unlock()
	return _time_of(maxi(newest, 0))


func _open(at: float) -> void:
	close()
	_from = at
	_shown_at = -1
	_stop = false
	_ended = false
	var piped := OS.execute_with_pipe(Tube.ffmpeg, ["-v", "error", "-ss", "%.3f" % at,
			"-i", Tube.video_path(id), "-an", "-vf",
			"scale=%d:%d:force_original_aspect_ratio=decrease,pad=%d:%d:(ow-iw)/2:(oh-ih)/2,fps=%d"
			% [W, H, W, H, int(FPS)], "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], true)
	if piped.is_empty():
		_ended = true
		return
	_pipe = piped["stdio"]
	_pid = piped["pid"]
	_thread = Thread.new()
	_thread.start(_read)


func _read() -> void:
	var index := 0
	while not _stop:
		_mutex.lock()
		var full := _queue.size() >= AHEAD
		_mutex.unlock()
		if full:
			OS.delay_msec(5)
			continue
		var bytes := _frame()
		if bytes.size() < FRAME:
			break
		var image := Image.create_from_data(W, H, false, Image.FORMAT_RGB8, bytes)
		_mutex.lock()
		_queue.append([index, image])
		_mutex.unlock()
		index += 1
	_mutex.lock()
	_ended = true
	_mutex.unlock()


## The next whole frame from the pipe, which hands over a few kilobytes a read; short at its end.
func _frame() -> PackedByteArray:
	var bytes := PackedByteArray()
	while bytes.size() < FRAME and not _stop:
		var more := _pipe.get_buffer(FRAME - bytes.size())
		if more.is_empty():
			break
		bytes.append_array(more)
	return bytes


## Stop decoding (the TV off, a seek, quitting).
func close() -> void:
	_stop = true
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_pid = -1
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	_pipe = null
	_mutex.lock()
	_queue.clear()
	_mutex.unlock()
