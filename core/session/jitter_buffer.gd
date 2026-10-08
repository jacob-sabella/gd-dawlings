class_name JitterBuffer
extends RefCounted

## The guest's side of hearing the mix: packets in at whatever moment the network delivers them,
## frames out at exactly the rate the sound card asks.
##
## Those two never agree, in two different ways, and each needs its own answer:
##
## - **Jitter.** Packets leave the host evenly and arrive in clumps. A buffer has to be deep
##   enough to ride out the longest gap between clumps -- and no deeper, because every frame of
##   depth is a frame of delay between the host's speakers and yours. So the depth is measured,
##   not configured: how late the latest recent packet was against the earliest, plus one
##   read's worth for the card to take. Lateness, not average jitter -- a buffer sized to the
##   typical packet runs dry on the untypical one, and that one is the click everyone hears.
##
## - **Drift.** Two machines' sound-card clocks are never the same clock. 48000Hz here is
##   48003Hz there, which is a frame every six seconds -- nothing, until an hour later the buffer
##   has quietly emptied or quietly grown by half a second. So frames are read at a rate nudged
##   very slightly faster or slower, by how far the depth is from where it should be. A tenth of
##   a percent is inaudible as pitch; it is still forty-eight frames a second of correction.
##
## Pure arithmetic over PackedVector2Array, no audio device, so the suite can feed it a network
## that misbehaves on purpose.

## The floor on depth. Below this a single late packet is an underrun, whatever the jitter says.
const MIN_TARGET := 256
## The ceiling. Past this the mix is so far behind that it is no longer something to play along
## to, and it is better to admit the network is bad than to quietly slide further back.
const MAX_TARGET := 4800
## How far the read rate may be bent, either way. 0.2% is about three cents: below what anyone
## hears as pitch, comfortably above any real pair of crystal clocks.
const MAX_BEND := 0.002
## How hard the depth error is corrected. Small: the depth is noisy from packet to packet, and
## the goal is to follow the clocks, not the noise.
const GAIN := 0.00002

var sample_rate := 48000.0
## The depth being aimed for, in frames.
var target := MIN_TARGET
## Extra on top of the measured lateness, in msec: what is spent on not being exactly right.
var margin_ms := 1.0

## Counters a person can be shown, and a test can assert on.
var packets := 0
var lost := 0
var late := 0
var underruns := 0

var _frames := PackedVector2Array()
## Fractional read position into _frames.
var _pos := 0.0
var _next_seq := -1
## Transit time of the quickest recent packet, in msec, on the guest's clock against the host's
## stream time. Only differences of it mean anything: the two clocks never agreed on zero.
var _base_ms := INF
## How much later than `_base_ms` recent packets have been, decaying so one bad second does not
## set the delay forever.
var _spread_ms := 0.0
## The largest read the card has asked for.
var _pull_frames := 0
## For `take`: how much the consumer behind it swallows at once. Godot's mixer takes 512 frames
## from a generator in one go, so that is the depth that must be there at the instant it does.
var step_frames := 0
var _priming := true
var _ratio := 1.0
## The host's frame number of `_frames[0]`, counted from its first packet: what turns the read
## head into a place in the host's stream, which is what a song position is stamped against.
var _base := 0


## The host's frame number at the read head: the next frame to be handed on. See HeardClock.
func read_frame() -> float:
	return _base + _pos


## Frames waiting to be played.
func depth() -> int:
	return maxi(0, _frames.size() - int(_pos))


func jitter_ms() -> float:
	return _spread_ms


## The read rate right now, relative to the sender's. Above one means catching up.
func ratio() -> float:
	return _ratio


## One packet from the host. `seq` counts packets, `arrival_ms` is the local clock when it came
## in, `packet_ms` is how much audio a packet carries.
func push(seq: int, frames: PackedVector2Array, arrival_ms: float) -> void:
	var packet_ms := frames.size() * 1000.0 / sample_rate
	if _next_seq >= 0 and seq < _next_seq:
		# Overtaken. Its frames have already been played around -- as silence or as the next
		# packet early -- and splicing them in now would be the past, played late.
		late += 1
		return
	if _next_seq >= 0 and seq > _next_seq:
		var missing := seq - _next_seq
		lost += missing
		# A gap in the stream is filled, not closed up: closing it would pull everything after
		# it earlier and the depth would fall by a packet per loss. Filled with the last frame
		# fading out rather than hard zeros, which click.
		var held := _frames[_frames.size() - 1] if not _frames.is_empty() else Vector2.ZERO
		var fill := mini(missing * frames.size(), MAX_TARGET)
		for i in fill:
			_frames.append(held * maxf(0.0, 1.0 - float(i) / 64.0))
	_next_seq = seq + 1
	packets += 1
	_frames.append_array(frames)
	# Taken from the newest packet every time rather than kept as a running count: a long loss
	# is filled with less than it lost (see above), and a count would carry that error forever.
	_base = (seq + 1) * frames.size() - _frames.size()
	_measure_lateness(seq, arrival_ms, packet_ms)
	# A runaway backlog -- the guest's tab was asleep, the network burst ten seconds at once --
	# is cut back to the target, from the old end. Old audio is the least useful audio.
	if depth() > MAX_TARGET * 2:
		var drop := depth() - target
		_frames = _frames.slice(int(_pos) + drop)
		_base += int(_pos) + drop
		_pos = 0.0


func _measure_lateness(seq: int, arrival_ms: float, packet_ms: float) -> void:
	var transit := arrival_ms - seq * packet_ms
	# The quickest path, allowed to creep later very slowly: two clocks drifting apart look
	# exactly like the network getting slower, and a floor that never moved would read a slow
	# clock as ever-growing lateness.
	_base_ms = minf(_base_ms + 0.0005, transit)
	_spread_ms = maxf(_spread_ms * 0.9995, transit - _base_ms)
	_retarget(packet_ms)


func _retarget(packet_ms: float) -> void:
	var wanted := (_spread_ms + packet_ms + margin_ms) * sample_rate / 1000.0 \
			+ maxi(_pull_frames, step_frames)
	target = clampi(int(wanted), MIN_TARGET, MAX_TARGET)


## `count` frames for a consumer that keeps a queue of its own -- an AudioStreamGenerator -- or
## nothing, if there are not yet `count` to give. `queued` is how much that queue holds, because
## the delay a person hears is both buffers together, and that sum is what is steered to the
## target. Running dry is not counted here: the queue behind may still be playing, and only it
## knows when it truly ran out (see `reprime`).
func take(count: int, queued: int) -> PackedVector2Array:
	if _priming:
		if depth() + queued < target or depth() < count + 2:
			return PackedVector2Array()
		_priming = false
	if float(depth()) < count * (1.0 + MAX_BEND) + 2.0:
		return PackedVector2Array()
	var error := float(depth() + queued - target)
	_ratio = clampf(1.0 + error * GAIN, 1.0 - MAX_BEND, 1.0 + MAX_BEND)
	var out := PackedVector2Array()
	out.resize(count)
	for i in count:
		var at := int(_pos)
		out[i] = _frames[at].lerp(_frames[at + 1], _pos - at)
		_pos += _ratio
	if _pos > 4096.0:
		var cut := int(_pos)
		_frames = _frames.slice(cut)
		_base += cut
		_pos -= cut
	return out


## The queue behind `take` ran out: the listener heard a gap. Counted, and nothing more is
## handed over until the depth is back -- dribbling each packet out the moment it lands is how
## one dropout becomes a stutter.
func reprime() -> void:
	# A queue that runs out before anything was ever handed to it is a player that started
	# first, not a gap anyone heard.
	if not _priming:
		underruns += 1
	_priming = true


## `count` frames for the sound card, now. Never fewer: a short read would be the card's
## underrun instead of ours, and ours is the one that can be made quiet.
func pull(count: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(count)
	if count > _pull_frames:
		_pull_frames = count
		_retarget(0.0)
	if _priming:
		if depth() < target:
			return out
		_priming = false
	# Bend the read rate toward the target depth.
	var error := float(depth() - target)
	_ratio = clampf(1.0 + error * GAIN, 1.0 - MAX_BEND, 1.0 + MAX_BEND)
	var size := _frames.size()
	for i in count:
		var at := int(_pos)
		if at + 1 >= size:
			# Ran dry. Silence from here, and wait until the depth is back before playing again,
			# rather than playing each packet the instant it lands -- that is the stutter.
			underruns += 1
			_priming = true
			_frames = PackedVector2Array()
			_pos = 0.0
			return out
		var frac := _pos - at
		out[i] = _frames[at].lerp(_frames[at + 1], frac)
		_pos += _ratio
	# Played frames dropped from the front now and then, not every pull: slicing a ring of a few
	# thousand frames on every 128-frame read is most of the cost of this whole class.
	if _pos > 4096.0:
		var cut := int(_pos)
		_frames = _frames.slice(cut)
		_base += cut
		_pos -= cut
	return out
