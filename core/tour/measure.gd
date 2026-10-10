class_name TourMeasure
extends RefCounted

## The three statistics a brief can judge against, all of them read off real numbers the
## built-in engine already produces -- nothing here is new instrumentation invented for Tour.
##
## Loudness reads the same `AudioServer` bus-peak calls `GodotBackend._drive_levels` already
## polls every physics frame, on the real master bus. Balance drops Godot's own
## `AudioEffectSpectrumAnalyzer` onto that bus for the brief's duration only, and removes it
## again. Timing reads notes already placed on the timeline against `MixState.beat_at`, the
## same tempo-map lookup the transport's own bar/beat counter uses.
##
## One class per statistic, each `start()`-ed once, `sample(delta)`-ed every physics tick while
## the brief runs, and `result()`-ed once at the end; `Tour` runs whichever subset a brief names
## (`TourBrief.measures`). Every sampler here degrades to an inert result off `GodotBackend`
## (there is nothing to read), which is also why Tour gates a run on `DAW.backend is GodotBackend`
## in the first place.


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
