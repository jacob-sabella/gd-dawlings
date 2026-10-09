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
## The master's send sockets, by name, and the bus each one's sound is on here.
const SOURCES := {&"mix": Ears.MIX, &"keys": Ears.KEYS}
## What each source is called on the tablet and the panel.
const TITLES := {&"mix": "MIX", &"keys": "MY KEYS"}
## A channel strip's send socket is named for its track: "track_5". Its sound here is the track's
## cue (GodotBackend.cue_bus), where this machine plays the tracks itself.
const TRACK := "track_"
## A player's keys, on the pack their ghost wears: "keys_7", by peer id. Their notes are played
## here (TheirKeys), so wherever this machine is, it hears them.
const PLAYER := "keys_"
## A receiver's level: from off, through unity, to a little gain for a quiet source.
const FLOOR_DB := -60.0
const TOP_DB := 6.0

signal changed()

## Where each receiver's plug is: a source's name, or empty while it lies in the tablet's tray.
var sockets: Array[StringName] = []
## Each receiver's level, in dB; FLOOR_DB and under is off.
var levels_db: Array[float] = []
## Whether this machine plays the tracks one by one, so a track's socket can be heard here: the
## built-in engine on a host. A guest has the host's mix in one stream, and Reaper plays itself.
var hears_tracks := false:
	set(v):
		if v != hears_tracks:
			hears_tracks = v
			changed.emit()


func _init() -> void:
	for i in RECEIVERS:
		sockets.append(&"")
		levels_db.append(0.0)


## A socket a plug may go into: one there is, or none.
static func valid_socket(socket: StringName) -> bool:
	return socket == &"" or SOURCES.has(socket) or track_of(socket) > 0 or player_of(socket) > 0


static func track_socket(index: int) -> StringName:
	return StringName(TRACK + str(index))


## The track a socket is on a strip of, or 0 for the master's.
static func track_of(socket: StringName) -> int:
	return _numbered(socket, TRACK)


static func player_socket(peer: int) -> StringName:
	return StringName(PLAYER + str(peer))


## The player whose keys a socket is on, or 0.
static func player_of(socket: StringName) -> int:
	return _numbered(socket, PLAYER)


static func _numbered(socket: StringName, prefix: String) -> int:
	var s := String(socket)
	if not s.begins_with(prefix) or not s.substr(prefix.length()).is_valid_int():
		return 0
	return maxi(int(s.substr(prefix.length())), 0)


## What a socket is called: the master's by TITLES, a strip's by its track's name.
static func title_of(socket: StringName) -> String:
	if TITLES.has(socket):
		return TITLES[socket]
	var peer := player_of(socket)
	if peer > 0:
		return "%s'S KEYS" % Session.name_of(peer).to_upper()
	var index := track_of(socket)
	if index <= 0:
		return ""
	var t: MixState.TrackState = DAW.state.tracks.get(index)
	return t.display_name().to_upper() if t != null else "TRACK %d" % index


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
		var bus := bus_of(i)
		if bus == &"" or levels_db[i] <= FLOOR_DB:
			continue
		gain[bus] = float(gain.get(bus, 0.0)) + db_to_linear(levels_db[i])
	var out := {}
	for bus in gain:
		out[bus] = linear_to_db(gain[bus])
	return out


## The bus whose sound receiver `receiver` carries, or empty: nothing patched, or a track this
## machine does not play by itself.
func bus_of(receiver: int) -> StringName:
	var s := sockets[receiver]
	if SOURCES.has(s):
		return SOURCES[s]
	if player_of(s) > 0:
		return TheirKeys.bus_of(player_of(s))
	var index := track_of(s)
	return GodotBackend.cue_bus(index) if index > 0 and hears_tracks else &""


## Whether receiver `receiver` is in a socket whose sound does not reach this machine by itself.
func unheard(receiver: int) -> bool:
	return sockets[receiver] != &"" and bus_of(receiver) == &""


## The tracks patched, for their cues to be played: in order, each once.
func tracks() -> Array[int]:
	var out: Array[int] = []
	for s in sockets:
		var index := track_of(s)
		if index > 0 and index not in out:
			out.append(index)
	out.sort()
	return out


## The players whose keys are patched, each once, in order.
func players() -> Array[int]:
	var out: Array[int] = []
	for s in sockets:
		var peer := player_of(s)
		if peer > 0 and peer not in out:
			out.append(peer)
	out.sort()
	return out
