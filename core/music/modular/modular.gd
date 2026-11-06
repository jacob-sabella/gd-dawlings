class_name Modular
extends RefCounted

## What the modular room shares with the rooms around it (docs/architecture.md, "The modular room"):
## the rack itself (core/music/rack, native/rack) is the synth; this is the names the world and the
## session use to reach it.
##
## SOURCE is what a note is sent as when it plays the rack (a guest's keys at the rack sound in the
## host's, Presence.modular_heard); STATION is the rack's place in a venue (Stations.spot).
##
## THE WORLD (docs/spatial_loop.md part two, slice 53; idea #31). The room's own music-makers have
## sockets out in the room (WorldSocket): `world:weather`, `world:drips`, `world:venue`,
## `world:ring_1` to `_8` and `world:marbles` (WORLD), the outputs of the rack's WORLD module
## (RackPatch). Each carries a level (0..1) and a gate. What they carry comes as events, WORLD (a
## level) and TRIG (a gate opened for WORLD_GATE), worked out from the song clock and the rows on
## every machine (ModularWorld) and played into the rack's engine (RackVoice.play_world).

const SOURCE := &"modular"
const STATION := &"modular"

## What the world's events are: [seconds, kind, a, b]. WORLD socket level (a world socket's level,
## 0..1); TRIG socket (its gate opened). The others are kept so the kinds keep their numbers.
enum Event { ON, OFF, BEND, KNOB, PATCH, WORLD, TRIG }

## The world's sockets, in the order of the rack's WORLD module's outputs.
const WORLD: Array[StringName] = [&"world:weather", &"world:drips", &"world:venue", &"world:ring_1",
		&"world:ring_2", &"world:ring_3", &"world:ring_4", &"world:ring_5", &"world:ring_6", &"world:ring_7",
		&"world:ring_8", &"world:marbles"]

## How long a world socket's gate stays open after a TRIG: blocks, so 48 ms.
const WORLD_GATE_BLOCKS := 36
const WORLD_GATE := WORLD_GATE_BLOCKS * 64 / 48000.0


static func is_world(id: StringName) -> bool:
	return WORLD.has(id)


## The world socket ring `n` (from 1) of the looper's stack has: `world:ring_3`.
static func ring_socket(n: int) -> StringName:
	return StringName("world:ring_%d" % n)


## A jack as a card letters it: a world socket by what it is in the room (`THE WEATHER`, `LOOPER
## RING 3`), a rack input by its path (`VCF CV`).
static func jack_title(id: StringName) -> String:
	if is_world(id):
		return world_title(id)
	return String(id).replace(".", " ").to_upper()


## A world socket's name: `THE WEATHER`, `THE DRIPS`, `THE VENUE'S INSTRUMENT`, `LOOPER RING 3`.
static func world_title(id: StringName) -> String:
	var name := String(id).trim_prefix("world:")
	if name.begins_with("ring_"):
		return "LOOPER RING %s" % name.trim_prefix("ring_")
	return {"weather": "THE WEATHER", "drips": "THE DRIPS", "venue": "THE VENUE'S INSTRUMENT"}.get(name, name.to_upper())
