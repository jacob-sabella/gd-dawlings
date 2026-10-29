class_name Jack
extends RefCounted

## What a jack is: the names of its two ends and the kinds of thing that go down it
## (docs/spatial_loop.md, foundation B). Static, pure: nothing here holds a patch. The room's
## patch is `Jacks`, and the plug on an instrument is `JackSocket`.
##
## A source is what plays: an item's id (`shaker`, `bell2`, a Tour spill's `cowbell2`), `harp`,
## `keys:P`, player P's own keys, or `chord:P`, player P's chord hand (part two, slice 33). A
## sink is where it goes: `track_N`, recorded onto track N as MIDI, or `player_P`, into player
## P's instrument (slice 6). The empty sink is unplugged, which is what every source is until
## somebody plugs it: it then does exactly what it did before there were jacks.
##
## A jack sends what its source is. A pitched source (the harp, a player's keys, a bell) sends
## NOTE_ON and NOTE_OFF of its own pitches, and CC, its controls beside them: `pitch` the
## controller (DawKitClip.PITCH_BEND, 1 or 11, Session.CONTROL_KINDS) and `velocity` its value,
## -8192 to 8191 for the bend (docs/spatial_loop.md slice 14). Unpitched percussion sends TRIGGER,
## which a receiving instrument turns into a note of its own (slice 6). Onto a track, both are
## recorded as the source would record them anyway: a bell its chord tone on its channel, a
## shaker its drum note.
##
## A player's chord hand sends CHORD, a shape and not a note: on each change of the chord it holds,
## `pitch` the chord's root as a pitch class (0 to 11) and `velocity` its quality, one more than
## its place in Harmony.QUALITIES (`chord_quality`), 0 for no shape held. Into a bandmate it is
## their chord while it is held (ChordHand.take); it never goes onto a track.
##
## The weather is a source that is no item (part two, slice 44): `weather`, the rain or snow on a
## venue's glass, and `drips`, the cave's (Weather). Every machine schedules the same drops from the
## song clock, so its jack goes onto a track only, where the host records them; never into a
## bandmate, who hears the same drops already. So is the marble run's `marbles` (MarbleRun, slice 49),
## its bells rung by marbles every machine rolls from the clock and the room's blocks.

enum Kind { NOTE_ON, NOTE_OFF, TRIGGER, CC, CHORD }

const TRACK := "track_"
const PLAYER := "player_"
const KEYS := "keys:"
const CHORD := "chord:"
## The chord harp, the room's to play (ChordHarp.SOURCE).
const HARP := &"harp"
## The world's sources: the weather's (Weather.SOURCE, Weather.DRIPS) and the marble run's
## (MarbleRun.SOURCE).
const WORLD: Array[StringName] = [&"weather", &"drips", &"marbles"]
## The longest a source or a sink's name may be: an item's id is short, and a peer's ask is
## bounded before the host stores it.
const NAME_MOST := 32
## The highest number a sink or a player's keys may name: as high as a peer's id goes (ENet gives
## out ids up to 2^31 - 1, so `player_1717822209` is a player), and no higher.
const NUMBER_MOST := 2147483647


## The sink that records onto track `index`.
static func track_sink(index: int) -> StringName:
	return StringName("%s%d" % [TRACK, index])


## The track a sink records onto, or 0 for a sink that is not a track.
static func track_of(sink: StringName) -> int:
	return _number_after(sink, TRACK)


## The sink that plays into player `peer`'s instrument.
static func player_sink(peer: int) -> StringName:
	return StringName("%s%d" % [PLAYER, peer])


## The player a sink plays into, or 0 for a sink that is not a player.
static func player_of(sink: StringName) -> int:
	return _number_after(sink, PLAYER)


## Player `peer`'s own keys, as a source.
static func keys_source(peer: int) -> StringName:
	return StringName("%s%d" % [KEYS, peer])


## The player whose keys a source is, or 0 for a source that is not a player's keys.
static func keys_player(source: StringName) -> int:
	return _number_after(source, KEYS)


## Player `peer`'s chord hand, as a source.
static func chord_source(peer: int) -> StringName:
	return StringName("%s%d" % [CHORD, peer])


## The player whose chord hand a source is, or 0 for a source that is not a chord hand.
static func chord_player(source: StringName) -> int:
	return _number_after(source, CHORD)


## The player a source is part of, their keys or their chord hand, or 0 for the harp or an item:
## who alone may plug it and send down it.
static func own_player(source: StringName) -> int:
	var keys := keys_player(source)
	return keys if keys > 0 else chord_player(source)


## Whether `source` is an instrument item's (an id), not the harp nor a player's keys or chord
## hand nor the weather: what can go onto a track, where HitRecorder takes its hits down.
static func is_item(source: StringName) -> bool:
	return source != HARP and not String(source).begins_with(KEYS) and not String(source).begins_with(CHORD) \
			and not is_world(source)


## Whether `source` is the world's (WORLD: the weather, the drips, the marbles): no item, onto a
## track only.
static func is_world(source: StringName) -> bool:
	return WORLD.has(source)


## Whether `sink` is a sink at all, by its shape: unplugged (empty), a track or a player. Whether
## that track is there, or that player in the room, is the host's to say (`Jacks.refusal`).
static func valid_sink(sink: StringName) -> bool:
	return sink == &"" or track_of(sink) > 0 or player_of(sink) > 0


## Whether `source` could be a source, by its shape: a name, not too long.
static func valid_source(source: StringName) -> bool:
	return source != &"" and String(source).length() <= NAME_MOST


## What a source sends down a jack: NOTE_ON, NOTE_OFF and CC for one with pitches of its own,
## TRIGGER for one without.
static func kinds_of(pitched: bool) -> Array[Kind]:
	if pitched:
		return [Kind.NOTE_ON, Kind.NOTE_OFF, Kind.CC]
	return [Kind.TRIGGER]


## How many qualities a CHORD's `velocity` may name: one each of Harmony.QUALITIES, and 0 for none.
static func quality_count() -> int:
	return Harmony.QUALITIES.size()


## A chord's quality as a CHORD sends it: one more than its place in Harmony.QUALITIES (`F` 1,
## `Dm` 2, `G7` 10), or 0 for a name that does not read as one.
static func chord_quality(chord: String) -> int:
	if Harmony.chord_tones(chord).is_empty():
		return 0
	var spelled := chord.left(2) if chord.length() >= 2 and chord[1] in ["#", "b"] else chord.left(1)
	return Harmony.QUALITIES.keys().find(chord.substr(spelled.length())) + 1


## A chord's root as a CHORD sends it, a pitch class, or -1 for a name that does not read.
static func chord_root(chord: String) -> int:
	var tones := Harmony.chord_tones(chord)
	return tones[0] if not tones.is_empty() else -1


## The chord a CHORD's `root` and `quality` name, spelled as `key` writes its notes: `F`, `Bb7`;
## "" for no shape (quality 0) or numbers out of range.
static func chord_named(root: int, quality: int, key: Harmony) -> String:
	if root < 0 or root > 11 or quality < 1 or quality > quality_count():
		return ""
	return key.note_name(root, false) + str(Harmony.QUALITIES.keys()[quality - 1])


## `name`'s whole number after `prefix`, or 0: `track_12` is 12, `track_`, `track_x` and
## `track_-3` are nothing, and nor is anything over NUMBER_MOST.
static func _number_after(name: StringName, prefix: String) -> int:
	var s := String(name)
	if not s.begins_with(prefix):
		return 0
	var digits := s.substr(prefix.length())
	if digits.is_empty() or digits.length() > 10 or not digits.lstrip("0123456789").is_empty():
		return 0
	var n := int(digits)
	return n if n > 0 and n <= NUMBER_MOST else 0
