class_name TheirKeys
extends Node

## Other players' keys, played here, for a personal mix that has a plug in them (PersonalMix).
##
## Nobody's sound crosses the session for this: their notes do (Session.note_played), a few bytes
## each, and this machine plays them on the same tine synth the player hears themselves on
## (MonitorSynth). So what is heard is their playing as it reaches here -- one way to the host and,
## on a guest, one more on -- with no jitter buffer, since a note held back to smooth the timing
## would only be later. Only the players `set_players` names are played, each on a bus of its
## own (`bus_of`) that a pair of headphones turns up (Ears); nothing else of it is heard.
##
## A player's bus is made the first time it is wanted and kept: buses are numbered, and taking
## one out from among the built-in engine's would renumber them under it. A session has a few
## players, so a few spare buses.

## {peer id: MonitorSynth}, for the players being played.
var synths: Dictionary = {}


## The bus a player's keys play on here, by name.
static func bus_of(peer: int) -> StringName:
	return StringName("Their keys %d" % peer)


## Play the keys of `peers`, and of nobody else.
func set_players(peers: Array) -> void:
	for peer in synths.keys():
		if peer not in peers:
			(synths[peer] as MonitorSynth).queue_free()
			synths.erase(peer)
	for peer in peers:
		if synths.has(peer):
			continue
		var bus := bus_of(int(peer))
		if AudioServer.get_bus_index(bus) < 0:
			var at := AudioServer.bus_count
			AudioServer.add_bus(at)
			AudioServer.set_bus_name(at, bus)
			AudioServer.set_bus_send(at, &"Master")
		var synth := MonitorSynth.new()
		synth.name = "Keys%d" % peer
		# Through Godot: the helper is this player's own keys, one per machine.
		synth.allow_native = false
		synth.bus = bus
		synth.volume_db = Session.guest_midi.monitor_db if Session.guest_midi != null else -6.0
		add_child(synth)
		synth.start()
		synths[int(peer)] = synth


func players() -> Array:
	return synths.keys()


## A key or the pedal from `from`, as Session.note_played says it.
func play(kind: int, pitch: int, velocity: int, from: int) -> void:
	var synth: MonitorSynth = synths.get(from)
	if synth == null:
		return
	match kind:
		Session.Note.ON: synth.note_on(pitch, velocity)
		Session.Note.OFF: synth.note_off(pitch)
		Session.Note.PEDAL_DOWN: synth.sustain(true)
		Session.Note.PEDAL_UP: synth.sustain(false)
