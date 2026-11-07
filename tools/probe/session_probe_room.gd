class_name SessionProbeRoom
extends RefCounted

## What the guest plays and sees in the room: the wheel, plugs, made items, cassettes given, pasted and heard, sections
## rearranged, the sampler and the platter.
## Moved out of `tools/probe/session_probe.gd` without change of behaviour; the state stays on the probe node, which keeps a one-line delegate for each name another file or a string reaches.

var probe: SessionProbe


func _init(of: SessionProbe) -> void:
	probe = of


## One key, down or up, as a MIDI keyboard would send it. Returns when the guest stamped it.
func _play(down: bool, pitch: int, velocity: int, changed_usec: Array) -> int:
	var before: int = changed_usec[0]
	var e := InputEventMIDI.new()
	e.message = MIDI_MESSAGE_NOTE_ON if down else MIDI_MESSAGE_NOTE_OFF
	e.pitch = pitch
	e.velocity = velocity
	e.channel = 0
	Input.parse_input_event(e)
	while changed_usec[0] == before:
		await probe.get_tree().process_frame
	return changed_usec[0]


func _keep_publishing(head: Transform3D, pointing: String) -> void:
	probe._head = head
	probe._pointing = pointing
	var timer := Timer.new()
	timer.wait_time = 0.05
	timer.autostart = true
	timer.timeout.connect(func(): Session.publish_presence(probe._head, probe._pointing, probe._pointing_local))
	probe.add_child(timer)


## The wheel's seat in the room's venue (Session.room), in the session's frame, as both halves
## stand it: Stations.seat with nothing to say where a person fits, since neither half here stands
## a studio's furniture round it. Null where the venue stands no wheel.
func _wheel_seat() -> Variant:
	var venue := Venue.make(Session.room.get("venue", Venue.IDS[0]))
	var seat: Variant = Stations.seat(venue, &"wheel")
	venue.free()
	return seat


## Going to a station in a headset (docs/spatial_loop.md slice 11), as the studio does it: a
## simulated rig in the session's frame (RoomAnchor, handed over whole) travels to the wheel's
## seat, and from then on the head this half publishes is the one Presence would, wherever the
## travel put it.
func _travel_to_the_wheel() -> void:
	var anchor := RoomAnchor.new()
	probe.add_child(anchor)
	anchor.adopt_virtual_frame(1.2)
	var rig := XRRig.new()
	rig.simulated = true
	probe.add_child(rig)
	rig.head.position = SessionProbe.TRAVEL_OFFSET
	var seat: Variant = _wheel_seat()
	probe.check("the room's venue stands a wheel to go to", seat != null)
	if seat == null:
		return
	rig.travel(seat as Transform3D)
	await probe.get_tree().create_timer(XRRig.FADE * 2.0 + 0.1).timeout
	var presence := Presence.new()
	presence.head_node = rig.head
	presence.frame = anchor
	probe._head = presence.head_in_session()
	presence.free()
	var wanted := (seat as Transform3D) * SessionProbe.TRAVEL_OFFSET
	probe.check("my travel put my head at the wheel's seat, as I stood in my play space (%.3f m)" % probe._head.origin.distance_to(wanted),
			probe._head.origin.distance_to(wanted) < 0.05 and rig.away and rig.veil() == 0.0)


## The first send that goes somewhere, as [track, slot]: the same answer on both halves, since
## the guest's copy of the project is the host's.
## A send the way a guest's hand makes one: a pin pressed on the routing bay, from the last track
## that sends nothing (so `_first_send` stays the one it was) into the first track it may. A guest
## asks (DAW.create_send's guest branch), the pin shows asked for, and seats when the host's send
## comes back in its mix.
func _press_a_bay_pin() -> void:
	probe._bay = PatchbaySurface.new()
	probe.add_child(probe._bay)
	StageLink.wire_bay(probe._bay)
	probe._bay._process(0.0)
	var indices := DAW.state.track_indices()
	for k in range(indices.size() - 1, -1, -1):
		var from: int = indices[k]
		if not DAW.state.track(from).sends.is_empty():
			continue
		for to: int in indices:
			probe._bay.matrix.show_line(from, true)
			probe._bay.matrix.show_line(to, false)
			var pin := probe._bay.pin_for(from, to)
			if pin == null or pin.cell().get("blocked", false) or pin.cell().get("on", false):
				continue
			pin.grab_begin(probe, pin.global_position)
			pin.grab_end(probe)
			probe._bay_pin = [from, to]
			probe.check("my bay pin %s asks the host, and says so" % [probe._bay_pin], pin.cell().get("pending", false))
			return
	probe.check("the bay had a crossing to press", false)


## The send the guest's bay pin made, [track, slot], on the host: the one track with a send more
## than when the guest came; [] when there is none.
func _send_the_guests_pin_made() -> Array:
	for index in DAW.state.track_indices():
		var t := DAW.state.track(index)
		if probe._sends_before.has(index) and t.sends.size() == int(probe._sends_before[index]) + 1:
			var slots: Array = t.sends.keys()
			slots.sort()
			return [index, int(slots[-1])]
	return []


static func _first_send(state: MixState) -> Array:
	for index in state.track_indices():
		var t := state.track(index)
		var slots: Array = t.sends.keys()
		slots.sort()
		for slot in slots:
			if int(slot) >= 1 and (t.sends[slot] as MixState.SendState).resolve(state) > 0:
				return [index, int(slot)]
	return []


## The guest's SET, as `whose` markers have it: a marker of brackets alone at WHEEL_BAR's start,
## the harmony from there by it (its second bar C), and the bar before it still D minor.
func _check_wheel(whose: String) -> void:
	var s := DAW.state
	var at := s.bar_to_seconds(SessionProbe.WHEEL_BAR + 1.0)
	var key := DAWBackend.marker_key(s.markers, at)
	var named: String = s.markers.get(key, "") if not is_nan(key) else ""
	probe.check("the guest's SET is a marker in %s markers at bar %d (%s)" % [whose, SessionProbe.WHEEL_BAR + 1, named],
			named == "[%s]" % SessionProbe.WHEEL_INSIDE)
	var second := Harmony.at(s, s.bar_to_seconds(SessionProbe.WHEEL_BAR + 2.0) + 0.01)
	var before := Harmony.at(s, at - 0.05)
	print("wheel: %s at %.3f; bar %d is %s in %s, the bar before %s in %s" % [named, at, SessionProbe.WHEEL_BAR + 2,
			second.chord_name, second.key_name, before.chord_name, before.key_name])
	probe.check("and Harmony.at reads it there: C in E minor, after D minor's Dm (%s, %s)" % [second.chord_name, before.chord_name],
			second.chord_name == "C" and second.key_name == "E minor" and before.chord_name == "Dm")


func _other_id() -> int:
	for id in Session.participants:
		if id != Session.local_peer_id:
			return id
	return 0


## A note from the other half, by what played it: plain keys into `_notes`, an instrument's into
## `_sourced`.
func _on_note_played(kind: int, pitch: int, velocity: int, from: int, song: float,
		source := &"") -> void:
	if not is_instance_valid(probe):
		return
	if source == &"":
		probe._notes.append([kind, pitch, velocity, from])
	else:
		probe._sourced.append([kind, pitch, from, source])


## A room of items, as the studio keeps one.
func _make_room() -> void:
	probe._room = ItemRoom.new()
	probe.add_child(probe._room)
	# Made items' rows are the session's, as the studio shares them (slice 23).
	probe._room.made = Session.made
	# The sampler (slice 26), as the studio stands one: its cassettes into this room.
	if Session.role == Session.Role.HOST:
		probe._sampler = Sampler.new()
		probe._sampler.items = probe._room
		probe._sampler.authority = Session.is_authority
		probe._sampler.local_peer = func() -> int: return Session.local_peer_id
		probe._sampler.name_of = Session.name_of
		probe.add_child(probe._sampler)
	# The probe's one hand-percussion instrument, a cowbell on the floor (the jacks and the snapped
	# hits are played on it).
	probe._room.spawn(&"cowbell", &"cowbell", Transform3D(Basis.IDENTITY, Vector3(0.6, 0.8, -1.0)))


## The host's answer to a plug, as the studio's: the host's rule (Jacks.refusal), and the room
## published with the jack in it.
func _answer_plug(args: Array, from: int) -> void:
	var item: Item = probe._room.items.get(args[0]) if probe._room != null else null
	var holder := Session.holder_of(item.network_key()) if item != null else 0
	var room: Dictionary = Session.room.duplicate(true)
	var rows: Dictionary = room.get("jacks", {})
	var now := StringName(str(rows.get(String(args[0]), "")))
	if Jacks.plug_refusal(args[0], item, args[1], from, holder, now, Session.participants.keys()) != "":
		return
	if args[1] == &"":
		rows.erase(String(args[0]))
	else:
		rows[String(args[0])] = String(args[1])
	room["jacks"] = rows
	Session.publish_room(room)
	if probe._jacks != null:
		probe._jacks.set_patch(rows)


## The host's answer to a guest's pull (slice 23), as the studio's: the clip packed from my own song,
## minted, its row sent once, the cassette put in the guest's hand by the holds, and the room naming
## it.
func _answer_make(args: Array, from: int) -> void:
	var made := probe._room.mint(args[0], ItemRoom.made_data(args[0], args[1]), from) if probe._room != null else null
	probe.check("the guest's pull is one I can mint (%s)" % (probe._room.mint_refusal if probe._room != null else "no room"), made != null)
	if made == null:
		return
	Session.publish_made(made.id)
	Session.hand_to(from, made.network_key())
	probe._made_for_guest.append(made.id)
	var room: Dictionary = Session.room.duplicate(true)
	room["made"] = probe._room.made_ids()
	Session.publish_room(room)


## A cassette of my own, minted here and handed to the guest, as the studio's give does it.
func _give_a_cassette() -> void:
	var guest := _other_id()
	var made := probe._room.mint(CassetteItem.KIND, ItemRoom.made_data(CassetteItem.KIND, SessionProbe.PULL_FROM))
	probe.check("I mint a cassette of my own (%s)" % probe._room.mint_refusal, made != null)
	if made == null:
		return
	Session.publish_made(made.id)
	Session.hand_to(guest, made.network_key())
	probe._made_for_guest.append(made.id)
	var room: Dictionary = Session.room.duplicate(true)
	room["made"] = probe._room.made_ids()
	Session.publish_room(room)


## Both cassettes are the guest's, as my table has it, and their rows mine.
func _check_cassettes_given() -> void:
	var guest := _other_id()
	probe.check("the guest's pull and my give are two cassettes (%s)" % [probe._made_for_guest],
			probe._made_for_guest == [&"cassette1", &"cassette2"])
	for id in probe._made_for_guest:
		var item: Item = probe._room.items.get(id)
		probe.check("%s is in the guest's glove, as my table has it (%d)" % [id, Session.holder_of(item.network_key()) if item != null else -1],
				item != null and Session.holder_of(item.network_key()) == guest)
		probe.check("and its row is the room's (%s)" % id, Session.made.has(id))
	var pulled := probe._room.items.get(&"cassette1") as CassetteItem
	var from := DAW.state.item(SessionProbe.PULL_TRACK, 0)
	if pulled != null and from != null:
		var clip := MixWire.unpack_item(pulled.clip)
		probe.check("and the pulled one is my clip (%s, %.2f s)" % [pulled.clip_name(), pulled.length()],
				clip != null and is_equal_approx(clip.start, from.start) and is_equal_approx(clip.length, from.length))


## The host's answer to a guest's paste (slice 24), as the studio's: only the cassette in the
## asker's hand, its clip from my own row, pasted as one step for the guest, or refused with why.
func _answer_paste(args: Array, from: int) -> void:
	probe._paste_asked = args
	var cassette := probe._room.items.get(args[0]) as CassetteItem if probe._room != null else null
	if cassette == null or Session.holder_of(cassette.network_key()) != from:
		probe._paste_said = "not in the asker's hand"
		return
	probe._paste_said = DAW.paste_item(args[1], args[2], cassette.clip)
	Session.tell(from, probe._paste_said if not probe._paste_said.is_empty() else "Pasted.")


## The guest's paste, as my DAW has it: asked by the cassette's id, PASTE_TRACK and its time at
## PASTE_BAR, and an item there that is the cassette's clip but for its start and track, one step.
## The demo song's items are windows of parts, so on Reaper (which has none) it is refused, and says so.
func _check_pasted() -> void:
	probe.check("the guest's paste names the cassette I gave it, track %d and a time at bar %d (%s)" % [SessionProbe.PASTE_TRACK, int(SessionProbe.PASTE_BAR), probe._paste_asked],
			probe._paste_asked.size() == 3 and probe._paste_asked[0] == &"cassette2" and probe._paste_asked[1] == SessionProbe.PASTE_TRACK
			and DAW.state.bar_beat(float(probe._paste_asked[2])).begins_with("%d.1." % int(SessionProbe.PASTE_BAR)))
	var cassette := probe._room.items.get(&"cassette2") as CassetteItem
	if cassette != null and cassette.clip.has("part") and not DAW.can(DAWBackend.Capability.DEMO_PARTS):
		probe.check("on Reaper a demo part is refused, and it says why (%s)" % probe._paste_said, probe._paste_said.contains("built-in engine"))
		return
	probe.check("and I pasted it (%s)" % ("yes" if probe._paste_said.is_empty() else probe._paste_said), probe._paste_said.is_empty())
	var it: MixState.ItemState = null
	if probe._paste_asked.size() == 3:
		for item: MixState.ItemState in DAW.state.track(SessionProbe.PASTE_TRACK).items:
			if absf(item.start - float(probe._paste_asked[2])) < 0.001:
				it = item
	var mine := MixWire.pack_item(it) if it != null else {}
	var theirs := cassette.clip.duplicate() if cassette != null else {}
	mine.erase("start")
	theirs.erase("start")
	probe.check("on track %d at bar %d is the cassette's clip but for its start and track (%s)" % [SessionProbe.PASTE_TRACK, int(SessionProbe.PASTE_BAR), it.name if it != null else "none"],
			it != null and not theirs.is_empty() and mine == theirs)


## The song's seconds at a bar of the sections' stretch, ARRANGE_BAR from 0.
func _arrange_at(bars: float) -> float:
	return DAW.state.bar_to_seconds(SessionProbe.ARRANGE_BAR + 1.0 + bars)


## Three regions of mine past the song, two bars each, a marker inside the second and a take of
## mine inside the third (slice 29), for the guest to rearrange.
func _lay_out_sections() -> void:
	probe._arrange_depth = DAW.state.undo_depth
	for k in 3:
		DAW.add_region(_arrange_at(2.0 * k), _arrange_at(2.0 * k + 2.0), SessionProbe.ARRANGE_NAMES[k])
	DAW.add_marker(_arrange_at(3.5), "Probe hook")
	DAW.insert_midi_take(SessionProbe.HOST_MIDI_TRACK, _arrange_at(4.5), _arrange_at(5.5),
			[[_arrange_at(4.75), _arrange_at(5.0), 60, 100, 0]], "Probe take")
	probe._arrange_steps = 5


## The guest's order C A B (slice 29), as my DAW has it: C first, where A was, with my take in it, and
## B last with its marker; as one step named for it, on the built-in engine.
func _check_rearranged() -> void:
	var regions: Array = DAW.state.regions
	var named := func(n: String) -> Array:
		for r in regions:
			if r[2] == n:
				return r
		return []
	var a: Array = named.call("Probe A")
	var b: Array = named.call("Probe B")
	var c: Array = named.call("Probe C")
	probe.check("the guest's order put C first, then A, then B, where the three were (%s)" % [[a, b, c]],
			not c.is_empty() and absf(float(c[0]) - _arrange_at(0.0)) < 0.002 and not a.is_empty()
			and absf(float(a[0]) - _arrange_at(2.0)) < 0.002 and not b.is_empty() and absf(float(b[0]) - _arrange_at(4.0)) < 0.002)
	var hook := false
	for t in DAW.state.markers:
		if DAW.state.markers[t] == "Probe hook" and absf(float(t) - _arrange_at(5.5)) < 0.002:
			hook = true
	probe.check("the marker inside B went with it", hook)
	var take := false
	for it: MixState.ItemState in DAW.state.track(SessionProbe.HOST_MIDI_TRACK).items:
		if it.name == "Probe take" and absf(it.start - _arrange_at(0.5)) < 0.002:
			take = true
	probe.check("and my take inside C with C", take)
	if not c.is_empty() and absf(float(c[0]) - _arrange_at(0.0)) < 0.002:
		probe._arrange_steps += 1
	if probe._reaper_resource == "" and DAW.state.undo_depth > 0:
		var last := str(DAW.state.undo_names[DAW.state.undo_depth - 1])
		probe.check("as one step of mine, called for it (%s)" % last, last == "arrange sections")


## The rearrangement and the layout taken back: to where the history was, or a step at a time where
## the DAW does not say its depth.
func _take_back_the_sections() -> void:
	if probe._arrange_depth >= 0 and DAW.state.undo_depth >= 0:
		DAW.undo_to(probe._arrange_depth)
	else:
		for _i in probe._arrange_steps:
			DAW.undo()


## The paste taken back, one step, and the made items gone.
func _take_back_the_paste() -> void:
	if probe._paste_said.is_empty():
		DAW.undo()
	for id in probe._made_for_guest:
		probe._room.unmake(id)
		Session.drop_made(id)


## The host's answer to the guest's REC (slice 26), as the studio's: on for its next sound, or off,
## and the room published with the row.
func _answer_sampler(args: Array, from: int) -> void:
	if probe._sampler == null:
		return
	probe._sampler.armed_by = from if args[0] else 0
	_publish_sampler_room()


func _publish_sampler_room() -> void:
	var room: Dictionary = Session.room.duplicate(true)
	room["sampler"] = probe._sampler.armed_by if probe._sampler != null else 0
	room["made"] = probe._room.made_ids() if probe._room != null else []
	Session.publish_room(room)


## A use the host hears (Session.item_used), for the sampler, as the studio's: only of what is in
## its user's hand. Caught, its cassette's row goes to everyone and the room names it, REC off.
func _sample_a_use(id: StringName, down: bool, from: int, take: int) -> void:
	if probe._sampler == null or probe._room == null or not down or from == Session.local_peer_id:
		return
	var item: Item = probe._room.items.get(id)
	if item == null or Session.holder_of(item.network_key()) != from:
		return
	var file_name := probe._sampler.next_name(item.use_kind(true))
	var made := probe._sampler.heard(item, item.use_kind(true), take, from, item.use_pitch())
	if made == null:
		return
	probe._sampled = [made.id, file_name, from]
	Session.publish_made(made.id)
	_publish_sampler_room()


## The guest's squeeze, as I caught it: its take came with it, one WAV of exactly Foley's stream for
## that take, a cassette the guest made of it, and REC off.
func _check_sampled() -> void:
	var guest := _other_id()
	var takes: Array = []
	for n in probe._uses.size():
		if probe._uses[n][0] == &"duck" and probe._uses[n][1] and probe._uses[n][2] == guest:
			takes.append(probe._use_takes[n])
	probe.check("the guest's squeeze reached me with the take its hand rang (%s)" % [takes], takes.has(SessionProbe.SAMPLE_TAKE))
	probe.check("my sampler caught it (%s)" % [probe._sampled], probe._sampled.size() == 3 and probe._sampled[2] == guest)
	if probe._sampled.size() != 3:
		return
	var path := DAW.backend.media_path(probe._sampled[1])
	var bytes := FileAccess.get_file_as_bytes(path)
	var body := bytes.slice(AudioTake.HEADER_BYTES) if bytes.size() > AudioTake.HEADER_BYTES else PackedByteArray()
	probe.check("as one WAV in my media, %s, equal to Foley's stream for take %d (%d bytes)" % [probe._sampled[1], SessionProbe.SAMPLE_TAKE, body.size()],
			String(probe._sampled[1]).begins_with("duck_squeeze_") and body == Foley.take_of(&"duck_squeeze", SessionProbe.SAMPLE_TAKE).data)
	var cassette := probe._room.items.get(probe._sampled[0]) as CassetteItem
	probe.check("and a sample cassette of it, made by the guest", cassette != null and cassette.data.get("sample") == "duck_squeeze"
			and cassette.clip.get("source") == probe._sampled[1] and (Session.made[probe._sampled[0]] as Array)[1] == guest)
	probe.check("and REC is off, in the room too (%s)" % [Session.room.get("sampler")], probe._sampler.armed_by == 0
			and int(Session.room.get("sampler", -1)) == 0)


## The sample cassette and its file taken away again.
func _take_back_the_sample() -> void:
	if probe._sampled.size() == 3:
		probe._room.unmake(probe._sampled[0])
		Session.drop_made(probe._sampled[0])
		DirAccess.remove_absolute(DAW.backend.media_path(probe._sampled[1]))
		_publish_sampler_room()


## Anything can be a sample (slice 26): at 59.36 I press the host's sampler's REC, as the studio's
## press asks; by 59.42 the room's row is mine. At 59.44 I take the duck, and at 59.48 squeeze it,
## my hand ringing SAMPLE_TAKE. By 59.55 the host's sample cassette of it is mine, its row here and
## the room naming it, and REC is off.
func _sample_a_squeeze() -> void:
	await probe.item_checks._until(59.36)
	var seq := Session.ask_room(Sampler.VERB, [true])
	probe.check("my REC is asked of the host (seq %d)" % seq, seq > 0)
	await probe.item_checks._until(59.42)
	probe.check("and the room's sampler row is mine: REC replicates (%s)" % [Session.room.get("sampler")],
			int(Session.room.get("sampler", 0)) == Session.local_peer_id)
	await probe.item_checks._until(59.44)
	Session.claim_hold(SessionProbe.DUCK)
	await probe.item_checks._until(59.48)
	probe.check("the duck is in my hand, as the host's table has it", Session.holder_of(SessionProbe.DUCK) == Session.local_peer_id)
	Session.send_item_use(&"duck", true, SessionProbe.SAMPLE_TAKE)
	Session.send_item_use(&"duck", false, SessionProbe.SAMPLE_TAKE + 1)
	await probe.item_checks._until(59.55)
	probe.check("REC is off again in the host's room (%s)" % [Session.room.get("sampler")], int(Session.room.get("sampler", -1)) == 0)
	var mine: Array = []
	for id in Session.made:
		var row: Array = Session.made[id]
		var data: Variant = bytes_to_var(row[2]) if row.size() == 3 and row[2] is PackedByteArray else null
		if data is Dictionary and data.get("sample") == "duck_squeeze" and int(row[1]) == Session.local_peer_id:
			mine.append(id)
	probe.check("and the host's sample cassette of my squeeze is here, made by me (%s)" % [mine], mine.size() == 1)
	probe.check("named in the room", mine.size() == 1 and (Session.room.get("made", []) as Array).has(mine[0]))
	Session.release_hold(SessionProbe.DUCK)


## The guest's spin of its platter, as my DAW has it (slice 27): my playhead at PLATTER_TURNS, a bar a
## turn, or just past it if the song played on when the guest let go.
func _check_platter_seek() -> void:
	var at := Platter.seconds_of(SessionProbe.PLATTER_TURNS)
	var now := DAW.state.position_seconds
	probe.check("the guest's spin of its platter moved my playhead to bar %d (%.3f s, wanted %.3f)" % [roundi(SessionProbe.PLATTER_TURNS) + 1, now, at],
			now >= at - 0.01 and now <= at + (0.3 if DAW.state.playing else 0.01))


## The guest's crank, as my history has it (slice 28): CRANK_NOTCHES steps back from `from`, in one
## jump. Where my DAW does not say its depth, that it asked two undos is the guest's check.
func _check_cranked(from: int) -> void:
	if from < 0:
		probe.check("my DAW does not say its history's depth, so the guest's crank asked undos (checked there)", true)
		return
	probe.check("the guest's history crank took my history %d back, from %d to %d" % [SessionProbe.CRANK_NOTCHES, from,
			DAW.state.undo_depth], from >= SessionProbe.CRANK_NOTCHES and DAW.state.undo_depth == from - SessionProbe.CRANK_NOTCHES)


## Sections rearranged (slice 29): at 60.24 I ask the order C A B of the host's three probe regions,
## as my copy of its regions has them, its other regions where they are; nothing moves here until the
## host's mix says so. By 60.34 my copy has C first, and the room's notice names the new order.
func _rearrange_the_sections() -> void:
	await probe.item_checks._until(60.24)
	var regions: Array = DAW.state.regions
	var at: Array = []
	for n in SessionProbe.ARRANGE_NAMES:
		for i in regions.size():
			if regions[i][2] == n:
				at.append(i)
	probe.check("I have the host's three probe sections, one after another (%s)" % [at], at.size() == 3
			and at[1] == at[0] + 1 and at[2] == at[1] + 1)
	if at.size() != 3:
		return
	var order: Array = range(regions.size())
	order[at[0]] = at[2]
	order[at[1]] = at[0]
	order[at[2]] = at[1]
	var said := DAW.arrange_sections(order)
	probe.check("my order is asked of the host (%s)" % ("asked" if said.is_empty() else said), said.is_empty())
	await probe.item_checks._until(60.34)
	var first: Array = DAW.state.regions[at[0]] if DAW.state.regions.size() > at[0] else []
	probe.check("and my copy has C where A was (%s)" % [first], not first.is_empty() and first[2] == "Probe C")
	probe.check("and the room was told the new order (%s)" % [probe._notices.filter(func(t): return t.contains("sections"))],
			probe._notices.any(func(t): return t.contains("rearranged the sections") and t.contains("Probe C · Probe A · Probe B")))


## A tape reel for undo history (slice 28): at 59.78 I turn a history crank of my own, as the
## studio's on the tape deck, back CRANK_NOTCHES a notch at a time, and leave it to settle. Not
## played back, so the host's transport is as the end needs it. It asks the host one undo_to, and
## by 60.12 my copy of the host's history is there.
func _crank_the_history() -> void:
	await probe.item_checks._until(59.78)
	var crank := ReelCrank.new()
	crank.plays_back = false
	probe.add_child(crank)
	Session.keep_intents = true
	Session.kept_intents.clear()
	var from: int = DAW.state.undo_depth
	for n in SessionProbe.CRANK_NOTCHES:
		crank.turn_to(-(n + 1))
		await probe.get_tree().process_frame
	await probe.item_checks._until(60.08)
	var asks := Session.kept_intents.filter(func(i: Array) -> bool: return i[0] in [&"undo_to", &"undo", &"redo"])
	if from >= 0:
		probe.check("my crank, settled, asked the host one undo_to(%d) (%s)" % [from - SessionProbe.CRANK_NOTCHES, asks], asks.size() == 1
				and asks[0][0] == &"undo_to" and int(asks[0][1][0]) == from - SessionProbe.CRANK_NOTCHES and crank.clicks == SessionProbe.CRANK_NOTCHES)
	else:
		probe.check("my crank, settled, asked the host %d undos, its depth unsaid (%s)" % [SessionProbe.CRANK_NOTCHES, asks],
				asks.size() == SessionProbe.CRANK_NOTCHES and asks.all(func(i: Array) -> bool: return i[0] == &"undo"))
	Session.keep_intents = false
	Session.kept_intents.clear()
	await probe.item_checks._until(60.12)
	if from >= 0:
		probe.check("and the host's history came back %d steps back (%d, from %d)" % [SessionProbe.CRANK_NOTCHES, DAW.state.undo_depth, from],
				DAW.state.undo_depth == from - SessionProbe.CRANK_NOTCHES and crank.standing() == from - SessionProbe.CRANK_NOTCHES)
	crank.queue_free()


## A DJ platter (slice 27): at 59.6 I take hold of a platter of my own, as the studio's on the deck's
## cart, and turn it to PLATTER_TURNS over the next frames, letting go once my hand has been still on
## it long enough to read as still (from where the sections before leave the song, well past bar 7, a
## quick turn back let go at once would be a flick, and spin back). My turns are seeks asked of the host,
## SEEK_HZ a second at most, and never a scrub: the host's DAW is the host's.
func _spin_the_platter() -> void:
	await probe.item_checks._until(59.6)
	var platter := Platter.new()
	platter.authority = Session.is_authority
	probe.add_child(platter)
	Session.keep_intents = true
	Session.kept_intents.clear()
	var began := Time.get_ticks_msec()
	platter.hold()
	var from := platter.turns
	var frames := 0
	while (Time.get_ticks_msec() - began) / 1000.0 < 0.04:
		frames += 1
		platter.turn_to(lerpf(from, SessionProbe.PLATTER_TURNS, minf((Time.get_ticks_msec() - began) / 30.0, 1.0)))
		await probe.get_tree().process_frame
	platter.turn_to(SessionProbe.PLATTER_TURNS)
	await probe.get_tree().process_frame
	var still_from := Time.get_ticks_msec()
	while absf(platter.speed()) > 0.001 and Time.get_ticks_msec() - still_from < 250:
		await probe.get_tree().process_frame
	platter.let_go()
	await probe.item_checks._until(59.72)
	var seconds := (Time.get_ticks_msec() - began) / 1000.0
	var seeks := Session.kept_intents.filter(func(i: Array) -> bool: return i[0] == &"seek")
	probe.check("my platter's turns were seeks asked of the host, %d in %.2f s, %d a second at most" % [seeks.size(), seconds,
			roundi(Platter.SEEK_HZ)], not seeks.is_empty() and seeks.size() <= ceili(seconds * Platter.SEEK_HZ) + 1
			and is_equal_approx(float(seeks[-1][1][0]), Platter.seconds_of(SessionProbe.PLATTER_TURNS)))
	probe.check("and never a scrub", not Session.kept_intents.any(func(i: Array) -> bool: return i[0] == &"scrub"))
	Session.keep_intents = false
	Session.kept_intents.clear()
	platter.queue_free()


## The file the ear's cassette plays (slice 25): in my media folder only, named for this run's port.
func _ear_file() -> String:
	return "Probe Ear %d.wav" % probe._port


## A cassette at the ear (slice 25): an audio cassette of EAR_FILE, a file only my media folder has,
## minted and named in the room. Its clip names the file, so a guest may fetch it (FileSend._plays_here).
func _mint_an_ear_cassette() -> void:
	var path := ProjectSettings.globalize_path(AudioTake.DIR.path_join(_ear_file()))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(AudioTake.DIR))
	var tone := PackedFloat32Array()
	for n in int(SessionProbe.EAR_SECONDS * 48000):
		tone.append(sin(n * 0.04) * 0.3)
	DawKitAudioFile.write_wav(path, tone, 1, 48000)
	var clip := {"start": 0.0, "length": SessionProbe.EAR_SECONDS, "name": "Probe ear", "source": _ear_file()}
	var made := probe._room.mint(CassetteItem.KIND, {"clip": clip, "track": SessionProbe.SENT_TRACK, "index": 0, "track_name": "EAR"})
	probe.check("I mint an audio cassette of a file only I have (%s)" % probe._room.mint_refusal, made != null and FileAccess.file_exists(path))
	if made == null:
		return
	probe._ear_cassette = made.id
	Session.publish_made(made.id)
	var room: Dictionary = Session.room.duplicate(true)
	room["made"] = probe._room.made_ids()
	Session.publish_room(room)


## The guest's ear asked me for the file, once, and I sent it whole; then the cassette and file go.
func _check_ear_file_sent() -> void:
	probe.check("the guest's ear fetched the file from me, once (%d sent)" % Session.files.fetches_served,
			Session.files.fetches_served == 1)
	if probe._ear_cassette != &"":
		probe._room.unmake(probe._ear_cassette)
		Session.drop_made(probe._ear_cassette)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(AudioTake.DIR.path_join(_ear_file())))


## A cassette at the ear (slice 25): at 59.2 I hold the host's audio cassette to my ear (an EarCue, as
## the studio's), with no file of it here: FETCHING, and asked of the host once. By 59.32 the copy is
## in FETCHED, byte for byte the host's, and it plays on the keys' bus.
func _hear_a_cassette() -> void:
	await probe.item_checks._until(59.2)
	probe._room.apply_made(Session.room.get("made", []))
	var tape: CassetteItem = null
	for id in probe._room.items:
		var c := probe._room.items[id] as CassetteItem
		if c != null and str(c.clip.get("source", "")) == _ear_file():
			tape = c
	probe.check("the host's audio cassette is real here (%s)" % (tape.clip_name() if tape != null else "none"), tape != null)
	var ear := EarCue.new()
	probe.add_child(ear)
	ear.hold(tape)
	probe.check("held to my ear with no file of it here, it is FETCHING, asked once (%s, %d)" % [ear.tag(), Session.files.fetches_asked],
			ear.hearing == EarCue.Hearing.FETCHING and tape != null and tape.hearing == "FETCHING"
			and Session.files.fetches_asked == 1)
	await probe.item_checks._until(59.32)
	var copy := Session.files.fetched_path(_ear_file())
	var theirs := ProjectSettings.globalize_path(AudioTake.DIR.path_join(_ear_file()))
	probe.check("the host's file is in my FETCHED folder (%s)" % copy, not copy.is_empty() and copy.contains("fetched"))
	if FileAccess.file_exists(theirs):
		probe.check("byte for byte the host's", FileAccess.get_file_as_bytes(copy) == FileAccess.get_file_as_bytes(theirs))
	probe.check("and it plays at my ear, on the keys' bus (%s)" % ear.tag(), ear.hearing == EarCue.Hearing.PLAYING
			and ear.player.bus == AudioPorts.MONITOR)
	probe.check("asked only once", Session.files.fetches_asked == 1)
	ear.hold(null)
	ear.queue_free()
