class_name SessionProbeItems
extends RefCounted

## The rest of the room's checks: jacks worn, chords driven, spectra heard, the carved clash, the drum and the djembe
## struck, the railing, the weather and the looper.
## Moved out of `tools/probe/session_probe.gd` without change of behaviour; the state stays on the probe node, which keeps a one-line delegate for each name another file or a string reaches.

var probe: SessionProbe


func _init(of: SessionProbe) -> void:
	probe = of


## Clips as cassettes (slice 23): at 58.86 I pull PULL_TRACK's first clip, as the studio's pull asks;
## by 58.97 the host has minted it and handed me one of its own, and both are in my glove: their
## rows here, the holds mine, and the room naming them made real.
func _pull_a_cassette() -> void:
	await _until(58.86)
	var seq := Session.ask_room(&"make", [CassetteItem.KIND, SessionProbe.PULL_FROM])
	check("my pull is asked of the host (seq %d)" % seq, seq > 0)
	await _until(58.97)
	probe._room.apply_made(Session.room.get("made", []))
	for id: StringName in [&"cassette1", &"cassette2"]:
		var item := probe._room.items.get(id) as CassetteItem
		check("%s's row reached me before the room named it (%s)" % [id, Session.made.keys()], Session.made.has(id))
		check("and it is real here, carrying its clip (%s)" % (item.clip_name() if item != null else "none"),
				item != null and not item.clip.is_empty() and item.length() > 0.0)
		check("in my glove: the host's table says so (%d)" % [Session.holder_of(item.network_key()) if item != null else -1],
				item != null and Session.holder_of(item.network_key()) == Session.local_peer_id)
	var pulled := probe._room.items.get(&"cassette1") as CassetteItem
	check("the one I pulled is the host's clip from track %d" % SessionProbe.PULL_TRACK,
			pulled != null and pulled.from_track == SessionProbe.PULL_TRACK and pulled.from_index == 0)


## A cassette onto a track (slice 24): at 58.99 I paste the cassette the host gave me (cassette2) onto
## PASTE_TRACK at PASTE_BAR, as the studio's press asks: its id, the track and the time, never the
## clip. By 59.08 the host's mix has given me the item there, the clip it was but for its start.
func _paste_a_cassette() -> void:
	await _until(58.99)
	var at := DAW.state.bar_to_seconds(SessionProbe.PASTE_BAR)
	var cassette := probe._room.items.get(&"cassette2") as CassetteItem
	var seq := Session.ask_room(&"paste", [&"cassette2", SessionProbe.PASTE_TRACK, at])
	check("my paste of the host's cassette is asked by its id, track and time (seq %d)" % seq, seq > 0 and cassette != null)
	await _until(59.08)
	if probe._reaper_host and cassette != null and cassette.clip.has("part"):
		check("on Reaper the host refused my demo part, and said why (%s)" % [probe._notices.slice(-3)],
				probe._notices.any(func(t): return str(t).contains("built-in engine")))
		return
	var it: MixState.ItemState = null
	for item: MixState.ItemState in DAW.state.track(SessionProbe.PASTE_TRACK).items:
		if absf(item.start - at) < 0.001:
			it = item
	check("the host's mix gives me it on track %d at bar %d (%s)" % [SessionProbe.PASTE_TRACK, int(SessionProbe.PASTE_BAR), it.name if it != null else "none"],
			it != null and cassette != null and it.name == cassette.clip_name()
			and is_equal_approx(it.length, cassette.length()))
	check("and the host told me (%s)" % [probe._notices.slice(-2)], probe._notices.any(func(t): return str(t) == "Pasted."))


## Jacks of this half's own, as the studio keeps them: what comes down a cable plays this half's
## keys, and is kept, as is what it played there.
func _wear_jacks() -> void:
	probe._jacks = Jacks.new()
	probe.add_child(probe._jacks)
	probe._jacks.keys = Session.guest_midi
	Session.jack_played.connect(probe._jacks.received)
	Session.jack_played.connect(func(source: StringName, kind: int, pitch: int, _v: int, from: int, song: float) -> void:
		probe._jacked.append([source, kind, pitch, from, song]))
	Session.guest_midi.note.connect(func(kind: int, pitch: int, _v: int, song: float, source: StringName) -> void:
		if source == Jacks.CABLE:
			probe._cabled.append([kind, pitch, song]))


## A clock to hear the song by (GuestMidi.heard_source): playing from `from_seconds` now, on.
func _given_clock(from_seconds: float, recording: bool) -> Callable:
	var t0 := Time.get_ticks_usec()
	return func() -> Dictionary:
		return {"seconds": from_seconds + (Time.get_ticks_usec() - t0) / 1e6, "playing": true,
				"recording": recording, "valid": true}


## A quarter second past the host's D minor marker.
func _ring_song() -> float:
	for t in DAW.state.markers:
		if str(DAW.state.markers[t]) == SessionProbe.KEY_MARKER:
			return float(t) + 0.25
	return -1.0


## Host: the guest's chord hand, plugged into me (part two, slice 33), holding IV of D minor: my
## chord hand takes Gm from them, and it plays Gm's tones.
func _check_chord_into_me(chords: ChordHand) -> void:
	var source := Jack.chord_source(probe.room_checks._other_id())
	var key := Harmony.at(DAW.state, DAW.state.position_seconds)
	check("the guest's chord hand is plugged into me (%s)" % [probe._jacks.patch],
			probe._jacks.sink_of(source) == Jack.player_sink(1))
	check("and its chord came down the jack: IV of D minor, Gm, from the guest (%s from %d)"
			% [chords.their_chord(key), chords.their_player()],
			chords.their_chord(key) == "Gm" and chords.their_player() == probe.room_checks._other_id() and chords.plays_theirs())


## Guest: my chord hand's jack into the host at 60.62, as P in the chord layer asks it; IV held at
## 60.66, sent down it as Jacks.send_chord does each frame; unplugged at 60.74.
func _drive_their_chord_hand() -> void:
	await _until(60.62)
	var chords := ChordHand.new()
	probe.add_child(chords)
	var mine := Jack.chord_source(Session.local_peer_id)
	Session.ask_room(&"plug", [mine, Jack.player_sink(1)])
	await _until(60.66)
	check("the host's room has my chord hand into the host (%s)" % [probe._jacks.patch], probe._jacks.sink_of(mine) == Jack.player_sink(1))
	chords.pick(3)
	var key := Harmony.at(DAW.state, chords.now())
	check("I hold IV, which in D minor is Gm (%s)" % chords.own_chord(chords.now()),
			chords.own_chord(chords.now()) == "Gm" and ChordHand.numeral_of(key, 3) == "iv")
	await _until(60.74)
	Session.ask_room(&"plug", [mine, &""])
	await _until(60.78)
	check("and unplugged it (%s)" % [probe._jacks.patch], probe._jacks.sink_of(mine) == &"")
	chords.queue_free()


## Guest: from 60.82 my ruler point at POINT_AT on the presence stream, as Presence.pointing_of says a
## time on the ruler, and a sticky note at NOTE_AT, as PointAndMark.add_note makes one: an add_marker
## intent. I stop pointing at 60.94.
func _point_and_note() -> void:
	await _until(60.82)
	probe._pointing = Presence.RULER_KEY + ("%.3f" % SessionProbe.POINT_AT)
	probe._pointing_local = Vector3.ZERO
	check("my sticky note is asked as a marker", PointAndMark.add_note(SessionProbe.NOTE_AT, SessionProbe.NOTE_WORDS))
	await _until(60.94)
	probe._pointing = ""


## Host: the guest's point, heard on the presence stream as the song time it means, and its note in
## my markers (slice 35).
func _check_point_and_note() -> void:
	var guest: Session.Participant = Session.participants.get(probe.room_checks._other_id())
	var said := guest.pointing_at if guest != null else ""
	check("the guest's ruler point arrived as the time it means (%s)" % said, said.begins_with(Presence.RULER_KEY)
			and absf(said.trim_prefix(Presence.RULER_KEY).to_float() - SessionProbe.POINT_AT) < 0.001)
	var at := DAWBackend.marker_key(DAW.state.markers, SessionProbe.NOTE_AT)
	check("and its sticky note is in my markers (%s)" % [DAW.state.markers.get(at, "-") if not is_nan(at) else "-"],
			not is_nan(at) and str(DAW.state.markers[at]) == Harmony.note_named(SessionProbe.NOTE_WORDS))


## The host's measure for the probe's spectra (slice 36): the kick's and the bass's bands, the rest
## of every track silent.
static func _probe_spectrum(track: int) -> PackedFloat32Array:
	var out := Spectra.silent()
	for spec in [[SessionProbe.SPECTRA_KICK, SessionProbe.SPECTRA_KICK_BANDS, SessionProbe.SPECTRA_KICK_DB], [SessionProbe.SPECTRA_BASS, SessionProbe.SPECTRA_BASS_BANDS, SessionProbe.SPECTRA_BASS_DB]]:
		if track == spec[0]:
			for i in range(spec[1][0], spec[1][1] + 1):
				out[i] = spec[2]
	return out


## Guest: by 61.1 the host's spectra are mine, as the wall reads them (a Spectra of my own, as the
## studio stands one): the kick's and the bass's bands within a byte's half step, and the two found
## clashing over the bands they share.
func _hear_the_spectra() -> void:
	await _until(61.1)
	var mine := Spectra.new()
	probe.add_child(mine)
	var shown := mine.latest()
	var step := (Spectra.TOP_DB - Spectra.FLOOR_DB) / 255.0
	var near := func(track: int, band: int, db: float) -> bool:
		return shown.has(track) and absf((shown[track] as PackedFloat32Array)[band] - db) <= step * 0.5 + 0.001
	check("the host's spectra reached me (%d tracks, %s)" % [shown.size(), mine.reason()],
			mine.reason() == "" and near.call(SessionProbe.SPECTRA_KICK, 5, SessionProbe.SPECTRA_KICK_DB) and near.call(SessionProbe.SPECTRA_BASS, 5, SessionProbe.SPECTRA_BASS_DB)
			and near.call(SessionProbe.SPECTRA_KICK, 0, Spectra.FLOOR_DB) and near.call(SessionProbe.SPECTRA_BASS, 8, SessionProbe.SPECTRA_BASS_DB))
	var clashes := Spectra.clashes(shown)
	check("and the kick and the bass clash where they meet (%s)" % [clashes],
			clashes.size() == 1 and clashes[0]["a"] == SessionProbe.SPECTRA_KICK and clashes[0]["b"] == SessionProbe.SPECTRA_BASS
			and clashes[0]["from"] == SessionProbe.SPECTRA_BASS_BANDS[0] and clashes[0]["to"] == SessionProbe.SPECTRA_KICK_BANDS[1])
	mine.queue_free()


## Guest: from 61.14 my own EQ wall over the probe's kick and bass, their glow clicked without a push
## (which asks for nothing), then grabbed on the bass's side and dragged CARVE_SHARE of a full push down, held until 61.22 so the host's EQ comes back to
## me while the push is still one edit; by 61.24 the host's mix gives the carve back to me.
func _carve_the_clash() -> void:
	await _until(61.14)
	var given := {SessionProbe.SPECTRA_KICK: _probe_spectrum(SessionProbe.SPECTRA_KICK), SessionProbe.SPECTRA_BASS: _probe_spectrum(SessionProbe.SPECTRA_BASS)}
	var wall := EqWall.new()
	wall.name = "CarveWall"
	wall.spectra = func() -> Dictionary: return given
	wall.reference = func() -> float: return 0.0
	probe.add_child(wall)
	wall._process(0.0)
	var glow: EqWall.Clash = wall.glows[0] if not wall.glows.is_empty() else null
	check("my wall lights the kick's and the bass's clash, the bass on its right (%s)" % [glow.clash if glow != null else {}],
			glow != null and glow.visible and glow.right_track() == SessionProbe.SPECTRA_BASS and EqCarve.choice() != "")
	if glow == null or not glow.visible:
		wall.queue_free()
		return
	var hand := Node.new()
	probe.add_child(hand)
	var mid := (EqWall.y_of_hz(Spectra.edges(glow.clash["from"]).x) + EqWall.y_of_hz(Spectra.edges(glow.clash["to"]).y)) * 0.5
	var at := Vector3(EqWall.middle_x() + 0.05, mid, 0.022)
	# A click first, as a desk does to see what a glow does: no push, so nothing asked for, and the
	# host's chain has only the push's EQ after (_check_carve), not a flat one of the click's too.
	glow.grab_begin(hand, wall.to_global(at))
	glow.grab_end(hand)
	check("a click on the glow with no push asks for no EQ", glow.push.is_empty() and not EqWall.Clash.asked_for(SessionProbe.SPECTRA_BASS))
	glow.grab_begin(hand, wall.to_global(at))
	glow.grab_move(hand, wall.to_global(at - Vector3(0, EqCarve.PUSH_FULL * SessionProbe.CARVE_SHARE, 0)))
	check("my push is on the bass (%s)" % glow.readout(), not glow.push.is_empty() and int(glow.push["track"]) == SessionProbe.SPECTRA_BASS)
	await _until(61.22)
	glow.grab_end(hand)
	await _until(61.24)
	var fx := EqCarve.carver_on(SessionProbe.SPECTRA_BASS)
	check("the host's mix gives my carve back to me: an EQ on the bass (%s)" % [DAW.state.fx(SessionProbe.SPECTRA_BASS, fx).name if fx >= 0 else "none"],
			fx >= 0)
	if fx >= 0 and EqCarve.engine() == &"built_in":
		var f := DAW.state.fx(SessionProbe.SPECTRA_BASS, fx)
		var bands := EqCarve.bands_for(SessionProbe.SPECTRA_BASS_BANDS[0], SessionProbe.SPECTRA_KICK_BANDS[1])
		var cut := bands.map(func(b: int) -> float: return EqCarve.eq21_db(float(f.params.get(b, 0.5))))
		check("its bands in the clash cut %.0f dB (%s)" % [SessionProbe.CARVE_DB, cut], cut.all(func(db: float) -> bool: return absf(db - SessionProbe.CARVE_DB) < 0.05))
	hand.queue_free()
	wall.queue_free()


## Host: the guest's carve (slice 37), as my DAW has it: an EQ at the end of the bass's chain, on the
## built-in engine its bands in the clash at CARVE_DB, as one step named for the carve, which one
## undo takes back. On Reaper the ReaEQ is taken away by hand; its band waits on its parameters'
## names, which the stand-in does not have, so only the built-in engine's cut is checked.
func _check_carve(chain_was: int, depth_was: int) -> void:
	var t := DAW.state.track(SessionProbe.SPECTRA_BASS)
	var fx := EqCarve.carver_on(SessionProbe.SPECTRA_BASS)
	check("the guest's push is an EQ at the end of my track %d's chain (%s, %s from %d)" % [SessionProbe.SPECTRA_BASS, DAW.state.fx(SessionProbe.SPECTRA_BASS, fx).name if fx >= 0 else "none", t.plugins(), chain_was],
			fx >= 0 and t.plugins().size() == chain_was + 1 and t.plugins()[-1] == fx)
	var from: int = SessionProbe.SPECTRA_BASS_BANDS[0]
	var to: int = SessionProbe.SPECTRA_KICK_BANDS[1]
	if fx >= 0 and EqCarve.engine() == &"built_in":
		var f := DAW.state.fx(SessionProbe.SPECTRA_BASS, fx)
		var bands := EqCarve.bands_for(from, to)
		var cut := bands.map(func(b: int) -> float: return EqCarve.eq21_db(float(f.params.get(b, 0.5))))
		var flat := range(21).filter(func(b: int) -> bool: return not bands.has(b)) \
				.all(func(b: int) -> bool: return is_equal_approx(EqCarve.eq21_db(float(f.params.get(b, 0.5))), 0.0))
		check("its bands in the clash cut %.0f dB, the rest flat (%s, %s)" % [SessionProbe.CARVE_DB, EqCarve.bands_words(bands), cut],
				cut.all(func(db: float) -> bool: return absf(db - SessionProbe.CARVE_DB) < 0.05) and flat)
		var engine := DAW.backend as GodotBackend
		if engine != null:
			var effect := AudioServer.get_bus_effect(engine._bus[SessionProbe.SPECTRA_BASS], 1 + fx) as AudioEffectEQ21
			check("an EQ21 on the bass's bus, cut there too", effect != null and absf(effect.get_band_gain_db(bands[0]) - SessionProbe.CARVE_DB) < 0.05)
	if probe._reaper_resource == "":
		var last: String = str(DAW.state.undo_names[DAW.state.undo_depth - 1]) if DAW.state.undo_depth > 0 else ""
		var named := "%s: carve %s" % [t.display_name(), Spectra.span_words(from, to)]
		check("as one step, called the carve (%s, %d after %d: %s)" % [last, DAW.state.undo_depth, depth_was, DAW.state.undo_names.slice(maxi(depth_was - 2, 0), DAW.state.undo_depth)], DAW.state.undo_depth == depth_was + 1 and last == named)
		DAW.undo()
		check("which one undo takes back whole", EqCarve.carver_on(SessionProbe.SPECTRA_BASS) == -1 and t.plugins().size() == chain_was)
	elif fx >= 0:
		DAW.remove_fx(SessionProbe.SPECTRA_BASS, fx)


## Guest: the test drum stood at DRUM_HOME by 61.28, as the host stands its own, and at 61.3 my
## fingertip down through its rim at DRUM_SPEED, as Strike reads a tracked hand, to DRUM_SONG: the
## slap, sent to the host as a hit by my room's `played` (Session.send_item_hit, with its zone).
func _strike_the_drum() -> void:
	await _until(61.28)
	var drum := probe._room.spawn(&"testdrum", &"testdrum", SessionProbe.DRUM_HOME) as TestDrumItem
	var strike := Strike.new()
	strike.set_physics_process(false)
	probe.add_child(strike)
	await _until(61.3)
	var clock := InstrumentItem.clock
	InstrumentItem.clock = func() -> float: return SessionProbe.DRUM_SONG
	var face: Dictionary = drum.faces()[0]
	var rim: Vector3 = (face["frame"] as Transform3D).origin + Vector3(TestDrumItem.HEAD_RADIUS * 0.9, 0, 0)
	var dt := 1.0 / 90.0
	for i in 6:
		strike.step({[&"probe", 0]: rim + Vector3.UP * (0.05 - i * SessionProbe.DRUM_SPEED * dt)}, dt)
	InstrumentItem.clock = clock
	check("my fingertip through the test drum's rim plays its slap (%s)" % drum.last_zone,
			drum.last_zone == &"slap" and drum.state == Item.State.HOME)
	# The djembe (slice 40), which my room has had put away since it was made: stood as the host
	# stands its own, and slapped at its rim at 61.32.
	probe._room.stand(&"djembe", SessionProbe.DJEMBE_HOME)
	var djembe := probe._room.items.get(&"djembe") as HandDrum
	await _until(61.32)
	InstrumentItem.clock = func() -> float: return SessionProbe.DJEMBE_SONG
	var head: Vector3 = (djembe.faces()[0]["frame"] as Transform3D).origin + Vector3(djembe.head_radius() * 0.92, 0, 0)
	for i in 6:
		strike.step({[&"probe", 1]: head + Vector3.UP * (0.05 - i * SessionProbe.DRUM_SPEED * dt)}, dt)
	InstrumentItem.clock = clock
	check("my fingertip through the djembe's rim plays its slap (%s)" % djembe.last_zone,
			probe._room.stands(&"djembe") and djembe.last_zone == &"slap" and djembe.state == Item.State.HOME)
	# Drum pads on anything (slice 41): a pad of my own marked on a surface by a fingertip's dwell, the
	# kit's face, and struck at once, to PAD_SONG.
	var kit := probe._room.items.get(KitItem.KIND) as KitItem
	probe._room.stand(KitItem.KIND, SessionProbe.KIT_HOME)
	var pads := SurfacePads.new()
	pads.path = SessionProbe.PAD_FILE
	pads.hands = true
	pads.set_physics_process(false)
	probe.add_child(pads)
	pads.clear()
	kit.surface = pads
	pads.set_marking(true)
	for i in 10:
		pads.dwell({[&"probe", 2]: SessionProbe.PAD_AT + Vector3.UP * (0.05 - i * 0.005)}, dt)
	for i in ceili(SurfacePads.DWELL / dt) + 2:
		pads.dwell({[&"probe", 2]: SessionProbe.PAD_AT}, dt)
	pads.set_marking(false)
	InstrumentItem.clock = func() -> float: return SessionProbe.PAD_SONG
	var pad: Vector3 = (pads.pad_frame(0).origin if pads.pads.size() == 1 else SessionProbe.PAD_AT)
	for i in 6:
		strike.step({[&"probe", 3]: pad + Vector3.UP * (0.05 - i * SessionProbe.DRUM_SPEED * dt)}, dt)
	InstrumentItem.clock = clock
	check("my fingertip's dwell marks a pad, and coming down through it plays the kit's kick (%s)" % kit.last_zone,
			pads.pads.size() == 1 and kit.last_zone == &"kick" and kit.state == Item.State.HOME)
	pads.clear()
	kit.surface = null
	pads.queue_free()
	# The rooftop's railing (slice 42), stood as the host stands its own: my fingertip into the third
	# tuned baluster's front, toward the parapet, to RAILING_SONG.
	var spec := _stand_the_railing()
	var baluster := probe._room.items.get(VenueInstrument.bar_id(SessionProbe.RAILING_BAR)) as VenueInstrument.Bar
	InstrumentItem.clock = func() -> float: return SessionProbe.RAILING_SONG
	var middle: Vector3 = (spec["spot"] as Transform3D) * (VenueInstrument.bar_frame(spec, SessionProbe.RAILING_BAR).origin
			+ Vector3(0, VenueInstrument.bar_length(spec, SessionProbe.RAILING_BAR) * 0.5, 0))
	for i in 6:
		strike.step({[&"probe", 4]: middle + Vector3.BACK * (0.05 - i * SessionProbe.DRUM_SPEED * dt)}, dt)
	InstrumentItem.clock = clock
	var tone := VenueInstrument.scale_tone(Harmony.at(DAW.state, SessionProbe.RAILING_SONG), int(spec["low"]), SessionProbe.RAILING_BAR)
	check("my fingertip into the railing's third baluster rings its scale tone (%d, %d)" % [baluster.last_note, tone],
			probe._room.stands(baluster.id) and baluster.last_note == tone and baluster.state == Item.State.HOME)
	strike.queue_free()


## Host: the guest's strike on the test drum (slice 38) reached me from the guest with its zone and
## the song position it was played to, and, as Presence plays a bandmate's strike, my drum rings it
## where it stands: nobody holds it.
func _check_drum_strike() -> void:
	var hits := probe._item_hits.filter(func(h: Array) -> bool: return h[0] == &"testdrum")
	check("the guest's strike on the test drum reached me with its zone and song (%s)" % [hits],
			hits.size() == 1 and hits[0][2] == probe.room_checks._other_id() and hits[0][6] == &"slap"
			and is_equal_approx(float(hits[0][3]), SessionProbe.DRUM_SONG) and int(hits[0][1]) == InstrumentItem.velocity_for(SessionProbe.DRUM_SPEED))
	var drum := probe._room.items.get(&"testdrum") as TestDrumItem
	if hits.size() != 1 or drum == null:
		return
	var presence := Presence.new()
	presence.items = probe._room
	var was := drum._take
	var hit: Array = hits[0]
	presence._on_item_hit(hit[0], hit[1], hit[2], hit[3], hit[4], hit[5], hit[6])
	check("and my drum plays it where it stands, on the slap, held by nobody",
			drum._take == was + 1 and drum.last_zone == &"slap" and drum.state == Item.State.HOME
			and Session.holder_of(drum.network_key()) == 0)
	presence.free()


## Host: the guest's slap on the djembe (slice 40) reached me from the guest with its zone and song,
## and my djembe, which stands where the guest's does, rings it there on its slap, held by nobody.
func _check_djembe_slap() -> void:
	var hits := probe._item_hits.filter(func(h: Array) -> bool: return h[0] == &"djembe")
	check("the guest's slap on the djembe reached me with its zone and song (%s)" % [hits],
			hits.size() == 1 and hits[0][2] == probe.room_checks._other_id() and hits[0][6] == &"slap"
			and is_equal_approx(float(hits[0][3]), SessionProbe.DJEMBE_SONG) and int(hits[0][1]) == InstrumentItem.velocity_for(SessionProbe.DRUM_SPEED))
	var djembe := probe._room.items.get(&"djembe") as HandDrum
	if hits.size() != 1 or djembe == null:
		return
	var presence := Presence.new()
	presence.items = probe._room
	var was := djembe._take
	var hit: Array = hits[0]
	presence._on_item_hit(hit[0], hit[1], hit[2], hit[3], hit[4], hit[5], hit[6])
	check("and my djembe plays it where it stands, its slap's sound, held by nobody",
			probe._room.stands(&"djembe") and djembe._take == was + 1 and djembe.last_zone == &"slap"
			and djembe.kind_of_hit(true, djembe.last_zone) == &"djembe_slap" and Session.holder_of(djembe.network_key()) == 0)
	presence.free()


## The rooftop's railing (slice 42), as the studio stands it there: the room's venue bars dressed as
## its set and stood on its spot. Answers the set.
func _stand_the_railing() -> Dictionary:
	var rooftop := RooftopVenue.new()
	var spec := VenueInstrument.filled(rooftop.instrument())
	rooftop.free()
	VenueInstrument.dress(probe._room, spec)
	for id: StringName in VenueInstrument.homes(spec):
		probe._room.stand(id, VenueInstrument.homes(spec)[id])
	return spec


## The loft's Thunderstorm (slice 44), as the studio stands it in the loft's storm, and what it
## schedules over WEATHER_BAR of this half's song: [step, note, velocity] for each drop, in order.
func _weather_schedule() -> Array:
	var loft := Venue.make(&"loft", LoftVenue.STORM)
	var spec := Weather.spec_of(loft)
	var venue_seed := Weather.seed_of(loft.venue_id())
	loft.free()
	var out: Array = []
	if spec.is_empty():
		return out
	var from := DAW.state.bar_to_seconds(SessionProbe.WEATHER_BAR)
	for drop: Dictionary in Weather.drops(spec, venue_seed, DAW.state, from, DAW.state.bar_to_seconds(SessionProbe.WEATHER_BAR + 1.0)):
		out.append([int(drop["step"]), int(drop["note"]), int(drop["velocity"])])
	return out


## Host: my schedule of the Thunderstorm's bar (slice 44) in my room for the guest to set its own
## beside, and the switch OFF, as a room starts.
func _publish_the_weather() -> void:
	var room: Dictionary = Session.room.duplicate(true)
	room["weather_probe"] = _weather_schedule()
	room[Weather.VERB] = false
	Session.publish_room(room)
	check("my Thunderstorm schedules drops over its gusting bar (%d)" % (room["weather_probe"] as Array).size(),
			not (room["weather_probe"] as Array).is_empty())


## The host's answer to the guest's press on the weather's switch (slice 44), as the studio's: the
## room's row `weather`, LISTEN or OFF, published.
func _answer_weather(args: Array, _from: int) -> void:
	var room: Dictionary = Session.room.duplicate(true)
	room[Weather.VERB] = bool(args[0])
	Session.publish_room(room)


func _answer_looper(args: Array, from: int) -> void:
	if probe._looper_was.is_empty():
		var s := DAW.state
		probe._looper_was = {"playing": s.playing, "at": s.position_seconds, "looping": s.looping,
				"loop": [s.loop_start, s.loop_end]}
	var out := Looper.answer(Session.room.get(Looper.VERB, []), int(args[0]), int(args[1]), from, Session.name_of)
	var room: Dictionary = Session.room.duplicate(true)
	room[Looper.VERB] = out["row"]
	Session.publish_room(room)


## The host's answer to the guest's layer (slice 45), as the studio's: written onto a track of the
## guest's own (Looper.write_layer) while the row is theirs, and the row cleared.
func _answer_looper_layer(args: Array, from: int) -> void:
	var row: Array = Session.room.get(Looper.VERB, [])
	if row.is_empty() or int(row[0]) != from:
		return
	probe._looper_layers.append(Looper.write_layer(Session.name_of(from), float(args[0]), float(args[1]), args[2]))
	var room: Dictionary = Session.room.duplicate(true)
	room[Looper.VERB] = []
	Session.publish_room(room)


## Host: the guest's slap asked me for the looper and was given the next bar, not the far one it
## named; its layer is on "<GUEST> LOOP 1" in the LOOPER folder, its key and its hit over the span
## the row gave it; and the row is clear. On Reaper with more of the project than the bank, the
## tracks are made but not yet in my mirror when write_layer looks them up (see docs/spatial_loop.md).
func _check_looper_layer() -> void:
	var asks := probe._room_asks.filter(func(a: Array) -> bool: return a[0] == Looper.VERB)
	var layers := probe._room_asks.filter(func(a: Array) -> bool: return a[0] == Looper.LAYER_VERB)
	check("the guest's slap on the looper reached me (%s)" % [asks],
			asks.size() == 1 and asks[0][1] == [SessionProbe.LOOPER_ASKED_BAR, SessionProbe.LOOPER_BARS] and asks[0][2] == probe.room_checks._other_id())
	check("and its layer (%d)" % layers.size(), layers.size() == 1 and layers[0][2] == probe.room_checks._other_id())
	var named := Looper.layer_name(Session.name_of(probe.room_checks._other_id()), 1)
	var index := Looper.track_named(DAW.state, named)
	var folder := Looper.folder_of(DAW.state)
	check("which is on a track of its own, %s, in the LOOPER folder (track %d, folder %d)" % [named, index, folder],
			index > 0 and folder > 0 and index > folder and Looper.folder_end(DAW.state, folder) >= index)
	var t := DAW.state.tracks.get(index) as MixState.TrackState
	var notes: Array = []
	if t != null and t.items.size() == 1:
		notes = MidiTake.unpack_relative(t.items[0].notes, t.items[0].start)
	var span: Array = [layers[0][1][0], layers[0][1][1]] if layers.size() == 1 else []
	check("its key and its hit, one item over the %d bars it was given (%s)" % [SessionProbe.LOOPER_BARS, notes],
			notes.size() == SessionProbe.LOOPER_NOTES.size() and not span.is_empty()
			and is_equal_approx(t.items[0].start, float(span[0]))
			and is_equal_approx(t.items[0].start + t.items[0].length, float(span[1]))
			and notes.map(func(n: Array) -> int: return int(n[2])) == [60, 38])
	check("and my room's looper row is clear", (Session.room.get(Looper.VERB, [0]) as Array).is_empty())


## Host: the guest's pull on its layer's ring (slice 46) took "<GUEST> LOOP 1" out of my project and
## left the LOOPER folder; on the built-in engine as one step, named for the ring (the edit the guest
## opened round its grab). On Reaper the mute is an OSC write, an undo point of Reaper's own.
func _check_ring_pulled() -> void:
	var named := Looper.layer_name(Session.name_of(probe.room_checks._other_id()), 1)
	var index := Looper.track_named(DAW.state, named)
	check("the guest's pull on its looper ring deleted %s from my project (track %d), the LOOPER folder left (%d)" % [named, index, Looper.folder_of(DAW.state)],
			index == 0 and Looper.folder_of(DAW.state) > 0)
	if probe._reaper_resource == "":
		var last: String = str(DAW.state.undo_names[DAW.state.undo_depth - 1]) if DAW.state.undo_depth > 0 else ""
		check("as one step, named for the ring (%s)" % last, last == "%s: ring" % named)


## Host: the guest's layer and the LOOPER folder taken out again, last first, and my transport and
## loop as they were before its slap.
func _take_back_the_looper() -> void:
	for at in [Looper.track_named(DAW.state, Looper.layer_name(Session.name_of(probe.room_checks._other_id()), 1)),
			Looper.folder_of(DAW.state)]:
		if at > 0:
			DAW.remove_track(at)
	if probe._looper_was.is_empty():
		return
	DAW.set_loop_range(probe._looper_was["loop"][0], probe._looper_was["loop"][1])
	DAW.set_looping(probe._looper_was["looping"])
	if not probe._looper_was["playing"]:
		DAW.transport_stop()
	DAW.seek(probe._looper_was["at"])


## Guest: the looper slapped (slice 45), asking for a far bar; by 61.68 the host's row gives me the
## next bar instead, LOOPER_BARS of it; my layer over that span sent; by 61.82 my mirror of the host's
## mix has it on a track of my own in the LOOPER folder. At 61.84 I pull its ring off (slice 46), and by
## 61.98 my mirror no longer has it.
func _loop_a_layer() -> void:
	await _until(61.6)
	var seq := Session.ask_room(Looper.VERB, [SessionProbe.LOOPER_ASKED_BAR, SessionProbe.LOOPER_BARS])
	check("my slap on the looper is asked of the host (seq %d)" % seq, seq > 0)
	await _until(61.68)
	var row: Array = Session.room.get(Looper.VERB, [])
	var span := Looper.span_of(row, DAW.state)
	check("and the host's row gives me the looper, %d bars from a bar of its choosing (%s)" % [SessionProbe.LOOPER_BARS, row],
			row.size() == 3 and int(row[0]) == Session.local_peer_id and int(row[1]) != SessionProbe.LOOPER_ASKED_BAR
			and int(row[2]) == SessionProbe.LOOPER_BARS and not span.is_empty())
	if span.is_empty():
		return
	var notes: Array = []
	for n: Array in SessionProbe.LOOPER_NOTES:
		notes.append([span[0] + n[0], span[0] + n[1], n[2], n[3], n[4]])
	Session.ask_room(Looper.LAYER_VERB, [float(span[0]), float(span[1]), notes])
	await _until(61.82)
	var named := Looper.layer_name(Session.name_of(Session.local_peer_id), 1)
	var index := Looper.track_named(DAW.state, named)
	var folder := Looper.folder_of(DAW.state)
	check("and my copy of the host's mix has %s in its LOOPER folder (track %d, folder %d)" % [named, index, folder],
			index > folder and folder > 0 and Looper.folder_end(DAW.state, folder) >= index)
	check("and the room's looper row is clear again", (Session.room.get(Looper.VERB, [0]) as Array).is_empty())
	# Its ring (slice 46): a stand of my own from my mirror, a hand closed on the layer's ring and pulled
	# 0.5 m off it, then opened.
	await _until(61.84)
	var rings := LooperRings.new()
	probe.add_child(rings)
	rings.set_physics_process(false)
	rings.set_process(false)
	rings.refresh()
	var ring := rings.ring_named(named)
	check("my stand has %s's ring, from my mirror of the host's LOOPER folder (%d rings)" % [named, rings.rings.size()], ring != null)
	if ring != null:
		var at := rings.global_transform * (LooperRings.rest_of(ring.slot) + Vector3(0, 0, LooperRings.RADIUS))
		rings.step_hands([{"hand": &"probe", "at": at, "closed": true}], 1.0 / 60.0)
		rings.step_hands([{"hand": &"probe", "at": at + Vector3(0, 0, 0.5), "closed": true}], 1.0 / 60.0)
		rings.step_hands([{"hand": &"probe", "at": at + Vector3(0, 0, 0.5), "closed": false}], 1.0 / 60.0)
		check("and my pull takes it off my stand at once, asked of the host", rings.ring_named(named) == null)
	await _until(61.98)
	check("by 61.98 my copy of the host's mix no longer has %s" % named, Looper.track_named(DAW.state, named) == 0)
	rings.queue_free()


## Host: the guest's lyrics (slice 56), as my song has them: its two lines, the first stamped by its
## TAP at the song it heard, LYRIC_SONG, and the second still untimed.
func _check_the_guests_tap() -> void:
	var lyr := Lyrics.parse(DAW.state.lyrics)
	var lines := lyr.lines
	check("the guest's lyrics are my song's: two lines (%s)" % DAW.state.lyrics.c_escape(),
			lines.size() == 2 and str(lines[0]["text"]) == "line one" and str(lines[1]["text"]) == "line two")
	check("its TAP stamped the first at the song it heard, the second still untimed",
			lines.size() == 2 and absf(float(lines[0]["t"]) - SessionProbe.LYRIC_SONG) < 0.1 and float(lines[1]["t"]) == Lyrics.UNTIMED)


## Guest: a lyric board of my own (slice 56): at 64.52 it writes two untimed lines, and at 64.6,
## hearing the song from LYRIC_SONG, TAP stamps the first. Both are intents the host's song takes.
func _tap_the_lyrics() -> void:
	await _until(64.52)
	var board := LyricBoard.new()
	probe.add_child(board)
	check("my board writes two lines to the host's song", board.write_text("line one\nline two") == "")
	await _until(64.6)
	board.heard_source = _given_clock(SessionProbe.LYRIC_SONG, true)
	var why := board.tap()
	check("and TAP, the song playing, stamps the first (%s)" % why, why.is_empty())
	board.queue_free()


## Host: the guest's press on the weather's switch (slice 44) reached me from the guest, and my
## room's row is LISTEN.
func _check_weather_asked() -> void:
	var asks := probe._room_asks.filter(func(a: Array) -> bool: return a[0] == Weather.VERB)
	check("the guest's press on the weather's switch reached me (%s)" % [asks],
			asks.size() == 1 and asks[0][1] == [true] and asks[0][2] == probe.room_checks._other_id())
	check("and my room's weather row is LISTEN", Session.room.get(Weather.VERB, false) == true)


## Guest: the weather's switch pressed (slice 44), LISTEN asked of the host, and by 61.56 its room's
## row says so; and my own schedule of the Thunderstorm's bar, from my copy of the host's song, is
## the host's drop for drop.
func _press_the_weather() -> void:
	await _until(61.46)
	var seq := Session.ask_room(Weather.VERB, [true])
	check("my press on the weather's switch is asked of the host (seq %d)" % seq, seq > 0)
	await _until(61.56)
	check("and the room's weather row is LISTEN (%s)" % [Session.room.get(Weather.VERB)],
			Session.room.get(Weather.VERB, false) == true)
	var theirs: Array = Session.room.get("weather_probe", [])
	var mine := _weather_schedule()
	check("both halves schedule the same drops over the Thunderstorm's bar (%d here, %d there)" % [mine.size(), theirs.size()],
			not mine.is_empty() and mine == theirs)


## Host: the guest's strike on the railing's third baluster (slice 42) reached me from the guest with
## its song, and my baluster, which stands where the guest's does, rings it there on the song's
## scale tone at that moment, its own sound, held by nobody.
func _check_railing_strike() -> void:
	var id := VenueInstrument.bar_id(SessionProbe.RAILING_BAR)
	var hits := probe._item_hits.filter(func(h: Array) -> bool: return h[0] == id)
	check("the guest's strike on the railing reached me with its song (%s)" % [hits],
			hits.size() == 1 and hits[0][2] == probe.room_checks._other_id() and is_equal_approx(float(hits[0][3]), SessionProbe.RAILING_SONG)
			and int(hits[0][1]) == InstrumentItem.velocity_for(SessionProbe.DRUM_SPEED))
	var baluster := probe._room.items.get(id) as VenueInstrument.Bar
	if hits.size() != 1 or baluster == null:
		return
	var presence := Presence.new()
	presence.items = probe._room
	var was := baluster._take
	var hit: Array = hits[0]
	presence._on_item_hit(hit[0], hit[1], hit[2], hit[3], hit[4], hit[5], hit[6])
	var tone := VenueInstrument.scale_tone(Harmony.at(DAW.state, SessionProbe.RAILING_SONG), int(baluster.set_spec["low"]), SessionProbe.RAILING_BAR)
	check("and my baluster rings it where it stands, on the song's scale tone there (%d), held by nobody" % baluster.last_note,
			probe._room.stands(id) and baluster._take == was + 1 and baluster.last_note == tone
			and baluster.sound_kind(true) == &"baluster" and Session.holder_of(baluster.network_key()) == 0)
	presence.free()


## Host: the guest's hit on a pad of its own (slice 41) reached me on the kit with its drum and song,
## and my kit rings it: from the guest's ghost where there is one, here at the kit, held by nobody.
func _check_pad_hit() -> void:
	var hits := probe._item_hits.filter(func(h: Array) -> bool: return h[0] == KitItem.KIND)
	check("the guest's pad hit reached me on the kit with its drum and song (%s)" % [hits],
			hits.size() == 1 and hits[0][2] == probe.room_checks._other_id() and hits[0][6] == &"kick"
			and is_equal_approx(float(hits[0][3]), SessionProbe.PAD_SONG) and int(hits[0][1]) == InstrumentItem.velocity_for(SessionProbe.DRUM_SPEED))
	var kit := probe._room.items.get(KitItem.KIND) as KitItem
	if hits.size() != 1 or kit == null:
		return
	var presence := Presence.new()
	presence.items = probe._room
	var was := kit._take
	var hit: Array = hits[0]
	presence._on_item_hit(hit[0], hit[1], hit[2], hit[3], hit[4], hit[5], hit[6])
	check("and my kit rings it, its kick's sound, held by nobody",
			kit._take == was + 1 and kit.last_zone == &"kick" and kit.kind_of_hit(true, kit.last_zone) == &"kick"
			and Session.holder_of(kit.network_key()) == 0)
	presence.free()


func _take_back_the_note() -> void:
	var at := DAWBackend.marker_key(DAW.state.markers, SessionProbe.NOTE_AT)
	if not is_nan(at):
		DAW.remove_marker(at)


## Waits until `seconds` into the probe by this process's clock, never before. A timer made at the end
## of a long frame is credited with that whole frame on its first tick and so can fire early by as
## much (the first ring of a sound made is tens of milliseconds), so it is waited out again until the
## clock agrees.
func _until(seconds: float) -> void:
	var left := seconds + probe._shift - (Time.get_ticks_msec() - probe._start) / 1000.0
	while left > 0.0:
		await probe.get_tree().create_timer(left).timeout
		left = seconds + probe._shift - (Time.get_ticks_msec() - probe._start) / 1000.0


func check(label: String, ok: bool) -> void:
	probe._checks += 1
	if not ok:
		probe._failures += 1
	print("%s  %s" % ["PASS" if ok else "FAIL", label])


static func _has_guest_mark(state: MixState) -> bool:
	return state.markers.values().has("GUEST")
