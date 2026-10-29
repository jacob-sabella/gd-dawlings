class_name ControlAffordance
extends StaticBody3D

## Anything a hand or a cursor can take hold of: a fader cap, a knob, a button, a patch point.
##
## One contract for every input medium. A mouse ray, a tracked controller and a pinching hand all
## arrive here as the same three calls, which is the only reason the console works identically on
## a monitor and in passthrough. The temptation to give the mouse its own path -- because a mouse
## has a scroll wheel and a hand does not -- is what ends with two divergent control sets.
##
## GRABBED VALUES ARE PROVISIONAL. While held, a control shows the HAND's value and writes it to
## Reaper, and it ignores what Reaper echoes back about itself. On release it stops ignoring and
## snaps to whatever Reaper actually settled on. That gap is not a bug to hide: Reaper may clamp
## or quantise a value, and the fader should end up where the mix really is rather than where the
## hand left it.

signal grab_started(by: Node)
signal grab_ended(by: Node)
signal value_committed(value: float)

## 0..1 in the control's own terms, whatever it drives.
@export var value: float = 0.0

var held_by: Node = null
## Somebody ELSE in the session has their hand on this -- on their own copy of it, in their own
## room. Set from outside (core/session/presence.gd), from the host's table of who holds what,
## and refused like a second local hand. Not `held_by`: a local hold also stops the control
## listening to the mix, and a fader somebody else is moving must keep moving under your eyes.
var claimed_by: Object = null

## How long after a hand lets go the control keeps its own value against older echoes.
##
## A guest's fader writes go to the host and come back, and the replies still in flight at the
## moment of release describe where the fader WAS -- so a released fader jumped back down its
## travel and then up again as the queue drained, which reads as the desk refusing the move.
## For this long, an echo that is not the value the hand left is held back; the one that is
## ends the wait early; and when the wait runs out the newest held-back value is applied, so a
## mix that really did settle somewhere else (Reaper clamps, quantises) still has the last word.
const SETTLE_MSEC := 450

## One undo step for the whole of a grab, for a control whose drag writes more than one value (a
## puck that is pan and volume, a grouped fader that moves its group): DAW.open_edit when the hand
## closes, DAW.close_edit when it lets go. Writes to one control fold by time already; writes to
## several, alternating every frame, do not, and without this a drag is a step a frame.
var edits_as_one := false
## () -> String. What this control's edit is called in the history list; see edit_name.
var describe_edit: Callable = Callable()
## Whether this control's edit is open, so one let-go closes exactly the one grab opened.
var _edit_open := false
## Whether the edit open is a scroll's (nudge) rather than a grab's, and when it ends: notches
## closer together than OfflineBackend.GESTURE_MS are one gesture, as a drag's frames are.
var _scrolling := false
var _scroll_ends_at := 0
## The control whose edit is open on this machine. One player has one edit open at a time
## (DAW.open_edit), so a second hand's grab, or a scroll on another control, opens its own over
## it; a let-go then closes it only if it is still the one this control opened.
static var _edit_owner: ControlAffordance = null

var _settle_until := 0
var _settle_value := 0.0
var _settle_pending := NAN


const GROUP := &"controls"


func _enter_tree() -> void:
	add_to_group(GROUP)


## Held by a hand, or written by a write bead over it (WriteBead): either way its value is not
## the mix's to move until it is let go, and nothing may rebuild or re-point it meanwhile.
func is_held() -> bool:
	return held_by != null or bead != null


# --- automation by gesture (docs/spatial_loop.md part two, slice 22) --------------------------

## () -> Array: the lane this control writes, [track index, target] as MixState.TrackState.
## automation names it ("volume", "pan", "mute", "send:<destination>", "fx:<slot>:<param>"; track 0
## the master), or [] for none. Set by whoever builds the control, as `describe_title` is, and
## asked each time, because a strip flipped to show a send is writing a different lane.
var automates: Callable = Callable()
## (value: float, again: bool) -> void. How a write bead's value is written, for a control whose
## own path is not a value (a mute button): the bead's 0..1, as the lane would set it. `again` is a
## still bead's keep-alive (write_from_bead), which must reach the DAW even when nothing changes.
## Unset, the control's own `_on_bead_write` is used.
var bead_writes: Callable = Callable()
## The write bead writing this control now, or null. While it is, the control ignores the mix's
## echoes as a held one does, and a hand cannot take it: the bead was first.
var bead: Node = null


## The lane a write bead over this control writes ([track index, target]), or [] when it writes
## none: no `automates`, or a target DawKitAutomation cannot name.
func automation_target() -> Array:
	if not automates.is_valid():
		return []
	var lane = automates.call()
	if not (lane is Array) or (lane as Array).size() != 2 or typeof(lane[0]) not in [TYPE_INT, TYPE_FLOAT] \
			or int(lane[0]) < 0 or DawKitAutomation.kind_of(str(lane[1])).is_empty():
		return []
	return [int(lane[0]), str(lane[1])]


## Where a write bead stands over this control and where its thread starts, in the control's own
## space. Overridden where "above" is somewhere else: a fader's bead stands over the top of its
## travel, its thread from the cap.
func bead_anchor() -> Vector3:
	return Vector3(0, 0.032, 0.016)


func bead_foot() -> Vector3:
	return Vector3(0, 0, 0.006)


## The bead's value (0..1, this control's own terms) written as the hand would write it, so the
## control follows the bead and the mix follows the control. `again`: the same value written once
## more by a still bead (WriteBead.KEEP_ALIVE_MSEC), so the edit it is in has a write and is not
## closed as idle; a control that writes only what changes (`bead_writes`) writes it anyway.
func write_from_bead(v: float, again := false) -> void:
	v = clampf(v, 0.0, 1.0)
	if bead_writes.is_valid():
		value = v
		_on_value_changed()
		bead_writes.call(v, again)
		return
	_on_bead_write(v)


## Override: write `v` wherever a drag would. The default only shows it.
func _on_bead_write(v: float) -> void:
	value = v
	_on_value_changed()


# --- a cassette onto a track (docs/spatial_loop.md part two, slice 24) ------------------------

## () -> int: the track a cassette pressed on this control pastes onto, at the playhead: a console
## strip's controls, a stage voice. Set by whoever builds the control, as `automates` is, and asked
## each time. Unset, or 0, nothing pastes here, and a press with a cassette in the hand works the
## control as ever.
var pastes_onto: Callable = Callable()


## Where something that pastes (Item.pastes), pressed on this control at `at` (global), goes:
## [track, song seconds], or [] for nowhere. `fine` is the hand's fine modifier, for a control
## whose time snaps (TimelineLanes). By `pastes_onto`, at the playhead.
func paste_spot(_at: Vector3, _fine: bool) -> Array:
	if not pastes_onto.is_valid() or DAW.state == null:
		return []
	var track := int(pastes_onto.call())
	if track <= 0 or not DAW.state.tracks.has(track):
		return []
	return [track, DAW.state.position_seconds]


## Where `item` (one that pastes), pressed on this control at `at`, goes: `paste_spot`, for
## anything a track takes. Override where what is pressed matters: a section block takes a chord
## brick and nothing else (docs/spatial_loop.md part two, slice 31).
func paste_spot_for(_item: Item, at: Vector3, fine: bool) -> Array:
	return paste_spot(at, fine)


## What a press here would paste, for a hand over this control carrying something that pastes:
## "click pastes the Kick Verse 1 cassette onto Bass at 12.1.00"; "" for none. What the hover card
## says instead of the control's own hint, since the press is the paste's. What the carried thing
## says it does there (Item.paste_text: a chord brick's chords) where it says.
func paste_words() -> String:
	for by in _hovered_by:
		var hand := by as Interactor
		if hand == null or not is_instance_valid(hand.carrying) or not hand.carrying.pastes():
			continue
		var spot := paste_spot_for(hand.carrying, hand.hover_point, hand.fine())
		if spot.is_empty():
			continue
		var desk := hand is MouseInteractor
		# The press as the hand has it (Interactor.paste_press_words): a bare hand has no trigger.
		var press := hand.paste_press_words()
		var does := hand.carrying.paste_text(spot)
		if does.is_empty():
			var cassette := hand.carrying as CassetteItem
			var what := "the %s cassette" % cassette.clip_name() if cassette != null else hand.carrying.item_title().to_lower()
			does = "pastes %s onto %s at %s" % [what, DAW.state.track(int(spot[0])).display_name(),
					DAW.state.bar_beat(float(spot[1]))]
		return "%s %s; %s" % [press + ("," if press.contains(" or ") else ""), does,
				"Q puts it down" if desk else "letting go puts it down"]
	return ""


## The hover card's hint: `hint()`, and while the song plays, on a control a write bead can write,
## that the bead is there. With a cassette in the hand over a control it pastes onto, what the press
## pastes, and where (`paste_words`).
func card_hint() -> String:
	var pasting := paste_words()
	if not pasting.is_empty():
		return pasting
	var said := hint()
	if automation_target().is_empty() or DAW.state == null or not DAW.state.playing:
		return said
	var bead_words := "the bead above writes automation"
	return bead_words if said.is_empty() else "%s  ·  %s" % [said, bead_words]


## The name this control goes by across the session: how one participant's "I am holding
## this" is matched to the same control on everyone else's desk. Stable across machines by
## construction, because it is what the control SAYS it is -- "KICK  VOLUME" -- and not where it
## sits in a scene tree that each participant has arranged differently. Override where the
## title is about the pointer rather than the control.
func network_key() -> String:
	return title()


## Mine alone: never claimed as a hold or shown as someone's pointer across the session. A
## wardrobe button by a mirror is; a fader is not.
func personal() -> bool:
	return false


## Something that plays while the cursor is over it, with no hand on it: the harp's strings, which
## a wiggle of the mouse over a ringing one wobbles (MouseInteractor.wiggle; docs/spatial_loop.md
## part two, slice 15). False for everything that is only worked by a grab.
func plays_under_cursor() -> bool:
	return false


## `at` is the contact point in global space -- the ray hit, or the fingertip.
## Can this control be worked by looking at it, without a press?
##
## False by default, and the default is the careful one. Dwell is the alternative to a press for
## anyone who cannot hold a trigger steady, cannot pinch, or is working one-handed with a cable
## in the other -- but it fires from ATTENTION, and attention lands on things by accident all
## the time. A momentary button that gets dwelt on fires a command the person can undo; a fader
## that gets dwelt on takes a mix somewhere they did not ask for and cannot easily get back.
## So controls opt in, and only the ones where a mistaken activation is cheap do.
func dwell_activates() -> bool:
	return false


## How far through its dwell this control is, 0 to 1. Override to show it.
##
## Not optional in practice. A timer that fires with no indication of how long is left is the
## interaction equivalent of an unlabelled button: the first thing anyone does is look away in
## case it goes off, which defeats the mechanism.
func set_dwell_progress(_fraction: float) -> void:
	pass


func grab_begin(by: Node, at: Vector3) -> void:
	if claimed_by != null or bead != null:
		return
	if held_by != null and held_by != by:
		# Two people reaching for one fader. First hand wins and the second is simply told no,
		# rather than the two averaging into a value neither person asked for.
		return
	held_by = by
	if edits_as_one:
		# Before the handler: a control that writes on contact (the trough of a fader) writes
		# into the edit too.
		_open_edit()
	else:
		_end_others_scroll()
	_on_grab_begin(at)
	# After the handler, so a control whose sound depends on where it was grabbed has been told
	# where that was. Before the signal, because the signal is what the rest of the scene reacts
	# to and the noise the object makes should not arrive after its consequences.
	Foley.play(self, _foley_contact(), contact_volume_db)
	grab_started.emit(by)


func grab_move(by: Node, at: Vector3) -> void:
	if held_by != by:
		return
	_on_grab_move(at)


func grab_end(by: Node) -> void:
	if held_by != by:
		return
	_on_grab_end()
	held_by = null
	_close_edit()
	_hold_against_echoes()
	grab_ended.emit(by)
	value_committed.emit(value)


## A grab that lapses without a let-go -- the control taken out of the room in a hand -- still
## closes its edit, or history would wait EDIT_IDLE for a release that is never coming.
func _exit_tree() -> void:
	_close_edit()


## What this control's edit is called in the history list, or "" for the name of its first write
## ("Kick: volume"), which is right for a control that is one thing however much it moves. Set
## `describe_edit` where the gesture is more than that: a puck that is pan and volume is "Kick:
## place", not "Kick: pan".
func edit_name() -> String:
	return describe_edit.call() if describe_edit.is_valid() else ""


func _open_edit() -> void:
	_end_others_scroll()
	DAW.open_edit(edit_name())
	_edit_open = true
	_scrolling = false
	_edit_owner = self


func _close_edit() -> void:
	if not _edit_open:
		return
	_edit_open = false
	_scrolling = false
	if _edit_owner == self:
		_edit_owner = null
		DAW.close_edit()


## Another control's scroll still gathering is over once this one is taken hold of: what this
## hand does next is not part of that wheel turn.
func _end_others_scroll() -> void:
	if _edit_owner != null and _edit_owner != self and is_instance_valid(_edit_owner) and _edit_owner._scrolling:
		_edit_owner._close_edit()


## Reaper says this control is now at `v`. Honoured unless a hand is on it.
func apply_remote(v: float) -> void:
	if is_held():
		return
	if Time.get_ticks_msec() < _settle_until:
		if absf(v - _settle_value) < 0.0005:
			_settle_until = 0
			_settle_pending = NAN
		else:
			_settle_pending = v
			return
	value = v
	_on_value_changed()


## Take `v` now, past the echo wait: for when the control has been pointed at a different
## value altogether (a strip flipped to show a send), so what it was waiting for is moot.
func snap_to(v: float) -> void:
	if is_held():
		return
	_settle_until = 0
	_settle_pending = NAN
	apply_remote(v)


func is_settling() -> bool:
	return Time.get_ticks_msec() < _settle_until


func _hold_against_echoes() -> void:
	_settle_value = value
	_settle_pending = NAN
	_settle_until = Time.get_ticks_msec() + SETTLE_MSEC
	if is_inside_tree():
		get_tree().create_timer(SETTLE_MSEC / 1000.0 + 0.01).timeout.connect(_echo_wait_over)


func _echo_wait_over() -> void:
	if not is_instance_valid(self) or is_held() or is_settling():
		return
	if not is_nan(_settle_pending):
		var v := _settle_pending
		_settle_pending = NAN
		apply_remote(v)


## What this control sounds like when a hand closes on it, or null for the ones that are silent.
##
## The MECHANISM lives here and the SOUND does not, which is the whole point: in a headset every
## control needs to be able to say "you have me" at the instant it is true, so no control should
## have to grow its own player to do it. But a fader cap does not click and a patch point does
## not tick, and a base class that invented a generic noise for everything would be worse than
## silence -- it would make four different objects feel like the same object.
func _foley_contact() -> AudioStream:
	return null


## Trimmed per control, because these are not equally loud in life. A button is the loudest thing
## on a desk and a knob detent is near the floor of what you can hear over a monitor mix.
var contact_volume_db: float = 0.0


# --- nudging ---------------------------------------------------------------------------------

## A relative adjustment with no position: a scroll-wheel notch, a thumbstick flick.
##
## The mouse's best gesture and the one this contract was missing. Over a knob in any DAW the
## wheel turns the knob; here it zoomed the camera, which is the kind of thing that makes
## a person stop trusting the wheel at all. It is a member of the contract, not a mouse path
## beside it, for the reason dwell is: it is another way to say "set this", to the same control,
## and a headset's thumbstick says it too.
##
## Returns whether the control took it. A button has no "a bit more", and the wheel should go on
## meaning zoom over one rather than doing nothing.
##
## Refused while someone ELSE holds the control, for the same reason a second grab is: their
## hand is the value until they let go.
func nudge(by: Node, notches: int, fine: bool) -> bool:
	if notches == 0 or claimed_by != null or bead != null or (held_by != null and held_by != by):
		return false
	# A wheel turn on a control that writes several values is one step, as its drag is: the first
	# notch opens an edit, and notches closer together than GESTURE_MS share it. Not while a
	# grab's edit is open on it -- the notch is part of that drag.
	var gathering := edits_as_one and is_inside_tree() and not (_edit_open and not _scrolling)
	if gathering and not (_edit_open and _edit_owner == self):
		_open_edit()
		_scrolling = true
	elif not edits_as_one:
		_end_others_scroll()
	if not _on_nudge(notches, fine):
		if gathering and _scrolling:
			_close_edit()
		return false
	if gathering:
		_scroll_ends_at = Time.get_ticks_msec() + OfflineBackend.GESTURE_MS
		get_tree().create_timer(OfflineBackend.GESTURE_MS / 1000.0).timeout.connect(_end_scroll)
	_hold_against_echoes()
	# A nudge is a whole gesture, so it commits like the end of one. Whatever records history
	# listens to this, and a wheel turn that it never heard of would be a change nobody can undo.
	value_committed.emit(value)
	return true


## A scroll's edit closed once no notch has come for GESTURE_MS. Each notch sets a timer; one
## that fires while a later notch is still within its time waits out the rest of it.
func _end_scroll() -> void:
	if not _scrolling:
		return
	var left := _scroll_ends_at - Time.get_ticks_msec()
	if left <= 0 or not is_inside_tree():
		_close_edit()
	else:
		get_tree().create_timer(left / 1000.0 + 0.005).timeout.connect(_end_scroll)


## Override to accept nudges. Move `value`, write it wherever a drag would, return true.
func _on_nudge(_notches: int, _fine: bool) -> bool:
	return false


# --- saying what it is ----------------------------------------------------------------------
#
# A hand on a fader knows it is on the fader. A cursor over one does not: it has no weight, no
# contact, nothing but a picture of an arrow on top of a picture of a desk. On a monitor the
# only way to know what you are about to move is for the thing to say so, and to say what it is
# set to in the units the mix is made of, not as a position.
#
# Set by whoever BUILDS the control, because that is what knows the meaning. A knob does not
# know it is the kick's pan; the strip that put it there does. The defaults are only what the
# control can say about itself without being told.

## () -> String. What this is: "KICK  PAN", "REACOMP  THRESHOLD".
var describe_title: Callable = Callable()
## (value: float) -> String. What it is set to, in its own units: "-4.2 dB", "L 30".
var describe_value: Callable = Callable()

var _hovered_by: Array[Node] = []

signal hover_changed(hovered: bool)


func title() -> String:
	if describe_title.is_valid():
		return describe_title.call()
	return _default_title()


func readout() -> String:
	if describe_value.is_valid():
		return describe_value.call(value)
	return _default_readout()


## What can be done to it, in words, for anyone who has not been told. Kept short: this sits
## under the value on the hover card and is read once, then ignored, which is the point.
func hint() -> String:
	return ""


func is_hovered() -> bool:
	return not _hovered_by.is_empty()


## Counted per interactor, not a flag. Two hands, or a hand and a cursor in a hybrid session,
## can rest on one control, and the first to leave must not switch the highlight off under
## the second.
func hover_enter(by: Node) -> void:
	if by in _hovered_by:
		return
	_hovered_by.append(by)
	if _hovered_by.size() == 1:
		hover_changed.emit(true)


func hover_exit(by: Node) -> void:
	if not by in _hovered_by:
		return
	_hovered_by.erase(by)
	if _hovered_by.is_empty():
		hover_changed.emit(false)


func _default_title() -> String:
	return String(name).to_upper()


func _default_readout() -> String:
	return "%d%%" % roundi(value * 100.0)


func _on_grab_begin(_at: Vector3) -> void: pass
func _on_grab_move(_at: Vector3) -> void: pass
func _on_grab_end() -> void: pass
func _on_value_changed() -> void: pass
