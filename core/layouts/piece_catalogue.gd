class_name PieceCatalogue
extends RefCounted

## Which single items a player may take out of a room and put into one (docs/layouts.md 4.2 and 7). Only
## single items are here: a piece the shell or a zone supplies (the wheel on the bricks table, the drums on
## their riser, the venue's own instrument), the prop shelf that carries the toys and the Tour case that
## starts a run are part of the room and stay; the modular room is room-scale and not an edit of this kind.
##
## Three sorts of entry. A piece the layout already stands on a trolley (the cassette rack, the sampler, the
## hoop) may be `REMOVABLE` and put back by `add`, one of each. A piece a zone of the venue holds (the fifths
## wheel, the section blocks, the looper, the lyric board: `ZONED`) may be removed and put back the same way;
## it has no spot of its own to give, the zone is where it stands, so `add` of one is only "put it back" and
## is refused in a room whose shell has no such zone. And a piece the layout does not stand may be added as
## many times as its `limit`, each a copy built by the same builder the venue uses (`ADDABLE`): the basketball
## hoop, `Hoop.new`, on a trolley of the hoop's `PieceDef`. All are built or taken down by `RoomSync`.
##
## Not here, and why: the drum circle's plaque (the hand drums round it are items whose homes read the
## venue's ring, so taking the plaque down leaves them standing about it), the venue's instrument and
## weather (the shell supplies them), the Tour case and the prop shelf (see above), the control room's
## furniture (the MIXING neighbourhood and its wires are built once), and every item -- toys, small
## instruments, tablets: they are the room's replicated `ItemRoom.KINDS`, each with an id the session knows,
## so a second one is a new item kind and not a piece; a layout does not place items, their shelf is placed.
## The wheel, the sections, the looper and the lyric board are views of the song (`DAW`), rebuilt in every
## venue already, so taking one down loses nothing; none can be a second copy, as the stations and the
## song's one wheel, section row, looper row and lyrics would be shown twice.

## Kinds that can be added as copies, and the most of them in one room (the room's own included).
const ADDABLE := {&"hoop": {"title": "BASKETBALL HOOP", "limit": 4}}
## What the player sees for the pieces a zone holds.
const ZONED_TITLES := {&"wheel": "FIFTHS WHEEL", &"sections": "SECTION BLOCKS", &"looper": "LOOPER", &"lyrics": "LYRIC BOARD"}
## Layout pieces a room may do without. Each can be put back with `add`.
const REMOVABLE: Array[StringName] = [&"cassette_rack", &"sampler", &"hoop", &"wheel", &"sections", &"looper", &"lyrics"]
## The removable pieces a zone holds: no trolley, no spot to choose; the studio stands them where the venue's
## zone has room (`PieceHost.stand`).
const ZONED: Array[StringName] = [&"wheel", &"sections", &"looper", &"lyrics"]


## Every kind the ADD list offers, in the order it shows them.
static func kinds() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in REMOVABLE:
		out.append(k)
	return out


## Whether `kind` may be added as another copy.
static func copies(kind: StringName) -> bool:
	return ADDABLE.has(kind)


## The most of `kind` a room holds: its copies' limit, or one.
static func limit(kind: StringName) -> int:
	return int(ADDABLE[kind]["limit"]) if ADDABLE.has(kind) else 1


## What the player sees for `kind`.
static func title(kind: StringName) -> String:
	if ADDABLE.has(kind):
		return String(ADDABLE[kind]["title"])
	return String(ZONED_TITLES[kind]) if ZONED_TITLES.has(kind) else String(kind).replace("_", " ").to_upper()


## Whether `id` is a piece a zone holds (put back, never placed).
static func zoned(id: StringName) -> bool:
	return id in ZONED


## Whether this build can make `kind` as a copy a room added. A kind it cannot is shown as a named plate.
static func buildable(kind: StringName) -> bool:
	return copies(kind)


## Whether `id` (a layout piece's id) may be removed.
static func removable(id: StringName) -> bool:
	return id in REMOVABLE


## The next unused id for a copy of `kind` among `taken` (ids already in the room): `hoop_2`, `hoop_3`, ...
static func next_id(kind: StringName, taken: Array) -> StringName:
	var n := 2
	while "%s_%d" % [kind, n] in taken:
		n += 1
	return StringName("%s_%d" % [kind, n])
