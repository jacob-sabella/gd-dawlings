class_name TourMeasure
extends RefCounted

## The statistics a brief, or the crowd, can judge against, all of them read off real numbers
## the built-in engine already produces -- nothing here is new instrumentation invented for Tour.
##
## Loudness reads the same `AudioServer` bus-peak calls `GodotBackend._drive_levels` already
## polls every physics frame, on the real master bus. Balance drops Godot's own
## `AudioEffectSpectrumAnalyzer` onto that bus for the brief's duration only, and removes it
## again. Timing reads notes already placed on the timeline against `MixState.beat_at`, the
## same tempo-map lookup the transport's own bar/beat counter uses.
##
## Loudness and Balance are brief-long averages, read once at the end -- never live, never on
## the card; that is what `Ear` below is for, and why the master bus's own two bars sat out of
## every brief until now (docs/loop_backlog.md's "Tour" section: the limiter at -0.3 dB sits
## above the old loudness ceiling, and the clean band's spread was never measured). `Ear` is
## that calibration done: a live, windowed crowd reading, measured by tools/tour_ear.sh and
## judged by `TourEar` (core/tour/tour_ear.gd) -- see that file's `THRESHOLDS` for the numbers.
##
## One class per statistic, each `start()`-ed once, `sample(delta)`-ed every physics tick while
## the brief runs, and `result()`-ed once at the end (or, for `Ear`, live, any time); `Tour` runs
## whichever subset a brief names (`TourBrief.measures`) plus `Ear` whenever `TourBrief.crowd` is
## true. Every sampler here degrades to an inert result off `GodotBackend` (there is nothing to
## read), which is also why Tour gates a run on `DAW.backend is GodotBackend` in the first place.


class Loudness extends RefCounted:
	var _sum_sq := 0.0
	var _ticks := 0
	var _peak_db := -100.0

	func start() -> void:
		_sum_sq = 0.0
		_ticks = 0
		_peak_db = -100.0

	func sample(_delta: float) -> void:
		if not (DAW.backend is GodotBackend):
			return
		var bus := AudioServer.get_bus_index(GodotBackend.MASTER_BUS)
		if bus < 0:
			return
		var db := maxf(AudioServer.get_bus_peak_volume_left_db(bus, 0),
				AudioServer.get_bus_peak_volume_right_db(bus, 0))
		_peak_db = maxf(_peak_db, db)
		var lin := db_to_linear(db)
		_sum_sq += lin * lin
		_ticks += 1

	## {"avg_db": the brief's running power-average, "peak_db": its loudest instant}.
	func result() -> Dictionary:
		if _ticks == 0:
			return {"avg_db": -100.0, "peak_db": _peak_db}
		return {"avg_db": linear_to_db(sqrt(_sum_sq / float(_ticks))), "peak_db": _peak_db}


class Balance extends RefCounted:
	const LOW := Vector2(20.0, 250.0)
	const MID := Vector2(250.0, 4000.0)
	const HIGH := Vector2(4000.0, 16000.0)

	var _fx: AudioEffectSpectrumAnalyzer = null
	var _bus_index := -1
	var _sum_low := 0.0
	var _sum_mid := 0.0
	var _sum_high := 0.0
	var _ticks := 0

	## Adds its own `AudioEffectSpectrumAnalyzer` to the master bus. Invisible to the player and
	## to the rack: it never touches `GodotBackend`'s own effect chain.
	func start() -> void:
		_sum_low = 0.0
		_sum_mid = 0.0
		_sum_high = 0.0
		_ticks = 0
		_fx = null
		_bus_index = -1
		if not (DAW.backend is GodotBackend):
			return
		_bus_index = AudioServer.get_bus_index(GodotBackend.MASTER_BUS)
		if _bus_index < 0:
			return
		_fx = AudioEffectSpectrumAnalyzer.new()
		AudioServer.add_bus_effect(_bus_index, _fx)

	func sample(_delta: float) -> void:
		if _fx == null or _bus_index < 0:
			return
		var slot := _slot_of(_fx, _bus_index)
		if slot < 0:
			return
		var inst := AudioServer.get_bus_effect_instance(_bus_index, slot) as AudioEffectSpectrumAnalyzerInstance
		if inst == null:
			return
		_sum_low += linear_to_db(maxf(inst.get_magnitude_for_frequency_range(LOW.x, LOW.y).length(), 0.00001))
		_sum_mid += linear_to_db(maxf(inst.get_magnitude_for_frequency_range(MID.x, MID.y).length(), 0.00001))
		_sum_high += linear_to_db(maxf(inst.get_magnitude_for_frequency_range(HIGH.x, HIGH.y).length(), 0.00001))
		_ticks += 1

	## {"low_db", "mid_db", "high_db"}: each band's average over the brief.
	func result() -> Dictionary:
		if _ticks == 0:
			return {"low_db": -100.0, "mid_db": -100.0, "high_db": -100.0}
		return {"low_db": _sum_low / float(_ticks), "mid_db": _sum_mid / float(_ticks),
				"high_db": _sum_high / float(_ticks)}

	## Removes the analyzer again, so a brief leaves the bus exactly as it found it.
	func stop() -> void:
		if _fx != null and _bus_index >= 0:
			var slot := _slot_of(_fx, _bus_index)
			if slot >= 0:
				AudioServer.remove_bus_effect(_bus_index, slot)
		_fx = null
		_bus_index = -1

	static func _slot_of(fx: AudioEffect, bus_index: int) -> int:
		for i in AudioServer.get_bus_effect_count(bus_index):
			if AudioServer.get_bus_effect(bus_index, i) == fx:
				return i
		return -1


## The crowd's live hearing: the same peak and spectrum reads as Loudness/Balance, but kept as a
## rolling `WINDOW_SECONDS` average rather than a brief-long one, so the card recovers mid-brief
## as the band mixes, and read any time rather than once at the end.
##
## Godot reads a bus's peak after its effects and before its volume (MixRender's header says so,
## and compensates by the fader the same way); without adding the master fader back in here, the
## one obvious fix for "too quiet" -- pushing the master -- would never be heard, since the peak
## read never moves. `sample` adds `DAW.taper_to_db(DAW.state.master.volume)` to the raw peak for
## exactly that reason.
class Ear extends RefCounted:
	const WINDOW_SECONDS := 2.0

	var _bus_index := -1
	var _fx: AudioEffectSpectrumAnalyzer = null
	## Ring of [lin_sq, low_db, mid_db, high_db, delta], oldest first; trimmed in `sample` to
	## hold at most `WINDOW_SECONDS` worth of ticks.
	var _ticks: Array = []
	## Set once the ring has held a full window, and never cleared except by `start()`/`stop()`:
	## `ready()` asks this rather than the ring's current span, which can dip a tick below the
	## window right after a trim.
	var _filled := false

	func start() -> void:
		_ticks = []
		_filled = false
		_fx = null
		_bus_index = -1
		if not (DAW.backend is GodotBackend):
			return
		_bus_index = AudioServer.get_bus_index(GodotBackend.MASTER_BUS)
		if _bus_index < 0:
			return
		_fx = AudioEffectSpectrumAnalyzer.new()
		AudioServer.add_bus_effect(_bus_index, _fx)

	func sample(delta: float) -> void:
		if _fx == null or _bus_index < 0:
			return
		var slot := Balance._slot_of(_fx, _bus_index)
		if slot < 0:
			return
		var inst := AudioServer.get_bus_effect_instance(_bus_index, slot) as AudioEffectSpectrumAnalyzerInstance
		if inst == null:
			return
		var peak_db := maxf(AudioServer.get_bus_peak_volume_left_db(_bus_index, 0),
				AudioServer.get_bus_peak_volume_right_db(_bus_index, 0))
		var fader_db := DAW.taper_to_db(DAW.state.master.volume) if DAW.state != null else 0.0
		var lin := db_to_linear(peak_db + fader_db)
		var low := linear_to_db(maxf(inst.get_magnitude_for_frequency_range(Balance.LOW.x, Balance.LOW.y).length(), 0.00001))
		var mid := linear_to_db(maxf(inst.get_magnitude_for_frequency_range(Balance.MID.x, Balance.MID.y).length(), 0.00001))
		var high := linear_to_db(maxf(inst.get_magnitude_for_frequency_range(Balance.HIGH.x, Balance.HIGH.y).length(), 0.00001))
		_ticks.append([lin * lin, low, mid, high, maxf(delta, 0.0001)])
		var span := 0.0
		for t in _ticks:
			span += t[4]
		if span >= WINDOW_SECONDS:
			_filled = true
		while span > WINDOW_SECONDS and _ticks.size() > 1:
			span -= _ticks[0][4]
			_ticks.pop_front()

	## Whether a full window has been heard yet: false while filling, and false off `GodotBackend`
	## (there is nothing to read, so it never fills).
	func ready() -> bool:
		return _filled

	## {"heard": bool, "avg_db", "low_db", "mid_db", "high_db", "spread_db", "tilt_db"}; every
	## value is -100.0 while `heard` is false (no window yet, or nothing to measure). `avg_db` is
	## the fader-compensated power-average peak; `spread_db` is the loudest band minus the
	## quietest; `tilt_db` is `low_db - mid_db`, signed, for which way an unhappy balance leans.
	func result() -> Dictionary:
		if not ready() or _ticks.is_empty():
			return {"heard": false, "avg_db": -100.0, "low_db": -100.0, "mid_db": -100.0,
					"high_db": -100.0, "spread_db": -100.0, "tilt_db": -100.0}
		var sum_sq := 0.0
		var sum_low := 0.0
		var sum_mid := 0.0
		var sum_high := 0.0
		var total := 0.0
		for t in _ticks:
			sum_sq += t[0] * t[4]
			sum_low += t[1] * t[4]
			sum_mid += t[2] * t[4]
			sum_high += t[3] * t[4]
			total += t[4]
		var low: float = sum_low / total
		var mid: float = sum_mid / total
		var high: float = sum_high / total
		var hi_band := maxf(low, maxf(mid, high))
		var lo_band := minf(low, minf(mid, high))
		return {"heard": true, "avg_db": linear_to_db(sqrt(sum_sq / total)), "low_db": low,
				"mid_db": mid, "high_db": high, "spread_db": hi_band - lo_band, "tilt_db": low - mid}

	## Removes the analyzer again. Idempotent, so `Tour` can call it on a brief's own `_ear` and
	## again at `_end_run` without caring which already ran.
	func stop() -> void:
		if _fx != null and _bus_index >= 0:
			var slot := Balance._slot_of(_fx, _bus_index)
			if slot >= 0:
				AudioServer.remove_bus_effect(_bus_index, slot)
		_fx = null
		_bus_index = -1
		_ticks = []
		_filled = false


class Timing extends RefCounted:
	var _track_index := 0
	var _from_seconds := 0.0
	var _grid := 0.125

	## `track_index`: which track's placed notes this brief judges. `from_seconds`: only notes
	## starting at or after this song position count, so an earlier brief's playing is not
	## re-judged by this one. `grid_beats`: the grid a note is judged against -- the default,
	## an eighth, caps the worst possible reading at 0.0625 beats, which is why the pocket
	## brief's old thresholds were unreachable (docs/loop_backlog.md's "Tour" section); Tour's
	## dragging-keys flaw asks for a quarter beat instead, so a real drag can fail it.
	func start(track_index: int, from_seconds: float, grid_beats := 0.125) -> void:
		_track_index = track_index
		_from_seconds = from_seconds
		_grid = grid_beats

	## Timing is read from placed notes at `result()` time, not sampled tick by tick.
	func sample(_delta: float) -> void:
		pass

	## {"avg_beats_off", "worst_beats_off", "notes"}: how far each note's on-time lands from the
	## nearest grid point, against the project's real tempo map.
	func result() -> Dictionary:
		var out := {"avg_beats_off": 1.0, "worst_beats_off": 1.0, "notes": 0}
		if DAW.state == null or not DAW.state.tracks.has(_track_index):
			return out
		var track: MixState.TrackState = DAW.state.track(_track_index, false)
		if track == null:
			return out
		var total := 0.0
		var worst := 0.0
		var count := 0
		for it: MixState.ItemState in track.items:
			var notes := it.notes
			var i := 0
			while i + MidiTake.NOTE_WIDTH - 1 < notes.size():
				var on_seconds := it.start + notes[i]
				i += MidiTake.NOTE_WIDTH
				if on_seconds < _from_seconds:
					continue
				var beat := DAW.state.beat_at(on_seconds)
				var q := roundf(beat / _grid) * _grid
				var off := absf(beat - q)
				total += off
				worst = maxf(worst, off)
				count += 1
		if count == 0:
			return out
		return {"avg_beats_off": total / float(count), "worst_beats_off": worst, "notes": count}


## Whether notes already placed on a track play a TourPart (core/tour/tour_part.gd): the hand
## percussion's channel (9) and pitch tell one part's notes from another's, since who played
## them is not on the lane (see tour_part.gd's class note). Like Timing, read from placed notes
## at `result()` time, not sampled tick by tick; unlike Timing, every note matching the part's
## channel/pitch is sorted into "on" or "off" the grid rather than averaged, since a part fails
## by being mostly off grid (flailing), not by its average miss.
class Rhythm extends RefCounted:
	var _track_index := 0
	var _from_seconds := 0.0
	var _part: TourPart = null

	## `track_index`: the lane a part's notes land on (Tour.STAGE_TRACK -- every part shares the
	## one lane, since both recorders land on the first armed track regardless of who is
	## playing). `from_seconds`: notes before this do not count; 0.0 in practice, since the
	## Stage lane starts empty every brief. `part`: whose grid judges them.
	func start(track_index: int, from_seconds: float, part: TourPart) -> void:
		_track_index = track_index
		_from_seconds = from_seconds
		_part = part

	func sample(_delta: float) -> void:
		pass

	## {"on": notes landing within the part's window, "off": the rest that still matched its
	## instrument, "notes": on + off}.
	func result() -> Dictionary:
		var out := {"on": 0, "off": 0, "notes": 0}
		if _part == null or DAW.state == null or not DAW.state.tracks.has(_track_index):
			return out
		var track: MixState.TrackState = DAW.state.track(_track_index, false)
		if track == null:
			return out
		var on := 0
		var off := 0
		var bpb := float(maxi(DAW.state.beats_per_bar, 1))
		for it: MixState.ItemState in track.items:
			var notes := it.notes
			var i := 0
			while i + MidiTake.NOTE_WIDTH - 1 < notes.size():
				var on_seconds := it.start + notes[i]
				var pitch := int(notes[i + 2])
				var channel := int(notes[i + 4])
				i += MidiTake.NOTE_WIDTH
				if on_seconds < _from_seconds or not _matches(channel, pitch):
					continue
				var pos := fposmod(DAW.state.beat_at(on_seconds), bpb)
				if _on_grid(pos, bpb):
					on += 1
				else:
					off += 1
		return {"on": on, "off": off, "notes": on + off}

	## -1 on a part's own `channel` means any channel but 9, the hand percussion's -- a keytar's
	## stabs, wherever they come from, never land on that channel. Everything else (shaker,
	## tambourine) asks for an exact channel and, when given, an exact pitch.
	func _matches(channel: int, pitch: int) -> bool:
		var chan_ok := channel == _part.channel if _part.channel >= 0 else channel != 9
		if not chan_ok:
			return false
		return _part.pitches.is_empty() or pitch in _part.pitches

	func _on_grid(pos: float, bpb: float) -> bool:
		if not _part.beats.is_empty():
			var best := INF
			for target in _part.beats:
				best = minf(best, _circular(pos, target, bpb))
			return best <= _part.window
		if _part.grid > 0.0:
			var q := fposmod(roundf(pos / _part.grid) * _part.grid, bpb)
			return _circular(pos, q, bpb) <= _part.window
		return false

	## The shorter way round a bar between two beat positions: a target at 3.95 is close to a
	## note at 0.05 (the NEXT bar's "on"), not far from it.
	static func _circular(pos: float, target: float, bpb: float) -> float:
		var d := absf(pos - target)
		return minf(d, bpb - d)
