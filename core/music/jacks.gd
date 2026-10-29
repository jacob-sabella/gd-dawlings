class_name Jacks
extends Node

## The room's output jacks: which source goes into which sink (`Jack`), and what a hit played
## here does about it (docs/spatial_loop.md, slices 5 and 6). The studio's, beside its HitRecorder.
##
## The patch is a row in the room, not a send: `room_state()["jacks"]`, {source: sink}, the
## host's like everything else in the room. A hand here that steps a socket says so (`asked`),
## and the studio does it at once and asks the host with the `plug` room verb, predicted and
## rolled back the way the tablet's `patch` is. It is not the patchbay's data (a cable there is a
## DAW send) and not the patch wall's (this machine's PipeWire).
##
## Every instrument hit played here comes through `hit` (ItemRoom.played), so every percussion
## item and every bell has a jack with no change to any of them. Unplugged, a hit goes where it
## always went: into the take on the armed track; or where its instrument says it goes by default
## (`goes_to`, InstrumentItem.default_sink: the drum pads' kit onto the drum track, part two,
## slice 41). Into `track_N`, the HitRecorder records it onto
## track N, armed or not, and not onto the armed track as well.
##
## Into `player_P`, a bandmate, what the source plays goes down a cable to P's own keys instead
## (`send_to`, Session.send_jack: up to the host, which checks it, and on to P alone). A pitched
## source sends its own notes: a bell its chord tone and, `note_seconds` later, its off; the harp
## its strings (ChordHarp); a player's keys what they play (`keys:P`, a thru: they are still
## heard, sent and taken down at home as well), and their controls beside the notes as CC (the
## bend, the mod wheel, expression: GuestMidi.control_sent). Percussion sends a TRIGGER. Every event carries
## the one song position it was played to. On P (`received`) each plays on P's keys with source
## `&"cable"` at that position, so it sounds on P's synth, goes to everyone as P's notes and lands
## in P's take where it was played, not where it arrived. A TRIGGER becomes the chord tone at its
## position, one tone up each hit (root, third, fifth, top, round again), for TRIGGER_SECONDS. A
## CC moves P's wheel (GuestMidi.control, source `&"cable"`), so it bends what the cable plays and
## lands in P's take beside its notes.
## `&"cable"` is in P's instruments (GuestMidi.reach) while anything is plugged into P.
##
## A player's chord hand has a jack too (`chord:P`, part two, slice 33): into a bandmate, the
## chord P's hand holds goes down it as a CHORD on each change (`send_chord`: the shape, a new
## key under a latched one, the plug itself), and an open hand as one of no quality. On Q it is
## Q's chord from P (ChordHand.take) while P holds it, and let go when it is unplugged or P
## leaves (`_follow_cables`). Only P plugs it and sends down it, and never onto a track: a chord
## is not notes to record. A chord is sent once, not over and over, so neither end may lose one
## to a plug the room has not told everyone about yet: a CHORD that reaches Q before the room
## says the jack goes into Q again is held until it does (`_held_chords`), and P sends what it
## holds again once the host's room says where the jack goes (`answered`).
##
## A jack into the player who is playing its source is no cable (`cable_into`): somebody else
## plugged the room's harp into Ada, or a shaker at home, and then Ada played it. Its notes go
## where an unplugged source's would, onto her keys and into her take, not down a cable back into
## herself, which the host would refuse.
##
## A source that went into this player and was taken out (`_cut`) plays nothing more here: a
## NOTE_ON or TRIGGER the host passed before it heard the unplug, arriving after it, would press a
## note whose off the host then refuses, and it would never stop. And every patch from the host
## lets go of whatever a cable has down that the patch no longer sends into this player.
##
## Who may plug what is the host's (`plug_refusal`): the hand that holds the source, or anyone
## while the source is at home on its shelf or stand; anyone the harp, which is the room's; only
## P their own keys and chord hand; only into a track there is or a bandmate in the room. And
## whoever a jack goes into may always take it out. Who may send down one is the host's too
## (`send_refusal`).

const GROUP := &"jacks"
## What a cable's notes say they came from, on the keys they play (GuestMidi.instruments).
const CABLE := &"cable"
## How long a TRIGGER's chord tone sounds (s).
const TRIGGER_SECONDS := 0.3
## Where a TRIGGER's chord tones are voiced (Harmony.voiced), the four of them: a keyboard's
## middle, as the fingertips are.
const TRIGGER_CENTRE := 60
const TRIGGER_TONES := 4

## How long a source's last hit shows on its lead (s), falling to nothing (SignalBeads), and the
## level a hit at full velocity shows at (the fader law: 0.716 is 0 dBFS) and at the softest.
const HEARD_FADE := 0.6
const HEARD_LOUD := 0.74
const HEARD_SOFT := 0.3

## A hand here stepped `source`'s socket on to `sink`: for the studio to do, and ask the host.
signal asked(source: StringName, sink: StringName)
## The patch changed, and every socket shows it.
signal changed()

## {source: sink}, both Strings, as the room's state carries them; a source not in it is
## unplugged.
var patch: Dictionary = {}
## Where hits are taken down: the studio's.
var recorder: HitRecorder = null
## (to, source, kind, pitch, velocity, song): how an event goes down a cable into a bandmate.
## Session.send_jack unless told otherwise (the suite's spy).
var send: Callable = Callable()
## (peer, from: Vector3) -> Vector3 or null: where a cable into `peer` ends, the nearer glove of
## their ghost here (Presence.cable_end); null where they have no ghost to hold it.
var far_end: Callable = Callable()
## This player's keys: what a cable into them plays, and whose notes go out of `keys:P`.
## Session.guest_midi, set by the studio.
var keys: GuestMidi = null:
	set(v):
		if keys != null and is_instance_valid(keys) and keys.note.is_connected(_on_keys_note):
			keys.note.disconnect(_on_keys_note)
			keys.control_sent.disconnect(_on_keys_control)
		keys = v
		if keys != null:
			keys.note.connect(_on_keys_note)
			keys.control_sent.connect(_on_keys_control)
		_follow_cables()

## The notes a cable has down on this player's keys: {"from|source|pitch": [from, source, pitch]}.
var _down := {}
## How far up its chord each sender's percussion has walked: {"from|source": hits}.
var _walks := {}
## Each source's last hit here, for its lead's beads: {source: [level, Time msec]}.
var _heard := {}
## Notes to let go later: [seconds left, to, source, pitch, song] for a bell's off to send down
## its cable (`to` above 0), [seconds left, 0, source, pitch, song, from] for a TRIGGER's tone here.
var _later: Array = []
## The sources going into this player as the patch last said, and those that went into them and
## were taken out since, whose late notes are dropped (`received`) until one goes into them again:
## {source: true}, both.
var _mine := {}
var _cut := {}
## What this player's keys last sent down their cable of each control, {kind: value}: a resend of
## the same value is not sent down a reliable cable again. Forgotten at every note, so the one
## right behind a note-on (GuestMidi.resend_controls) always goes.
var _cabled := {}
## What this player's chord hand last sent down its jack: [to, root, quality], `to` 0 while it goes
## into nobody, quality 0 for no shape held (Jack.Kind.CHORD), -1 for not known there: whatever
## the hand holds then goes, an open hand too.
var _chord_sent := [0, -1, 0]
## The bandmate the host's room last said this player's chord hand goes into (`answered`), 0 for
## nobody.
var _chord_answered := 0
## A CHORD that came down a jack cut here (`_cut`), for the next patch to say yes or no to:
## {source: [from, root, quality]}. The host passes a chord the moment it plugs the jack, and
## the room saying so comes after it.
var _held_chords := {}


func _enter_tree() -> void:
	add_to_group(GROUP)


func _exit_tree() -> void:
	# What a cable had down here is let go with the room: the keys stay, the cables do not.
	if keys != null and is_instance_valid(keys):
		for key in _down.keys():
			var d: Array = _down[key]
			_release(d[0], d[1], d[2], NAN)
		keys.reach(CABLE, false)
		_let_go_chords(&"")
		if keys.note.is_connected(_on_keys_note):
			keys.note.disconnect(_on_keys_note)
			keys.control_sent.disconnect(_on_keys_control)


## The jacks of the room `node` is in, or null outside one (an item alone in a test).
static func of(node: Node) -> Jacks:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_tree().get_first_node_in_group(GROUP) as Jacks


## Where `source` goes: a sink, or empty for unplugged.
func sink_of(source: StringName) -> StringName:
	return StringName(patch.get(String(source), ""))


## The player `source` goes into, or 0 when it goes into none.
func player_into(source: StringName) -> int:
	return Jack.player_of(sink_of(source))


## The bandmate `source`'s cable goes into, or 0: none, or this player, whose own playing a jack
## into them never takes away (it goes where it would unplugged).
func cable_into(source: StringName) -> int:
	var to := player_into(source)
	return 0 if to == Session.local_peer_id else to


## Every source going into player `peer`.
func into(peer: int) -> Array[StringName]:
	var sink := String(Jack.player_sink(peer))
	var out: Array[StringName] = []
	for source in patch:
		if patch[source] == sink:
			out.append(StringName(source))
	return out


## `source` into `sink`, or unplugged (empty). Whether it may be is not asked here: a hand's
## ask is the studio's to check, the room's answer the host's. True if anything changed.
func plug(source: StringName, sink: StringName) -> bool:
	if not Jack.valid_source(source) or not Jack.valid_sink(sink) or sink_of(source) == sink:
		return false
	if sink == &"":
		patch.erase(String(source))
	else:
		patch[String(source)] = String(sink)
	show_all()
	return true


## The room's patch, as the host has it: this replaces the one here whole. Rows that are not a
## jack are left out.
func set_patch(rows: Dictionary) -> void:
	var was := patch
	patch = {}
	for source in rows:
		var sink := StringName(str(rows[source]))
		if Jack.valid_source(StringName(str(source))) and Jack.valid_sink(sink) and sink != &"":
			patch[str(source)] = String(sink)
	if patch != was:
		show_all()
	else:
		# The same patch still lets go of strays: a note a cable has down here from a source it
		# does not send into this player, whose off is never coming.
		_follow_cables()


## The host's own patch (Studio.apply_room, before this guest's unanswered plugs go on top). Once
## it says this player's chord hand goes into a bandmate it did not say before, what the hand
## holds goes down the jack again at the next tick, an open hand too: sent at the plug, it could
## reach them before the room told them the jack goes into them (`_cut`), and this one comes
## after the room did.
func answered(rows: Dictionary) -> void:
	if Session.local_peer_id == 0:
		return
	var to := Jack.player_of(StringName(str(rows.get(String(Jack.chord_source(Session.local_peer_id)), ""))))
	if to == _chord_answered:
		return
	_chord_answered = to
	if to > 0:
		_chord_sent = [to, -1, -1]


## The patch, in the shape the room's state carries.
func state() -> Dictionary:
	return patch.duplicate()


## `source` is gone from the room (a Tour spill swallowed, a personal copy put back): its plug
## goes with it. True if it had one.
func drop(source: StringName) -> bool:
	return plug(source, &"") if patch.has(String(source)) else false


## Player `peer` left: every jack into them, and their keys' and chord hand's own, unplugged. True
## if any was.
func drop_player(peer: int) -> bool:
	var any := false
	for source in patch.keys():
		if Jack.player_of(StringName(patch[source])) == peer or Jack.own_player(StringName(source)) == peer:
			any = plug(StringName(source), &"") or any
	return any


## A hit played by a hand here, at song position `at` (InstrumentItem.played's one read): onto
## the track its jack goes into, down the cable into a bandmate, or, unplugged, the way it always
## went. Into a bandmate a bell sends its note and, `note_seconds` later, its off; percussion a
## TRIGGER. Neither is taken down here: it lands in their take. `zone`, where on a fixed one it was
## struck, for the note the take records (HitRecorder.hit).
func hit(item: InstrumentItem, velocity: int, at: float, zone := &"") -> void:
	# Its source: its id, or a venue's set's one (InstrumentItem.jack_source), whichever bar it was.
	var source := item.jack_source()
	heard_from(source, velocity)
	var to := cable_into(source)
	if to > 0:
		if item.pitched():
			var pitch := item.last_note
			# Rung again before the last ring's off: that one ends now, so its off never ends this.
			_let_go(func(due: Array) -> bool: return int(due[1]) > 0 and due[2] == source and int(due[3]) == pitch)
			send_to(to, source, Jack.Kind.NOTE_ON, pitch, velocity, at)
			_later.append([item.note_seconds(), to, source, pitch, at + item.note_seconds()])
		else:
			send_to(to, source, Jack.Kind.TRIGGER, 0, velocity, at)
		return
	if recorder == null:
		return
	var track := Jack.track_of(goes_to(source, item))
	recorder.hit(item, velocity, at, track if takes_midi(track) else 0, -1, zone)


## Where `source`'s hits go: its plug, or, unplugged, its `item`'s default sink (InstrumentItem.
## default_sink: the kit's drum track, docs/spatial_loop.md part two, slice 41), which is never a
## bandmate and never a row in the room. Empty for the armed track.
func goes_to(source: StringName, item: Item = null) -> StringName:
	var sink := sink_of(source)
	if sink == &"" and item is InstrumentItem:
		return (item as InstrumentItem).default_sink()
	return sink


## `source` played here at `velocity`: what its lead's beads show, fading over HEARD_FADE.
func heard_from(source: StringName, velocity: int, now_msec: int = -1) -> void:
	var level := lerpf(HEARD_SOFT, HEARD_LOUD, clampf(float(velocity) / 127.0, 0.0, 1.0))
	_heard[source] = [level, Time.get_ticks_msec() if now_msec < 0 else now_msec]


## How loud `source`'s last hit here still shows, 0..1: its level at the hit, falling to nothing
## over HEARD_FADE. Nothing for a source that has not played.
func level_of(source: StringName, now_msec: int = -1) -> float:
	var last: Array = _heard.get(source, [])
	if last.is_empty():
		return 0.0
	var age := float((Time.get_ticks_msec() if now_msec < 0 else now_msec) - int(last[1])) / 1000.0
	return maxf(float(last[0]) * (1.0 - age / HEARD_FADE), 0.0) if age >= 0.0 else float(last[0])


## The chord this player's chord hand holds (ChordHand.own_chord), down `chord:P`'s jack while it
## goes into a bandmate: sent when it changes, from no shape to one, one to another, a latched
## degree into a new key, or the jack into another bandmate; and an open hand as quality 0 to the
## one who had a chord. Nothing goes while nothing was sent and no shape is held. Everything goes
## again once the host's room says where the jack goes (`answered`). Each frame (`tick`), so no
## change is missed however it came.
func send_chord() -> void:
	if Session.local_peer_id == 0:
		return
	var mine := Jack.chord_source(Session.local_peer_id)
	var to := cable_into(mine)
	if to <= 0:
		_chord_sent = [0, -1, 0]
		return
	var hand := ChordHand.mine
	var song := hand.now() if hand != null and is_instance_valid(hand) else -1.0
	var chord := hand.own_chord(song) if hand != null and is_instance_valid(hand) else ""
	var now := [to, Jack.chord_root(chord), Jack.chord_quality(chord)]
	if now == _chord_sent:
		return
	var was_here := int(_chord_sent[0]) == to and int(_chord_sent[2]) != 0
	_chord_sent = now
	if int(now[2]) == 0 and not was_here:
		return
	if int(now[2]) > 0:
		heard_from(mine, 100)
	send_to(to, mine, Jack.Kind.CHORD, maxi(int(now[1]), 0), int(now[2]), song)


## One event down the cable into player `to`, at song position `song` (-1 for not known).
func send_to(to: int, source: StringName, kind: int, pitch: int, velocity: int, song: float) -> void:
	if send.is_valid():
		send.call(to, source, kind, pitch, velocity, song)
	else:
		Session.send_jack(to, source, kind, pitch, velocity, song)


## A note on this player's own keys (GuestMidi.note): out of `keys:P` too, while it goes into a
## bandmate. Not what came in on a cable, so two players plugged into each other never feed
## back, and not the harp's, which has a jack of its own.
func _on_keys_note(kind: int, pitch: int, velocity: int, song: float, source: StringName) -> void:
	if kind == Session.Note.ON and source != CABLE:
		heard_from(Jack.HARP if source == Jack.HARP else Jack.keys_source(Session.local_peer_id), velocity)
	if source == CABLE or source == Jack.HARP:
		return
	var mine := Jack.keys_source(Session.local_peer_id)
	var to := cable_into(mine)
	if to <= 0:
		return
	_cabled.clear()
	match kind:
		Session.Note.ON:
			send_to(to, mine, Jack.Kind.NOTE_ON, pitch, velocity, song)
		Session.Note.OFF:
			send_to(to, mine, Jack.Kind.NOTE_OFF, pitch, 0, song)


## A control on this player's own keys (GuestMidi.control_sent): out of `keys:P` as CC too, while
## it goes into a bandmate, the controller as `pitch` and its value as `velocity`. Not a cable's or
## the harp's, as `_on_keys_note`; and a resend of what the cable already has is not sent again,
## since the cable is reliable and loses nothing.
func _on_keys_control(kind: int, value: int, song: float, source: StringName) -> void:
	if source == CABLE or source == Jack.HARP:
		return
	var mine := Jack.keys_source(Session.local_peer_id)
	var to := cable_into(mine)
	if to <= 0 or _cabled.get(kind) == value:
		return
	_cabled[kind] = value
	send_to(to, mine, Jack.Kind.CC, kind, value, song)


# --- a cable into this player -----------------------------------------------------------------

## An event down a cable into this player (Session.jack_played), passed by the host: played on
## this player's keys with source `&"cable"` at the song position it was played to (`song`; -1,
## not known, plays it at this player's own). A TRIGGER becomes the next tone of the chord at
## `song`, held TRIGGER_SECONDS. A CC moves this player's wheel as the cable (GuestMidi.control),
## taken only while the cable owns it. A NOTE_ON, TRIGGER or CC from a source this player has taken
## out (`_cut`) is dropped: the host passed it before it heard, and its off will not come. A
## NOTE_ON or TRIGGER also lights its source's lead here (`heard_from`), so the cable a bandmate
## plays into this player carries beads on this player's machine too. A CHORD is a bandmate's chord
## hand (`chord:P`): taken as this player's chord from them (ChordHand.take), quality 0 let go.
## One from a cut source is held for the next patch instead (`_held_chords`): plugged in again,
## the host passed it before the room told this player so, and it is not sent twice.
func received(source: StringName, kind: int, pitch: int, velocity: int, from: int, song: float) -> void:
	if keys == null:
		return
	var at := song if song >= 0.0 else NAN
	if kind == Jack.Kind.NOTE_OFF:
		_release(from, source, pitch, at)
		return
	if _cut.has(String(source)):
		if kind == Jack.Kind.CHORD:
			_held_chords[String(source)] = [from, pitch, velocity]
		return
	if kind == Jack.Kind.CHORD:
		_take_chord(source, from, pitch, velocity)
		return
	# In reach at once, though the room saying so may not have come yet: the host checked it.
	keys.reach(CABLE, true)
	# Its lead here (a bandmate's, hanging where their glove would be) carries what came down it.
	if kind == Jack.Kind.NOTE_ON or kind == Jack.Kind.TRIGGER:
		heard_from(source, velocity)
	match kind:
		Jack.Kind.NOTE_ON:
			_press(from, source, pitch, velocity, at)
		Jack.Kind.TRIGGER:
			var tone := walk(from, source, song)
			_press(from, source, tone, velocity, at)
			_later.append([TRIGGER_SECONDS, 0, source, tone, song + TRIGGER_SECONDS if song >= 0.0 else NAN, from])
		Jack.Kind.CC:
			keys.control(pitch, velocity, CABLE, at)


## A bandmate's chord hand down `source`: this player's chord while it is held, no note of its own.
func _take_chord(source: StringName, from: int, root: int, quality: int) -> void:
	var hand := ChordHand.mine
	if hand != null and is_instance_valid(hand):
		hand.take(source, from, root, quality)
	if quality > 0:
		heard_from(source, 100)


## The chord tone a TRIGGER from `from`'s `source` plays at `song`: one up the chord each hit,
## root, third, fifth, top and round again, voiced at TRIGGER_CENTRE in the chord at `song` (the
## playhead when not known).
func walk(from: int, source: StringName, song: float) -> int:
	var key := "%d|%s" % [from, source]
	var step: int = _walks.get(key, 0)
	_walks[key] = step + 1
	var seconds := song
	if seconds < 0.0:
		seconds = DAW.state.position_seconds if DAW.state != null else 0.0
	var tones := Harmony.voiced(Harmony.at(DAW.state, seconds), TRIGGER_CENTRE, TRIGGER_TONES)
	return tones[step % tones.size()]


func _press(from: int, source: StringName, pitch: int, velocity: int, at: float) -> void:
	pitch = clampi(pitch, 0, 127)
	var key := "%d|%s|%d" % [from, source, pitch]
	if _down.has(key):
		_release(from, source, pitch, at)
	_down[key] = [from, source, pitch]
	keys.note_on(pitch, clampi(velocity, 1, 127), 0, 0.0, false, CABLE, at)


## A cable's note let go: off on the keys only when no other cable still has that pitch down.
func _release(from: int, source: StringName, pitch: int, at: float) -> void:
	pitch = clampi(pitch, 0, 127)
	var key := "%d|%s|%d" % [from, source, pitch]
	if not _down.has(key):
		return
	_down.erase(key)
	if cable_holds(pitch):
		return
	keys.note_off(pitch, 0, 0.0, false, CABLE, at)


## Whether a cable has `pitch` down on this player's keys.
func cable_holds(pitch: int) -> bool:
	return _down.values().any(func(d: Array) -> bool: return int(d[2]) == pitch)


## `&"cable"` in this player's instruments while anything goes into them, and out once the last
## plug has gone, which lets go of all it had down. What a source still had down when it was
## unplugged is let go, and the source is cut (`_cut`) until it goes into this player again. A
## chord held from a cut source (`_held_chords`) is taken once the patch says it goes into this
## player again, and dropped if it says it does not.
func _follow_cables() -> void:
	var mine := Jack.player_sink(Session.local_peer_id)
	var now := {}
	for source in patch:
		if patch[source] == String(mine):
			now[source] = true
			_cut.erase(source)
	for source in _mine:
		if not now.has(source):
			_cut[source] = true
	_mine = now
	var held := _held_chords
	_held_chords = {}
	for source in held:
		if now.has(source):
			var c: Array = held[source]
			_take_chord(StringName(source), int(c[0]), int(c[1]), int(c[2]))
	if keys == null or not is_instance_valid(keys):
		return
	for key in _down.keys():
		var d: Array = _down[key]
		if sink_of(d[1]) != mine:
			_release(d[0], d[1], d[2], NAN)
	# A bandmate's chord from a jack that no longer goes into this player (or that the room never
	# said did) is let go, as a stray note is.
	var hand := ChordHand.mine
	if hand != null and is_instance_valid(hand):
		for source in hand.taken_sources():
			if not now.has(String(source)):
				hand.let_go(source)
	var plugged := Session.local_peer_id != 0 and not into(Session.local_peer_id).is_empty()
	if not plugged:
		_let_go_chords(&"")
		_down.clear()
		_walks.clear()
		_later = _later.filter(func(due: Array) -> bool: return int(due[1]) > 0)
	keys.reach(CABLE, plugged)


func _process(delta: float) -> void:
	tick(delta)


## A bandmate's chord down `source`'s jack let go here (all of them, with none named).
func _let_go_chords(source: StringName) -> void:
	var hand := ChordHand.mine
	if hand != null and is_instance_valid(hand):
		hand.let_go(source)


## Time passing: every TRIGGER tone here and every bell's off to send that is due, let go, and the
## chord hand's chord sent down its jack if it changed (`send_chord`).
func tick(delta: float) -> void:
	send_chord()
	if _later.is_empty():
		return
	for due in _later:
		due[0] = float(due[0]) - delta
	_let_go(func(due: Array) -> bool: return float(due[0]) <= 0.0)


## Every note waiting to be let go that `pick` picks, let go now: a bell's off sent down its
## cable (`to` above 0), or a TRIGGER's tone here.
func _let_go(pick: Callable) -> void:
	var keep: Array = []
	var go: Array = []
	for due in _later:
		if pick.call(due):
			go.append(due)
		else:
			keep.append(due)
	_later = keep
	for due in go:
		if int(due[1]) > 0:
			send_to(int(due[1]), due[2], Jack.Kind.NOTE_OFF, int(due[3]), 0, float(due[4]))
		elif keys != null:
			_release(int(due[5]), due[2], int(due[3]), float(due[4]))


# --- stepping a socket ------------------------------------------------------------------------

## Where a press (`way` 1) or a step back (-1) takes `source`'s socket: through unplugged, the
## tracks that take MIDI (an item's only) and each bandmate, round again, so every hand gets back
## to unplugged by pressing.
func next_sink(source: StringName, way: int) -> StringName:
	var cycle := sinks(source)
	var at := maxi(cycle.find(sink_of(source)), 0)
	return cycle[posmod(at + signi(way), cycle.size())]


## A hand here stepped `item`'s socket, `way` 1 on or -1 back: said, for the studio to do.
func step(item: InstrumentItem, way: int) -> void:
	if item != null:
		step_source(item.id, way)


## A hand here stepped `source`'s socket. A jack that goes into this player is taken out by it,
## whoever's it is: whoever a jack goes into may always unplug it.
func step_source(source: StringName, way: int) -> void:
	if way == 0 or not Jack.valid_source(source):
		return
	if Session.local_peer_id != 0 and player_into(source) == Session.local_peer_id:
		asked.emit(source, &"")
		return
	asked.emit(source, next_sink(source, way))


## Everything going into this player taken out: asked, one by one (Shift+P with an empty hand, or
## a press on the socket for it on their wrist, JackSocket.into_me). How many there were.
func unplug_mine() -> int:
	var mine := into(Session.local_peer_id)
	for source in mine:
		asked.emit(source, &"")
	return mine.size()


## What `source`'s socket steps through: unplugged; then, for an instrument item, each track that
## takes MIDI, in order; then each bandmate in the room but the source's own player. The harp and
## a player's keys are keys already, and go onto the armed track by the keys' own choice, and a
## chord hand's chord is no notes, so their sockets step through bandmates only.
static func sinks(source := &"") -> Array[StringName]:
	var out: Array[StringName] = [&""]
	if DAW.state != null and (Jack.is_item(source) or Jack.is_world(source)):
		for index in DAW.state.track_indices():
			if takes_midi(int(index)):
				out.append(Jack.track_sink(int(index)))
	# The weather plays on every machine already: onto a track, never down a cable.
	if Jack.is_world(source):
		return out
	for peer in bandmates():
		if peer != Jack.own_player(source):
			out.append(Jack.player_sink(peer))
	return out


## Everyone in the room but this player, in the order they came (their ids rising).
static func bandmates() -> Array[int]:
	var out: Array[int] = []
	for id in Session.participants:
		if int(id) != Session.local_peer_id:
			out.append(int(id))
	out.sort()
	return out


## Whether track `index` is there to take a take of notes: any track but a frozen one, whose items
## are one render until it is thawed.
static func takes_midi(index: int) -> bool:
	if index <= 0 or DAW.state == null:
		return false
	var t := DAW.state.track(index, false)
	return t != null and not t.is_frozen()


## What a sink is called on a tag and a hover card: `3 BASS`, `GRACE`, or `unplugged`.
static func sink_name(sink: StringName) -> String:
	var track := Jack.track_of(sink)
	if track > 0:
		var t := DAW.state.track(track, false) if DAW.state != null else null
		return "%d %s" % [track, t.display_name().to_upper()] if t != null else "TRACK %d (GONE)" % track
	var player := Jack.player_of(sink)
	if player > 0:
		if Session.participants.has(player):
			return Session.name_of(player).to_upper()
		return "PLAYER %d (GONE)" % player
	return "unplugged"


## What a source is called in a notice: `shaker`, `handbell 2`, `chord harp`, `your keys`,
## `Ada's chord hand`.
static func source_name(source: StringName, item: Item = null) -> String:
	if item is InstrumentItem:
		return (item as InstrumentItem).jack_title().to_lower()
	if item != null:
		return item.item_title().to_lower()
	if source == Jack.HARP:
		return "chord harp"
	if source == MarbleRun.SOURCE:
		return "marble run"
	if Jack.is_world(source):
		var title := str(Weather.spec_of(Stations.here).get("title", "")) if Stations.here != null \
				and is_instance_valid(Stations.here) else ""
		return title.to_lower() if title != "" else ("drips" if source == Weather.DRIPS else "weather")
	var player := Jack.keys_player(source)
	if player > 0:
		return "your keys" if player == Session.local_peer_id else "%s's keys" % Session.name_of(player)
	player = Jack.chord_player(source)
	if player > 0:
		return "your chord hand" if player == Session.local_peer_id else "%s's chord hand" % Session.name_of(player)
	return String(source)


# --- the host's word --------------------------------------------------------------------------

## The host's word on peer `from`'s ask to plug instrument `item` into `sink`, `holder` the peer
## whose hand has the item (Session.holds; 0 for nobody): empty if it may, else why not, in words.
## The hand that holds it may; anyone may while it is at home; nobody may into a track that is
## not there. Whether a player sink is in the room is `plug_refusal`'s.
static func refusal(item: Item, sink: StringName, from: int, holder: int) -> String:
	if not (item is InstrumentItem):
		return "there is no jack on that"
	if not Jack.valid_sink(sink):
		return "there is no such jack"
	if holder != 0 and holder != from:
		return "it is in somebody else's hand"
	if holder == 0 and item.state != Item.State.HOME:
		return "it can be plugged in a hand, or on its shelf"
	var track := Jack.track_of(sink)
	if track > 0 and not takes_midi(track):
		return "there is no track %d to record onto" % track
	return ""


## The host's word on peer `from`'s ask to plug `source` into `sink` (the `plug` verb): `item` the
## instrument that is the source (null for the harp and a player's keys), `holder` whose hand has
## it, `now` where it goes now and `members` who is in the room. Whoever a jack goes into may take
## it out. Into a player: one in the room, and not the one plugging it. The harp is anyone's to
## plug, a player's keys and chord hand only theirs, and none of them goes onto a track. The weather
## (Jack.WORLD) is anyone's, onto a track only. An item is `refusal`'s.
static func plug_refusal(source: StringName, item: Item, sink: StringName, from: int, holder: int,
		now: StringName, members: Array) -> String:
	if not Jack.valid_sink(sink):
		return "there is no such jack"
	if sink == &"" and from != 0 and Jack.player_of(now) == from:
		return ""
	var player := Jack.player_of(sink)
	if player > 0:
		if not members.has(player):
			return "player %d is not in the room" % player
		if player == from:
			return "a jack goes into a bandmate, not into yourself"
	if Jack.is_world(source):
		# The weather is the room's, anyone's to plug, onto a track only: everyone hears it already.
		if player > 0:
			if source == MarbleRun.SOURCE:
				return "the marble run goes onto a track: everyone hears its bells already"
			return "the weather goes onto a track: everyone hears it already"
		var onto := Jack.track_of(sink)
		if onto > 0 and not takes_midi(onto):
			return "there is no track %d to record onto" % onto
		return ""
	var chords := Jack.chord_player(source)
	if chords > 0:
		if chords != from:
			return "only %s plugs their own chord hand" % Session.name_of(chords)
		if Jack.track_of(sink) > 0:
			return "a chord hand goes into a bandmate, not onto a track"
		return ""
	var keys := Jack.keys_player(source)
	if keys > 0 or source == Jack.HARP:
		if keys > 0 and keys != from:
			return "only %s plugs their own keys" % Session.name_of(keys)
		if Jack.track_of(sink) > 0:
			return "its notes are keys, and go onto the armed track"
		return ""
	return refusal(item, sink, from, holder)


## The host's word on an event peer `from` sends down `source`'s jack into player `to`, given the
## room's patch (`rows`) and `holder`, the peer whose hand has the source item (Session.holds): it
## passes only while the patch sends `source` into `to`, and only from the source's player: an
## item's holder, P for `keys:P` and `chord:P`, any member for the harp and for an instrument that
## stands still (`fixed`: the hand drums, a venue's set), which nobody holds and anyone plays where
## it stands. Whether `to` and `from` are in the room is Session's to say (Session.jack_refusal).
static func send_refusal(rows: Dictionary, source: StringName, to: int, from: int, holder: int,
		fixed := false) -> String:
	if StringName(str(rows.get(String(source), ""))) != Jack.player_sink(to):
		return "its jack does not go into player %d" % to
	var keys := Jack.keys_player(source)
	if keys > 0:
		return "" if keys == from else "those are %s's keys" % Session.name_of(keys)
	var chords := Jack.chord_player(source)
	if chords > 0:
		return "" if chords == from else "that is %s's chord hand" % Session.name_of(chords)
	if source == Jack.HARP or fixed:
		return ""
	return "" if holder != 0 and holder == from else "it is not in their hand"


## Every socket in the room shows where its source goes now, and this player's keys follow what is
## plugged into them.
func show_all() -> void:
	if is_inside_tree():
		var mine := into(Session.local_peer_id) if Session.local_peer_id != 0 else [] as Array[StringName]
		for node in get_tree().get_nodes_in_group(JackSocket.SOCKETS):
			var socket := node as JackSocket
			if socket != null and socket.into_me:
				socket.show_ins(mine)
			elif socket != null and socket.source_id() != &"":
				socket.show_sink(sink_of(socket.source_id()))
	_follow_cables()
	changed.emit()
