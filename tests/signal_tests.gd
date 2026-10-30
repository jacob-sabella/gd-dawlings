extends RefCounted

## The signal glasses' tests (docs/spatial_loop.md part three), called from tests/run_tests.gd's
## `_test_signal_*`: the graph and its breaks, the fixes, the meters on the built-in engine, the
## Reaper estimate, the wire to a guest, the glasses and the view, the trace.

var t: Node


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


func close_to(label: String, a: float, b: float, epsilon := 0.0001) -> void:
	t.close_to(label, a, b, epsilon)


## The stand-in's thirteen tracks: DRUMS (1) a folder of 2 to 5, Bass DI (6), Rhodes (7), Gtr Amp (8),
## VOX (9) a folder of 10 and 11, Strings (12), Verb Rtn (13).
func _offline() -> OfflineBackend:
	var backend := OfflineBackend.new()
	backend.state = MixState.new()
	DAW.use(backend)
	return backend


## A plugin in a track's slot, as a backend reports one.
static func plug(s: MixState, track: int, slot: int, name: String, type := "VST") -> MixState.FXState:
	var f := s.fx(track, slot)
	f.name = name
	f.type = type
	return f


## A send as the cache holds one.
static func send(s: MixState, track: int, slot: int, dest: int, taper: float, pre := false, key := false) -> MixState.SendState:
	var sd := s.send(track, slot)
	sd.dest_track = dest
	sd.dest_name = s.track(dest).display_name()
	sd.volume = taper
	sd.pre_fader = pre
	sd.key = key
	return sd


## The stages and roads: a plain track's input, fader and the master; a chain's plugins in order;
## a folder's children into the folder's input and the folder into the master; a post-fader send
## from the fader, a pre-fader one from the last plugin, a key send as a branch; the master to OUT.
func graph_roads() -> void:
	_offline()
	var s := DAW.state
	plug(s, 6, 0, "EQ")
	plug(s, 6, 1, "ReaComp")
	send(s, 6, 1, 13, 0.6)
	send(s, 6, 2, 13, 0.5, true)
	send(s, 2, 1, 6, 0.716, false, true)
	var g := SignalGraph.build(s)
	var bass := g.trace(SignalGraph.in_id(6))
	var ids: Array = bass.stages.map(func(x: SignalGraph.Stage) -> String: return x.id)
	check("a chain: input, its plugins in order, its fader, the master, OUT (%s)" % [ids],
			ids == ["t6:in", "t6:fx0", "t6:fx1", "t6:fader", "master", "out"])
	check("a plugin's stage is named for its track and the plugin", g.stage("t6:fx1").title == "BASS DI · REACOMP")
	check("a post-fader send branches from the fader, into its destination's input",
			g.stage("t6:fader").branches.has("t6:send1") and g.stage("t6:send1").next == "t13:in")
	check("a pre-fader send from the last plugin", g.stage("t6:fx1").branches.has("t6:send2") and g.stage("t6:send2").pre)
	check("a key send is a branch marked a key", g.stage("t2:send1").key and g.stage("t2:fader").branches.has("t2:send1"))
	check("a folder's child plays into the folder's input", g.stage("t2:fader").next == "t1:in")
	check("and the folder into the master", g.stage("t1:fader").next == "master")
	check("and the master to OUT", g.stage("master").next == "out")
	var kick: Array = g.trace(SignalGraph.in_id(2)).stages.map(func(x): return x.id)
	check("a child's road runs through its folder (%s)" % [kick], kick.find("t1:in") == kick.find("t2:fader") + 1
			and kick.slice(-4) == ["t1:in", "t1:fader", "master", "out"])
	var roads := g.roads()
	check("every road is a pipe, the branches too", roads.any(func(r): return r[0] == "t6:fader" and r[1] == "t6:send1")
			and roads.any(func(r): return r[0] == "t6:send1" and r[1] == "t13:in")
			and roads.any(func(r): return r[0] == "master" and r[1] == "out"))
	DAW.state.transport_changed.emit()


## Every reason a stage stops the sound, and its words; a bypassed effect is no break and a bypassed
## instrument is; the solo-in-place cases; the first break wins; a heard road ends at OUT.
func graph_breaks() -> void:
	_offline()
	var s := DAW.state
	s.playing = true
	var why := func(from: String) -> SignalGraph.Trace: return SignalGraph.build(s, _sources(s)).trace(from)
	var heard: SignalGraph.Trace = why.call(SignalGraph.play_id(6))
	check("an unbroken road ends at OUT, heard", heard.heard() and heard.stages[-1].id == "out")
	s.track(6).mute = true
	var muted: SignalGraph.Trace = why.call(SignalGraph.play_id(6))
	check("muted: the fader stops it, in words, with UNMUTE (%s)" % muted.words, muted.reason == SignalGraph.MUTED
			and muted.broke_at.id == "t6:fader" and muted.words == "muted" and muted.fix.get("label") == "UNMUTE")
	s.track(6).volume = 0.0
	check("the first reason a stage has is the one said", (why.call(SignalGraph.play_id(6)) as SignalGraph.Trace).reason == SignalGraph.MUTED)
	s.track(6).mute = false
	var silent: SignalGraph.Trace = why.call(SignalGraph.play_id(6))
	check("a fader at −∞, with FADER TO 0 dB", silent.reason == SignalGraph.FADER_SILENT and silent.fix.get("label") == "FADER TO 0 dB")
	s.track(6).volume = 0.716
	s.track(7).solo = true
	var out: SignalGraph.Trace = why.call(SignalGraph.play_id(6))
	check("soloed out, naming the soloed track (%s)" % out.words, out.reason == SignalGraph.SOLOED_OUT
			and out.words == "soloed out: Rhodes is soloed" and out.fix.get("label") == "UNSOLO")
	s.track(7).solo = false
	s.track(2).solo = true
	send(s, 2, 1, 13, 0.5)
	check("solo in place: a soloed kick keeps its folder up", SignalGraph.soloed_out(s, 1) == 0)
	check("and the return it sends to", SignalGraph.soloed_out(s, 13) == 0)
	check("and leaves the snare out", SignalGraph.soloed_out(s, 3) == 2)
	s.track(2).solo = false
	s.track(1).solo = true
	check("a soloed folder keeps its children up", SignalGraph.soloed_out(s, 4) == 0 and SignalGraph.soloed_out(s, 6) == 1)
	s.track(1).solo = false
	s.track(1).mute = true
	var folder: SignalGraph.Trace = why.call(SignalGraph.play_id(3))
	check("a child's road stopped by its folder says the folder (%s)" % folder.words, folder.reason == SignalGraph.FOLDER_MUTED
			and folder.broke_at.id == "t1:fader" and folder.words.contains("DRUMS") and folder.fix.get("label") == "UNMUTE")
	s.track(1).mute = false
	(s.track(2).sends[1] as MixState.SendState).volume = 0.0
	var g := SignalGraph.build(s)
	check("a send at −∞, with a SEND fix", g.stage("t2:send1").halt == SignalGraph.SEND_SILENT
			and str(g.stage("t2:send1").fix.get("label")).begins_with("SEND TO"))
	s.track(6).main_send = false
	var nowhere: SignalGraph.Trace = why.call(SignalGraph.play_id(6))
	check("routed nowhere, with SEND TO MASTER", nowhere.reason == SignalGraph.NO_ROUTE
			and nowhere.words.contains("master") and nowhere.fix.get("label") == "SEND TO MASTER")
	s.track(6).main_send = true
	plug(s, 7, 0, "Surge XT", "VST3i").enabled = false
	var bypassed: SignalGraph.Trace = why.call(SignalGraph.play_id(7))
	check("a bypassed instrument plays nothing, with BYPASS OFF", bypassed.reason == SignalGraph.INSTRUMENT_BYPASSED
			and bypassed.fix.get("label") == "BYPASS OFF")
	s.fx(7, 0).type = "VST3"
	var dry: SignalGraph.Trace = why.call(SignalGraph.play_id(7))
	check("a bypassed effect passes it dry, and says so", dry.heard() and dry.stages[2].bypassed)
	s.fx(7, 0).enabled = true
	s.track(7).meter_peak = PackedFloat32Array([-10.0, -INF])
	var nothing: SignalGraph.Trace = why.call(SignalGraph.play_id(7))
	check("a plugin with sound in and silence out (%s)" % nothing.words, nothing.reason == SignalGraph.PLUGIN_SILENT
			and nothing.words.contains("Surge XT") and nothing.fix.is_empty())
	s.track(7).meter_peak = PackedFloat32Array()
	s.playing = false
	var stopped: SignalGraph.Trace = why.call(SignalGraph.play_id(6))
	check("stopped, a track's own playback stops at once, with PLAY", stopped.reason == SignalGraph.STOPPED
			and stopped.broke_at.id == "t6:play" and stopped.fix.get("label") == "PLAY")
	s.playing = true
	s.track(12).items = []
	check("a track with nothing on it has nothing to play", (why.call(SignalGraph.play_id(12)) as SignalGraph.Trace).reason == SignalGraph.EMPTY)
	check("a folder plays its children, and is not empty", (why.call(SignalGraph.play_id(1)) as SignalGraph.Trace).heard())
	s.master.volume = 0.0
	check("a master at −∞", (why.call(SignalGraph.play_id(6)) as SignalGraph.Trace).reason == SignalGraph.MASTER_SILENT)
	s.master.volume = 0.69
	# The room's sources: the mic (a voice), an instrument, a station heard locally.
	for i in s.tracks:
		s.track(i).rec_arm = false
	s.track(10).monitor = 0
	var mic: SignalGraph.Trace = why.call(SignalGraph.source_id("mic"))
	check("the mic's track not armed, with ARM (%s)" % mic.words, mic.reason == SignalGraph.NOT_ARMED
			and mic.broke_at.id == "src:mic" and mic.fix.get("label") == "ARM")
	s.track(10).rec_arm = true
	var unmonitored: SignalGraph.Trace = why.call(SignalGraph.source_id("mic"))
	check("armed, monitoring off, with MONITOR ON", unmonitored.reason == SignalGraph.MONITOR_OFF and unmonitored.fix.get("label") == "MONITOR ON")
	s.track(10).monitor = 1
	s.track(10).input = "none"
	var no_input: SignalGraph.Trace = why.call(SignalGraph.source_id("mic"))
	check("no record input, and no fix: the sign says where to choose one", no_input.reason == SignalGraph.NO_INPUT
			and no_input.fix.is_empty() and no_input.words.contains("F2"))
	s.track(10).input = ""
	var sung: SignalGraph.Trace = why.call(SignalGraph.source_id("mic"))
	check("armed, monitored, an input: the voice goes through its folder to OUT", sung.heard()
			and sung.stages.map(func(x): return x.id).has("t9:in"))
	s.track(10).rec_arm = false
	var shaker: SignalGraph.Trace = why.call(SignalGraph.source_id("shaker"))
	check("an instrument with no track armed: nothing records it, live on MONITOR (%s)" % shaker.words,
			shaker.reason == SignalGraph.NOT_ARMED and shaker.words.contains("MONITOR"))
	var jacked: SignalGraph.Trace = why.call(SignalGraph.source_id("bell1"))
	check("one jacked into a track goes onto it armed or not", jacked.heard())
	var grains: SignalGraph.Trace = why.call(SignalGraph.source_id("grains"))
	check("a station heard in your ears only says so", grains.reason == SignalGraph.LOCAL)
	s.track(6).mute = true
	s.track(6).rec_arm = false
	var first: SignalGraph.Trace = why.call(SignalGraph.source_id("kick_in"))
	check("the first break on the road is the one said: unarmed before muted", first.reason == SignalGraph.NOT_ARMED)


## The sources graph_breaks traces: the mic on Lead Vox (10), the shaker with nothing armed, a bell
## jacked into Strings (12), the grain cloud, and something played onto Bass DI (6).
func _sources(s: MixState) -> Array:
	return [
		{"id": "mic", "title": "MIC", "track": 10, "kind": SignalGraph.VOICE},
		{"id": "shaker", "title": "SHAKER", "track": HitRecorder.armed_track(), "kind": SignalGraph.NOTES},
		{"id": "bell1", "title": "BELL", "track": 12, "kind": SignalGraph.NOTES, "jacked": true},
		{"id": "grains", "title": "GRAIN CLOUD", "track": 0, "kind": SignalGraph.LOCAL_SOURCE},
		{"id": "kick_in", "title": "PADS", "track": 6, "kind": SignalGraph.NOTES},
	]


## A fix is one step in the history, however many writes it makes: a grouped mute let go, three
## solos let go. Undone, all of it comes back at once.
func fixes_are_one_step() -> void:
	var backend := _offline()
	var s := DAW.state
	s.playing = true
	DAW.set_track_group(2, 1)
	DAW.set_track_group(3, 1)
	DAW.set_track_mute(2, true)
	check("a grouped mute mutes the group", s.track(2).mute and s.track(3).mute)
	var depth := backend._undo.size()
	var tr := SignalGraph.build(s).trace(SignalGraph.play_id(2))
	check("the trace offers UNMUTE", tr.fix.get("label") == "UNMUTE")
	check("and it is done", SignalGraph.apply_fix(tr.fix) and not s.track(2).mute and not s.track(3).mute)
	check("as one step (%d -> %d)" % [depth, backend._undo.size()], backend._undo.size() == depth + 1)
	DAW.undo()
	check("one undo puts the group's mutes back", s.track(2).mute and s.track(3).mute)
	DAW.set_track_mute(2, false)
	for i in [6, 7, 8]:
		DAW.set_track_solo(i, true)
	depth = backend._undo.size()
	var out := SignalGraph.build(s).trace(SignalGraph.play_id(12))
	SignalGraph.apply_fix(out.fix)
	check("UNSOLO lets every solo go, as one step", not [6, 7, 8].any(func(i): return s.track(i).solo)
			and backend._undo.size() == depth + 1)
	DAW.undo()
	check("and one undo brings all three back", [6, 7, 8].all(func(i): return s.track(i).solo))
	s.track(6).main_send = true
	DAW.set_track_main_send(6, false)
	var route := SignalGraph.build(s).trace(SignalGraph.play_id(6))
	depth = backend._undo.size()
	SignalGraph.apply_fix(route.fix)
	check("SEND TO MASTER is the new verb, one step", s.track(6).main_send and backend._undo.size() == depth + 1)
	check("and the road runs on to OUT", SignalGraph.build(s).trace(SignalGraph.play_id(6)).heard())
	DAW.undo()
	check("undone, it is routed nowhere again", not s.track(6).main_send)
	check("a stage with no fix does nothing", not SignalGraph.apply_fix({}))


## A guest's fix is the host's intent: the open edit, the write, the close.
func a_guests_fix_is_an_intent() -> void:
	_offline()
	DAW.state.track(6).mute = true
	var fix := SignalGraph.build(DAW.state).trace(SignalGraph.play_id(6)).fix
	t._as_session(Session.Role.GUEST, 5)
	Session.keep_intents = true
	Session.kept_intents.clear()
	SignalGraph.apply_fix(fix)
	var verbs: Array = Session.kept_intents.map(func(c): return c[0])
	check("a guest asks the host, in one edit (%s)" % [verbs], verbs == [&"open_edit", &"set_track_mute", &"close_edit"])
	check("and changes nothing itself", DAW.state.track(6).mute)
	Session.keep_intents = false
	Session.start_solo()


## The meters on the wire: `/track/N/vu/signal` is volatile and round-trips its four arrays; the
## master send is durable, and a snapshot carries it; a guest's graph reads the host's meters.
func the_meters_ride_the_wire() -> void:
	var backend := _offline()
	var s := DAW.state
	check("a track's chain meters are volatile", backend.is_volatile("/track/6/vu/signal"))
	check("its master send is not", not backend.is_volatile("/track/6/mainsend"))
	plug(s, 6, 0, "EQ")
	send(s, 6, 1, 13, 0.5)
	var bass := s.track(6)
	bass.meter_peak = PackedFloat32Array([-8.0, 1.5])
	bass.meter_rms = PackedFloat32Array([-12.0, -4.0])
	bass.meter_gr = PackedFloat32Array([NAN])
	bass.meter_sends = PackedFloat32Array([-14.0])
	bass.vu_l = FaderLaw.to_taper(2.3)
	bass.main_send = false
	var guest := MixState.new()
	for entry in MixWire.snapshot(s):
		MixWire.apply(guest, entry[0], entry[1])
	check("a snapshot carries a master send that is off", not guest.track(6).main_send and guest.track(7).main_send)
	MixWire.apply_replicated(guest, [["/track/6/vu/signal", MixWire.pack_meters(bass)], ["/track/6/vu/L", [bass.vu_l]]])
	var g := guest.track(6)
	check("the four arrays arrive as they were sent", g.meter_peak == bass.meter_peak and g.meter_rms == bass.meter_rms
			and g.meter_sends == bass.meter_sends and g.meter_gr.size() == 1 and is_nan(g.meter_gr[0]))
	var host_graph := SignalGraph.build(s)
	var guest_graph := SignalGraph.build(guest)
	for id in ["t6:in", "t6:fx0", "t6:fader", "t6:send1"]:
		check("the guest's %s reads the host's (%s, %s)" % [id, guest_graph.stage(id).level_words(), host_graph.stage(id).level_words()],
				guest_graph.stage(id).level_words() == host_graph.stage(id).level_words() and guest_graph.stage(id).measured)
	check("so the guest's glasses see the host's clip", guest_graph.clips().size() >= 1
			and SignalGraph.clip_words(guest_graph.clips()[0]) == "CLIPPING +2.3 dB at BASS DI fader")
	MixWire.apply_replicated(guest, [["/track/6/vu/signal", ["junk"]]])
	check("a malformed meter leaves them as they were", guest.track(6).meter_peak == bass.meter_peak)


## Reaper has a track's meter, not a stage's: the input and plugins are not measured, the fader is,
## and a send is estimated from the track's meter and its level (post-fader: plus the send; pre:
## less the fader too), said with ≈. GetMeters' answer lands as the plugins' gain reduction and the
## master send, through the replication stream.
func reaper_estimates_its_sends() -> void:
	var backend := ReaperBackend.new()
	backend.state = MixState.new()
	var s := backend.state
	for i in [1, 2]:
		s.track(i).name = "T%d" % i
	s.track(1).name = "Bass"
	plug(s, 1, 0, "ReaComp")
	s.track(1).volume = FaderLaw.to_taper(-3.0)
	s.track(1).vu_l = FaderLaw.to_taper(-6.0)
	s.track(1).vu_r = s.track(1).vu_l
	send(s, 1, 1, 2, FaderLaw.to_taper(-6.0))
	send(s, 1, 2, 2, FaderLaw.to_taper(-6.0), true)
	var g := SignalGraph.build(s)
	check("the input and the plugin are not measured", g.stage("t1:in").level_words() == "not measured"
			and not g.stage("t1:fx0").measured and not g.stage("t1:fx0").estimated)
	close_to("the fader is measured", g.stage("t1:fader").peak_db, -6.0, 0.01)
	check("a send is estimated", g.stage("t1:send1").estimated and not g.stage("t1:send1").measured)
	close_to("post-fader: the track's peak and the send", g.stage("t1:send1").peak_db, -12.0, 0.01)
	close_to("pre-fader: less the fader too", g.stage("t1:send2").peak_db, -9.0, 0.01)
	check("and said with ≈ (%s)" % g.stage("t1:send1").level_words(), g.stage("t1:send1").level_words().begins_with("≈ −12.0 dBFS"))
	check("a plugin's silence is never claimed on Reaper", SignalGraph.build(s).stage("t1:fx0").halt == &"")
	backend._on_meters({"ok": true, "tracks": [{"index": 1, "peak": [0.5, 0.5], "hold_db": -6.0, "main_send": false,
			"gr": [-4.5]}, {"index": 2, "peak": [0.0, 0.0], "hold_db": -150.0, "main_send": true, "gr": {}}],
			"master": [0.5, 0.5]})
	check("GetMeters' gain reduction reaches the plugin (%s)" % [s.track(1).meter_gr], s.track(1).meter_gr.size() == 1
			and is_equal_approx(s.track(1).meter_gr[0], -4.5) and s.track(2).meter_gr.is_empty())
	check("reported by the plugin, not derived", SignalGraph.build(s).stage("t1:fx0").level_words() == "not measured"
			and is_equal_approx(SignalGraph.build(s).stage("t1:fx0").gr_db, -4.5)
			and not SignalGraph.build(s).stage("t1:fx0").gr_derived)
	check("and its master send, which is off", not s.track(1).main_send and s.track(2).main_send)
	check("into the replication stream", backend._repl_volatile.has("/track/1/vu/signal") and backend._repl_durable.has("/track/1/mainsend"))
	check("a gain reduction the bridge says none of is NAN in its place",
			is_nan(ReaperBackend.meter_gr_of(["none", -2.0])[0]) and ReaperBackend.meter_gr_of(["none", -2.0])[1] == -2.0)
	backend.free()


## A sine of amplitude 0.5 on Snare's lane, through an EQ bypassed and a compressor squeezing it:
## the built-in engine's probes read the input at the sine's own peak and RMS, the EQ's output the
## same, the compressor's gain reduction below zero; post-fader is the chain's end and the fader; a
## send its own bus; a probe is torn down when nobody wants the meters.
func the_built_in_engine_taps_every_stage() -> void:
	var backend := GodotBackend.new()
	backend.state = MixState.new()
	DAW.use(backend)
	var s := DAW.state
	DAW.add_fx(3, "eq")
	DAW.add_fx(3, "compressor")
	var comp_slot: int = s.track(3).plugins()[1]
	# The EQ bypassed: its probe holds the same effect object, bypassed too, and passes it as it came.
	DAW.set_fx_enabled(3, s.track(3).plugins()[0], false)
	DAW.set_fx_param(3, comp_slot, 0, 0.5)
	DAW.set_fx_param(3, comp_slot, 1, 0.6)
	DAW.set_fx_param(3, comp_slot, 2, 0.0)
	DAW.create_send(3, 13)
	var slot: int = s.track(3).sends.keys()[0]
	DAW.set_send_volume(3, slot, FaderLaw.to_taper(-6.0))
	var rate := int(AudioServer.get_mix_rate())
	var seconds := 6
	var data := PackedByteArray()
	data.resize(rate * seconds * 4)
	for i in rate * seconds:
		var v := int(0.5 * sin(TAU * 1000.0 * i / rate) * 32767.0)
		data.encode_s16(i * 4, v)
		data.encode_s16(i * 4 + 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = rate
	wav.data = data
	backend._take_streams["sine.wav"] = wav
	var item := MixState.ItemState.new()
	item.start = 0.0
	item.length = float(seconds)
	item.source = "sine.wav"
	item.name = "sine"
	s.set_track_items(3, [item])
	DAW.seek(0.0)
	DAW.transport_play()
	var until := Time.get_ticks_msec() + 1600
	while Time.get_ticks_msec() < until:
		backend.want_signal_meters()
		await t.get_tree().process_frame
	var probes: Array = backend.probes().get(3, [])
	check("a probe a stage: the input and after each plugin (%d)" % probes.size(), probes.size() == 3)
	check("each plays into the muted keys bus, heard by nobody", probes.all(func(p):
			return AudioServer.get_bus_send(AudioServer.get_bus_index(p[0])) == StringName(GodotBackend.KEYS_BUS)))
	var g := SignalGraph.build(s)
	var sine_peak := 20.0 * log(0.5) / log(10.0)
	close_to("the input reads the sine's peak (%s)" % g.stage("t3:in").level_words(), g.stage("t3:in").peak_db, sine_peak, 0.5)
	close_to("and its RMS, 3 dB under", g.stage("t3:in").rms_db, sine_peak - 3.01, 0.7)
	close_to("a bypassed EQ puts out what it took in", g.stage(SignalGraph.fx_id(3, s.track(3).plugins()[0])).peak_db, sine_peak, 0.6)
	var comp := g.stage(SignalGraph.fx_id(3, comp_slot))
	check("the compressor squeezes it, and its gain reduction is worked out (%s)" % comp.level_words(),
			comp.gr_db < -2.0 and comp.gr_derived and comp.peak_db < sine_peak - 1.0)
	# The rest with the chain bypassed too, so it is linear: a send replays the track's plugins on its
	# own bus at the send's level, so after a compressor it would read less squeezed than the track.
	DAW.set_fx_enabled(3, comp_slot, false)
	until = Time.get_ticks_msec() + 500
	while Time.get_ticks_msec() < until:
		backend.want_signal_meters()
		await t.get_tree().process_frame
	g = SignalGraph.build(s)
	check("bypassed, its stage says so and passes it on", g.stage(SignalGraph.fx_id(3, comp_slot)).bypassed
			and absf(g.stage(SignalGraph.fx_id(3, comp_slot)).peak_db - sine_peak) < 0.6)
	var fader_db := FaderLaw.to_db(s.track(3).volume)
	close_to("post-fader is the chain's end and the fader (%s)" % g.stage("t3:fader").level_words(),
			g.stage("t3:fader").peak_db, sine_peak + fader_db, 0.7)
	var sd := g.stage(SignalGraph.send_id(3, slot))
	check("the send is measured, off its own bus", sd.measured and not sd.estimated)
	close_to("at the chain's end, the fader and the send (%s)" % sd.level_words(), sd.peak_db, sine_peak + fader_db - 6.0, 0.7)
	check("the folder's sum and the master are measured", g.stage("t1:fader").peak_db > SignalGraph.FLOOR_DB
			and g.stage("master").peak_db > SignalGraph.FLOOR_DB)
	DAW.set_track_mute(3, true)
	until = Time.get_ticks_msec() + 400
	while Time.get_ticks_msec() < until:
		backend.want_signal_meters()
		await t.get_tree().process_frame
	g = SignalGraph.build(s)
	check("muted, the fader reads nothing and the input still reads the sine: the sign goes at the fader",
			g.stage("t3:in").peak_db > sine_peak - 1.0 and g.stage("t3:fader").peak_db < SignalGraph.FLOOR_DB
			and g.trace(SignalGraph.play_id(3)).broke_at.id == "t3:fader")
	DAW.set_track_mute(3, false)
	DAW.transport_stop()
	until = Time.get_ticks_msec() + GodotBackend.SIGNAL_KEEP_MSEC + 300
	while Time.get_ticks_msec() < until:
		await t.get_tree().process_frame
	var left := 0
	for b in AudioServer.bus_count:
		if AudioServer.get_bus_name(b).begins_with(GodotBackend.METER_PREFIX):
			left += 1
	check("unwanted, the probes go and the meters empty (%d left)" % left, left == 0 and backend.probes().is_empty()
			and s.track(3).meter_peak.is_empty())
	check("while guests are here they are wanted whoever asked", (func() -> bool:
		var had := Session.participants.duplicate()
		Session.participants[98] = {}
		Session.participants[99] = {}
		var wanted := backend.signal_meters_wanted()
		Session.participants = had
		return wanted).call())


## A view drawn from a place for every stage: a track's stages at x = its index, the sources
## behind, the master and OUT in front. For the view's tests, without a room.
static func spread(id: String) -> Variant:
	if id == "master":
		return Vector3(7, 1, -3)
	if id == "out":
		return Vector3(7, 2, -3)
	if id.begins_with("src:"):
		return Vector3(float(id.length()), 1, 3)
	if id.begins_with("t"):
		return Vector3(float(int(id.substr(1, id.find(":") - 1))), 1, 0)
	return null


## Whether two colours are the one hue, however bright (a pipe glows past 1.0).
static func same_hue(a: Color, b: Color) -> bool:
	var x := Color(a.r, a.g, a.b) / maxf(maxf(a.r, a.g), maxf(a.b, 0.0001))
	var y := Color(b.r, b.g, b.b) / maxf(maxf(b.r, b.g), maxf(b.b, 0.0001))
	return absf(x.r - y.r) + absf(x.g - y.g) + absf(x.b - y.b) < 0.12


## A: the pipes. As thick as loud and coloured by health (in words too: a tag over a hot fader, a
## CLIPPING tag over one past 0 dBFS); a stub and a sign where the sound stops, saying why; one
## TRANSPORT STOPPED sign for the stopped transport, not one a track.
func the_pipes_show_the_level() -> void:
	_offline()
	var s := DAW.state
	s.playing = true
	for i in s.tracks:
		s.track(i).vu_l = FaderLaw.to_taper(-18.0)
		s.track(i).vu_r = FaderLaw.to_taper(-18.0)
	s.master.vu_l = FaderLaw.to_taper(-10.0)
	var view := SignalView.new()
	view.place = spread
	t.add_child(view)
	var draw := func(times := 40) -> void:
		var g := SignalGraph.build(s)
		for i in times:
			view.update(g, 0.05)
	draw.call()
	var quiet: Array = view.shown.get("t7:fader>master", [])
	check("a track's pipe runs from its fader to the master (%s)" % [view.shown.keys().slice(0, 6)], not quiet.is_empty())
	check("drawn in segments (%d)" % view.segments, view.segments > 20)
	check("at -18 dBFS it is shown at -18 (%.1f)" % quiet[0], absf(float(quiet[0]) + 18.0) < 0.5)
	check("in the track's own colour", same_hue(quiet[2], view._track_colour(7)))
	s.track(7).vu_l = FaderLaw.to_taper(-1.5)
	draw.call()
	var hot: Array = view.shown["t7:fader>master"]
	check("louder is thicker (%.4f > %.4f)" % [hot[1], quiet[1]], float(hot[1]) > float(quiet[1]))
	check("and near 0 dBFS amber", same_hue(hot[2], SignalView.AMBER))
	check("with its figure in words (%s)" % [view.tags_shown], view.tags_shown.any(
			func(w: String) -> bool: return w.contains("RHODES fader") and w.contains("−1.5 dBFS")))
	s.track(6).vu_l = FaderLaw.to_taper(2.3)
	draw.call()
	var over: Array = view.shown["t6:fader>master"]
	check("over 0 dBFS red", same_hue(over[2], SignalView.RED))
	check("and tagged CLIPPING with how far and where (%s)" % [view.tags_shown],
			"CLIPPING +2.3 dB at BASS DI fader" in view.tags_shown)
	s.track(8).mute = true
	draw.call()
	var muted: Array = view.shown["t8:fader>master"]
	check("a muted track's pipe is a thin stub (%.4f)" % muted[1], is_equal_approx(float(muted[1]), SignalView.RADIUS_MIN))
	var sign := view.signs_shown.filter(func(w: String) -> bool: return w.begins_with("MUTED") and w.contains("GTR AMP"))
	check("ending at a sign that says why, and the fix (%s)" % [sign], sign.size() == 1
			and (sign[0] as String).contains("GTR AMP") and (sign[0] as String).contains("UNMUTE"))
	s.playing = false
	draw.call(2)
	var stopped := view.signs_shown.filter(func(w: String) -> bool: return w.begins_with("TRANSPORT STOPPED"))
	check("the stopped transport is one sign, at the master (%d)" % stopped.size(), stopped.size() == 1)
	view.queue_free()


## B: why can't I hear this? A trace lights a stage at a time, stops at the first break and says it,
## offers the fix where there is one; a heard one runs to OUT; a fix done is one undo step, and the
## trace again runs on past it.
func a_trace_stops_at_the_first_break() -> void:
	var backend := _offline()
	var s := DAW.state
	s.playing = true
	s.track(8).mute = true
	s.track(8).volume = 0.0
	var view := SignalView.new()
	view.place = spread
	view.screen_card = true
	t.add_child(view)
	var tr := SignalGraph.build(s).trace(SignalGraph.play_id(8))
	check("the first break is the mute, not the fader after it (%s)" % tr.reason, tr.reason == SignalGraph.MUTED
			and tr.broke_at.id == "t8:fader")
	view.trace(tr, "Gtr Amp")
	check("it starts with one stage lit", view.lit == 1 and not view.trace_done())
	view.update(SignalGraph.build(s), SignalView.TRACE_STEP * 1.05)
	check("and lights on a step later, quicker through stages that stand at one place (%d lit)" % view.lit,
			view.lit >= 3 and view._step_to(1) < SignalView.TRACE_STEP)
	check("said on the card a line a stage (%s)" % view.card_text.text.replace("\n", " / "),
			view.card_text.text.begins_with("WHY CAN'T I HEAR GTR AMP?") and view.card_text.text.contains("✓ GTR AMP playback"))
	for i in 20:
		view.update(SignalGraph.build(s), SignalView.TRACE_STEP)
	check("at the end it says where and why", view.trace_done() and view.card_text.text.contains("✗ GTR AMP fader")
			and view.card_text.text.contains("MUTED: muted"))
	check("with the fix to press, by its key too", view.card_fix.visible and view.card_fix.text.contains("UNMUTE")
			and view.fix_key.visible)
	var asked: Array = []
	view.fix_asked.connect(func(f: Dictionary) -> void: asked.append(f))
	view.card_fix.pressed.emit()
	check("the card's FIX asks for it", asked.size() == 1 and asked[0]["label"] == "UNMUTE")
	var depth := backend._undo.size()
	SignalGraph.apply_fix(asked[0])
	check("done, it is one undo step", not s.track(8).mute and backend._undo.size() == depth + 1)
	var again := SignalGraph.build(s).trace(SignalGraph.play_id(8))
	check("and the trace runs on to the next break: the fader (%s)" % again.reason, again.reason == SignalGraph.FADER_SILENT)
	SignalGraph.apply_fix(again.fix)
	var heard := SignalGraph.build(s).trace(SignalGraph.play_id(8))
	check("fixed again, it is heard, and ends at OUT", heard.heard() and heard.stages[-1].id == "out")
	view.trace(heard, "Gtr Amp")
	for i in 20:
		view.update(SignalGraph.build(s), SignalView.TRACE_STEP)
	check("said HEARD, with no fix to offer", view.card_text.text.contains("HEARD") and not view.card_fix.visible
			and not view.fix_key.visible)
	s.track(8).volume = FaderLaw.to_taper(0.0)
	var still := SignalView.new()
	still.motion = 0.0
	still.place = spread
	t.add_child(still)
	still.trace(SignalGraph.build(s).trace(SignalGraph.play_id(8)), "Gtr Amp")
	check("with motion off it is lit at once", still.trace_done())
	view.clear_trace()
	check("cleared, nothing is lit", view.tracing == null and not view.card.visible and not view.fix_key.visible)
	view.queue_free()
	still.queue_free()


## The glasses, in a room: on your head you see the signal, on a bandmate's you do not; X shows it
## without them; nothing of the view is room state. Y traces what the cursor is on, and says so
## when there is nothing; Shift-Y fixes; and on a guest the fix is the host's intent.
func the_glasses_are_yours_alone() -> void:
	t._offline()
	var saved_layout := Session.layout
	Session.layout = LayoutProfile.new()
	Session.layout.save_path = "user://test_layout_profile.cfg"
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	t.add_child(studio)
	await t.get_tree().physics_frame
	var room := studio.items
	var dispenser := room.items.get(&"glasses") as SignalGlassesItem
	check("a pair of signal glasses is on the prop shelf", dispenser != null and dispenser.state == Item.State.HOME
			and dispenser.home.is_equal_approx(studio.venue.glasses_spot()))
	check("a personal kind: each player takes their own", &"glasses" in ItemRoom.PERSONAL_KINDS)
	var help: Array = WelcomeCard.ROOM.filter(func(r: Array) -> bool: return r[0] == "See the signal")
	check("F1's ROOM page names X, Y and Shift-Y", help.size() == 1 and (help[0][1] as String).begins_with("X,")
			and (help[0][1] as String).contains("Y over anything") and (help[0][1] as String).contains("Shift-Y"))
	check("a hover card says what they do", dispenser.hint().contains("where the sound goes"))
	var wrong: Array = []
	for id in Venue.IDS:
		studio.set_venue(id, false)
		if not dispenser.home.is_equal_approx(studio.venue.glasses_spot()):
			wrong.append(id)
	check("in every venue (%s)" % [wrong], wrong.is_empty())
	studio.set_venue(&"studio", false)
	studio.console._rebuild()
	studio.stage._rebuild()
	check("no glasses, no signal", not studio.signal_view_on())
	studio._follow_signal(0.1)
	check("and no view made", studio.signal_view == null)

	t._as_session(Session.Role.HOST, 1)
	Session.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	Session._register(1, "Ada", 0)
	var hand := studio.get_node("MouseHand") as MouseInteractor
	var before := room.state().duplicate(true)
	dispenser.grab_begin(hand, dispenser.global_position)
	var mine := hand.carrying as SignalGlassesItem
	check("taken, a pair of my own (%s)" % (mine.id if mine != null else &""), mine != null and mine.id == &"glasses1")
	mine.use(true)
	check("a click puts them on", hand.worn == mine and hand.carrying == null)
	check("and I see the signal", studio.signal_view_on())
	DAW.state.playing = true
	studio._follow_signal(0.1)
	check("the view is made and drawn (%d segments)" % studio.signal_view.segments,
			studio.signal_view != null and studio.signal_view.visible and studio.signal_view.segments > 20)
	check("in this room: a track's pipe from its voice or strip to the master",
			studio.signal_place("master") is Vector3 and studio.signal_place("t7:fader") is Vector3)
	var keys := str(room.state().keys()) + str(studio.signal_view.get_meta_list())
	check("nothing of the view is room state (%s)" % [room.state().keys()], not keys.to_lower().contains("signal"))
	var phones := room.take_personal(&"headphones", 1)
	hand.pick_up(phones)
	hand.wear()
	check("headphones on send the glasses home: one head (%s)" % [hand.worn], hand.worn is HeadphonesItem
			and hand.worn == phones and not studio.signal_view_on())
	studio._follow_signal(0.1)
	check("and the view goes", not studio.signal_view.visible)
	hand.take_off()
	room.send_home(hand.carrying)

	var theirs := room.take_personal(&"glasses", 2)
	room.wear(theirs, true)
	check("a bandmate's pair on their head shows me nothing", not studio.signal_view_on())

	studio.toggle_signal_view()
	check("X shows it with no glasses", studio.signal_view_on())
	studio._follow_signal(0.1)
	check("drawn", studio.signal_view.visible)

	DAW.state.track(7).mute = true
	studio._follow_signal(0.1)
	var sources := studio.signal_sources()
	check("the room's sources are listed (%s)" % [sources.map(func(r): return r["id"])], sources.any(
			func(r: Dictionary) -> bool: return r["id"] == String(ChordHarp.SOURCE)) and sources.any(
			func(r: Dictionary) -> bool: return r["kind"] == SignalGraph.LOCAL_SOURCE))
	var told: Array = []
	var listen := func(text: String) -> void: told.append(text)
	Session.notice.connect(listen)
	check("nothing to trace says so", not studio.trace_pointed(hand) and told.size() == 1
			and (told[0] as String).contains("Nothing that sounds"))
	var strip: Node = null
	for s in studio.console.strips:
		if s.track_index == 7:
			strip = s
	var target := studio.signal_target_of(strip.find_children("*", "ControlAffordance", true, false)[0], Vector3.ZERO)
	check("a control on a strip traces its track (%s)" % [target], target == [SignalGraph.play_id(7), "Rhodes"])
	var harp_target := studio.signal_target_of(studio.harp.find_children("*", "ControlAffordance", true, false)[0])
	check("a control on the harp traces the harp", not harp_target.is_empty() and harp_target[0] == "src:harp")
	check("Y traces it", studio.trace_from(target[0], target[1]) and studio.signal_view.tracing != null
			and studio.signal_view.tracing.reason == SignalGraph.MUTED)
	check("and the toast says where and why, and the fix key", (told[-1] as String).contains("stops at RHODES fader")
			and (told[-1] as String).contains("Shift-Y: UNMUTE"))
	var depth := (DAW.backend as OfflineBackend)._undo.size()
	check("Shift-Y fixes it, one undo step", studio.fix_traced() and not DAW.state.track(7).mute
			and (DAW.backend as OfflineBackend)._undo.size() == depth + 1)
	studio._follow_signal(0.1)
	check("and the trace runs again, past it", studio.signal_view.tracing != null and studio.signal_view.tracing.heard())
	check("with nothing traced, Shift-Y says so", studio.signal_view.tracing.fix.is_empty() and not studio.fix_traced())

	DAW.state.track(7).mute = true
	studio.trace_from(target[0], target[1])
	t._as_session(Session.Role.GUEST, 5)
	Session.keep_intents = true
	Session.kept_intents.clear()
	studio.fix_traced()
	var verbs: Array = Session.kept_intents.map(func(c): return c[0])
	check("on a guest the fix is asked of the host (%s)" % [verbs], &"set_track_mute" in verbs and DAW.state.track(7).mute)
	Session.keep_intents = false
	Session.notice.disconnect(listen)
	studio.toggle_signal_view()
	check("X again: off", not studio.signal_view_on())
	Session.start_solo()
	Session.layout = saved_layout
	studio.queue_free()
	await t.get_tree().process_frame


# --- D and E: the routing bay's meters and its skyline ---------------------------------------------

## The bay's pin with track `src`'s row and `dst`'s column, and that row's empty crossing into `cold`.
static func _sockets_of(m: PinMatrix, row: int) -> Array:
	var out: Array = []
	for pin in m.pins():
		if pin.r == row and not pin.cell().get("on", false) and not pin.cell().get("blocked", false) \
				and not pin.cell().get("pending", false):
			out.append(pin)
	return out


## Always on: a row's header meters its track after the fader, with a clip light held and said in
## words; a hot row's empty sockets glow; a column's meter adds what its sends bring in and goes over
## 0 dBFS where no one send does, said so; a patched pin carrying nothing is dull and says why; on
## the stand-in (as on Reaper) a send's level is an estimate, marked ≈. Only what the window shows
## is read, and nothing is made for it.
func bay_meters_always_on() -> void:
	var bay: PatchbaySurface = t._bay()
	var m := bay.matrix
	var s := DAW.state
	s.playing = true
	for i in s.tracks:
		s.track(i).vu_l = FaderLaw.to_taper(-30.0)
		s.track(i).vu_r = FaderLaw.to_taper(-30.0)
	# What sends into the return, at 0 dB each.
	var into: Array = []
	for i in s.track_indices():
		for k in bay._sends_between(i, 13):
			s.send(i, k).volume = FaderLaw.to_taper(0.0)
			into.append(i)
	check("the stand-in's return has sends into it (%s)" % [into], into.size() >= 3)
	m._read_meters(0.05, 1.0)
	var rows := m.row_count()
	var made_before := m.get_child_count()
	var kick := m.line_for(into[0], true)
	var kick_row := kick.index
	check("a row header has its meter (%s)" % kick.readout(), kick.readout().contains("peak −30.0 dBFS"))
	check("no clip, no light", not m.clip_lit(into[0], true) and not m.row_hot(kick_row))
	var cold_bore: Color = m._sockets.colour_of((_sockets_of(m, kick_row)[0] as PinMatrix.Pin).slot)
	s.track(into[0]).vu_l = FaderLaw.to_taper(1.5)
	m._read_meters(0.05, 1.0)
	check("past 0 dBFS the light holds (%s)" % kick.readout(), m.clip_lit(into[0], true) and kick.readout().contains("CLIPPED +1.5 dB"))
	check("and the row is hot", m.row_hot(kick_row))
	var warm: Color = m._sockets.colour_of((_sockets_of(m, kick_row)[0] as PinMatrix.Pin).slot)
	check("its empty sockets glow, faintly (%s over %s)" % [warm, cold_bore], warm.r > cold_bore.r + 0.1 and warm.r < 0.8)
	s.track(into[0]).vu_l = FaderLaw.to_taper(-30.0)
	m._read_meters(0.05, 1.0)
	check("a clip is still said a moment later", m.clip_lit(into[0], true))
	check("the meter falls after a peak, it does not drop", float(m._row_level[into[0]][0]) > -29.0)
	# The column: four sends of −4 dBFS, none hot, add to +8.
	for i in into:
		s.track(i).vu_l = FaderLaw.to_taper(-4.0)
		s.track(i).vu_r = FaderLaw.to_taper(-4.0)
	m._read_meters(0.05, 1.0)
	var ret := m.line_for(13, false)
	check("a column meters what arrives, added (%s)" % ret.readout(), ret.readout().contains("arriving, peaks added, ≈ +"))
	check("over 0 dBFS together goes red, though no one send is, in words",
			m.clip_lit(13, false) and ret.readout().contains("OVER 0 dBFS TOGETHER") and ret.readout().contains("though no one send is"))
	var pin := m.pin_for(into[0], 13)
	check("a send's card: its level, then what it carries, ≈ for an estimate (%s)" % pin.readout(),
			pin.readout().begins_with("0.0 dB send · peaking ≈ −4.0 dBFS"))
	m._pulse(0.0)
	var lit_head := m._heads.colour_of(pin.slot).v
	s.track(into[0]).mute = true
	m._pulse(0.0)
	check("a patched send carrying nothing is dull (%.2f under %.2f)" % [m._heads.colour_of(pin.slot).v, lit_head],
			m._heads.colour_of(pin.slot).v < lit_head * 0.4)
	check("and says so, and why (%s)" % pin.readout(), pin.readout().contains("patched · no signal: %s: muted" % s.track(into[0]).display_name().to_upper()))
	s.track(into[0]).mute = false
	s.playing = false
	for i in s.tracks:
		s.track(i).vu_l = 0.0
		s.track(i).vu_r = 0.0
	bay._why_graph = null
	check("stopped, it says the transport (%s)" % pin.readout(), pin.readout().contains("the transport is stopped"))
	for i in 5:
		m._read_meters(1.0 / PinMatrix.METER_HZ, 1.0)
	check("reading the meters makes nothing (%d children, %d before)" % [m.get_child_count(), made_before],
			m.get_child_count() == made_before and m.row_count() == rows)
	# A measured send: the built-in engine's meter_sends, no ≈.
	var t3 := s.track(into[0])
	var n := 0
	for k in t3.sends:
		n += 1
	t3.meter_sends = PackedFloat32Array()
	t3.meter_sends.resize(n)
	t3.meter_sends.fill(-9.0)
	check("a measured send says its figure plainly (%s)" % pin.readout(), pin.readout().contains("peaking −9.0 dBFS")
			and not pin.readout().contains("≈"))
	t3.meter_sends = PackedFloat32Array()
	bay.queue_free()


## With the glasses on the bay is a skyline: every send a tower its level tall, a column's arrival a
## tower on its header, amber and red tops with their figures, still at motion 0 between readings;
## the card reads "KICK → BASS DI · −6.0 dB send · peaking −3.1 dBFS"; a tower's top dragged up
## sets its send's level, one undo step a drag, and a guest's drag is the host's to carry out; the
## glasses off, the towers go. The studio stands the bay up when the view is on.
func bay_skyline() -> void:
	var bay: PatchbaySurface = t._bay()
	var m := bay.matrix
	var s := DAW.state
	s.playing = true
	var into: Array = []
	for i in s.track_indices():
		for k in bay._sends_between(i, 13):
			s.send(i, k).volume = FaderLaw.to_taper(-6.0)
			into.append(i)
	for i in s.tracks:
		s.track(i).vu_l = FaderLaw.to_taper(-12.0)
		s.track(i).vu_r = FaderLaw.to_taper(-12.0)
	m._read_meters(0.05, 1.0)
	check("no glasses, no towers", m.tower_height(m.pin_for(into[0], 13).r, m.pin_for(into[0], 13).c) == 0.0)
	m.skyline = true
	m._read_meters(0.05, 1.0)
	var a := m.pin_for(into[0], 13)
	var b := m.pin_for(into[1], 13)
	var quiet := m.tower_height(a.r, a.c)
	check("a send stands up as a tower (%.3f m)" % quiet, quiet > 0.05)
	close_to("as tall as what it carries, −18 dBFS on the dB scale", quiet, PinMatrix.level_share(-18.0) * m.tower_max, 0.002)
	s.track(into[0]).vu_l = FaderLaw.to_taper(4.0)
	m._read_meters(0.05, 1.0)
	m._read_meters(0.5, 1.0)
	check("louder is taller (%.3f > %.3f)" % [m.tower_height(a.r, a.c), m.tower_height(b.r, b.c)], m.tower_height(a.r, a.c) > m.tower_height(b.r, b.c) + 0.02)
	check("its top near 0 dBFS amber, with its figure (%s)" % [m.tags_shown], m.tags_shown.any(func(w: String) -> bool: return w == "≈ −2.0 dBFS"))
	s.track(into[0]).vu_l = FaderLaw.to_taper(9.0)
	for i in 4:
		m._read_meters(0.5, 1.0)
	check("past 0 dBFS red, '+x dB' (%s)" % [m.tags_shown], m.tags_shown.any(func(w: String) -> bool: return w == "≈ +3.0 dB"))
	var flat := 0
	var shown_tags := 0
	for tag: Label3D in m._tags:
		if tag.visible:
			shown_tags += 1
			if tag.billboard == BaseMaterial3D.BILLBOARD_DISABLED and not tag.no_depth_test and tag.position.z < 0.01:
				flat += 1
	check("a tag lies flat on the board, not turned to the eye nor drawn over what is nearer (%d of %d)" % [flat, shown_tags],
			shown_tags > 0 and flat == shown_tags)
	var sum_k := (m.pins().size() + m._col_lines.find(m.line_for(13, false))) * 2
	check("the column's arrival is a tower on its header", m._towers.transform_of(sum_k).basis.get_scale().z > 0.05)
	s.track(into[0]).vu_l = FaderLaw.to_taper(9.0)
	m._read_meters(0.05, 0.0)
	s.track(into[0]).vu_l = FaderLaw.to_taper(-12.0)
	var still := m.tower_height(a.r, a.c)
	m._read_meters(0.05, 0.0)
	m._read_meters(0.05, 0.0)
	check("at motion 0 a tower stands still between readings", is_equal_approx(m.tower_height(a.r, a.c), still))
	for i in 25:
		m._read_meters(0.05, 0.0)
	check("and moves once a second (%.3f)" % m.tower_height(a.r, a.c), m.tower_height(a.r, a.c) < still - 0.02)
	var top := m.tower_for(into[0], 13)
	check("its top is a control", top != null and top.collision_layer == 2)
	var name := "%s  →  %s" % [s.track(into[0]).display_name().to_upper(), s.track(13).display_name().to_upper()]
	check("its card reads 'KICK → BASS DI · −6.0 dB send · peaking …' (%s · %s)" % [top.title(), top.readout()],
			top.title() == name and top.readout().begins_with("−6.0 dB send · peaking ≈ −18.0 dBFS"))
	check("and says how to work it (%s)" % top.hint(), top.hint().contains("drag the top up or down"))
	var depth := maxi(s.undo_depth, 0)
	var hand := Node3D.new()
	t.add_child(hand)
	var from := top.global_position
	var up := m.global_basis.y.normalized()
	top.grab_begin(hand, from)
	for i in 6:
		top.grab_move(hand, from + up * (0.01 * (i + 1)))
	top.grab_end(hand)
	var after := FaderLaw.to_db(s.send(into[0], bay._sends_between(into[0], 13)[0]).volume)
	check("dragged up, the send comes up (%.1f dB)" % after, after > -6.0 + 2.0)
	check("one undo step for the drag (%d → %d)" % [depth, s.undo_depth], s.undo_depth == depth + 1)
	DAW.undo()
	close_to("and Ctrl-Z puts it back", FaderLaw.to_db(s.send(into[0], bay._sends_between(into[0], 13)[0]).volume), -6.0, 0.05)
	check("a still press and let go pulls the pin, as a crossing's press", true)
	t._as_session(Session.Role.GUEST, 5)
	Session.keep_intents = true
	Session.kept_intents.clear()
	top = m.tower_for(into[0], 13)
	top.grab_begin(hand, from)
	top.grab_move(hand, from + up * 0.05)
	top.grab_end(hand)
	var verbs: Array = Session.kept_intents.map(func(c): return c[0])
	check("a guest's drag asks the host, as one edit (%s)" % [verbs], verbs.size() >= 3 and verbs[0] == &"open_edit"
			and verbs.has(&"set_send_volume") and verbs[-1] == &"close_edit")
	Session.keep_intents = false
	Session.start_solo()
	hand.queue_free()
	m.skyline = false
	m._read_meters(0.05, 1.0)
	check("the glasses off, the towers go", m.tower_height(a.r, a.c) == 0.0 and m.tower_for(into[0], 13) == null)
	bay.queue_free()


## `seconds` of a stereo sine at `hz`, its peak `db` dBFS, the right channel times `right`.
static func _sine(seconds: float, hz: float, db: float, right := 1.0, rate := 48000.0) -> PackedVector2Array:
	var frames := PackedVector2Array()
	frames.resize(int(seconds * rate))
	var a := pow(10.0, db / 20.0)
	for i in frames.size():
		var v := a * sin(TAU * hz * i / rate)
		frames[i] = Vector2(v, v * right)
	return frames


## LEVELS' loudness (slice 66): BS.1770 as EBU Tech 3341 tests it. A 1 kHz stereo sine at −23 dBFS
## reads −23 LUFS momentary, short-term and integrated; silence after it is gated out of the
## integrated; the true peak is the sine's; the phase is +1 for one signal in both channels and −1
## for one inverted; and the loudness rides the wire to a guest, or says it was not measured.
func loudness_meter_measures_bs1770() -> void:
	var meter := LoudnessMeter.new()
	meter.set_rate(48000.0)
	meter.feed(_sine(6.0, 1000.0, -23.0))
	close_to("a −23 dBFS 1 kHz stereo sine is −23 LUFS integrated (%.2f)" % meter.integrated, meter.integrated, -23.0, 0.1)
	close_to("and short-term (%.2f)" % meter.short_term, meter.short_term, -23.0, 0.1)
	close_to("and momentary (%.2f)" % meter.momentary, meter.momentary, -23.0, 0.1)
	close_to("its true peak is the sine's (%.2f dBTP)" % meter.true_peak_db, meter.true_peak_db, -23.0, 0.2)
	close_to("in phase, the correlation is +1 (%.2f)" % meter.correlation, meter.correlation, 1.0, 0.01)
	meter.feed(_sine(4.0, 1000.0, -120.0))
	close_to("silence after it is gated out of the integrated (%.2f)" % meter.integrated, meter.integrated, -23.0, 0.15)
	check("while the short-term falls away (%s)" % LoudnessMeter.words(meter.short_term), meter.short_term < -60.0 or not is_finite(meter.short_term))
	meter.reset()
	check("RESET starts it again", not is_finite(meter.integrated) and meter.seconds == 0.0)
	meter.feed(_sine(1.0, 1000.0, -20.0, -1.0))
	close_to("one channel inverted, the correlation is −1 (%.2f)" % meter.correlation, meter.correlation, -1.0, 0.01)
	check("and LEVELS says in words that mono cancels it (%s)" % LevelsWall.phase_verdict(meter.correlation),
			LevelsWall.phase_verdict(meter.correlation).contains("OUT OF PHASE: in mono it cancels"))
	check("one in both is mono-safe", LevelsWall.phase_verdict(1.0).ends_with("MONO-SAFE"))
	meter.reset()
	meter.set_rate(44100.0)
	meter.feed(_sine(3.0, 1000.0, -23.0, 1.0, 44100.0))
	close_to("at 44.1 kHz too (%.2f)" % meter.integrated, meter.integrated, -23.0, 0.1)
	check("LUFS in words", LoudnessMeter.words(-14.04) == "−14.0 LUFS")

	var backend := _offline()
	var s := DAW.state
	check("the built-in engine measures loudness, the stand-in does not", GodotBackend.new().measures_loudness() and not backend.measures_loudness())
	check("the master's loudness is volatile", backend.is_volatile("/master/vu/loudness"))
	var m := s.master
	m.loudness_measured = true
	m.lufs_m = -12.5
	m.lufs_s = -13.25
	m.lufs_i = -14.5
	m.true_peak_db = -0.4
	m.true_peak_recent_db = -1.2
	m.correlation = 0.42
	m.loudness_seconds = 63.0
	var guest := MixState.new()
	MixWire.apply_replicated(guest, [["/master/vu/loudness", MixWire.pack_loudness(m)]])
	var g := guest.master
	check("the loudness rides the wire to a guest", g.loudness_measured and is_equal_approx(g.lufs_s, -13.25)
			and is_equal_approx(g.lufs_i, -14.5) and is_equal_approx(g.true_peak_db, -0.4) and is_equal_approx(g.correlation, 0.42)
			and is_equal_approx(g.loudness_seconds, 63.0))
	m.loudness_measured = false
	MixWire.apply_replicated(guest, [["/master/vu/loudness", MixWire.pack_loudness(m)]])
	check("and its host's 'not measured' too", not guest.master.loudness_measured)
	t._as_session(Session.Role.GUEST, 5)
	Session.keep_intents = true
	Session.kept_intents.clear()
	DAW.reset_loudness()
	check("a guest's RESET asks the host", Session.kept_intents.map(func(c): return c[0]).has(&"reset_loudness"))
	Session.keep_intents = false
	Session.start_solo()


## A LEVELS wall on its own over the stand-in's tracks, read now.
func _levels(tracks := 13) -> LevelsWall:
	var offline := OfflineBackend.new()
	offline.track_count = tracks
	DAW.use(offline)
	var wall := LevelsWall.new()
	wall.wanted = func() -> bool: return true
	t.add_child(wall)
	wall._process(0.0)
	return wall


## LEVELS (slice 66): a column a track against fixed lines, the peak held as a tick and a number,
## red over 0; gain reduction pushing it down from the top, lettered; a column dragged is the
## track's fader, one undo step, a guest's an intent; the wheel; the window scrolls a big session;
## the master's loudness against the target in words, true peak and phase; on Reaper, said not
## measured; motion 0 moves it once a second.
func levels_wall_reads_every_track() -> void:
	var wall := _levels()
	var s := DAW.state
	check("a column a track (%d)" % wall.columns.size(), wall.columns.size() == s.track_indices().size())
	check("every column a control", wall.columns.all(func(c): return c.collision_layer == 2))
	check("the lines at −18, −6 and 0 dBFS, lettered", wall.find_children("*", "Label3D", true, false).any(
			func(l): return (l as Label3D).text == "−18 dBFS") and wall.find_children("*", "Label3D", true, false).any(
			func(l): return (l as Label3D).text == "0 dBFS"))
	s.playing = true
	for i in s.tracks:
		s.track(i).vu_l = FaderLaw.to_taper(-30.0)
		s.track(i).vu_r = FaderLaw.to_taper(-30.0)
	var c0: LevelsWall.Column = wall.columns[0]
	var c1: LevelsWall.Column = wall.columns[1]
	var one := c0.track
	s.track(one).vu_l = FaderLaw.to_taper(-6.0)
	wall._words_clock = 1000.0
	wall.read(0.05)
	var fill := wall._bank.transform_of(0 * 5 + 1)
	close_to("a column's top is its peak on the scale", fill.origin.y + fill.basis.get_scale().y * 0.5, LevelsWall.y_of(-6.0), 0.002)
	check("its held peak over it in figures (%s)" % wall._numbers[0].text, wall._numbers[0].text == "−6.0")
	check("its name under it (%s)" % wall._names[0].text, wall._names[0].text == LevelsWall.title_of(one))
	s.track(one).vu_l = FaderLaw.to_taper(-30.0)
	wall.read(0.5)
	var fallen := wall._bank.transform_of(1)
	check("it falls after the peak", fallen.origin.y + fallen.basis.get_scale().y * 0.5 < LevelsWall.y_of(-6.0) - 0.01)
	wall._words_clock = 1000.0
	wall.read(0.05)
	check("while the held peak holds", wall._numbers[0].text == "−6.0")
	s.track(one).vu_l = FaderLaw.to_taper(2.5)
	wall._words_clock = 1000.0
	wall.read(0.05)
	check("over 0 dBFS the figure says +2.5, in red (%s)" % wall._numbers[0].text, wall._numbers[0].text == "+2.5"
			and wall._numbers[0].modulate.r > 0.9 and wall._numbers[0].modulate.g < 0.6)
	check("and its card says CLIPPING (%s)" % c0.readout(), c0.readout().contains("CLIPPING"))
	s.track(c1.track).meter_gr = PackedFloat32Array([-4.0, NAN])
	wall._words_clock = 1000.0
	wall.read(0.05)
	var gr := wall._bank.transform_of(1 * 5 + 3)
	close_to("a compressor's gain reduction hangs from the top, its dB long", gr.basis.get_scale().y, 4.0 / LevelsWall.db_per_m(), 0.001)
	close_to("from the top of the scale", gr.origin.y + gr.basis.get_scale().y * 0.5, LevelsWall.scale_foot() + LevelsWall.scale_tall(), 0.001)
	check("lettered (%s)" % wall._grs[1].text, wall._grs[1].visible and wall._grs[1].text == "GR −4.0")
	check("and on its card", c1.readout().contains("GR −4.0 dB"))
	check("its card says how to work it (%s)" % c1.hint(), c1.hint().contains("drag up or down"))

	var t1 := s.track(c1.track)
	t1.volume = FaderLaw.to_taper(-6.0)
	var depth := maxi(s.undo_depth, 0)
	var hand := Node3D.new()
	t.add_child(hand)
	var from := c1.global_position
	var up := wall.global_basis.y.normalized()
	c1.grab_begin(hand, from)
	for i in 5:
		c1.grab_move(hand, from + up * (0.02 * (i + 1)))
	c1.grab_end(hand)
	close_to("dragged up 10 cm, the fader comes up by the scale's dB (%.1f)" % FaderLaw.to_db(t1.volume),
			FaderLaw.to_db(t1.volume), -6.0 + 0.1 * LevelsWall.db_per_m(), 0.15)
	check("one undo step for the drag (%d → %d)" % [depth, s.undo_depth], s.undo_depth == depth + 1)
	DAW.undo()
	close_to("and Ctrl-Z puts it back", FaderLaw.to_db(t1.volume), -6.0, 0.05)
	c1.nudge(hand, 1, false)
	close_to("a wheel notch is 0.5 dB", FaderLaw.to_db(t1.volume), -5.5, 0.05)
	c1.nudge(hand, -1, true)
	close_to("Shift's 0.1", FaderLaw.to_db(t1.volume), -5.6, 0.05)
	t._as_session(Session.Role.GUEST, 5)
	Session.keep_intents = true
	Session.kept_intents.clear()
	c1.grab_begin(hand, from)
	c1.grab_move(hand, from + up * 0.05)
	c1.grab_end(hand)
	var verbs: Array = Session.kept_intents.map(func(c): return c[0])
	check("a guest's drag asks the host, as one edit (%s)" % [verbs], verbs.size() >= 3 and verbs[0] == &"open_edit"
			and verbs.has(&"set_track_volume") and verbs[-1] == &"close_edit")
	Session.keep_intents = false
	Session.start_solo()
	hand.queue_free()

	var m := s.master
	m.loudness_measured = false
	wall._words_clock = 1000.0
	wall.read(0.05)
	check("no loudness measured, it says so (%s / %s)" % [wall.short_words, wall.phase_words],
			wall.short_words == "LOUDNESS NOT MEASURED" and wall.phase_words.contains("not measured"))
	m.loudness_measured = true
	m.lufs_s = -12.0
	m.lufs_i = -13.0
	m.lufs_m = -11.0
	m.true_peak_recent_db = 0.6
	m.true_peak_db = 0.6
	m.correlation = -0.6
	wall._words_clock = 1000.0
	wall.read(0.05)
	check("short-term LUFS (%s)" % wall.short_words, wall.short_words == "SHORT-TERM −12.0 LUFS")
	check("integrated and momentary (%s)" % wall.integrated_words, wall.integrated_words.begins_with("INTEGRATED −13.0 LUFS · MOMENTARY −11.0 LUFS"))
	check("against the target in words (%s)" % wall.verdict_words, wall.verdict_words == "+2.0 LU OVER STREAMING −14")
	check("the true peak over 0, said (%s)" % wall.peak_words, wall.peak_words.begins_with("TRUE PEAK ≈ +0.6 dBTP") and wall.peak_words.contains("IT CLIPS"))
	check("the phase out, said (%s)" % wall.phase_words, wall.phase_words.contains("OUT OF PHASE"))
	wall._target_key.pressed.emit()
	check("TARGET steps to club (%s)" % wall.verdict_words, wall.verdict_words == "4.0 LU UNDER CLUB −8")
	wall._target_key.pressed.emit()
	wall._target_key.pressed.emit()
	wall._target_key._on_nudge(4, false)
	check("the wheel sets a custom target (%s)" % wall.target_name(), wall.target_name() == "CUSTOM −14.0")
	m.lufs_s = -14.4
	wall._words_clock = 1000.0
	wall.read(0.05)
	check("within a LU it is on target (%s)" % wall.verdict_words, wall.verdict_words.begins_with("ON TARGET"))
	wall.target = 0
	wall.queue_free()

	var big := _levels(40)
	check("a big session scrolls (%d of 40 shown)" % big.columns.size(), big.columns.size() == 16)
	check("the foot says which (%s)" % big._foot.text, big._foot.text.begins_with("TRACKS 1-16 OF 40"))
	check("the wheel over the names scrolls", big._names_strip._on_nudge(-1, false) and big.first == 3)
	big._right_key.pressed.emit()
	check("▶ moves on (%d)" % big.first, big.first == 18)
	big._words_clock = 1000.0
	big.read(0.0)
	check("and the columns are those tracks (%s)" % big._names[0].text, big._names[0].text == LevelsWall.title_of(DAW.state.track_indices()[18]))
	big.motion = func() -> float: return 0.0
	var k: int = DAW.state.track_indices()[18]
	DAW.state.track(k).vu_l = FaderLaw.to_taper(-3.0)
	var before := big._bank.transform_of(1)
	big._process(0.05)
	check("at motion 0 it stands still between seconds", big._bank.transform_of(1).is_equal_approx(before))
	for i in 25:
		big._process(0.05)
	check("and moves once a second", not big._bank.transform_of(1).is_equal_approx(before))
	big.queue_free()


## Look to solo (slice 67), the solo itself: held, the track looked at alone -- every other solo
## let go, its mute lifted -- following the look once it rests; let go, every solo and mute exactly
## as they were, in one history step that changes nothing; a grouped track's mates left alone.
func look_solo_puts_everything_back() -> void:
	_offline()
	var s := DAW.state
	s.track(2).solo = true
	s.track(9).solo = true
	s.track(6).mute = true
	s.track(7).mute = true
	var before := {}
	for i in s.track_indices():
		before[i] = [s.track(i).solo, s.track(i).mute]
	var depth := maxi(s.undo_depth, 0)
	var ls := LookSolo.new()
	var said := ls.press(6)
	check("held over BASS DI, it is soloed alone (%s)" % said, s.track(6).solo and not s.track(2).solo and not s.track(9).solo
			and said.begins_with("BASS DI alone while held"))
	check("its mute lifted, so it is heard", not s.track(6).mute)
	check("another's mute left as it was", s.track(7).mute)
	ls.look(7, 0.1)
	check("a glance at another track does not move it", s.track(6).solo and not s.track(7).solo)
	said = ls.look(7, 0.25)
	check("a look that rests moves it (%s)" % said, s.track(7).solo and not s.track(7).mute and not s.track(6).solo
			and s.track(6).mute and said.begins_with("RHODES alone now"))
	said = ls.release()
	var same := true
	for i in s.track_indices():
		same = same and before[i] == [s.track(i).solo, s.track(i).mute]
	check("let go, every solo and mute exactly as it was (%s)" % said, same and said.contains("as it was"))
	check("one history step (%d → %d)" % [depth, s.undo_depth], s.undo_depth == depth + 1)
	DAW.undo()
	same = true
	for i in s.track_indices():
		same = same and before[i] == [s.track(i).solo, s.track(i).mute]
	check("which, undone, changes nothing", same)
	DAW.state.track(6).group = 1
	DAW.state.track(8).group = 1
	ls.press(6)
	check("a grouped track's mates are not soloed with it", s.track(6).solo and not s.track(8).solo)
	ls.release()
	check("pressed at nothing it solos nothing, and lets go cleanly", ls.press(0).begins_with("Look to solo: look at a track")
			and s.track(2).solo and ls.release() == "" and s.track(2).solo and s.track(9).solo)
	DAW.state.track(6).group = 0
	DAW.state.track(8).group = 0


## Look to solo in the studio (slice 67): U needs the view on and says so; with it on, U held over a
## strip solos its track and let go puts it back; focus lost lets go; a guest's is the room verb, run
## by the host for them, one at a time, and their leaving lets it go.
func look_solo_in_the_studio() -> void:
	var saved_layout := Session.layout
	Session.layout = LayoutProfile.new()
	Session.layout.save_path = "user://test_layout_profile.cfg"
	_offline()
	Session.start_solo()
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	t.add_child(studio)
	await t.get_tree().process_frame
	await t.get_tree().physics_frame
	var s := DAW.state
	var said: Array = []
	var listen := func(text: String) -> void: said.append(text)
	Session.notice.connect(listen)
	var key := InputEventKey.new()
	key.keycode = KEY_U
	key.pressed = true
	studio.signal_key_on = false
	studio._unhandled_input(key)
	check("U without the view says what it needs (%s)" % [said], said.size() == 1 and said[0].begins_with("Look to solo needs the signal view on")
			and not studio.look_solo.held)
	studio.signal_key_on = true
	var strip: ChannelStrip = studio.console.strips[1] if studio.console.strips.size() > 1 else null
	var k := strip.track_index if strip != null else 0
	var other := 7 if k != 7 else 8
	var third := 6 if k != 6 else 8
	var pre := 12 if k != 12 else 11
	var hand := studio.get_node_or_null("MouseHand") as Interactor
	var control: ControlAffordance = null
	if strip != null:
		for n in strip.find_children("*", "", true, false):
			if n is ControlAffordance:
				control = n
				break
	check("a strip to look at (%s, %s, %s)" % [strip, control, hand], control != null and hand != null)
	hand.hovered = control
	check("what is looked at is that strip's track (%d)" % k, k > 0 and k != pre and studio.looked_track() == k)
	s.track(pre).solo = true
	said.clear()
	studio._unhandled_input(key)
	check("U held over it solos it alone (%s)" % [said], studio.look_solo.held and s.track(k).solo and not s.track(pre).solo
			and said.size() == 1 and said[0].begins_with("%s alone" % LookSolo._title(k)))
	studio._follow_signal(0.016)
	check("meanwhile the view signs no SOLOED OUT on every other track", studio.signal_view.quiet.has(SignalGraph.SOLOED_OUT))
	var up := InputEventKey.new()
	up.keycode = KEY_U
	up.pressed = false
	studio._unhandled_input(up)
	check("let go, it is as it was", not studio.look_solo.held and not s.track(k).solo and s.track(pre).solo)
	studio._unhandled_input(key)
	studio._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check("the window losing focus lets go", not studio.look_solo.held and not s.track(k).solo and s.track(pre).solo)
	studio._unhandled_input(key)
	studio.signal_key_on = false
	studio._process(0.016)
	check("the view going off lets go", not studio.look_solo.held and s.track(pre).solo)
	studio._unhandled_input(up)
	studio.signal_key_on = true
	check("a guest's look-solo is a room verb", Session.room_ask_is_valid(&"look_solo", [6, true]))
	studio._on_room_asked(&"look_solo", [other, true], 5)
	check("the host runs it for the guest", s.track(other).solo and not s.track(pre).solo)
	said.clear()
	studio._unhandled_input(key)
	check("one at a time: the host's own is refused and told why (%s)" % [said], not studio.look_solo.held
			and said.size() == 1 and said[0].contains("one at a time"))
	studio._unhandled_input(up)
	studio._on_room_asked(&"look_solo", [third, true], 5)
	check("the guest's follows their look", s.track(third).solo and not s.track(other).solo)
	Session.participant_left.emit(5)
	check("and the guest leaving lets it go", not s.track(third).solo and not s.track(other).solo and s.track(pre).solo
			and studio.guest_look_solos.is_empty())
	studio._on_room_asked(&"look_solo", [6, true], 5)
	studio._on_room_asked(&"look_solo", [0, false], 5)
	check("as their let-go does", not s.track(6).solo and s.track(pre).solo)
	s.track(pre).solo = false
	Session.notice.disconnect(listen)
	studio.queue_free()
	await t.get_tree().process_frame
	Session.layout = saved_layout
	_offline()


## The AUDIO DEVICES wall's levels (slice 65): PipeWire reports none, so only dawlings's own
## streams are metered, by the bus each plays, and every other port says it is not measured.
func patch_wall_meters_its_own_streams() -> void:
	_offline()
	AudioPorts.ensure_buses()
	var wall := PatchWallSurface.new()
	check("dawlings's own mix stream is metered, by its bus", wall.metered("dawlings_mix:output_FL")
			and wall.port_level("dawlings_mix:output_FR").z == SignalGraph.MEASURED)
	check("and the app's own output, by the master bus", wall.metered("Godot Engine:output_FL"))
	check("a sound card's port is not (%s)" % [wall.port_level("alsa_output.pci:playback_FL")],
			not wall.metered("alsa_output.pci:playback_FL") and wall.port_level("alsa_output.pci:playback_FL").z == SignalGraph.UNKNOWN)
	check("a port's side is read off its name", PatchWallSurface._side_of("output_FL") == -1
			and PatchWallSurface._side_of("playback_FR") == 1 and PatchWallSurface._side_of("monitor") == 0)
	wall.free()
