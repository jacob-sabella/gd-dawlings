extends Node
## N processes, one Tour run, a brief fixed and played to its end from every seat.
##
##   tools/tour_probe.sh N            (starts every process and reports)
##   godot --headless --path . tools/probe/tour_probe.tscn -- --as host|guest --band N
##       [--index k] [--port P]
##
## Why N processes and not fewer: `band_size` is read off `Session.participants.size()` the
## moment a brief starts, a holder's fix and a holder's part both cross the network exactly the
## way a real guest's would (DAW._do -> Session.send_intent, GuestMidi._commit ->
## Session.send_intent(&"insert_midi_take", ...) -> Session._place_take), and the draft pick that
## carries the run to its second brief is `Session.ask_tour` end to end. One process alone could
## never see any of that; eight is the top of the band this game promises to hold.
##
## Host-authoritative throughout, like Tour itself: the host drives the run and every DAW verb
## directly on the solo seat (band of 1) or through the desk when it holds a flaw or a part; a
## guest only ever reads `Tour.run` (rebuilt from `Session.tour`) and asks through
## `Session.ask_tour`/the same DAW verbs, which route to the host as a guest's always do.

const CODE := "TR88"
const NAMES := ["Grace", "Bo", "Cleo", "Dev", "Esme", "Finn", "Gil"]
## Four bars of any part in the catalogue clears its `need` -- see `_part_notes`.
const BARS_PLAYED := 4
## How long a guest gives the run to arrive after joining.
const SEEN_WITHIN := 2.0
## How long soundcheck (the parts rendering on WorkerThreadPool) is given before the host moves
## on to fixing flaws regardless.
const TUNING_DEADLINE := 15.0

var _checks := 0
var _failures := 0
var _notices: Array[String] = []
var _band := 1
var _index := 0
var _port := 7352
var _start := 0

# Host only.
var _original: DawKitProject = null
var _original_path := ""
var _saved_count_in := 0
var _takes_before := 0
var _takes_dir := ""
var _picked: StringName = &""

# Guest only.
var _hud: TourHud = null
## The given clock GuestMidi.heard_source reads while a part is played through the real
## recorder door (`_play_part_through_recorder`); see GuestMidi's own doc comment.
var _fake: Dictionary = {}


func _ready() -> void:
	var argv := OS.get_cmdline_user_args()
	var role := "host"
	for i in argv.size():
		if argv[i] == "--as" and i + 1 < argv.size():
			role = argv[i + 1]
		if argv[i] == "--band" and i + 1 < argv.size():
			_band = int(argv[i + 1])
		if argv[i] == "--index" and i + 1 < argv.size():
			_index = int(argv[i + 1])
		if argv[i] == "--port" and i + 1 < argv.size():
			_port = int(argv[i + 1])
	Session.notice.connect(func(t: String): _notices.append(t))
	Session.tour_changed.connect(_sync_roll)
	if role == "host":
		Tour.brief_started.connect(func(_i): _sync_roll())
		Tour.run_ended.connect(func(_w): _sync_roll())
	_start = Time.get_ticks_msec()
	if role == "host":
		await _host()
	else:
		await _guest()
	if role == "host":
		print("\n[host] %d tour checks, %d failed" % [_checks, _failures])
	else:
		print("\n[guest %d] %d tour checks, %d failed" % [_index, _checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## Mirrors scenes/studio.gd's `_sync_tour_roll`: a running take is sent (and a fresh one begun)
## about every bar while a brief is under way, rather than only when recording stops. Reads the
## same on both sides, since `Tour.take_roll_seconds` reads `Tour.run`, correct on either.
func _sync_roll() -> void:
	Session.guest_midi.roll_every = Tour.take_roll_seconds()


func _host() -> void:
	Session.local_name = "Ada"
	var engine := GodotBackend.new()
	DAW.use(engine)
	Session.code = CODE
	check("hosts", Session.host(_port))
	Tour.unlocks.save_path = "user://tour_unlocks_probe_%d.cfg" % _port
	Tour.unlocks.runs = 0
	Tour.unlocks.wins = 0
	_takes_dir = ProjectSettings.globalize_path(AudioTake.DIR)
	_takes_before = DirAccess.get_files_at(_takes_dir).size() if DirAccess.dir_exists_absolute(_takes_dir) else 0

	await _until(5.0)
	check("a band of %d is in the room" % _band, Session.participants.size() == _band)
	# By name, not by count: one guest counted eight times would be a band of eight too.
	var seats: Array = Session.participants.values().map(func(p): return p.display_name)
	seats.sort()
	var expected_seats: Array = ["Ada"] + NAMES.slice(0, _band - 1)
	expected_seats.sort()
	check("and every seat is its own process (%s)" % [seats], seats == expected_seats)
	check("Tour is available on the built-in engine", Tour.is_available())
	_original = ProjectBridge.capture(engine)
	_original_path = engine.project_path
	_saved_count_in = DAW.state.count_in_bars
	Tour.start_run()
	var run := Tour.run
	check("a run started, tuning up", run != null and run.state == TourRun.State.BRIEF and run.tuning)
	check("the band size is mine (%d)" % _band, run != null and run.band_size == _band)
	check("the flaw count matches the catalogue (%s)" % [run.flaws if run != null else []],
			run != null and run.flaws.size() == TourFlaws.count_for(_band, false))
	check("the part count matches the catalogue (%s)" % [run.parts if run != null else []],
			run != null and run.parts.size() == TourParts.count_for(_band, false))
	check("every flaw starts unfixed", run != null and not run.fixed.has(true))
	var holders_ok := run != null
	var seen_holders := {}
	if run != null:
		for h in run.holders:
			holders_ok = holders_ok and h != 0 and Session.participants.has(h) and not seen_holders.has(h)
			seen_holders[h] = true
	check("every part is held, one job each (%s)" % [run.holders if run != null else []], holders_ok)
	check("the band size rode the wire (%s)" % [Session.tour.get("band_size")],
			int(Session.tour.get("band_size", -1)) == _band)

	var tuning_deadline_ms := Time.get_ticks_msec() + int(TUNING_DEADLINE * 1000.0)
	while Tour.run != null and Tour.run.tuning and Time.get_ticks_msec() < tuning_deadline_ms:
		await get_tree().process_frame
	check("soundcheck ends within %.0f s" % TUNING_DEADLINE, Tour.run != null and not Tour.run.tuning)
	await _until(20.0)
	check("recording and playing once tuned", DAW.state.recording and DAW.state.playing)
	check("the count-in stayed off for the brief", DAW.state.count_in_bars == 0)
	check("the probe's own roll sync took", Session.guest_midi.roll_every > 0.0)

	run = Tour.run
	var fix_count := run.flaws.size() if _band <= 1 else run.flaws.size() - 1
	for i in fix_count:
		_fix_flaw(run.flaws[i], run)

	await _until(20.5)
	check("the host's fixes tick off the desk (%s)" % [run.fixed], run.fixed.slice(0, -1).all(func(f): return f))
	if _band > 1:
		check("and the last flaw waits for a guest", not run.fixed[-1])

	await _until(22.0)
	check("a guest's fix reached the desk and ticked (%s)" % [run.fixed], not run.fixed.has(false))
	var my_part := _my_part()
	if my_part == 0:
		await _play_part_through_recorder(0)
	elif my_part > 0:
		_play_part_direct(my_part)

	await _until(26.0)
	check("every part played and every flaw fixed ends the brief early", run.state == TourRun.State.DRAFTING)
	check("the brief scored something (%d)" % run.score, run.score > 0)
	check("three cards drafted", run.draft.size() == 3)
	var hits_ok := true
	for i in run.parts.size():
		var part := TourParts.by_id(run.parts[i])
		hits_ok = hits_ok and part != null and run.hits[i] >= part.need
	check("every part's hits cleared its need (%s)" % [run.hits], hits_ok)
	check("the Stage lane holds every part's take", DAW.state.track(Tour.STAGE_TRACK).items.size() >= run.parts.size())
	if run.draft.size() > 1:
		_picked = run.draft[1]
		if _band == 1:
			Session.ask_tour(&"draft_pick", [1])

	await _until(28.0)
	check("%s draft pick was applied" % ("my own" if _band == 1 else "a guest's"),
			run.brief_index == 1 and run.state == TourRun.State.BRIEF)
	check("my picked card landed (%s)" % [_picked], _picked in run.gear or _picked in run.curses)
	check("the band size held through the pick", run.band_size == _band)
	check("the new brief's parts are valid again", run.parts.size() == TourParts.count_for(_band, false))
	check("the new brief's draft is spent", run.draft.is_empty())

	await _until(30.0)
	Tour.abandon_run()
	check("the run is gone", Tour.run == null)
	check("the room was told the run is over", Session.tour.is_empty())
	var now_capture := ProjectBridge.capture(engine)
	var same := now_capture.same_as(_original)
	check("the host's own project is back exactly as it was (%s)" % ("" if same else now_capture.first_difference(_original)), same)
	check("and known by the same path", engine.project_path == _original_path)
	check("and the count-in is back", DAW.state.count_in_bars == _saved_count_in)
	check("and nothing is still recording", not DAW.state.recording)
	check("one run recorded, none won", Tour.unlocks.runs == 1 and Tour.unlocks.wins == 0)
	var saved := FileAccess.file_exists(Tour.unlocks.save_path)
	check("the run's unlocks were saved", saved)
	if saved:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Tour.unlocks.save_path))
	check("the roll sync is off again", Tour.take_roll_seconds() == 0.0 and Session.guest_midi.roll_every == 0.0)
	var takes_after := DirAccess.get_files_at(_takes_dir).size() if DirAccess.dir_exists_absolute(_takes_dir) else 0
	check("nothing leaked into user://takes (%d -> %d)" % [_takes_before, takes_after], takes_after == _takes_before)
	check("the recorder's fake clock is cleared", not Session.guest_midi.heard_source.is_valid())

	await _until(33.0)
	Session.leave()
	check("ending the run's session leaves the host solo", Session.role == Session.Role.SOLO)
	check("with its own mix still open", DAW.is_live())
	print("host work done at %.1fs of 33.0" % ((Time.get_ticks_msec() - _start) / 1000.0))
	await _until(34.0)


func _guest() -> void:
	Session.local_name = NAMES[_index - 1]
	# No mix stream: eight listeners of the host's audio feed are weight this probe does not need.
	Session.listen_choice = 0
	_hud = TourHud.new()
	add_child(_hud)

	await _until(1.0 + 0.3 * _index)
	check("joins", Session.join("127.0.0.1", _port, CODE))

	await _until(5.0 + SEEN_WITHIN)
	check("the band is whole (%d)" % _band, Session.participants.size() == _band)
	check("the run arrived within %.0f s" % SEEN_WITHIN, not Session.tour.is_empty() and Tour.run != null)
	var run := Tour.run
	check("the band size is mine (%d)" % _band, run != null and run.band_size == _band)
	check("the flaw count matches the catalogue", run != null and run.flaws.size() == TourFlaws.count_for(_band, false))
	check("the part count matches the catalogue", run != null and run.parts.size() == TourParts.count_for(_band, false))
	check("the host is named Ada", Session.name_of(1) == "Ada")
	check("the rescue song's snapshot arrived (%d tracks)" % DAW.state.tracks.size(),
			DAW.state.tracks.size() == TourProject.BAND.size())
	if run != null:
		for i in run.parts.size():
			var mine := run.holders[i] == Session.local_peer_id
			var want := "YOU" if mine else ("OPEN" if run.holders[i] <= 0 else Session.name_of(run.holders[i]).to_upper())
			check("part %d's line says who holds it (%s)" % [i, _hud_line(i)], _hud_line(i).begins_with(want))

	if _band > 1 and _index == _band - 1:
		await _until(21.0)
		_fix_flaw(Tour.run.flaws[-1], Tour.run)
		await _until(22.0)
		check("my fix ticked on the host's run", Tour.run.fixed[-1])

	await _until(22.0 + 0.1 * _index)
	var my_part := _my_part()
	if my_part == 0:
		await _play_part_through_recorder(0)
	elif my_part > 0:
		_play_part_direct(my_part)

	await _until(26.5)
	run = Tour.run
	check("the brief ended early, drafting", run != null and run.state == TourRun.State.DRAFTING)
	check("three cards drafted", run != null and run.draft.size() == 3)
	if my_part >= 0 and run != null:
		var part := TourParts.by_id(run.parts[my_part])
		check("my part played", run.played[my_part])
		check("and my HUD line shows it (%s)" % _hud_line(my_part),
				part != null and _hud_line(my_part).ends_with(part.progress_line(run.hits[my_part])))

	if _index == 1:
		await _until(27.0)
		run = Tour.run
		if run != null and run.draft.size() > 1:
			_picked = run.draft[1]
			Session.ask_tour(&"draft_pick", [1])

	await _until(28.5)
	run = Tour.run
	if _index == 1:
		check("my draft pick arrived (%s)" % [_picked], _picked in run.gear or _picked in run.curses)
	check("the band size held through the pick", run != null and run.band_size == _band)

	await _until(31.0)
	check("the run ended", Session.tour.is_empty() and Tour.run == null)

	await _until(34.5)
	check("the host's goodbye arrived", _notices.any(func(t): return t.contains("ended the session")))
	check("back on my own", Session.role == Session.Role.SOLO)
	check("with a mix of my own again", DAW.is_live())


## The verb table every flaw is fixed with, exactly as a player would reach for the knob: a plain
## DAW verb, which on a guest is one `Session.send_intent` round trip (DAW._do -> ... ->
## Session._receive_intent -> DAW.apply_intent) and on the host lands at once.
func _fix_flaw(id: StringName, run: TourRun) -> void:
	match id:
		&"quiet_vox":
			DAW.set_track_volume(10, DAW.db_to_taper(0.0))
		&"muddy_bass":
			DAW.set_fx_param(7, 0, 0, 0.5)
			DAW.set_fx_param(7, 0, 1, 0.5)
		&"muted_rhodes":
			DAW.set_track_mute(8, false)
		&"hard_pan":
			DAW.set_track_pan(9, 0.5)
		&"wrong_tempo":
			DAW.set_tempo(run.song_tempo)
		&"dragging_keys":
			DAW.quantize_item(TourProject.KEYS_TRACK, 0, 1.0)


## `bars` bars of `part`'s own grid (or fixed beats), from song position 0: [on, on + 0.05,
## pitch, 100, channel] rows, enough on their own to clear every catalogue entry's `need`.
func _part_notes(part: TourPart, bars: int) -> Array:
	var bpb := float(DAW.state.beats_per_bar)
	var beat := 60.0 / DAW.state.tempo
	var targets: Array[float] = []
	if not part.beats.is_empty():
		targets.assign(part.beats)
	else:
		var grid := part.grid if part.grid > 0.0 else 1.0
		var b := 0.0
		while b < bpb - 0.001:
			targets.append(b)
			b += grid
	var pitch := part.pitches[0] if not part.pitches.is_empty() else 60
	var channel := part.channel if part.channel >= 0 else 0
	var notes: Array = []
	for k in bars:
		for t in targets:
			var on: float = (float(k) * bpb + t) * beat
			notes.append([on, on + 0.05, pitch, 100, channel])
	return notes


## A part landed in one stroke, the same call HitRecorder._commit/GuestMidi._commit make when a
## take is done: on a guest this is one Session.send_intent round trip to Session._place_take.
func _play_part_direct(i: int) -> void:
	var part := TourParts.by_id(Tour.run.parts[i])
	var notes := _part_notes(part, BARS_PLAYED)
	DAW.insert_midi_take(Tour.STAGE_TRACK, notes[0][0], notes.back()[1] + 0.5, notes, "%s part" % Session.local_name)


## The same part, through the real recorder door (GuestMidi.follow/note_on/note_off) instead of
## one big insert: a given clock stands in for the mix stream (`heard_source`, "for the suite").
##
## Two things this door needs that a real player's pace hides. One: `follow()` has been ticking
## on the real clock (host_records()) since recording began, so a take may already be running
## when the fake clock takes over -- flushed first (`_commit`), or its stale `start` survives
## into the fake timeline and the first fake note gets clamped onto it (MidiTake.finish's
## clampf against the wrong `start`), landing nowhere near its grid point. Two: `follow` is
## called directly here rather than left to `_process()`'s own per-frame call -- this coroutine's
## resumption after an awaited frame is not ordered against when `_process()` runs within that
## same frame, so waiting on it left `follow()` seeing the fake clock late and dropped whichever
## notes landed before its first tick. Calling it ourselves, once right after every
## `_fake.seconds` move, is exactly what `_process()` would do, just not left to chance.
func _play_part_through_recorder(i: int) -> void:
	var part := TourParts.by_id(Tour.run.parts[i])
	var notes := _part_notes(part, BARS_PLAYED)
	var gm := Session.guest_midi
	var am_guest := not Session.is_authority()
	if am_guest:
		gm.keytar = true
	gm.monitor = false
	gm._commit()
	gm.heard_source = func(): return _fake
	_fake = {"seconds": 0.0, "playing": true, "recording": true, "valid": true}
	gm.follow(_fake)
	var bpb := float(DAW.state.beats_per_bar)
	var bar_seconds := bpb * 60.0 / DAW.state.tempo
	var bar_end := bar_seconds
	for n in notes:
		var on: float = n[0]
		var pitch: int = int(n[2])
		var channel: int = int(n[4])
		# `follow()` is called only once the note is fully closed, never between its on and off:
		# called in between, a roll landing right there restarts the take while the note is still
		# held, and the new take's replay of still-down keys hardcodes channel 0 (GuestMidi.follow,
		# whose `held` keeps no channel). This note's note-off, on its real channel, then finds
		# nothing to close (MidiTake keys by channel and pitch), so the note lands on channel 0
		# stretched to the take's end -- which a channel-9 part's judge no longer counts.
		_fake["seconds"] = on
		gm.note_on(pitch, 100, channel, 0.0, true)
		_fake["seconds"] = on + 0.05
		gm.note_off(pitch, channel, 0.0, true)
		gm.follow(_fake)
		if on + 0.05 >= bar_end:
			bar_end += bar_seconds
			# Still a frame a bar, matching a live brief's cadence, so anything else listening
			# for a tick (Session replication, the HUD) sees one.
			await get_tree().process_frame
	_fake["recording"] = false
	gm.follow(_fake)
	gm._commit()
	check("my take through the recorder landed on Stage (%s)" % [gm.last_take],
			int(gm.last_take.get("track", -1)) == Tour.STAGE_TRACK and gm.takes_sent >= 2)
	gm.heard_source = Callable()
	if am_guest:
		gm.keytar = false
	gm.monitor = true


## Index in `Tour.run.holders` held by this process, or -1. `Tour.run` is rebuilt on every
## `tour_changed` on a guest, so this is read fresh every time rather than cached.
func _my_part() -> int:
	var run := Tour.run
	if run == null:
		return -1
	for i in run.holders.size():
		if run.holders[i] == Session.local_peer_id:
			return i
	return -1


func _hud_line(i: int) -> String:
	var l := _hud.find_child("Part%d" % i, true, false) as Label
	return l.text if l != null else ""


func _until(seconds: float) -> void:
	var left := seconds - (Time.get_ticks_msec() - _start) / 1000.0
	if left > 0.0:
		await get_tree().create_timer(left).timeout


func check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
