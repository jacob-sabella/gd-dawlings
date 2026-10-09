class_name MicArm
extends RefCounted

## What picking up the mic does to the session (docs/items_loop.md): your voice goes onto a track,
## and putting it down takes it off again, leaving the track as it was.
##
## On the host, the voice is the DAW's own input, so the mic asks for a track to be armed with
## its monitoring on (`Session.send_intent`): the host hears themself through the DAW at its
## buffer's latency, and a take lands on that track the moment the host records.
##
## A guest's voice is not the DAW's input -- it is this machine's microphone, recorded here and
## placed on the host's timeline by song position (GuestAudio). So for a guest the mic points
## GuestAudio at the track and opts in to recording with the host; it arms nothing on the host,
## because an armed track there records the HOST's input over the guest's take. Hearing yourself
## as a guest is not done yet: the native helper carries keys, not a voice (see
## docs/loop_backlog.md).

## Names that say a track is for a voice, in the order a mic tries them.
const VOCAL_WORDS: Array[String] = ["lead vox", "vox", "vocal", "voice", "sing"]

## The track the mic has a voice on, or 0.
var track := 0
## How it was before: [rec_arm, monitor] on the host, [target_track, record_with_host] on a guest.
var _was: Array = []
var _as_guest := false


## The track a mic sings into: the one a guest has already chosen for their mic, if any; else the
## first named for a voice; else the first track there is.
static func track_for(tracks: Dictionary, chosen := 0) -> int:
	if chosen > 0 and tracks.has(chosen):
		return chosen
	var order := tracks.keys()
	order.sort()
	for word in VOCAL_WORDS:
		for i in order:
			if (tracks[i].name as String).to_lower().contains(word):
				return i
	return order[0] if not order.is_empty() else 0


## The mic came into a hand here.
func take() -> void:
	if track != 0:
		return
	_as_guest = Session.role == Session.Role.GUEST
	var audio: GuestAudio = Session.guest_audio
	track = track_for(DAW.state.tracks, audio.target_track if _as_guest and audio != null else 0)
	if track == 0:
		Session.notice.emit("There is no track to sing into.")
		return
	var name: String = DAW.state.track(track).name
	if _as_guest:
		if audio == null:
			track = 0
			return
		_was = [audio.target_track, audio.record_with_host]
		audio.target_track = track
		audio.record_with_host = true
		Session.notice.emit("Your mic is on %s: it records when the host records." % name)
	else:
		var t := DAW.state.track(track)
		_was = [t.rec_arm, t.monitor]
		Session.send_intent(&"set_track_rec_arm", [track, true])
		Session.send_intent(&"set_track_monitor", [track, DAW.MONITOR_ON])
		Session.notice.emit("Your mic is on %s, armed." % name)


## The mic left this hand, however it left.
func let_go() -> void:
	if track == 0:
		return
	if _as_guest:
		var audio: GuestAudio = Session.guest_audio
		if audio != null and _was.size() == 2:
			audio.target_track = _was[0]
			audio.record_with_host = _was[1]
	elif _was.size() == 2:
		Session.send_intent(&"set_track_rec_arm", [track, _was[0]])
		Session.send_intent(&"set_track_monitor", [track, _was[1]])
	track = 0
	_was = []
