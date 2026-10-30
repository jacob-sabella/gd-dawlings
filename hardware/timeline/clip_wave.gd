class_name ClipWave
extends RefCounted

## A sound file's shape at any zoom, for the clip editor (ClipEditorSurface): the loudest and
## quietest sample under each column of the panel, from the file itself.
##
## Not the take's overview (MixState.ItemState.peaks). That is fifty bytes a second, the loudest
## sample of each fiftieth: enough to see where a phrase is, and nothing like enough to trim to
## a hit, which happens inside one of those fiftieths. Here the samples are kept, folded to one
## channel, with two summaries over them -- the lowest and highest of every BLOCK frames, and of
## every BLOCK * BLOCK -- so a column of a whole take reads a few summary values and a column of
## five milliseconds reads the samples themselves, and either way a redraw is a few hundred
## lookups rather than a pass over the file.
##
## Reading a file is a pass over every sample in script, which for a long take is seconds, so it
## is asked for the way DawKitTransients is: `soon` answers at once with what is known and starts
## the reading on a worker thread if it is not, and `of_file` waits for it (a test, a tool). The
## last KEEP files are held, so going back and forth between two clips reads neither again.

## Frames a first summary value covers; the second covers BLOCK of those.
const BLOCK := 64
## Files held at once.
const KEEP := 4

## key (see _key) -> sound (see _read). Guarded by _lock, as workers write to it.
static var _found: Dictionary = {}
## Keys in the order they were last asked for, the oldest first: what is let go past KEEP.
static var _order: Array = []
static var _tasks: Dictionary = {}
static var _lock := Mutex.new()


## The sound at `path`, played backwards when `reversed`, if it has been read: {"mono":
## PackedFloat32Array, "rate": int, "seconds": float, "lo1", "hi1", "lo2", "hi2":
## PackedFloat32Array summaries}; {} while it is being read, and for a file that is not there. A
## file that cannot be read is {"error": why}.
static func soon(path: String, reversed := false) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var key := _key(path, reversed)
	_lock.lock()
	var known: Variant = _found.get(key)
	var task: int = _tasks.get(key, -1)
	if known != null:
		_order.erase(key)
		_order.append(key)
	_lock.unlock()
	if known != null:
		if task >= 0:
			WorkerThreadPool.wait_for_task_completion(task)
			_lock.lock()
			_tasks.erase(key)
			_lock.unlock()
		return known
	if task < 0:
		task = WorkerThreadPool.add_task(ClipWave._work.bind(path, reversed, key), false, "clip wave")
		_lock.lock()
		_tasks[key] = task
		_lock.unlock()
	return {}


## The same, waiting for the reading if it is under way or not yet asked for.
static func of_file(path: String, reversed := false) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	soon(path, reversed)
	settle()
	return soon(path, reversed)


## Waits for every reading under way.
static func settle() -> void:
	_lock.lock()
	var tasks := _tasks.duplicate()
	_tasks.clear()
	_lock.unlock()
	for key in tasks:
		WorkerThreadPool.wait_for_task_completion(tasks[key])


## Lets go of every file read.
static func forget() -> void:
	settle()
	_lock.lock()
	_found.clear()
	_order.clear()
	_lock.unlock()


static func _work(path: String, reversed: bool, key: String) -> void:
	var sound := _read(path, reversed)
	_lock.lock()
	_found[key] = sound
	_order.erase(key)
	_order.append(key)
	while _order.size() > KEEP:
		_found.erase(_order.pop_front())
	_lock.unlock()


## Read, folded to one channel (the channels' mean, which is what a zero crossing of the sound
## is a crossing of) and summarised.
static func _read(path: String, reversed: bool) -> Dictionary:
	var got := DawKitAudioFile.read(path)
	if not str(got.get("error", "")).is_empty():
		return {"error": got["error"]}
	var samples: PackedFloat32Array = got["samples"]
	var channels := maxi(int(got["channels"]), 1)
	var frames := samples.size() / channels
	var mono := PackedFloat32Array()
	mono.resize(frames)
	if channels == 1:
		mono = samples.slice(0, frames)
	else:
		for f in frames:
			mono[f] = (samples[f * 2] + samples[f * 2 + 1]) * 0.5
	if reversed:
		mono.reverse()
	var first := summarise(mono, mono, BLOCK)
	var second := summarise(first[0], first[1], BLOCK)
	var rate := maxi(int(got["rate"]), 1)
	return {"mono": mono, "rate": rate, "seconds": float(frames) / rate,
			"lo1": first[0], "hi1": first[1], "lo2": second[0], "hi2": second[1]}


## [lows, highs], one of each for every `block` values of `lo` and `hi` (the same array, for samples).
static func summarise(lo: PackedFloat32Array, hi: PackedFloat32Array, block: int) -> Array:
	var count := (lo.size() + block - 1) / block
	var lows := PackedFloat32Array()
	var highs := PackedFloat32Array()
	lows.resize(count)
	highs.resize(count)
	for b in count:
		var from := b * block
		var to := mini(from + block, lo.size())
		var l := lo[from]
		var h := hi[from]
		for i in range(from + 1, to):
			l = minf(l, lo[i])
			h = maxf(h, hi[i])
		lows[b] = l
		highs[b] = h
	return [lows, highs]


## The lowest and highest the sound goes between `from` and `to` seconds into it, as (low, high);
## (0, 0) wholly outside it. A stretch shorter than a frame is the sound there, read between the
## two frames either side of it, so a column of a few microseconds draws a line through the
## samples rather than a staircase.
static func span(sound: Dictionary, from: float, to: float) -> Vector2:
	if not sound.has("mono"):
		return Vector2.ZERO
	var mono: PackedFloat32Array = sound["mono"]
	var rate := float(sound["rate"])
	var frames := mono.size()
	var a := from * rate
	var b := to * rate
	if b < 0.0 or a >= frames or frames == 0:
		return Vector2.ZERO
	if b - a < 1.0:
		var v := sample_at(sound, (from + to) * 0.5)
		return Vector2(v, v)
	var ia := clampi(int(floor(a)), 0, frames - 1)
	var ib := clampi(int(ceil(b)), ia + 1, frames)
	var n := ib - ia
	if n >= BLOCK * BLOCK * 2:
		return _over(sound["lo2"], sound["hi2"], ia / (BLOCK * BLOCK), (ib + BLOCK * BLOCK - 1) / (BLOCK * BLOCK))
	if n >= BLOCK * 2:
		return _over(sound["lo1"], sound["hi1"], ia / BLOCK, (ib + BLOCK - 1) / BLOCK)
	return _over(mono, mono, ia, ib)


static func _over(lo: PackedFloat32Array, hi: PackedFloat32Array, a: int, b: int) -> Vector2:
	b = mini(b, lo.size())
	if a >= b:
		return Vector2.ZERO
	var l := lo[a]
	var h := hi[a]
	for i in range(a + 1, b):
		l = minf(l, lo[i])
		h = maxf(h, hi[i])
	return Vector2(l, h)


## The sound at `seconds` into it, between the frames either side; 0 outside it.
static func sample_at(sound: Dictionary, seconds: float) -> float:
	if not sound.has("mono"):
		return 0.0
	var mono: PackedFloat32Array = sound["mono"]
	var at := seconds * float(sound["rate"])
	var i := int(floor(at))
	if i < 0 or i >= mono.size():
		return 0.0
	var next := mono[i + 1] if i + 1 < mono.size() else mono[i]
	return lerpf(mono[i], next, at - i)


## Where the sound crosses zero nearest `seconds` into it, no further than `within` seconds away
## (seconds into the sound, between the two frames either side of the crossing), or NAN when it
## does not cross in that stretch. An edge cut there starts or stops the sound at silence, which
## is what keeps a cut that needs no fade from clicking.
static func zero_crossing(sound: Dictionary, seconds: float, within: float) -> float:
	if not sound.has("mono"):
		return NAN
	var mono: PackedFloat32Array = sound["mono"]
	var rate := float(sound["rate"])
	var centre := int(round(seconds * rate))
	var reach := maxi(int(ceil(within * rate)), 1)
	var best := NAN
	for d in reach + 1:
		for i: int in [centre - d, centre + d - 1]:
			if i < 0 or i + 1 >= mono.size():
				continue
			var a := mono[i]
			var b := mono[i + 1]
			if (a <= 0.0 and b > 0.0) or (a >= 0.0 and b < 0.0) or a == 0.0:
				var t: float = (i + (a / (a - b) if a != b else 0.0)) / rate
				if absf(t - seconds) <= within and (is_nan(best) or absf(t - seconds) < absf(best - seconds)):
					best = t
		if not is_nan(best):
			return best
	return best


static func _key(path: String, reversed: bool) -> String:
	return "%s|%d|%s" % [path, FileAccess.get_modified_time(path), "r" if reversed else "f"]
