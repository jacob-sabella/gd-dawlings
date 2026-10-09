class_name Ears
extends RefCounted

## What this machine plays to the person at it, with headphones on (docs/items_loop.md).
##
## A pair of headphones in the game is your personal mix, heard: closed backs keep the room out,
## so the room's own sounds -- the gear, the toys, the foley -- drop away while they are on, and
## what is in them is the mix and your keys. What goes into that mix, and how loud, is the
## personal mixer's (the tablet, to come): `listen` takes its levels.
##
## It is all this machine's: a gain at the head of each of its own buses (AudioPorts), before
## anything that taps them, so a ported bus carries it too. Nothing goes to the DAW and nobody
## else hears a difference. What it cannot reach it says (`reaches_mix`): a host on Reaper hears
## Reaper through the system, not through the game, and its mix is not the game's to change.
## Keys played through the native helper (NativeKeys) are their own node, out of reach as well.

## How much a closed back takes off the room, in dB. Studio cans isolate by 10 to 20 dB.
const ROOM_DB := -14.0
## Off: the floor of an amplifier, far below hearing.
const OFF_DB := -80.0
## Which buses carry what (AudioPorts' names).
const MIX := &"Mix"
const KEYS := &"Monitor"
const ROOM := &"Gear"
## What a personal mix has in it before anything is patched: the mix and your keys, as they are.
const PERSONAL := {MIX: 0.0, KEYS: 0.0}

## {bus name: AudioEffectAmplify at its head}.
static var _gains: Dictionary = {}


## Headphones `on` a head here, playing the personal mix `levels` ({bus: dB}; a bus left out is
## not in it), or off, and everything as before.
static func listen(on: bool, levels: Dictionary = PERSONAL) -> void:
	for bus in [MIX, KEYS]:
		_gain(bus, levels.get(bus, OFF_DB) if on else 0.0)
	_gain(ROOM, ROOM_DB if on else 0.0)


## The gain on `bus` now, in dB: 0 where nothing has been set.
static func gain_db(bus: StringName) -> float:
	var amp: AudioEffectAmplify = _gains.get(bus)
	return amp.volume_db if amp != null else 0.0


## Whether the mix this machine plays is the game's to change: a guest's stream, or anything but
## Reaper on a host. A host on Reaper hears Reaper itself.
static func reaches_mix(guest: bool, on_reaper: bool) -> bool:
	return guest or not on_reaper


static func _gain(bus: StringName, db: float) -> void:
	var at := AudioServer.get_bus_index(bus)
	if at < 0:
		return
	var amp: AudioEffectAmplify = _gains.get(bus)
	# Still on that bus, at its head? A bus layout rebuilt under it would have dropped it.
	var there := false
	if amp != null:
		for i in AudioServer.get_bus_effect_count(at):
			if AudioServer.get_bus_effect(at, i) == amp:
				there = true
				break
	if not there:
		if is_zero_approx(db):
			return
		amp = AudioEffectAmplify.new()
		AudioServer.add_bus_effect(at, amp, 0)
		_gains[bus] = amp
	amp.volume_db = db
