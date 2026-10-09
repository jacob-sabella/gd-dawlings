class_name PersonalMix
extends RefCounted

## What this person has patched into their own ears (docs/items_loop.md): the tablet's
## receivers, each fed by a wireless plug out in the room, each at a level of its own. What they
## add up to is what a pair of headphones on this person's head plays (Ears).
##
## Where each plug is is the room's -- everyone sees the plugs in the sockets, and the host keeps
## the table (the studio's `patches`) -- and comes here from it. The levels are this person's
## alone and go nowhere: a personal mix nobody else can hear has nothing to tell anyone.
##
## With nothing patched there is nothing to choose between, and headphones play the mix and your
## keys as they are (Ears.PERSONAL), so a pair picked up before the tablet still works.

## Receivers on a tablet, A to D.
const RECEIVERS := 4
const LETTERS := ["A", "B", "C", "D"]
## The send sockets there are, by name, and the bus each one's sound is on here.
const SOURCES := {&"mix": Ears.MIX, &"keys": Ears.KEYS}
## What each source is called on the tablet and the panel.
const TITLES := {&"mix": "MIX", &"keys": "MY KEYS"}
## A receiver's level: from off, through unity, to a little gain for a quiet source.
const FLOOR_DB := -60.0
const TOP_DB := 6.0

signal changed()

## Where each receiver's plug is: a source's name, or empty while it lies in the tablet's tray.
var sockets: Array[StringName] = []
## Each receiver's level, in dB; FLOOR_DB and under is off.
var levels_db: Array[float] = []


func _init() -> void:
	for i in RECEIVERS:
		sockets.append(&"")
		levels_db.append(0.0)


## A socket a plug may go into: one there is, or none.
static func valid_socket(socket: StringName) -> bool:
	return socket == &"" or SOURCES.has(socket)


## The plugs as the room has them, for this person: one socket name per receiver.
func set_sockets(to: Array) -> void:
	var now: Array[StringName] = []
	for i in RECEIVERS:
		var s := StringName(to[i]) if i < to.size() else &""
		now.append(s if valid_socket(s) else &"")
	if now == sockets:
		return
	sockets = now
	changed.emit()


func set_level(receiver: int, db: float) -> void:
	db = clampf(db, FLOOR_DB, TOP_DB)
	if receiver < 0 or receiver >= RECEIVERS or is_equal_approx(levels_db[receiver], db):
		return
	levels_db[receiver] = db
	changed.emit()


func is_patched() -> bool:
	return sockets.any(func(s: StringName) -> bool: return s != &"")


## What headphones play: {bus: dB}, for Ears.listen. Two receivers on one source add up, as two
## channels of a cue mixer fed the same thing do; a source nothing is patched to is not in it.
func ears_levels() -> Dictionary:
	if not is_patched():
		return Ears.PERSONAL
	var gain := {}
	for i in RECEIVERS:
		if sockets[i] == &"" or levels_db[i] <= FLOOR_DB:
			continue
		var bus: StringName = SOURCES[sockets[i]]
		gain[bus] = float(gain.get(bus, 0.0)) + db_to_linear(levels_db[i])
	var out := {}
	for bus in gain:
		out[bus] = linear_to_db(gain[bus])
	return out


## The bus whose sound receiver `receiver` carries, or empty.
func bus_of(receiver: int) -> StringName:
	var s := sockets[receiver]
	return SOURCES[s] if s != &"" else &""
