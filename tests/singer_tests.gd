extends RefCounted

## The vocal booth's singer (docs/singer.md), called from tests/run_tests.gd's `_test_*` wrappers: the row and its
## asks (SingerRow), the vocal part from a MIDI track (VocalPart), the lyric board's syllable (VocalPart.sung_span),
## what guests are sent (SingerLive), the engine's telemetry (VoiceTele), the bestiary (Bestiary), CHIMERA's sound
## rendered through the rack and bit for bit against CHIMERA's own CLI (tools/voice_parity.sh), and the voice live.

var t: Node


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


## The row: every field kept in range, the asks answered or refused, the steps of a pattern round trip.
func the_row_answers_its_asks() -> void:
	var row := SingerRow.sanitize({"mode": 9, "body": 3.0, "track": -2, "seq": "yes", "beat": "B . nope . | t", "x": 1})
	check("a row out of range is put in range", row["mode"] == SingerRow.MODES.size() - 1 and row["body"] == 1.0
			and row["track"] == 0 and row["seq"] == false and not row.has("x"))
	check("a pattern keeps only the notation", row["beat"] == "B . . | t")
	check("a preset's steps are its own sixteen", SingerRow.steps_of("Four on the floor").size() == SingerRow.STEPS)
	var steps := SingerRow.steps_of("B . t . | Pf . t .")
	check("steps round trip through a pattern", SingerRow.steps_of(SingerRow.beat_of(steps)) == steps)
	var r := SingerRow.fresh()
	check("set changes the row", SingerRow.answer(r, "set", ["vibrato", 0.8]) == "" and is_equal_approx(float(r["vibrato"]), 0.8))
	check("an unknown key is refused", SingerRow.answer(r, "set", ["volume", 1.0]) != "")
	check("a stone of the perch is a moment", SingerRow.is_moment("strike") and SingerRow.answer(r, "strike", [3]) == "")
	check("a stone past the perch is refused", SingerRow.answer(r, "strike", [Bestiary.STONES]) != ""
			and SingerRow.answer(r, "strike", [-1]) != "")
	check("a key outside the voice is refused", SingerRow.answer(r, "play", [5, true]) != "")
	var before := r.duplicate()
	SingerRow.answer(r, "say", ["hello there", false])
	check("a moment leaves the row as it was", r == before)
	var tr := SingerRow.fresh()
	check("PART steps round the song's tracks, then none", SingerRow.answer(tr, "part", [], [1, 2]) == "" and tr["part"] == 1
			and SingerRow.answer(tr, "part", [], [1, 2]) == "" and tr["part"] == 2
			and SingerRow.answer(tr, "part", [], [1, 2]) == "" and tr["part"] == 0)
	check("PART named is that track, and 0 is none", SingerRow.answer(tr, "part", [2], [1, 2]) == "" and tr["part"] == 2
			and SingerRow.answer(tr, "part", [0], [1, 2]) == "" and tr["part"] == 0
			and SingerRow.answer(tr, "part", [7], [1, 2]) == "" and tr["part"] == 1)


## The vocal part: a chord sings its top note, an overlap is cut, a gap is a rest, and the words the module takes.
func the_vocal_part_is_one_voice() -> void:
	var notes := [[2.0, 64, 1.0], [0.0, 60, 1.5], [0.0, 55, 1.5], [1.0, 62, 1.0], [5.0, 67, 2.0]]
	var mono := VocalPart.monophonic(notes)
	check("a chord sings its top note, in time order", mono.size() == 4 and mono[0][1] == 60 and mono[1][1] == 62)
	check("an overlapping note cuts the one before", is_equal_approx(float(mono[0][2]), 1.0))
	var line := VocalPart.song_line(notes, 100.0, 0)
	check("the song line is FIRST BPM BEAT then pairs, a rest as 0", line.begins_with("0 100.0000 0.000000 60 1.000000 62 1.000000 64 1.000000 0 2.000000 67 2.000000"))
	check("no notes, no line", VocalPart.song_line([], 100.0) == "" and VocalPart.song_line(notes, 0.0) == "")
	check("the syllable at a beat counts the notes begun", VocalPart.syllable_at(notes, 2.5) == 2 and VocalPart.syllable_at(notes, -1.0) == -1)
	var state := MixState.new()
	state.tempo = 120.0
	var tr := MixState.TrackState.new()
	var it := MixState.ItemState.new()
	it.start = 1.0
	it.length = 2.0
	# two notes: C4 at the item's start for half a second, E4 a second in for a second (MidiTake's five)
	it.notes = PackedFloat32Array([0.0, 0.5, 60, 100, 0, 1.0, 2.0, 64, 100, 0])
	tr.items.append(it)
	state.tracks[1] = tr
	var got := VocalPart.notes_of(state, 1)
	check("a MIDI track's notes come out in beats", got.size() == 2 and is_equal_approx(float(got[0][0]), 2.0)
			and is_equal_approx(float(got[0][2]), 1.0) and int(got[1][1]) == 64 and is_equal_approx(float(got[1][0]), 4.0))
	check("a track that is not there has no notes", VocalPart.notes_of(state, 7).is_empty())


## The lyric board lights the syllable sung: found along the lines in order, a held one is the one before, past
## the end it wraps as the voice does.
func the_board_finds_the_syllable_sung() -> void:
	var lrc := "[00:01.00]Twinkle twinkle\n[00:03.00]  little star"
	var syl := PackedStringArray(["Twin", "kle", "twin", "kle", "lit", "tle", "~", "star"])
	check("the first syllable is the first line's first letters", VocalPart.sung_span(lrc, syl, 0) == PackedInt32Array([0, 0, 4]))
	check("the second is the rest of the word", VocalPart.sung_span(lrc, syl, 1) == PackedInt32Array([0, 4, 3]))
	check("the same word again is found after the first", VocalPart.sung_span(lrc, syl, 2) == PackedInt32Array([0, 8, 4]))
	var lyr := Lyrics.parse(lrc)
	var second: int = lyr.sequence()[1]
	var lit := VocalPart.sung_span(lrc, syl, 4)
	check("a syllable on the next line is on that line, past its leading spaces", lit[0] == second
			and String(lyr.lines[second]["text"]).substr(lit[1], lit[2]) == "lit")
	check("a held syllable is the one before it", VocalPart.sung_span(lrc, syl, 6) == VocalPart.sung_span(lrc, syl, 5))
	check("past the end it wraps", VocalPart.sung_span(lrc, syl, 8) == VocalPart.sung_span(lrc, syl, 0))
	check("none sung, none lit", VocalPart.sung_span(lrc, syl, -1).is_empty() and VocalPart.sung_span(lrc, PackedStringArray(), 0).is_empty())
	check("the words sung are the lines' in order", Singer.words_of(lrc) == "Twinkle twinkle little star")
	# The prompter marks the syllable breaks inside words and lights the one sung where it now falls.
	var marks := VocalPart.spans(lrc, syl)
	var first: int = lyr.sequence()[0]
	var shown := VocalPart.marked(String(lyr.lines[first]["text"]), first, marks, VocalPart.sung_span(lrc, syl, 3))
	check("the line shows its syllables: %s" % shown[0], shown[0] == "Twin·kle twin·kle")
	check("and the one sung lit after the marks before it", shown[1] == Vector2i(14, 3)
			and String(shown[0]).substr(14, 3) == "kle")
	check("the fit is said", SingerHost._fit(24, 31) == "24 notes  ·  31 syllables: the last 7 not sung"
			and SingerHost._fit(8, 8).ends_with("every word sung") and SingerHost._fit(10, 8).ends_with("start again at note 9")
			and SingerHost._fit(0, 8) == "the PART has no notes yet")
	# The board shows it: its line now, the syllable laid over it.
	var board := LyricBoard.new()
	t.add_child(board)
	board.heard_source = func() -> Dictionary: return {"seconds": 1.5, "playing": true, "valid": true}
	board._predicted = lrc
	board._predicted_at = Time.get_ticks_msec()
	board.sung_source = func() -> PackedInt32Array: return lit
	var d := board.display(board.heard())
	check("the board's line now is the singer's, whatever the clock says", int(d["line"]) == second and d["sung"] == Vector2i(lit[1], lit[2]))
	board._show(d)
	var board_line: String = board.now_line.text
	check("and the line is lit to the end of that syllable, laid on the line's own letters",
			board.sung_line.visible and board.sung_line.text.ends_with("lit") and board_line.begins_with(board.sung_line.text)
			and is_equal_approx(board.sung_line.position.x, board.now_line.position.x))
	board.sung_source = func() -> PackedInt32Array: return PackedInt32Array()
	board._show(board.display(board.heard()))
	check("nothing sung, nothing lit", not board.sung_line.visible)
	board.queue_free()


## What a guest is sent: the voice's body, the head's lines in 16 bits, the syllable, the step and the board's span.
func a_guest_is_sent_the_singer() -> void:
	var frame := {"glottis": Vector2(0.5, -0.25), "lines": {}}
	for name in VoiceTele.LINES:
		frame["lines"][name] = PackedVector2Array([Vector2(1.23, 4.56), Vector2(-7.89, 0.01)])
	# a body as the engine says it: 17 articulators, a 2-section throat and a 1-section nose
	var tele := PackedFloat32Array()
	tele.resize(VoiceTele.HEADER + VoiceTele.ARTIC.size() + 3 * 3 + VoiceTele.FOLDS)
	tele[6] = 0.1
	tele[11] = VoiceTele.ARTIC.size()
	tele[12] = 2
	tele[13] = 1
	var span := PackedInt32Array([2, 3, 4])
	var args := SingerLive.pack(true, tele, frame, "twin", 5, span)
	var got := SingerLive.unpack(args, {})
	check("the body arrives", got["tele"] == tele and got["sung"] == "twin" and got["step"] == 5 and got["span"] == span)
	var f: Dictionary = got["frame"]
	check("the head's lines arrive to the hundredth of a centimetre", f["glottis"].is_equal_approx(Vector2(0.5, -0.25))
			and (f["lines"]["tongue"] as PackedVector2Array)[0].is_equal_approx(Vector2(1.23, 4.56)))
	check("a stopped singer is said as one word", SingerLive.pack(false, tele, frame, "", 0) == [false]
			and SingerLive.unpack([false], got).is_empty())
	check("anything else keeps what was there", SingerLive.unpack([true, "x"], got) == got
			and SingerLive.unpack([true, tele, PackedByteArray(), "", 0, PackedInt32Array([1])], got) == got)
	check("an empty frame keeps the last", SingerLive.unpack(SingerLive.pack(true, tele, {}, "", 0), got)["frame"] == f)
	check("fresh only while new", not SingerLive.fresh(got).is_empty() and SingerLive.fresh({"at": -100000}).is_empty())
	check("the entry is volatile", OfflineBackend.new().is_volatile(SingerLive.ADDRESS))
	var body := VoiceTele.read(tele)
	check("the telemetry reads", not body.is_empty() and is_equal_approx(float(body.get("rms", 0.0)), 0.1)
			and (body.get("areas", PackedFloat32Array()) as PackedFloat32Array).size() == 3)
	check("and a short one is nothing", VoiceTele.read(PackedFloat32Array()).is_empty() and VoiceTele.read(tele.slice(0, 20)).is_empty())


## A creature in every venue, and its stones in the song's key wherever the song is.
func every_venue_has_a_creature_in_key() -> void:
	var all_pitched := true
	for id: StringName in Venue.IDS:
		var c := Bestiary.of(id)
		all_pitched = all_pitched and Bestiary.KINDS.has(c["kind"])
	check("every venue has a creature whose call takes a note (%d venues)" % Venue.IDS.size(), all_pitched)
	check("the elephant is in a venue", Bestiary.BY_VENUE.values().has(&"elephant"))
	# the elephant's rumble pitch is 8..45 Hz in CHIMERA: every stone in every key inside it, or stones sound alike
	var in_reach := true
	for root in 12:
		var hk := Harmony.parse("[%s major]" % ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"][root])
		for n in Bestiary.STONES:
			var hz := 440.0 * pow(2.0, (Bestiary.note(hk, Bestiary.KINDS[&"elephant"], n) - 69) / 12.0)
			in_reach = in_reach and hz >= 8.0 and hz <= 45.0
	check("the elephant's stones are all inside its rumble's reach", in_reach)
	check("a venue not listed still has one", Bestiary.KINDS.has(Bestiary.of(&"somewhere_new")["kind"]))
	for key in ["[D minor]", "[Bb major]", "[F# minor]"]:
		var h := Harmony.parse(key)
		for kind: StringName in Bestiary.KINDS:
			var spec: Dictionary = Bestiary.KINDS[kind]
			var ok := true
			var last := -1
			for n in Bestiary.STONES:
				var m := Bestiary.note(h, spec, n)
				ok = ok and h.in_key(m) and m > last and absi(m - int(spec["low"])) <= 20
				last = m
			check("the %s's stones climb %s's scale" % [kind, key], ok)
	# every kind drawn as itself: an elephant once fell through to the songbird's outline
	var drawn := {}
	for venue: StringName in Bestiary.BY_VENUE:
		var kind: StringName = Bestiary.of(venue)["kind"]
		if drawn.has(kind):
			continue
		var p := CreaturePerch.new(Bestiary.of(venue))
		t.add_child(p)
		var m: ImmediateMesh = p._mesh
		drawn[kind] = (m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() if m.get_surface_count() > 0 else 0
		p.free()
	var counts := {}
	for kind: StringName in drawn:
		counts[drawn[kind]] = true
	check("every creature is drawn as itself (%s)" % JSON.stringify(drawn),
			drawn.size() == Bestiary.KINDS.size() and counts.size() == drawn.size() and not counts.has(0))
	var perch := CreaturePerch.new(Bestiary.of(&"garden"))
	t.add_child(perch)
	check("the perch has its stones, lettered", perch.stones.size() == Bestiary.STONES and perch.stones[0].legend_text != "")
	var hit := []
	perch.struck.connect(func(n: int) -> void: hit.append(n))
	perch.stones[2].down.emit(true)
	check("a stone struck says which", hit == [2])
	perch.queue_free()


## The rack's VOICE renders CHIMERA's singing: audible, not clipped, and silent before the song starts.
## The beat's sequencer plays with the song: its first kick on the first bar after PLAY, every kick on its beat
## a minute on, and after a seek to the middle of a bar it waits for the next bar and lands on it again (it
## kept its old phase and played 145 ms off the beat for good).
func the_beat_is_locked_to_the_song() -> void:
	if not RackEngine.available():
		check("(no engine on this machine: skipped)", true)
		return
	var s := Singer.new()
	var set_up := PackedStringArray(["knob v.mode %.4f" % Singer.position("mode", SingerRow.Mode.BEAT),
			"knob v.seq %.4f" % Singer.position("seq", 1.0), "bpm 120", "text v.beat Four on the floor", "play 0"])
	var long := RackEngine.render(s.patch, set_up + PackedStringArray(["run 62"]))
	var jumped := RackEngine.render(s.patch, set_up + PackedStringArray(["run 10", "sync 37.3", "run 4"]))
	s.free()
	# where each kick falls in beats (120 bpm: two a second)
	var kicks := _kicks(long)
	var first: float = kicks[0] * 2.0 if not kicks.is_empty() else -1.0
	check("the first kick falls on the first bar after PLAY", absf(first - 4.0) < 0.03)
	# from half a minute to a minute on, each beat: the hit around it (a quarter beat either side, so the
	# pattern's off-beat hats are not taken for it) starts within 15 ms of it
	var peak := 0.0
	for f in long:
		peak = maxf(peak, absf(f.x))
	var on_beat := 0
	for b in range(60, 120):
		var at := _onset(long, (b - 0.25) * 0.5, (b + 0.25) * 0.5, peak)
		if at >= 0.0 and absf(at - b * 0.5) < 0.015:
			on_beat += 1
	check("half a minute to a minute on, the kicks are still on their beats (within 15 ms)", on_beat >= 57)
	var after: Array = _kicks(jumped).filter(func(k: float) -> bool: return k > 10.0)
	var at: float = 37.3 + (after[0] - 10.0) * 2.0 if not after.is_empty() else -1.0
	check("after a seek to mid-bar, it waits and starts again on the next bar", absf(at - 40.0) < 0.03)


## When the first sound louder than 0.4 of `peak` between `from` and `to` seconds starts (-1 for none).
static func _onset(frames: PackedVector2Array, from: float, to: float, peak: float) -> float:
	for i in range(maxi(0, int(from * RackEngine.RATE)), mini(frames.size(), int(to * RackEngine.RATE))):
		if absf(frames[i].x) > peak * 0.4:
			return float(i) / RackEngine.RATE
	return -1.0


## The seconds at which the loudest hits start (a kick's onset), at most one per 0.3 s.
static func _kicks(frames: PackedVector2Array) -> Array:
	var peak := 0.0
	for f in frames:
		peak = maxf(peak, absf(f.x))
	var out := []
	var i := 0
	while i < frames.size():
		if absf(frames[i].x) > peak * 0.4:
			out.append(float(i) / RackEngine.RATE)
			i += int(0.3 * RackEngine.RATE)
		else:
			i += 1
	return out


func the_voice_renders_through_the_rack() -> void:
	if not RackEngine.available():
		check("(no engine on this machine: skipped)", true)
		return
	var s := Singer.new()
	var frames := RackEngine.render(s.patch, PackedStringArray(["text v.lyrics hello world", "bpm 120", "play 0",
			"text v.song 0 120 0.5 60 1 64 1 67 2", "run 3"]))
	s.free()
	var peak := 0.0
	var sq := 0.0
	for f in frames:
		peak = maxf(peak, absf(f.x))
		sq += f.x * f.x
	var rms := sqrt(sq / maxf(frames.size(), 1))
	print("  voice: ", frames.size(), " frames, peak ", peak, " rms ", rms)
	check("the voice renders its three seconds", frames.size() >= RackEngine.RATE * 3 - 480)
	check("it sings", rms > 0.01 and peak < 1.0)


## Bit for bit CHIMERA's own: tools/voice_parity.sh renders one melody with CHIMERA's CLI and through the rack.
func the_voice_is_chimeras_sample_for_sample() -> void:
	var out: Array = []
	var code := OS.execute("bash", ["-c", "cd '%s' && tools/voice_parity.sh" % ProjectSettings.globalize_path("res://")], out, true)
	var said := "\n".join(out)
	print("  ", said.strip_edges().get_slice("\n", said.strip_edges().count("\n")))
	if code != 0 and "cargo" in said and "not found" in said:
		check("(no Rust toolchain on this machine: skipped)", true)
		return
	check("the rack's voice equals CHIMERA's CLI in every sample", code == 0 and " 0 differ" in said)


## The voice live: started, told the lyrics and a line, it reports its body and the syllables it sings.
func the_voice_sings_live() -> void:
	if not RackEngine.available():
		check("(no engine on this machine: skipped)", true)
		return
	var s := Singer.new()
	# it is told where the song is here ("play 0"): a song left playing by another check must not move it
	s.follow_daw = false
	t.add_child(s)
	check("the singer starts", s.start())
	s.set_lyrics("[00:00.00]la di da")
	s.engine.say("bpm 120")
	s.engine.say("play 0")
	s.sing_part([[0.0, 60, 1.0], [1.0, 62, 1.0], [2.0, 64, 1.0]], 120.0)
	var seen_sung := false
	var loud := 0.0
	var deadline := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < deadline:
		await t.get_tree().process_frame
		loud = maxf(loud, float(s.body().get("rms", 0.0)))
		seen_sung = seen_sung or s.sung() >= 1
		if seen_sung and loud > 0.005 and not s.frame().is_empty():
			break
	check("it reports its body", not s.body().is_empty() and loud > 0.005)
	check("and the head's outlines", not s.frame().is_empty() and (s.frame()["lines"] as Dictionary).has("tongue"))
	check("and which syllable it is on", seen_sung and s.syllables().size() == 3)
	s.shutdown()
	s.queue_free()


## A take of the singer lands in time: the voice sings a part live while the song plays and it records, and the take,
## placed where the recording began, lines up with the same part rendered offline (the engine's own timing, which
## CHIMERA's CLI agrees with sample for sample) to within SYNC_MS.
const SYNC_MS := 25.0


func a_take_of_the_singer_is_in_sync() -> void:
	if not RackEngine.available():
		check("(no engine on this machine: skipped)", true)
		return
	var bpm := 120.0
	var notes := []
	for i in 8:
		notes.append([2.0 + i, [57, 60, 64, 62, 60, 57, 55, 57][i], 0.5])
	var words := "[00:00.00]ah ah ah ah ah ah ah ah"
	var reference := RackEngine.render(Singer.new().patch, PackedStringArray(["text v.lyrics ah ah ah ah ah ah ah ah",
			"bpm %f" % bpm, "play 0", "text v.song " + VocalPart.song_line(notes, bpm), "run 6"]))
	var s := Singer.new()
	t.add_child(s)
	var started := [-1]
	s.transport_override = func() -> Dictionary:
		var on: bool = started[0] >= 0
		return {"playing": on, "beats": (Time.get_ticks_usec() - started[0]) / 1e6 * bpm / 60.0 if on else 0.0, "bpm": bpm}
	check("the singer starts", s.start())
	s.set_track(9)
	s.set_lyrics(words)
	s.sing_part(notes, bpm)
	var warm := Time.get_ticks_msec() + 600
	while Time.get_ticks_msec() < warm:
		for k in 8:
			s.source.read()
			OS.delay_usec(1500)
		await t.get_tree().process_frame
	started[0] = Time.get_ticks_usec()
	check("it records from where the song is", s.record_start(0.0))
	# Read as the built-in engine's monitor does, a little at a time, for the six seconds.
	while Time.get_ticks_usec() - started[0] < 6_000_000:
		var until := Time.get_ticks_usec() + 12_000
		while Time.get_ticks_usec() < until:
			s.source.read()
			OS.delay_usec(1500)
		await t.get_tree().process_frame
	var take := s.source.take_tape()
	s.source.tape(false)
	s.shutdown()
	s.queue_free()
	var lag := _lag_ms(reference, take)
	print("  the take against the engine's own timing: %.1f ms (%d frames taken)" % [lag, take.size()])
	check("the take is %.0f ms off the song (within %.0f)" % [lag, SYNC_MS], absf(lag) <= SYNC_MS)


## How late `take` is against `reference` (ms, + late), by their loudness a millisecond at a time.
static func _lag_ms(reference: PackedVector2Array, take: PackedVector2Array) -> float:
	var a := _envelope(reference)
	var b := _envelope(take)
	var best := -INF
	var at := 0
	for lag in range(-400, 401):
		var sum := 0.0
		for i in range(maxi(0, -lag), mini(a.size(), b.size() - lag)):
			sum += a[i] * b[i + lag]
		if sum > best:
			best = sum
			at = lag
	return float(at)


static func _envelope(frames: PackedVector2Array) -> PackedFloat32Array:
	var per := RackEngine.RATE / 1000
	var out := PackedFloat32Array()
	out.resize(frames.size() / per)
	for k in out.size():
		var e := 0.0
		for j in per:
			e += absf(frames[k * per + j].x)
		out[k] = e / per
	return out


## Every venue letters the singer's words its own way, and every one of them is readable: the words at 7:1 against
## their panel, the sung syllable and the dim lines at 4.5:1, the shape held in, the lyrics never in capitals.
func every_venue_letters_the_words_readably() -> void:
	var looks := {}
	var all_ok := true
	var said := PackedStringArray()
	for id: StringName in Venue.IDS:
		var st := SingerStyle.of(id)
		var panel: Color = st["panel"]
		panel.a = 1.0
		var ok := SingerStyle.contrast(st["ink"], panel) >= SingerStyle.MIN_TEXT \
				and SingerStyle.contrast(st["lit"], panel) >= SingerStyle.MIN_ACCENT \
				and SingerStyle.contrast(st["dim"], panel) >= SingerStyle.MIN_ACCENT \
				and SingerStyle.contrast(st["note"], panel) >= SingerStyle.MIN_TEXT \
				and SingerStyle.contrast(st["ink"], SingerStyle.key_paint(st)) >= SingerStyle.MIN_TEXT \
				and (st["lit"] as Color).s >= SingerStyle.MIN_LIT_SATURATION * 0.8 \
				and float(st["slant"]) <= SingerStyle.MOST_SLANT and int(st["spacing"]) <= SingerStyle.MOST_SPACING \
				and float(st["bold"]) >= 0.0 and float(st["glow"]) <= SingerStyle.MOST_GLOW
		if not ok:
			said.append(String(id))
		all_ok = all_ok and ok
		looks[[(st["ink"] as Color).to_html(), st["caps"], st["spacing"], st["slant"]]] = true
	check("every venue's lettering is readable%s" % ("" if said.is_empty() else " (not: %s)" % ", ".join(said)), all_ok)
	check("and they are not all alike (%d looks in %d venues)" % [looks.size(), Venue.IDS.size()], looks.size() >= Venue.IDS.size() - 2)
	var bad := SingerStyle.readable({"ink": Color(0.1, 0.1, 0.1), "dim": Color(0.12, 0.1, 0.1), "lit": Color(0.2, 0.0, 0.0),
			"panel": Color(0.05, 0.05, 0.05), "caps": true, "spacing": 40, "slant": 0.9, "bold": -2.0, "glow": 9.0})
	check("a style made dark and wild is put right", SingerStyle.contrast(bad["ink"], Color(0.05, 0.05, 0.05)) >= SingerStyle.MIN_TEXT
			and float(bad["slant"]) == SingerStyle.MOST_SLANT and int(bad["spacing"]) == SingerStyle.MOST_SPACING
			and float(bad["bold"]) == 0.0 and float(bad["glow"]) == SingerStyle.MOST_GLOW)
	var line := Label3D.new()
	var key := Label3D.new()
	var club := SingerStyle.of(&"club")
	SingerStyle.dress(line, club, "line")
	SingerStyle.dress(key, club, "key")
	check("a lyric line is never in capitals, a key may be", not line.uppercase and key.uppercase)
	check("every label keeps a dark outline", line.outline_size >= 2 and (line.outline_modulate as Color).v < 0.2)
	line.free()
	key.free()


## The rack's VOICE played from its jacks alone (no keys, no song part): a sequencer's pitch and gate CV breathe
## a vowel on its steps, the pitch CV at 0 is middle C and +12 an octave up, nothing patched to the gate is silence,
## its audio goes on through Rings, and its ENV out opens a VCA on Plaits.
func the_voice_plays_from_its_jacks() -> void:
	if not RackEngine.available():
		check("(no engine on this machine: skipped)", true)
		return
	var from_seq := func(step: int, gate: bool, after: PackedStringArray) -> PackedVector2Array:
		var lines := PackedStringArray(["add c clock", "add s seq", "add v voice", "add o out", "cable c.beat s.clk",
				"cable s.pitch v.pitch", "knob v.mode %.4f" % Singer.position("mode", SingerRow.Mode.VOWEL)])
		if gate:
			lines.append("cable s.gate v.gate")
		for i in range(1, 17):
			lines.append("knob s.s%d %.5f" % [i, (step + 0.5) / 38.0])
		lines.append_array(after if not after.is_empty() else PackedStringArray(["cable v.out o.l"]))
		lines.append_array(PackedStringArray(["play 0", "run 4"]))
		return RackEngine.render({"modules": {}, "cables": []}, lines)
	var c4: PackedVector2Array = from_seq.call(13, true, PackedStringArray())
	var c5: PackedVector2Array = from_seq.call(25, true, PackedStringArray())
	var shut: PackedVector2Array = from_seq.call(13, false, PackedStringArray())
	var rung: PackedVector2Array = from_seq.call(13, true, PackedStringArray(["add r rings", "cable v.out r.in", "cable r.odd o.l"]))
	var led: PackedVector2Array = from_seq.call(13, true, PackedStringArray(["add w vca", "add p plaits", "cable p.out w.in",
			"cable v.env w.cv", "cable w.out o.l"]))
	var led_shut: PackedVector2Array = from_seq.call(13, false, PackedStringArray(["add w vca", "add p plaits",
			"cable p.out w.in", "cable v.env w.cv", "cable w.out o.l"]))
	var f4 := _pitch(c4, 2.1, 2.2)
	var f5 := _pitch(c5, 2.1, 2.2)
	print("  voice from its jacks: %.1f Hz and %.1f Hz; rms %.4f gated, %.4f not, %.4f through Rings, VCA %.4f / %.4f" % [
			f4, f5, _rms(c4), _rms(shut), _rms(rung), _rms(led), _rms(led_shut)])
	check("pitch CV 0 sings middle C (%.1f Hz)" % f4, absf(f4 - 261.6) < 8.0)
	check("pitch CV +12 sings an octave up (%.1f Hz)" % f5, absf(f5 / maxf(f4, 1.0) - 2.0) < 0.06)
	check("the gate CV breathes it, and with nothing on the gate it is silent", _rms(c4) > 0.03 and _rms(shut) < 0.002)
	# on the steps and off between: a beat's first quarter louder than its last (the gate is half a step)
	check("it follows the gate's steps", _rms(c4, 1.0, 1.25) > 1.5 * _rms(c4, 1.25, 1.5))
	check("its audio goes on through Rings", _rms(rung) > 0.01)
	check("its ENV out opens a VCA on Plaits, and stays shut with no gate", _rms(led) > 0.01 and _rms(led_shut) < 0.002)


static func _rms(frames: PackedVector2Array, from := 0.0, to := 1000.0) -> float:
	var sq := 0.0
	var n := 0
	for i in range(int(from * RackEngine.RATE), mini(frames.size(), int(to * RackEngine.RATE))):
		sq += frames[i].x * frames[i].x
		n += 1
	return sqrt(sq / maxf(n, 1))


## The fundamental between `from` and `to` seconds, by autocorrelation over 60..1000 Hz (0 when quiet).
static func _pitch(frames: PackedVector2Array, from: float, to: float) -> float:
	var a := PackedFloat32Array()
	for i in range(int(from * RackEngine.RATE), mini(frames.size(), int(to * RackEngine.RATE))):
		a.append(frames[i].x)
	if a.size() < 1000 or _rms(frames, from, to) < 0.005:
		return 0.0
	var best := 0.0
	var best_lag := 0
	for lag in range(RackEngine.RATE / 1000, RackEngine.RATE / 60):
		var sum := 0.0
		for i in a.size() - lag:
			sum += a[i] * a[i + lag]
		if sum > best:
			best = sum
			best_lag = lag
	return float(RackEngine.RATE) / best_lag if best_lag > 0 else 0.0


## Every venue's creature is heard: its own beast, its own call, struck on its lowest, middle and highest stone in
## the song's key, each call sounding (rendered through the rack as the perch plays it, Creature.call_at).
func every_venue_hears_its_creature() -> void:
	if not RackEngine.available():
		check("(no engine on this machine: skipped)", true)
		return
	var key := Harmony.parse("[A minor]")
	var said := PackedStringArray()
	var all_heard := true
	var venues := 0
	for id: StringName in Venue.IDS:
		var spec := Bestiary.of(id)
		var c := Creature.new()
		var lines := PackedStringArray(["knob %s.mode %.4f" % [Creature.ID, Singer.position("mode", SingerRow.Mode.BEAST)],
				"knob %s.beast %.4f" % [Creature.ID, Singer.position("beast", int(spec["beast"]))], "run 0.2"])
		var stones := [0, Bestiary.STONES / 2, Bestiary.STONES - 1]
		for n: int in stones:
			lines.append("text %s.call %d %d" % [Creature.ID, int(spec["call"]), Bestiary.note(key, spec, n)])
			lines.append("run 1.6")
		var frames := RackEngine.render(c.patch, lines)
		c.free()
		var levels := PackedStringArray()
		var heard := true
		for i in stones.size():
			var from := 0.2 + i * 1.6
			var r := _rms(frames, from, from + 1.6)
			levels.append("%.3f" % r)
			heard = heard and r > 0.005
		venues += 1
		all_heard = all_heard and heard
		said.append("%s %s [%s]%s" % [id, spec["kind"], ", ".join(levels), "" if heard else " NOT HEARD"])
	print("  creatures heard: ", "; ".join(said))
	check("every venue's creature is heard on its low, middle and high stones (%d venues)" % venues, all_heard)
