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


func _frames(n: int, from := 0) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(n)
	for i in n:
		out[i] = Vector2(from + i, from + i)
	return out


## Nothing is pushed to the generator until the cushion (60 ms) is in hand; then all of it goes at once.
func the_cushion_fills_before_the_first_push() -> void:
	var c := RackCushion.new()
	c.put(_frames(800))
	check("800 frames (17 ms) are not enough to start", c.pull(0, 16383).is_empty())
	var d := RackCushion.new()
	d.put(_frames(RackCushion.TARGET - 1))
	check("one frame short of the cushion pushes nothing", d.pull(0, 16383).is_empty())
	d.put(_frames(1, RackCushion.TARGET - 1))
	var first := d.pull(0, 16383)
	check("the cushion's worth goes in one push, in order", first.size() == RackCushion.TARGET and first[0].x == 0.0 \
			and first[first.size() - 1].x == RackCushion.TARGET - 1.0)
	var e := RackCushion.new()
	e.put(_frames(3000))
	check("a push is never more than the generator has room for", e.pull(0, 1000).size() == 1000)


## A generator that ran dry is not fed a trickle: it fills to the cushion again before it plays on.
func an_underrun_recovers() -> void:
	var c := RackCushion.new()
	c.put(_frames(RackCushion.TARGET))
	c.pull(0, 16383)
	check("playing", c.primed)
	c.put(_frames(800))
	check("the generator is empty: that is an underrun, counted", c.pull(0, 16383).is_empty() and c.underruns == 1)
	check("and it waits for the cushion", not c.primed)
	c.put(_frames(RackCushion.TARGET))
	check("which fed, it plays on", c.pull(0, 16383).size() > 0 and c.primed)


## The generator as the audio thread drains it, one 16.7 ms frame at a time, the engine making 800 frames a
## frame, a 100 ms stall of the main thread twice: nothing is dropped, the stream is whole and in order, the
## first stall may empty the generator once, and the cushion it then holds carries the second.
func nothing_is_dropped_under_a_stall() -> void:
	var c := RackCushion.new()
	var fill := 0
	var made := 0
	var heard := 0
	var last := -1.0
	var in_order := true
	var stall_over := 0
	var peak_fill := 0
	for frame in 600:
		# The audio thread drains what it can; the engine's reader files 800 frames.
		heard += mini(fill, 800)
		fill = maxi(fill - 800, 0)
		c.put(_frames(800, made))
		made += 800
		if (frame >= 250 and frame < 256) or (frame >= 400 and frame < 406):
			continue   # the main thread is stalled for 100 ms: no pull, the reader goes on
		var pushed := c.pull(fill, 16383 - fill)
		for f in pushed:
			if f.x < last:
				in_order = false
			last = f.x
		fill += pushed.size()
		peak_fill = maxi(peak_fill, fill)
		if frame == 256:
			stall_over = c.queued()
	check("no frame was dropped by a 100 ms stall", c.dropped == 0)
	check("and the stall's worth was in the queue after it (about 100 ms)", stall_over >= 4000)
	check("the first stall ran the generator dry once and the second, finding the deeper cushion, did not", c.underruns == 1)
	check("the cushion is deeper for it, and within the deepest", c.target > RackCushion.TARGET and c.target <= RackCushion.DEEPEST)
	check("the stream is in order", in_order)
	check("and what is held is at the target again afterwards (within slack)", fill + c.queued() <= c.target + RackCushion.SLACK + 800)
	check("the generator was never over-filled", peak_fill <= 16383)
	check("it kept feeding: most of the sound was heard", heard > made * 0.85)


## Playing fast is a smooth resample: no step, and the length is the ratio's.
func hurrying_is_smooth() -> void:
	var out := RackCushion.hurry(_frames(1000), 1.03)
	check("about 3 % fewer frames", absi(out.size() - 971) <= 1)
	var smooth := true
	for i in range(1, out.size()):
		if absf(out[i].x - out[i - 1].x - 1.03) > 0.001:
			smooth = false
	check("a ramp stays a ramp", smooth)
	check("a ratio of 1 changes nothing", RackCushion.hurry(_frames(50), 1.0) == _frames(50))


## The cushion is a jitter buffer: an underrun after the first seconds deepens it, one while the window is
## still opening does not, and a calm stretch gives the depth back.
func the_cushion_deepens_after_a_stall_and_gives_it_back() -> void:
	var c := RackCushion.new()
	c.put(_frames(RackCushion.TARGET))
	c.pull(0, 16383)
	c.put(_frames(4800))
	c.pull(0, 16383)
	check("a stall in the first seconds does not deepen it", c.target == RackCushion.TARGET and c.underruns == 1)
	for i in 200:
		c.put(_frames(800))
		c.pull(2000, 16383 - 2000)
	c.put(_frames(4800))
	c.pull(0, 16383)
	check("a stall of 100 ms later does, to a little over it", c.target >= 4800 and c.target < 6000)
	for i in 600:
		c.put(_frames(800))
		c.pull(c.target, 16383 - c.target)
	check("calm gives it back, 10 ms at a time", c.target < 4800)
	c.clear()
	check("and a new feed begins at the start depth", c.target == RackCushion.TARGET)
