extends RefCounted

## The rack's sound reaching the speakers whole (the bug: "modular synth audio out is super crushed"): the
## offline render of a shipped preset stays within the level it had on master, and the live stream the
## rack plays on its own (no track to carry it) is taken fast enough that nothing is dropped.

## Master-recorded levels of the `acid_line` preset, 4 s from a held C3 (RackEngine.render, 48 kHz).
const ACID_PEAK_MAX := 1.0
const MIN_RMS := 0.01
const MAX_CLIPPED := 0.001

var t: Node


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


func _levels(frames: PackedVector2Array) -> Dictionary:
	var peak := 0.0
	var sq := 0.0
	var clipped := 0
	for f in frames:
		for v in [f.x, f.y]:
			peak = maxf(peak, absf(v))
			sq += v * v
			if absf(v) >= 0.999:
				clipped += 1
	var n := maxf(frames.size() * 2.0, 1.0)
	return {"peak": peak, "rms": sqrt(sq / n), "clipped": clipped / n}


## A shipped preset, loaded as the game loads it, renders audibly and not crushed.
func a_preset_renders_clean() -> void:
	if not RackEngine.available():
		check("(no engine on this machine: skipped)", true)
		return
	var frames := RackEngine.render(RackPatch.preset(&"acid_line"), PackedStringArray(["note_on 48 100", "run 4"]))
	var l := _levels(frames)
	print("  acid_line: ", frames.size(), " frames, peak ", l["peak"], " rms ", l["rms"], " clipped ", l["clipped"])
	check("a preset renders its four seconds", frames.size() >= RackEngine.RATE * 4 - 480)
	check("it is audible", l["rms"] > MIN_RMS)
	check("and does not clip", l["peak"] <= ACID_PEAK_MAX and l["clipped"] <= MAX_CLIPPED)


## The rack that plays itself takes the engine's whole stream: in 1.5 s a reader on a thread has about
## 72000 frames, where a read once a frame (the old way) had 22000.
func the_direct_feed_takes_the_whole_stream() -> void:
	if not RackEngine.available():
		check("(no engine on this machine: skipped)", true)
		return
	var voice := RackVoice.new()
	t.add_child(voice)
	voice.patch = RackPatch.preset(&"acid_line")
	check("the engine starts", voice.start())
	voice.note_on(48)
	voice.source = voice.source if voice.source != null else RackEngine.Source.new(voice.engine)
	voice._start_reader()
	var got := PackedVector2Array()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1500:
		got.append_array(voice.take_direct(1 << 20))
		OS.delay_msec(16)
	var want := RackEngine.RATE * 1.5
	print("  direct feed took ", got.size(), " of ", want, " frames")
	check("at least 85% of what 1.5 s of sound is is taken (a frame-rate read took a third)", got.size() >= want * 0.85)
	check("and never more than the clock gives", got.size() <= want * 1.1)
	voice.shutdown()
	voice.queue_free()
