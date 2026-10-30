class_name LookSolo
extends RefCounted

## Look to solo (docs/spatial_loop.md part three, G): with the signal view on, held, the track
## looked at is soloed alone -- every other solo let go, the track itself unmuted -- and let go,
## every solo and mute this touched is put back exactly as it was.
##
## Held is U at a desk (the track under the cursor, Studio's mouse hand) or, in a headset, a hand
## cupped to an ear: a controller's grip squeezed with the controller beside the head, or a bare
## hand held open there (Studio._follow_look_solo; the head's gaze is what is looked at). While
## held the solo follows the look, once it has rested FOLLOW_AFTER on another track: a look round
## the room is a listen round the mix.
##
## Every write is DAW's, group-free (a grouped track's mates are not soloed with it), inside one edit
## "Look to solo" from press to let-go, so the history gains one step that, once let go, changes
## nothing. It runs where the mix is: on the host. A guest's ask is the room verb `look_solo`
## (Session.ROOM_VERBS; the track, 0 to let go) and the host runs a LookSolo for that guest, said to
## the room, since a guest hears only the host's stereo mix and there is no solo in one player's
## ears alone. One look-solo in the room at a time: a second, while one is held, is refused and
## told who has it. It never sticks: the window losing focus lets go (Studio._notification), a guest
## leaving lets theirs go (Session.participant_left), and a project replaced forgets what it held.

## The look must rest on another track this long (s) before the solo moves to it.
const FOLLOW_AFTER := 0.3
## The edit's name in the history.
const EDIT := "Look to solo"

## Whether it is held now, and the track soloed (0 while held over nothing).
var held := false
var track := 0
## Whose it is: 0 for this machine, else the guest's peer, whose writes these are (DAW.on_behalf_of).
var peer := 0

## Every track this changed, as it was: {track: [solo, mute]}.
var _was := {}
## Whether the other solos have been let go yet: only once a track is looked at, so a press at
## nothing changes nothing.
var _cleared := false
var _looking := 0
var _looked_for := 0.0


## Pressed, looking at `on_track` (0 for nothing yet): held, and that track soloed alone. Words to
## say, or "" for nothing to say.
func press(on_track: int) -> String:
	if held:
		return ""
	held = true
	_was.clear()
	track = 0
	_looking = on_track
	_looked_for = 0.0
	_cleared = false
	_as_peer(func() -> void: DAW.open_edit(EDIT))
	_solo(on_track)
	if track == 0:
		return "Look to solo: look at a track (a voice, a strip, a lane) to hear it alone."
	return "%s alone while held (look to solo): let go to put every solo back." % _title(track)


## One frame held, `delta` on, looking at `on_track`: the solo moves to it once the look has
## rested FOLLOW_AFTER on it. Words to say when it moved, else "".
func look(on_track: int, delta: float) -> String:
	if not held or on_track <= 0 or on_track == track:
		_looking = on_track
		_looked_for = 0.0
		return ""
	if on_track != _looking:
		_looking = on_track
		_looked_for = 0.0
	_looked_for += delta
	if _looked_for < FOLLOW_AFTER:
		return ""
	var from := track
	if from > 0:
		_put_back(from)
		# Back as it was, which may be soloed: it was one of the solos let go at the press.
		_set_solo(from, false)
	_solo(on_track)
	return "%s alone now (look to solo)" % _title(track) if track > 0 else ""


## Let go: every solo and mute this touched put back as it was, the edit closed. Words to say.
func release() -> String:
	if not held:
		return ""
	held = false
	var was := track
	for i in _was.keys():
		_put_back(i)
	_was.clear()
	track = 0
	_looking = 0
	_as_peer(func() -> void: DAW.close_edit())
	return "Look to solo let go: every solo and mute as it was." if was > 0 else ""


## Forgotten without writing anything: the project it held solos in is gone.
func forget() -> void:
	held = false
	track = 0
	_was.clear()


func _solo(on_track: int) -> void:
	var t := DAW.state.track(on_track, false) if on_track > 0 else null
	if t == null:
		track = 0
		return
	track = on_track
	if not _cleared:
		_cleared = true
		for i in DAW.state.track_indices():
			var other := DAW.state.track(i, false)
			if i != on_track and other != null and other.solo:
				_keep(i)
				_set_solo(i, false)
	_keep(on_track)
	if t.mute:
		_set_mute(on_track, false)
	if not t.solo:
		_set_solo(on_track, true)


func _keep(i: int) -> void:
	if _was.has(i):
		return
	var t := DAW.state.track(i, false)
	if t != null:
		_was[i] = [t.solo, t.mute]


func _put_back(i: int) -> void:
	var t := DAW.state.track(i, false)
	if t == null or not _was.has(i):
		return
	var was: Array = _was[i]
	if t.solo != bool(was[0]):
		_set_solo(i, bool(was[0]))
	if t.mute != bool(was[1]):
		_set_mute(i, bool(was[1]))


func _set_solo(i: int, on: bool) -> void:
	_as_peer(func() -> void:
		DAW.set_group_free(true)
		DAW.set_track_solo(i, on))


func _set_mute(i: int, on: bool) -> void:
	_as_peer(func() -> void:
		DAW.set_group_free(true)
		DAW.set_track_mute(i, on))


func _as_peer(write: Callable) -> void:
	if peer == 0:
		write.call()
	else:
		DAW.on_behalf_of(peer, write)


static func _title(i: int) -> String:
	var t := DAW.state.track(i, false)
	return t.display_name().to_upper() if t != null else "TRACK %d" % i
