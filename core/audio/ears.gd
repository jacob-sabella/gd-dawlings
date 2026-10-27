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

## Leaning in (docs/spatial_loop.md slice 19): how much the mix comes down by while one track is
## lifted out of it, in dB. The track's cue is at its own fader plus GodotBackend.LEAN_DB.
const LEAN_MIX_DB := -6.0
## What a card says where leaning cannot be done here.
const CANNOT_LEAN := "leaning needs the tracks played here (a host on the built-in engine)"

## A cassette at the ear (docs/spatial_loop.md part two, slice 25): its clip plays on the KEYS bus
## (Monitor) as a cue, never the mix, and everything else this machine plays comes down by this
## much, in dB, for as long as it does (`cue`).
const CUE_DUCK_DB := -10.0

## {bus name: AudioEffectAmplify at its head}.
static var _gains: Dictionary = {}
## The track leant in to, 0 for none (`lean`).
static var leaning := 0
## What `listen` was last told, so a lean starting or ending can play the same again with or
## without itself.
static var _on := false
static var _levels: Dictionary = PERSONAL
## A cassette's clip is playing at an ear here (`cue`, EarCue).
static var cueing := false


## Headphones `on` a head here, playing the personal mix `levels` ({bus: dB}; a bus left out is
## not in it), or off, and everything as before. A bus other than the mix and the keys -- a
## track's cue -- is for headphones only, and is off whenever they are: except the cue of a track
## leant in to, which is heard with them on or off, the mix LEAN_MIX_DB lower under it. While a
## cassette is at the ear (`cueing`), everything but the keys' bus it plays on is CUE_DUCK_DB lower
## again, and that bus is heard even where the personal mix leaves it out.
static func listen(on: bool, levels: Dictionary = PERSONAL) -> void:
	_on = on
	_levels = levels
	var duck := CUE_DUCK_DB if cueing else 0.0
	var lean := GodotBackend.cue_bus(leaning) if leaning > 0 and DAW.backend is GodotBackend else &""
	for bus in [MIX, KEYS]:
		var db: float = levels.get(bus, OFF_DB) if on else 0.0
		if bus == MIX and lean != &"":
			db += LEAN_MIX_DB
		if bus == MIX:
			db += duck
		elif cueing and db <= OFF_DB:
			# The cassette's clip is on this bus: headphones without the keys in them still hear it.
			db = 0.0
		_gain(bus, db)
	var cues: Array = levels.keys().filter(func(b: StringName) -> bool: return b not in [MIX, KEYS])
	for bus in _gains.keys():
		if bus not in [MIX, KEYS, ROOM] and bus not in cues and bus != lean:
			_gain(bus, OFF_DB)
	for bus in cues:
		if bus != lean:
			_gain(bus, (levels[bus] + duck) if on else OFF_DB)
	if lean != &"":
		# Its level is the cue bus's own, which the engine keeps at the fader plus LEAN_DB.
		_gain(lean, duck)
	_gain(ROOM, (ROOM_DB if on else 0.0) + duck)


## A cassette's clip playing at an ear here, or not (EarCue): the room CUE_DUCK_DB down for this
## player alone meanwhile, and as it was after. Nothing goes to the DAW.
static func cue(on: bool) -> void:
	if on == cueing:
		return
	cueing = on
	listen(_on, _levels)


## Whether this machine can lean in to a track: it plays the tracks one by one, as a host on the
## built-in engine does. A guest hears only the host's stereo stream, and a host on Reaper hears
## Reaper, so neither can lift one track out of it (docs/spatial_loop.md part two, "What is
## personal stays in your ears").
static func can_lean() -> bool:
	return Session.role != Session.Role.GUEST and DAW.backend is GodotBackend


## Lean in to `track`, or 0 to stop: that track's cue (GodotBackend.set_lean, a third player of
## its part through its own effects) at its own fader plus GodotBackend.LEAN_DB, and the mix
## LEAN_MIX_DB lower, in this player's ears alone. Nothing goes to the DAW. False, and nothing
## changes, where it cannot be done (`can_lean`): the caller shows CANNOT_LEAN.
static func lean(track: int) -> bool:
	if track > 0 and (not can_lean() or not DAW.state.tracks.has(track)):
		return false
	var engine := DAW.backend as GodotBackend
	if track == leaning and (engine == null or engine.leaning() == track):
		return true
	leaning = track
	if engine != null:
		engine.set_lean(track)
	listen(_on, _levels)
	return true


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
