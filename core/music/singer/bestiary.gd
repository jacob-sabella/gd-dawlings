class_name Bestiary
extends RefCounted

## A creature for every venue (docs/singer.md, the bestiary): one of CHIMERA's four animals, perched in the venue's
## vocal booth beside the singer (CreaturePerch) and played like the venue's instrument, a stone a note. Stone n
## sounds the creature's call pitched to the n-th tone of the song's scale up from the key's root nearest the
## creature's `low` (VenueInstrument.scale_tone), so it is in the song's key wherever the song is and retunes at a
## bracket, and each stone letters the note it sounds now.
##
## Which creature is where is the venue's character: birds where there are plants and sky, the seal where it is cold
## or wet, the alligator in the low, dark, big rooms, the elephant in the desert.

## The stones on a perch, as a venue instrument's bars.
const STONES := 8
## Each creature: its id in SingerRow.BEASTS, what it is called, its lowest stone (MIDI, near the call's own pitch,
## its `pitch_ref`) and the call a stone sounds (CHIMERA's call index): the one with a note in it. The elephant's is its
## rumble, the one call whose pitch is a pitch param (its trumpet's valve is not): 8 to 45 Hz, so its stones sit round
## C0 (a tonic a fifth below to a fourth above, the top stone an octave over it, never past 44 Hz) and are heard by
## the rumble's overtones through the trunk.
const KINDS := {
	&"songbird": {"beast": 0, "title": "SONGBIRD", "low": 84, "call": 0},  # the flute phrase, 2.6 kHz
	&"seal": {"beast": 1, "title": "SEAL", "low": 76, "call": 2},  # the U whistle, 1.7 kHz
	&"alligator": {"beast": 2, "title": "ALLIGATOR", "low": 36, "call": 1},  # the growl, raised from 45 Hz
	&"elephant": {"beast": 3, "title": "ELEPHANT", "low": 12, "call": 0},  # the rumble, 14 Hz
}
const BY_VENUE := {
	&"garden": &"songbird", &"greenhouse": &"songbird", &"rooftop": &"songbird", &"dome": &"songbird",
	&"chalk": &"songbird",
	&"cabin": &"seal", &"cave": &"seal", &"station": &"seal", &"studio": &"seal",
	&"club": &"alligator", &"grid": &"alligator", &"box": &"alligator",
	&"desert": &"elephant", &"stage": &"alligator", &"loft": &"seal",
}


## The creature of venue `id`: {kind, beast, title, low, call}. A venue not listed gets one by its name, so a new
## venue has one too.
static func of(id: StringName) -> Dictionary:
	var kind: StringName = BY_VENUE.get(id, KINDS.keys()[absi(String(id).hash()) % KINDS.size()])
	var out: Dictionary = (KINDS[kind] as Dictionary).duplicate()
	out["kind"] = kind
	return out


## Stone `n`'s note in harmony `h` for creature `spec` (`of`).
static func note(h: Harmony, spec: Dictionary, n: int) -> int:
	return VenueInstrument.scale_tone(h, int(spec.get("low", 60)), n)


## The harmony at the song's position now (C major with no song).
static func harmony_now() -> Harmony:
	var st: MixState = DAW.state if DAW != null else null
	return Harmony.at(st, st.position_seconds if st != null else 0.0)
