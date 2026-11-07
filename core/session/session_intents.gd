class_name SessionIntents
extends RefCounted

## The guest's write path: an intent sent to the host and applied there, the save and render announcements, a listen
## from a spot, a guest's rearranged sections and a placed take. Moved out of `core/session/session.gd` without change of behaviour; the state stays on the autoload, which keeps a
## one-line delegate (with its `@rpc` line where it has one) for each name another file, a string or the network reaches.

var session: Session


func _init(of: Session) -> void:
	session = of


## A guest's write, forwarded to the host.
##
## Intents name a VERB from the DAW vocabulary -- `set_track_volume`, `transport_play` -- and
## not a wire message. That is what keeps a guest DAW-agnostic: the host may be driving Reaper
## over OSC and the guest need not contain a single OSC address to take part, which is the same
## reason the surfaces do not contain one either. See core/daw/daw.gd.
func send_intent(verb: StringName, args: Array) -> void:
	if session.is_authority():
		DAW.apply_intent(verb, args)
		return
	if session.keep_intents:
		session.kept_intents.append([verb, args])
	if not session._connected():
		return
	session._receive_intent.rpc_id(1, verb, args)


func _receive_intent(verb: StringName, args: Array) -> void:
	if not session.is_authority() or not session._is_member(session.multiplayer.get_remote_sender_id()):
		return
	# Anyone the host let in may move any fader. With a session code that means anyone who was
	# told the code; without one, anyone on the network. The code is a door, not encryption:
	# right for a studio LAN, not for anything exposed to the internet. The verb is still checked against the vocabulary --
	# see DAW.apply_intent -- because trusting a peer with a fader is not the same as letting it
	# name any method on an object.
	if verb == &"insert_midi_take":
		_place_take(session.multiplayer.get_remote_sender_id(), args)
		return
	if verb == &"save_project":
		save_project_for(session.name_of(session.multiplayer.get_remote_sender_id()))
		return
	if verb == &"arrange_sections":
		_arrange_for(session.multiplayer.get_remote_sender_id(), args)
		return
	# Whose it is, so their edit group gathers their writes and nobody else's (DAW.open_edit).
	DAW.apply_intent(verb, args, session.multiplayer.get_remote_sender_id())


## Saves the open project where it is, and tells the whole room how it went: a save is the one
## thing everyone in a session wants to know happened, whoever pressed it. `who` is the name of
## whoever asked, which on the host is the host.
func save_project_for(who: String) -> PackedStringArray:
	var said: PackedStringArray = DAW.backend.save_project("")
	_announce_save(who, said)
	return said


func _announce_save(who: String, said: PackedStringArray) -> void:
	var where: String = DAW.backend.project_path.get_file()
	var text := "%s saved the project%s." % [who, " as " + where if not where.is_empty() else ""]
	if not said.is_empty():
		text = "%s saved the project, but: %s" % [who, "; ".join(said)]
	tell_room(text)


## Said to the room by whoever's DAW rendered: the host.
func _announce_render(files: PackedStringArray, problems: PackedStringArray) -> void:
	if not session.is_authority():
		return
	var text := "Rendered %s." % ", ".join(Array(files).map(func(f): return str(f).get_file()))
	if files.is_empty():
		text = "Nothing was rendered."
	if not problems.is_empty():
		text = "%s But: %s" % [text, "; ".join(problems)]
	tell_room(text)


## A notice for this participant and every other one.
func tell_room(text: String) -> void:
	session.notice.emit(text)
	if session.is_authority():
		for id in session.admitting._audience():
			session._told.rpc_id(id, text)


## Listen from my spot (docs/spatial_loop.md part two, slice 35): the shared transport sought to
## `seconds` and played -- `seek` and `transport_play`, intents from a guest like any other -- and
## everyone told who asked and from where, `Ada: listen from 1:23 (CHORUS)`: the song jumping
## under the whole band's hands is not a thing to do unannounced. A guest's words are the host's
## to say, from its own markers, after the intents it has already had.
func listen_from(seconds: float) -> void:
	var at := maxf(seconds, 0.0) if is_finite(seconds) else 0.0
	DAW.seek(at)
	DAW.transport_play()
	if session.is_authority():
		tell_room(listen_words(session.local_name if not session.participants.has(session.local_peer_id) else session.name_of(session.local_peer_id),
				DAW.state.markers, at))
	elif session._connected():
		session._listen_asked.rpc_id(1, at)


func _listen_asked(seconds: float) -> void:
	var from := session.multiplayer.get_remote_sender_id()
	if not session.is_authority() or not session._is_member(from) or not is_finite(seconds):
		return
	tell_room(listen_words(session.name_of(from), DAW.state.markers, maxf(seconds, 0.0)))


## What the room is told of a listen from `seconds`: who, the clock there, and the section it is in
## (Harmony.section_at), upper case, when there is one.
static func listen_words(who: String, markers: Dictionary, seconds: float) -> String:
	var section := Harmony.section_at(markers, seconds).to_upper()
	return "%s: listen from %s%s" % [who, Presence.clock(seconds), " (%s)" % section if section != "" else ""]


## A guest's rearrangement of the song's sections (DAW.arrange_sections), made as hers, and the room
## told: the whole song moving under everyone's hands is not a change to make unannounced. A refusal
## is told to her, as she could not see it any other way.
func _arrange_for(from: int, args: Array) -> void:
	var who := session.name_of(from)
	var order: Array = args[0] if args.size() == 1 and args[0] is Array else []
	var refusal := DAW.arrange_refusal(order)
	if not refusal.is_empty():
		session.notice.emit("%s's rearrangement was not made. %s" % [who, refusal])
		if session._connected():
			session._told.rpc_id(from, "Your rearrangement was not made. " + refusal)
		return
	var regions: Array = DAW.state.regions
	var names: Array = order.map(func(k): return str(regions[int(k)][2]))
	DAW.apply_intent(&"arrange_sections", args, from)
	tell_room("%s rearranged the sections: %s." % [who, " · ".join(names)])


## A guest's take, placed, and both sides told how it went: the guest because it cannot see a
## refusal any other way, the host because a new item appearing on its timeline unannounced is
## a surprise in the middle of a session.
func _place_take(from: int, args: Array) -> void:
	var who := session.name_of(from)
	var refusal := DAW.midi_take_refusal(args)
	if not refusal.is_empty():
		session.notice.emit("%s's take was not placed. %s" % [who, refusal])
		if session._connected():
			session._told.rpc_id(from, "Your take was not placed. " + refusal)
		return
	# Hers, not the host's: a take landing mid-way through the host's drag is a step of its own.
	DAW.apply_intent(&"insert_midi_take", args, from)
	var cleaned := MidiTake.clean_args(args)
	var track: String = DAW.state.track(cleaned[0]).display_name()
	var at := DAW.state.bar_beat(cleaned[1])
	var count := (cleaned[3] as Array).size()
	var notes := "%d %s" % [count, "note" if count == 1 else "notes"]
	# Not during a Tour run: a part's take is rolled every bar, and a notice a bar per player
	# playing one buries the room; the run's HUD ticks the part instead.
	if session.tour.is_empty():
		session.notice.emit("%s played %s onto %s at %s." % [who, notes, track, at])
	if session._connected():
		session._told.rpc_id(from, "Your take is on %s: %s from %s." % [track, notes, at])
