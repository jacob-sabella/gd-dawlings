class_name StageTable
extends Surface

## The stereo field as a stage (docs/spatial_loop.md slice 18, idea #1): a table on a trolley
## beside the desk, at desk height, with the tracks standing on it as voices (StageVoice). Across
## the table is pan, left to right as the player sees it; back from the front edge is level, +6 dB
## at the front edge and -40 dB at the back, linear in decibels, and past the back edge is -inf;
## the ring round a voice's foot is its width, 2 cm across for mono to 8 cm for full width.
##
## Its frame: the origin is the middle of the table top, +Y up, +Z toward the player. The front
## edge carries a sloped rail with a tag for each voice (its number and name, what it is set to,
## PAN < > keys and a RESET key), the bank keys at the left end and the SHOW key at the right.
## A tag's name is a handle on its voice (NameGrip): tracks at one pan and level stand in one
## place, and the name is how a ball under another is taken.
##
## Banked like the console: it shows eight tracks at a time, paged within the cached bank and
## asking the DAW for another bank past its end (ConsoleSurface._go_to_track). Or it shows the
## soloed tracks, or the selected ones (SHOW).
##
## Every write goes through DAW, so a guest's placing is an intent the host carries out, and a
## placing is one edit (StageVoice.edits_as_one): pan, volume and the width the wheel set while it
## was held are one undo step.
##
## Depth is its own handle (docs/spatial_loop.md slice 19): each voice stands on a stalk
## (StageVoice.Stalk), and how far it is lifted off the table, up to StageVoice.STALK_MOST, is
## how much it sends to the project's room (`room_track`), ROOM_LOW_DB just off the table to
## ROOM_TOP_DB at the top, linear in decibels. A mist round the voice shows the send; a voice on
## the table has none, however quiet it is. The first lift makes the send, inside the lift's own
## edit (`send_to_room`). With no room, the ROOM key on the rail's left end makes one (`add_room`):
## a track ROOM with a reverb on it.
##
## A sidechain is a rope (docs/spatial_loop.md slice 20, idea #18): dragged from the knot under one
## voice (StageVoice.Knot) to another, a rope is tied (`tie`), in one edit: the key send
## (DAW.create_sidechain) and a compressor on the other track listening to it, added first if it has
## none. Whether the rope added it is a room row (`ropes`), so whoever cuts it takes away only what
## it made. Every key send between two voices on the table is a rope (`Rope`), whoever made it: it
## sags when slack and lifts straight each time its track ducks, by Sidechain's estimate from the
## key's meter. Pulling its middle away ducks harder: the key send up and the threshold down,
## together, one undo step a let-go. The X beside the knot, or Backspace over the rope, cuts it
## (`cut`), one edit again. No verb of its own: create_sidechain, add_fx, set_send_volume,
## set_fx_param, remove_send and remove_fx.

## The top, across and deep (m), and how thick it is.
const SIZE := Vector2(1.2, 0.9)
const THICK := 0.04
## The levels the front and back edges stand for, and the decibel lines printed between.
const FRONT_DB := 6.0
const BACK_DB := -40.0
const LINES_DB := [6.0, 0.0, -6.0, -12.0, -20.0, -30.0, -40.0]
## How far either side of the middle hard left and hard right stand (m): short of the edge, so a
## hard-panned voice and its ring are on the table.
const HALF_PAN := 0.54
## Where a voice at -inf stands: on the lip behind the back edge.
const OFF_Z := -SIZE.y * 0.5 - 0.0175
## The ring's radius at no width and at full width (m).
const RING_MIN := 0.02
const RING_MAX := 0.08
## How near the middle a voice is put dead centre, unless fine (m).
const SNAP := 0.01
## Two presses without a drag this close together (s) put a track back: centre, 0 dB, full width.
const DOUBLE_PRESS := 0.35
## Tracks shown at once, and the steps the wheel and the keys take.
const PAGE := 8
const DB_STEP := 0.5
const DB_FINE := 0.1
const PAN_STEP := 0.005
const PAN_WHEEL := 0.025
const WIDTH_STEP := 0.05
const WIDTH_FINE := 0.01
## The rail along the front edge: how deep down its slope, and how far each end is kept for the
## bank keys and the SHOW key.
const RAIL_DEEP := 0.16
const RAIL_END := 0.13
## What SHOW steps through.
const SHOWS := [&"bank", &"soloed", &"selected"]
## A voice's stalk is its send to the room: just off the table ROOM_LOW_DB, at StageVoice.STALK_MOST
## ROOM_TOP_DB, linear in dB between; on the table, no send at all. The wheel over a stalk moves
## it ROOM_STEP a notch, ROOM_FINE fine.
const ROOM_LOW_DB := -40.0
const ROOM_TOP_DB := 0.0
const ROOM_STEP := 1.0
const ROOM_FINE := 0.1
## What ADD ROOM calls the track it makes.
const ROOM_NAME := "ROOM"
## A send asked for and not come this long after (ms) is asked for again, by the next lift or
## notch: long past a host's answer or Reaper's poll, so one that is merely slow is not made twice.
const ASK_AGAIN_MSEC := 3000
## A rope let go within this of a voice's foot (m, across the table) is tied to it.
const TIE_REACH := 0.07
## How far a rope's middle is pulled away at the most (m): Sidechain's pull of 1. The wheel over a
## rope pulls PULL_STEP of that a notch, PULL_FINE fine.
const PULL_MOST := 0.2
const PULL_STEP := 0.05
const PULL_FINE := 0.01
## How far a slack rope sags (a share of its span, at most SAG_MOST m), and how much ducking pulls it
## straight (dB).
const SAG_SHARE := 0.35
const SAG_MOST := 0.08
const DUCK_TAUT_DB := 12.0
const ROPE_RADIUS := 0.0035
## How fast the key's heard peak falls (dB a second), for the card's "ducks N dB on each hit".
const PEAK_FALL_DB := 3.0

## The rope rows have changed here: the host publishes the room.
signal ropes_changed
## A line for the room's notices. The surface does not reach the network: whoever stands it up
## (StageLink.wire) relays this, and gives `hosting` and `asking` below.
signal told(text: String)

## What the table is showing: the bank (a page of it), the soloed tracks or the selected ones.
var showing := &"bank"
## Which page of the cached bank the table shows, as the index into its tracks of the first.
var view_offset := 0
## The voices standing on it and the tags for them, by track.
var voices := {}
var tags := {}

var _rail: Node3D
var _range_label: Label3D
var _show_label: Label3D
var _empty_label: Label3D
var _leads := {}
var _presses := {}
var _levels := {}
var _pending_view := -1
var _room_key: TableKey
var _room_label: Label3D
## Lifts waiting for their sends: {track: send taper}, set once the send arrives. A guest's, which
## the host makes, and a host's on a DAW that makes its sends later (Reaper, by its poll). And the
## sends asked for, {track: when}, so a drag asks once rather than every frame (and a later lift or
## notch again only after ASK_AGAIN_MSEC, `forget_asked`), and the room asked for.
var _room_wanted := {}
var _sends_asked := {}
var _room_asked := ""
## The room row of ropes: {"2>6": whether the rope added the compressor it keys} (Sidechain.rope_key).
## The host's is the room's; a guest's has its own unanswered ties and cuts on top (`_rows_asked`,
## {key: [ask, tied, added]}).
var ropes := {}
## Whether this process writes the mix itself (the host, or alone), and how a guest asks the host
## for a room change (its ask's number, 0 for none sent). Given by StageLink.wire; a table no one
## wired is a host by itself.
var hosting: Callable = func() -> bool: return true
var asking: Callable = func(_verb: StringName, _args: Array) -> int: return 0
var _rows_asked := {}
## The host's bookkeeping of rows against undo (`_reconcile_rows`): the rows whose key send it has
## seen in the cache; rows that said the rope added its compressor, taken off by a cut or an undo,
## kept for the redo or undo that brings their key send back; the keys standing at the last look;
## and whether a look is due at the frame's end.
var _rows_seen := {}
var _rows_shelved := {}
var _keys_standing := {}
var _reconcile_due := false
## The ropes standing on the table, by key; the rope being drawn from a knot, from which track and
## to where; ropes whose compressor was asked for and has not come, {key: [from, to]}, given their
## threshold when it does; and each key track's heard peak (dB).
var rope_nodes := {}
var _loose: MeshInstance3D
var _tying := 0
var _tie_at := Vector2.ZERO
var _rope_wanted := {}
var _key_peaks := {}


func _ready() -> void:
	surface_kind = &"stage"
	if surface_id == &"":
		surface_id = &"stage_table"
	# The top faces up, so on a monitor it is laid back most of the way, leaving the player
	# looking down onto it as they would standing at it.
	screen_pitch_degrees = 70.0
	super()
	DAW.track_changed.connect(_on_track_changed)
	DAW.track_added.connect(_on_track_added)
	DAW.fx_changed.connect(func(t: int, _f: int) -> void:
		_refresh_room()
		_rope_arrived(t)
		_refresh_ropes())
	DAW.bank_changed.connect(mark_dirty)
	DAW.project_replaced.connect(mark_dirty)
	_hook_pan_mode()


func _process(delta: float) -> void:
	super(delta)
	if _pending_view >= 0 and not _anything_held():
		var wanted := _pending_view
		_pending_view = -1
		_go_to(wanted)
	# Lit by its meter, which falls at its own pace (VUMeter decays the cache's peaks).
	for track in voices:
		var t := DAW.state.track(track, false)
		if t == null:
			continue
		var was: float = _levels.get(track, 0.0)
		var now := maxf(t.vu_l, t.vu_r)
		var level := now if now > was else lerpf(was, now, clampf(delta * 6.0, 0.0, 1.0))
		_levels[track] = level
		(voices[track] as StageVoice).glow(level)
	for key in rope_nodes:
		var rope: Rope = rope_nodes[key]
		var db := FaderLaw.to_db(float(_levels.get(rope.from, 0.0)))
		_key_peaks[rope.from] = maxf(db, float(_key_peaks.get(rope.from, -INF)) - PEAK_FALL_DB * delta)
		rope.ducking = Sidechain.ducks(rope.from, rope.to, db)
		rope.shape()


# --- the arithmetic of the table ------------------------------------------------------------

## Where on the table a track at `pan` and `db` stands (the table's frame, at a voice's height).
static func spot_of(pan: float, db: float) -> Vector3:
	return Vector3((clampf(pan, 0.0, 1.0) - 0.5) * 2.0 * HALF_PAN, StageVoice.LIFT, z_of_db(db))


## How far toward the player (m) a level stands: the front edge at FRONT_DB, the back at BACK_DB,
## anything louder at the front edge and -inf on the lip behind the back.
static func z_of_db(db: float) -> float:
	if db == -INF or db < BACK_DB - 0.001:
		return OFF_Z
	var f := (clampf(db, BACK_DB, FRONT_DB) - BACK_DB) / (FRONT_DB - BACK_DB)
	return lerpf(-SIZE.y * 0.5, SIZE.y * 0.5, f)


## The level a place on the table stands for: -inf past the back edge.
static func db_of_z(z: float) -> float:
	if z < -SIZE.y * 0.5:
		return -INF
	var f := (minf(z, SIZE.y * 0.5) + SIZE.y * 0.5) / SIZE.y
	return lerpf(BACK_DB, FRONT_DB, f)


static func pan_of_x(x: float) -> float:
	return clampf(0.5 + x / (2.0 * HALF_PAN), 0.0, 1.0)


static func db_of_volume(taper: float) -> float:
	return FaderLaw.to_db(taper)


## The ring's radius for a width, and the width for a radius.
static func ring_of(width: float) -> float:
	return lerpf(RING_MIN, RING_MAX, clampf(width, 0.0, 1.0))


static func width_of(radius: float) -> float:
	return clampf((radius - RING_MIN) / (RING_MAX - RING_MIN), 0.0, 1.0)


## A track's number in the project, as the console and the timeline number it.
static func number_of(track: int) -> int:
	return DAW.state.bank_offset + track


## "pan 20 L", "pan C".
static func pan_words(pan: float) -> String:
	var off := roundi((pan - 0.5) * 200.0)
	if off == 0:
		return "pan C"
	return "pan %d %s" % [absi(off), "L" if off < 0 else "R"]


static func db_words(taper: float) -> String:
	var db := FaderLaw.to_db(taper)
	if db == -INF:
		return "-inf dB"
	return "%+.1f dB" % db if db > 0.05 else "%.1f dB" % db


## The send to the room a stalk lifted `lift` (m) off the table stands for, in dB: -inf on it.
static func send_db_of_lift(lift: float) -> float:
	if lift <= 0.0005:
		return -INF
	return lerpf(ROOM_LOW_DB, ROOM_TOP_DB, clampf(lift / StageVoice.STALK_MOST, 0.0, 1.0))


## How far off the table (m) a send of `db` stands: on it at -inf, at the top for ROOM_TOP_DB or
## more. A send quieter than ROOM_LOW_DB, but a send, is just off the table, where it shows.
static func lift_of_send_db(db: float) -> float:
	if db == -INF or is_nan(db):
		return 0.0
	var f := (clampf(db, ROOM_LOW_DB, ROOM_TOP_DB) - ROOM_LOW_DB) / (ROOM_TOP_DB - ROOM_LOW_DB)
	return maxf(f * StageVoice.STALK_MOST, 0.001)


## Whether a track's chain holds a reverb, by its plugins' names: "ReaVerbate", "Reverb".
static func has_reverb(t: MixState.TrackState) -> bool:
	if t == null:
		return false
	for f in t.fx.values():
		if (f as MixState.FXState).name.to_lower().contains("verb"):
			return true
	return false


## The project's room: the first track whose chain holds a reverb and that another track sends to
## (into its mix, not its key). With none, the first called ROOM_NAME with a reverb, which ADD ROOM
## made and nothing yet sends to. 0 for none.
static func room_track() -> int:
	var s := DAW.state
	if s == null:
		return 0
	var sent := {}
	for i in s.track_indices():
		for send in (s.tracks[i] as MixState.TrackState).sends.values():
			var to := (send as MixState.SendState).resolve(s)
			if to > 0 and to != i and not (send as MixState.SendState).key:
				sent[to] = true
	for i in s.track_indices():
		if sent.has(i) and has_reverb(s.tracks[i]):
			return i
	for i in s.track_indices():
		var t: MixState.TrackState = s.tracks[i]
		if t.display_name().to_upper() == ROOM_NAME and has_reverb(t):
			return i
	return 0


## Which of `track`'s sends goes to `room` (its send number, 1 first), 0 for none.
static func send_to(track: int, room: int) -> int:
	var t := DAW.state.track(track, false) if DAW.state != null else null
	if t == null or room <= 0:
		return 0
	for n in t.sends:
		var send: MixState.SendState = t.sends[n]
		if not send.key and send.resolve(DAW.state) == room:
			return int(n)
	return 0


## How loud `track` sends to the room, in dB: -inf with no room or no send.
static func room_send_db(track: int) -> float:
	var room := room_track()
	var n := send_to(track, room)
	if n == 0:
		return -INF
	return FaderLaw.to_db((DAW.state.track(track).sends[n] as MixState.SendState).volume)


## The plugin a room is made with: the first of the DAW's choices that is a reverb, by its id or
## name; empty where it offers none.
static func reverb_choice() -> String:
	if DAW.state == null:
		return ""
	for c in DAW.state.fx_choices:
		var row := c as Array
		if row.size() >= 2 and (str(row[0]).to_lower().contains("verb") or str(row[1]).to_lower().contains("verb")):
			return str(row[0])
	return ""


# --- what it shows --------------------------------------------------------------------------

## The tracks on the table, in order: a page of the bank, or the soloed or selected tracks (at
## most a page of them).
func shown_tracks() -> Array:
	var indices := DAW.state.track_indices()
	if showing == &"bank":
		view_offset = clampi(view_offset, 0, maxi(0, indices.size() - 1))
		view_offset -= view_offset % PAGE
		return indices.slice(view_offset, mini(view_offset + PAGE, indices.size()))
	var out := []
	for i in indices:
		var t: MixState.TrackState = DAW.state.tracks[i]
		if (t.solo if showing == &"soloed" else t.selected):
			out.append(i)
			if out.size() == PAGE:
				break
	return out


## "9-16 OF 40": which tracks the bank keys have the table on.
func range_text() -> String:
	var shown := shown_tracks() if showing == &"bank" else DAW.state.track_indices().slice(view_offset, view_offset + PAGE)
	if shown.is_empty():
		return "NO TRACKS"
	var total := DAW.state.project_track_count
	if total <= 0:
		total = DAW.state.bank_offset + DAW.state.tracks.size()
	return "%d-%d OF %d" % [number_of(shown[0]), number_of(shown[-1]), total]


## The next page (way 1) or the one before (-1). Held until no hand is on the table, as the
## console's bank keys are: a voice never changes which track it is under a hand.
func page(way: int) -> void:
	showing = &"bank"
	var wanted := DAW.state.bank_offset + view_offset + way * PAGE
	if wanted < 0:
		return
	if _anything_held():
		_pending_view = wanted
		return
	_go_to(wanted)


## Show the page beginning at project track `offset` (0 first), asking the DAW for another bank
## when it is not in the one cached.
func _go_to(offset: int) -> void:
	var cached := DAW.state.tracks.size()
	var local := offset - DAW.state.bank_offset
	if local < 0 or local >= cached:
		if DAW.state.project_track_count > 0 and offset >= DAW.state.project_track_count:
			return
		view_offset = 0
		DAW.set_track_bank(offset)
		return
	view_offset = local
	mark_dirty()


## SHOW: the bank, then the soloed tracks, then the selected ones.
func step_show() -> void:
	showing = SHOWS[(SHOWS.find(showing) + 1) % SHOWS.size()]
	mark_dirty()


## A new DAW (or the same one back) may want a ring now, or no longer: rebuilt, and told when
## Reaper's pan mode had to change for a width.
func _on_connection_changed() -> void:
	super()
	_hook_pan_mode()


func _hook_pan_mode() -> void:
	var reaper := DAW.backend as ReaperBackend
	if reaper != null and not reaper.pan_mode_set.is_connected(_on_pan_mode_set):
		reaper.pan_mode_set.connect(_on_pan_mode_set)


## Reaper's balance panner has no width, so the first width on a track sets it to stereo pan.
## Said once, here, and on the voice's card from then on (hint_of).
func _on_pan_mode_set(index: int) -> void:
	told.emit("%s: pan mode set to stereo pan, so it can have a width." % title_of(index))


func _on_track_changed(index: int, field: StringName) -> void:
	# Which tracks a soloed or selected table shows is the shape of it.
	if showing != &"bank" and (field == &"solo" or field == &"selected"):
		mark_dirty()
	if voices.has(index):
		(voices[index] as StageVoice).refresh()
	if tags.has(index):
		(tags[index] as Tag).refresh()
	if field == &"name" or field == &"colour":
		_refresh_range()
	# Which track is the room is any track's sends and names.
	if field == &"sends" or field == &"name":
		_refresh_room()
	if field == &"sends" and _room_wanted.has(index):
		_send_wanted(index)
	if field == &"sends":
		for key in _rope_wanted.keys():
			_rope_arrived(int(_rope_wanted[key][1]))
		_refresh_ropes()
	if field == &"name" and _room_asked != "":
		_on_track_added(index)


# --- placing --------------------------------------------------------------------------------

## A voice of `track` is being put at `want` (the table's frame, x across and z toward the
## player): pan and volume are written for it, only where they changed, and where it landed
## comes back. Dead centre within SNAP unless `fine`; at the front edge at most; past the back
## edge, -inf on the lip.
func place(track: int, want: Vector2, fine: bool) -> Vector2:
	var t := DAW.state.track(track, false)
	var x := clampf(want.x, -HALF_PAN, HALF_PAN)
	if not fine and absf(x) < SNAP:
		x = 0.0
	var z := minf(want.y, SIZE.y * 0.5)
	var db := db_of_z(z)
	if db == -INF:
		z = OFF_Z
	if t == null:
		return Vector2(x, z)
	var pan := pan_of_x(x)
	var taper := FaderLaw.to_taper(db)
	if absf(pan - t.pan) > 0.0001:
		DAW.set_track_pan(track, pan)
	if absf(taper - t.volume) > 0.00001:
		DAW.set_track_volume(track, taper)
	return Vector2(x, z)


## The wheel over a voice: half a decibel a notch, a tenth fine; down off -40 is -inf, and up from
## -inf is -40. Not past the front edge's +6 by the wheel, though a louder track keeps its level.
func nudge_volume(track: int, notches: int, fine: bool) -> bool:
	var t := DAW.state.track(track, false)
	if t == null:
		return false
	var db := FaderLaw.to_db(t.volume)
	var to: float
	if db == -INF:
		if notches < 0:
			return true
		to = BACK_DB
	else:
		to = db + notches * (DB_FINE if fine else DB_STEP)
		if notches > 0:
			to = minf(to, maxf(db, FRONT_DB))
		if to < BACK_DB - 0.001:
			to = -INF
	var taper := FaderLaw.to_taper(to)
	if absf(taper - t.volume) > 0.00001:
		DAW.set_track_volume(track, taper)
	return true


## The wheel over a voice or its tag's name: its level, or its width while it is held (and the
## DAW can set one).
func nudge_voice(track: int, held: bool, notches: int, fine: bool) -> bool:
	if held and DAW.can(DAWBackend.Capability.WIDTH):
		return nudge_width(track, notches, fine)
	return nudge_volume(track, notches, fine)


## The wheel while a voice is held: its width, five percent a notch, one fine.
func nudge_width(track: int, notches: int, fine: bool) -> bool:
	var t := DAW.state.track(track, false)
	if t == null or not DAW.can(DAWBackend.Capability.WIDTH):
		return false
	var w := clampf(t.width + notches * (WIDTH_FINE if fine else WIDTH_STEP), 0.0, 1.0)
	if absf(w - t.width) > 0.0001:
		DAW.set_track_width(track, w)
	return true


## PAN < > on a tag: `by` of the pan's travel (PAN_STEP is a percent of it as the console counts).
func nudge_pan(track: int, by: float) -> bool:
	var t := DAW.state.track(track, false)
	if t == null:
		return false
	var pan := clampf(t.pan + by, 0.0, 1.0)
	if absf(pan - t.pan) > 0.0001:
		DAW.set_track_pan(track, pan)
	return true


## A press with no drag: the second within DOUBLE_PRESS puts the track back. After the voice's
## let-go has closed its own edit, so the reset is an edit of its own ("Bass: reset").
func pressed(track: int) -> void:
	var now := Time.get_ticks_msec()
	if _presses.has(track) and now - int(_presses[track]) <= int(DOUBLE_PRESS * 1000.0):
		_presses.erase(track)
		reset.call_deferred(track)
		return
	_presses[track] = now


func forget_press(track: int) -> void:
	_presses.erase(track)


## Centre, 0 dB and full width, as one undo step: a double press, Backspace, or RESET.
func reset(track: int) -> void:
	var t := DAW.state.track(track, false)
	if t == null:
		return
	DAW.open_edit("%s: reset" % t.display_name())
	if absf(t.pan - 0.5) > 0.0001:
		DAW.set_track_pan(track, 0.5)
	var unity := FaderLaw.to_taper(0.0)
	if absf(t.volume - unity) > 0.00001:
		DAW.set_track_volume(track, unity)
	if DAW.can(DAWBackend.Capability.WIDTH) and t.width < 0.9999:
		DAW.set_track_width(track, 1.0)
	DAW.close_edit()


## Backspace on a desktop: the track of whatever on the table is under the cursor, put back.
## False when it is nothing of the table's.
func reset_under(control: Node) -> bool:
	if control == null or not is_instance_valid(control) or not is_ancestor_of(control):
		return false
	if control is Rope:
		return cut((control as Rope).from, (control as Rope).to)
	var n := control
	while n != null and n != self:
		if n.has_meta(&"stage_track"):
			reset(int(n.get_meta(&"stage_track")))
			return true
		n = n.get_parent()
	return false


# --- the room -------------------------------------------------------------------------------

## A stalk at `db` (-inf for on the table): `track`'s send to the room at that level, made first
## if it has none. Inside whatever edit the stalk has open, so a first lift is one undo step with
## its level, as the notice says. Asked for once a lift: a guest asks the host to make the send, and
## a DAW may make it only later (Reaper, by its poll); either way its level is set once it arrives
## (`_send_wanted`). Nothing with no room, or for the room itself; false then, and false for a send
## the DAW could not make.
func send_to_room(track: int, db: float) -> bool:
	var room := room_track()
	if room == 0 or room == track or DAW.state.track(track, false) == null:
		return false
	var taper := 0.0 if db == -INF else FaderLaw.to_taper(db)
	var n := send_to(track, room)
	if n == 0:
		if db == -INF:
			return true
		if _sends_asked.has(track):
			# Asked already: the level it is to have when it comes, or nothing if it could not be made.
			if _room_wanted.has(track):
				_room_wanted[track] = taper
			return _room_wanted.has(track)
		_sends_asked[track] = Time.get_ticks_msec()
		if not hosting.call():
			_room_wanted[track] = taper
			DAW.create_send(track, room)
			return true
		if not DAW.create_send(track, room):
			return false
		n = send_to(track, room)
		if n == 0:
			_room_wanted[track] = taper
			told.emit("%s: a send to %s asked for, at %s once it is made." % [title_of(track),
					title_of(room), "%.1f dB" % db])
			return true
		_sends_asked.erase(track)
		told.emit("%s: a send to %s made, at %s: one undo step with this lift." % [title_of(track),
				title_of(room), "%.1f dB" % db])
	var send: MixState.SendState = DAW.state.track(track).sends[n]
	if absf(send.volume - taper) > 0.00001:
		DAW.set_send_volume(track, n, taper)
	return true


## A lift's send has arrived (made by the host, or by a DAW's poll): set to the level it wanted.
func _send_wanted(track: int) -> void:
	var n := send_to(track, room_track())
	if n == 0:
		return
	var taper: float = _room_wanted[track]
	_room_wanted.erase(track)
	_sends_asked.erase(track)
	DAW.set_send_volume(track, n, taper)


## A new lift of `track`'s stalk, or a notch of its wheel: a send asked for ASK_AGAIN_MSEC ago or
## more that never came is asked for again. Not within a lift, which may hold its edit (and so the
## send) for as long as the hand holds the stalk.
func forget_asked(track: int) -> void:
	if Time.get_ticks_msec() - int(_sends_asked.get(track, -ASK_AGAIN_MSEC)) >= ASK_AGAIN_MSEC:
		_sends_asked.erase(track)


## The wheel over a stalk: ROOM_STEP a notch, ROOM_FINE fine. Up from no send is ROOM_LOW_DB; down
## past it is none.
func nudge_room(track: int, notches: int, fine: bool) -> bool:
	if room_track() == 0:
		told.emit(no_room_words())
		return true
	forget_asked(track)
	var db := room_send_db(track)
	var to: float
	if db == -INF:
		if notches < 0:
			return true
		to = ROOM_LOW_DB
	else:
		to = minf(db + notches * (ROOM_FINE if fine else ROOM_STEP), maxf(db, ROOM_TOP_DB))
		if to < ROOM_LOW_DB - 0.001:
			to = -INF
	return send_to_room(track, to)


## ADD ROOM: a track ROOM at the end of the project with a reverb on it, as one undo step. With a
## room already, says which. A guest asks for the track, and for its reverb once it arrives.
func add_room() -> void:
	var room := room_track()
	if room > 0:
		told.emit("The room is %s: lift a voice on its stalk to send to it." % title_of(room))
		return
	var plugin := reverb_choice()
	if plugin == "":
		told.emit("This DAW offers no reverb to make a room with.")
		return
	var count := DAW.state.project_track_count if DAW.state.project_track_count > 0 \
			else DAW.state.bank_offset + DAW.state.tracks.size()
	if not hosting.call():
		_room_asked = plugin
		DAW.add_track(count + 1, ROOM_NAME)
		told.emit("Asked the host for a ROOM track with a reverb on it.")
		return
	DAW.open_edit("Stage: add room")
	DAW.add_track(count + 1, ROOM_NAME)
	var made := count + 1 - DAW.state.bank_offset
	if DAW.state.tracks.has(made) and DAW.state.track(made).display_name() == ROOM_NAME:
		DAW.add_fx(made, plugin)
	else:
		# A DAW that adds its tracks later (Reaper, by its poll): the reverb when it comes.
		_room_asked = plugin
	DAW.close_edit()
	_refresh_room()
	if room_track() > 0:
		told.emit("%s made, with a reverb: lift a voice on its stalk to send to it." % title_of(room_track()))


## A track has come: on a guest that asked for a room, the ROOM it asked for, which is given its
## reverb now.
func _on_track_added(index: int) -> void:
	if _room_asked == "":
		return
	var t := DAW.state.track(index, false)
	if t == null or t.display_name() != ROOM_NAME or has_reverb(t):
		return
	DAW.add_fx(index, _room_asked)
	_room_asked = ""


## The room may be another track now, or none: the key's lettering and every voice's stalk.
func _refresh_room() -> void:
	if _room_label != null:
		var room := room_track()
		_room_label.text = "ROOM  %s" % title_of(room) if room > 0 else "ADD ROOM"
		Lettering.fit(_room_label, RAIL_END * 0.95, 26, 12)
		_room_key.lit = room == 0
	for track in voices:
		(voices[track] as StageVoice).refresh()


func no_room_words() -> String:
	return "No room to send to yet: ROOM, at the table's left end, makes a ROOM track with a reverb."


# --- the ropes ------------------------------------------------------------------------------

## The tracks `track` has a rope to (a key send to another voice on the table), and from.
func ropes_from(track: int) -> Array:
	return Sidechain.pairs().filter(func(p: Array) -> bool: return p[0] == track and voices.has(p[1])) \
			.map(func(p: Array) -> int: return p[1])


func ropes_into(track: int) -> Array:
	return Sidechain.pairs().filter(func(p: Array) -> bool: return p[1] == track and voices.has(p[0])) \
			.map(func(p: Array) -> int: return p[0])


## Where a voice's knot is (the table's frame): under its ball, wherever the ball stands.
func knot_point(track: int) -> Vector3:
	var v: StageVoice = voices.get(track)
	if v == null:
		return Vector3.ZERO
	return Vector3(v.position.x, v.position.y - StageVoice.KNOT_DROP, v.position.z)


## The voice a rope let go at `at` (across the table, x and z) is tied to: the nearest other voice
## whose foot is within TIE_REACH, or 0 for none.
func drop_target(from: int, at: Vector2) -> int:
	var best := 0
	var nearest := TIE_REACH
	for track in voices:
		if track == from:
			continue
		var v: StageVoice = voices[track]
		var d := at.distance_to(Vector2(v.position.x, v.position.z))
		if d <= nearest:
			nearest = d
			best = track
	return best


## A knot is being dragged from: the rope from it to the hand at `at` (across the table), lying
## loose, and the voice it would be tied to named on the notice line once, as the hand comes over it.
func draw_loose(from: int, at: Vector2) -> void:
	var start := knot_point(from)
	var end := Vector3(at.x, start.y, at.y)
	var target := drop_target(from, at)
	if target > 0:
		end = knot_point(target)
	if target != _tying_to():
		if target > 0:
			told.emit("%s -> %s: let go to tie the rope." % [title_of(from), title_of(target)])
	_tying = from
	_tie_at = at
	_loose.mesh = CableSweep.tube(rope_spine(start, end, Vector3.ZERO, sag_of(start, end, 0.0)), ROPE_RADIUS, 6)
	_loose.visible = true


func _tying_to() -> int:
	return drop_target(_tying, _tie_at) if _tying > 0 else 0


## The knot's let-go: tied to the voice under the hand, or put back.
func let_go_rope(from: int) -> void:
	var to := drop_target(from, _tie_at) if _tying == from else 0
	_tying = 0
	_loose.visible = false
	if to > 0:
		tie(from, to)
	else:
		told.emit("%s: no voice there to tie the rope to." % title_of(from))


## A rope from `from` to `to`, in one edit: a compressor on `to` if it has none (the DAW's first
## compressor choice), then the key send that it listens to, and the room's row saying whether the
## rope added the compressor. A compressor the rope adds starts at Sidechain.THRESHOLD_SLACK_DB, at
## once where the DAW has made it (the built-in engine), else as it arrives (a guest's host, Reaper's
## poll). False when there is a rope already, or nothing to listen with.
func tie(from: int, to: int) -> bool:
	if from == to or DAW.state.track(from, false) == null or DAW.state.track(to, false) == null:
		return false
	if Sidechain.key_send(from, to) > 0:
		told.emit("%s already ducks under %s." % [title_of(to), title_of(from)])
		return false
	var comp := Sidechain.compressor_on(to)
	var choice := Sidechain.compressor_choice()
	if comp < 0 and choice == "":
		told.emit("This DAW offers no compressor for %s to duck with." % title_of(to))
		return false
	var key := Sidechain.rope_key(from, to)
	DAW.open_edit("%s > %s: rope" % [_name_of(from), _name_of(to)])
	if comp < 0:
		DAW.add_fx(to, choice)
	var made := DAW.create_sidechain(from, to)
	if hosting.call() and not made:
		DAW.close_edit()
		told.emit("%s: the key send to %s could not be made." % [title_of(from), title_of(to)])
		return false
	_set_row(key, true, comp < 0)
	if hosting.call() and Sidechain.key_send(from, to) > 0:
		_rows_seen[key] = true
	if comp < 0:
		_rope_wanted[key] = [from, to]
		_rope_arrived(to)
	DAW.close_edit()
	_refresh_ropes()
	told.emit("%s -> %s: tied, %s: one undo step. Pull the rope's middle to duck harder." % [title_of(from),
			title_of(to), "a key send and a compressor listening to it" if comp < 0
			else "a key send that its compressor listens to"])
	return true


## A rope's compressor, asked for, has come to `track`: set to where a slack rope has it, once.
func _rope_arrived(track: int) -> void:
	for key in _rope_wanted.keys():
		var pair: Array = _rope_wanted[key]
		if int(pair[1]) != track:
			continue
		var comp := Sidechain.compressor_on(track)
		if comp < 0 or Sidechain.key_send(int(pair[0]), track) == 0:
			continue
		_rope_wanted.erase(key)
		var f := DAW.state.fx(track, comp)
		DAW.set_fx_param(track, comp, Sidechain.THRESHOLD_PARAM, Sidechain.threshold_value(f, Sidechain.THRESHOLD_SLACK_DB))


## Cut the rope from `from` to `to`, in one edit: its key send, and the compressor if the rope added
## it (the room's row says) and no other key send feeds `to`; one that was there before stays. A
## compressor another key still listens to stays too, and that key's row is given the rope's
## "added", so the last of them cut takes it away. False with no rope.
func cut(from: int, to: int) -> bool:
	var n := Sidechain.key_send(from, to)
	if n == 0:
		return false
	var key := Sidechain.rope_key(from, to)
	var added := bool(ropes.get(key, false))
	var heir := _heir_of(from, to) if added else 0
	var comp := Sidechain.compressor_on(to) if added and heir == 0 else -1
	DAW.open_edit("%s > %s: cut" % [_name_of(from), _name_of(to)])
	if comp >= 0:
		DAW.remove_fx(to, comp)
	DAW.remove_send(from, n)
	DAW.close_edit()
	_set_row(key, false, false)
	if heir > 0:
		_set_row(Sidechain.rope_key(heir, to), true, true)
	_rope_wanted.erase(key)
	_refresh_ropes()
	var what := "the key send and the compressor the rope added"
	if heir > 0:
		what = "the key send; %s's compressor stays, listening to %s" % [title_of(to), title_of(heir)]
	elif comp < 0:
		what = "the key send; %s keeps its own compressor" % title_of(to)
	told.emit("%s -> %s: cut, %s: one undo step." % [title_of(from), title_of(to), what])
	return true


## Another track whose key send feeds `to`, besides `from`'s: a voice on the table first (a rope
## that can be cut), else any; 0 for none.
func _heir_of(from: int, to: int) -> int:
	var others := ropes_into(to).filter(func(t: int) -> bool: return t != from)
	if others.is_empty():
		others = Sidechain.pairs().filter(func(p: Array) -> bool: return p[1] == to and p[0] != from) \
				.map(func(p: Array) -> int: return p[0])
	return int(others[0]) if not others.is_empty() else 0


## The X at a knot: every rope from that track cut, each its own step.
func cut_from(from: int) -> void:
	for to in ropes_from(from):
		cut(from, to)


## A rope pulled to `amount` (0 slack to 1, Sidechain.of_pull): its key send's level and its
## compressor's threshold, written only where they changed, inside whatever edit the rope's hand
## has open.
func pull(from: int, to: int, amount: float) -> void:
	var n := Sidechain.key_send(from, to)
	var comp := Sidechain.compressor_on(to)
	if n == 0 or comp < 0:
		return
	var want := Sidechain.of_pull(amount)
	var send: MixState.SendState = DAW.state.track(from).sends[n]
	var taper := FaderLaw.to_taper(want.x)
	if absf(send.volume - taper) > 0.00001:
		DAW.set_send_volume(from, n, taper)
	var f := DAW.state.fx(to, comp)
	var v := Sidechain.threshold_value(f, want.y)
	if absf(float(f.params.get(Sidechain.THRESHOLD_PARAM, -1.0)) - v) > 0.00001:
		DAW.set_fx_param(to, comp, Sidechain.THRESHOLD_PARAM, v)


## How far a rope is pulled now (0..1): its compressor's threshold, read back.
func rope_pull(from: int, to: int) -> float:
	var comp := Sidechain.compressor_on(to)
	if comp < 0:
		return 0.0
	return Sidechain.pull_of(Sidechain.threshold_db(DAW.state.fx(to, comp)))


## How far a rope ducks on each hit of its key track (dB): from the key's heard peak, or
## Sidechain.HIT_DB while none has been heard.
func rope_ducks(from: int, to: int) -> float:
	var peak := float(_key_peaks.get(from, -INF))
	return Sidechain.ducks(from, to, Sidechain.HIT_DB if peak == -INF else peak)


## Its card: "KICK -> BASS · ducks 6 dB on each hit · pull for more".
func rope_words(from: int, to: int) -> String:
	var ducks := roundi(rope_ducks(from, to))
	var duck := "ducks %d dB on each hit" % ducks if ducks > 0 else "not ducking yet"
	var more := "pull for more" if rope_pull(from, to) < 0.999 else "pulled as far as it goes"
	return "%s -> %s · %s · %s" % [_name_of(from).to_upper(), _name_of(to).to_upper(), duck, more]


## A knot's card: its ropes, or how to tie one.
func ropes_words(track: int) -> String:
	var out := ropes_from(track).map(func(to: int) -> String: return "rope to %s" % title_of(to))
	out.append_array(ropes_into(track).map(func(from: int) -> String: return "ducks under %s" % title_of(from)))
	return " · ".join(out) if not out.is_empty() else "no rope"


func knot_hint(track: int) -> String:
	var words := "drag from the knot under the ball to another voice: a rope, and that track ducks under this one (one undo step)"
	if not ropes_from(track).is_empty():
		words += "  ·  X beside the knot: cut"
	return words


func _name_of(track: int) -> String:
	var t := DAW.state.track(track, false)
	return t.display_name() if t != null else "Track %d" % track


## The rope rows as this room has them, `tied` or cut. Written at once on the host, and published;
## asked of the host on a guest, and kept on top of the room's until it answers.
func _set_row(key: String, tied: bool, added: bool) -> void:
	_shelve(key, tied)
	if tied:
		ropes[key] = added
	else:
		ropes.erase(key)
	if hosting.call():
		ropes_changed.emit()
		return
	var ask: int = asking.call(&"rope", [key, tied, added])
	if ask > 0:
		_rows_asked[key] = [ask, tied, added]


## The host's rows kept true to the mix across undo, which does not carry room state. A row whose
## key send it has seen and is gone now (an undo of the tie, the patchbay's X) is dropped and the
## room published, so a stale row can never take away a compressor someone else put there later;
## not before its send has first been seen, which on Reaper comes a poll after the tie, and only
## while both its tracks are in the cache, so a bank turned away from is not a send gone. A row
## that said "added", dropped or cut, is shelved, and comes back when its key send does by this
## rope's own history: the step just redone is its tie (`Kick > Bass DI: rope`) or the one just
## undone its cut. A key send back any other way (the patchbay) drops the shelved row. Run at the
## frame's end, after the backend has said what its history is now; a DAW that names no steps
## (Reaper) never brings a row back, and that rope then cuts as one keeping its compressor.
func _reconcile_rows() -> void:
	_reconcile_due = false
	if not hosting.call() or DAW.state == null:
		return
	var s := DAW.state
	var standing := {}
	for p in Sidechain.pairs():
		standing[Sidechain.rope_key(p[0], p[1])] = p
	var changed := false
	for key in ropes.keys():
		if standing.has(key):
			_rows_seen[key] = true
		elif _rows_seen.has(key) and _in_cache(key):
			if ropes[key]:
				_rows_shelved[key] = true
			ropes.erase(key)
			changed = true
	for key in _rows_seen.keys():
		if not ropes.has(key):
			_rows_seen.erase(key)
	var redone := str(s.undo_names[s.undo_depth - 1]) if s.undo_depth > 0 and s.undo_depth <= s.undo_names.size() else ""
	var undone := str(s.undo_names[s.undo_depth]) if s.undo_depth >= 0 and s.undo_depth < s.undo_names.size() else ""
	for key in _rows_shelved.keys():
		if not standing.has(key) or _keys_standing.has(key):
			continue
		_rows_shelved.erase(key)
		var pair: Array = standing[key]
		var named := "%s > %s: " % [_name_of(pair[0]), _name_of(pair[1])]
		if not ropes.has(key) and (redone == named + "rope" or undone == named + "cut"):
			ropes[key] = true
			_rows_seen[key] = true
			changed = true
	_keys_standing = standing
	if changed:
		ropes_changed.emit()


## Whether both tracks of a rope row ("2>6", project numbers) are in the cache's bank.
func _in_cache(key: String) -> bool:
	var ends := key.split(">")
	if ends.size() != 2 or not ends[0].is_valid_int() or not ends[1].is_valid_int():
		return false
	var off := DAW.state.bank_offset
	return DAW.state.tracks.has(int(ends[0]) - off) and DAW.state.tracks.has(int(ends[1]) - off)


## The host, answering a guest's tie or cut.
func answer_rope(key: String, tied: bool, added: bool) -> void:
	_shelve(key, tied)
	if tied:
		ropes[key] = added
	else:
		ropes.erase(key)
	ropes_changed.emit()


## The host: a row saying "added" that is being cut is kept for an undo of the cut
## (`_reconcile_rows`); one tied again needs none.
func _shelve(key: String, tied: bool) -> void:
	if not hosting.call():
		return
	if tied:
		_rows_shelved.erase(key)
	elif ropes.get(key, false):
		_rows_shelved[key] = true


## A guest: the room's rope rows, with its own asks the host has not answered (`answered`, the last
## of them it has) on top.
func apply_ropes(rows: Dictionary, answered: int) -> void:
	ropes = rows.duplicate()
	for key in _rows_asked.keys():
		var ask: Array = _rows_asked[key]
		if int(ask[0]) <= answered:
			_rows_asked.erase(key)
		elif ask[1]:
			ropes[key] = ask[2]
		else:
			ropes.erase(key)


## The ropes standing on the table: one for each key send between two voices on it.
func _refresh_ropes() -> void:
	if not _reconcile_due:
		_reconcile_due = true
		_reconcile_rows.call_deferred()
	if _loose == null:
		return
	var wanted := {}
	for p in Sidechain.pairs():
		if voices.has(p[0]) and voices.has(p[1]):
			wanted[Sidechain.rope_key(p[0], p[1])] = p
	for key in rope_nodes.keys():
		if not wanted.has(key):
			var gone: Rope = rope_nodes[key]
			rope_nodes.erase(key)
			gone.line.queue_free()
			gone.queue_free()
	for key in wanted:
		if rope_nodes.has(key):
			continue
		var rope := Rope.new()
		rope.name = "Rope%s" % key.replace(">", "_")
		rope.table = self
		rope.from = wanted[key][0]
		rope.to = wanted[key][1]
		rope.line = MeshInstance3D.new()
		rope.line.name = "Line%s" % key.replace(">", "_")
		rope.line.material_override = rope_paint()
		rope.line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_adopt(rope.line)
		_adopt(rope)
		rope_nodes[key] = rope
		rope.shape()
	for track in voices:
		(voices[track] as StageVoice).refresh()


## How far a rope between `a` and `b` sags when slack: a share of its span, less the more it is
## pulled.
static func sag_of(a: Vector3, b: Vector3, pulled: float) -> float:
	return minf(a.distance_to(b) * SAG_SHARE, SAG_MOST) * (1.0 - clampf(pulled, 0.0, 1.0))


## A rope's line from knot `a` to knot `b` (the table's frame), its middle moved `aside` and
## sagging `sag`, laid on the table where it would go through it.
static func rope_spine(a: Vector3, b: Vector3, aside: Vector3, sag: float) -> PackedVector3Array:
	var mid := (a + b) * 0.5 + aside - Vector3(0, sag, 0)
	var spine := CableSweep.smooth(PackedVector3Array([a, a.lerp(mid, 0.5) - Vector3(0, sag * 0.4, 0), mid,
			b.lerp(mid, 0.5) - Vector3(0, sag * 0.4, 0), b]), 6)
	return CableSweep.rest_on(spine, ROPE_RADIUS + 0.0005, 0.01)


static var _rope_paint: StandardMaterial3D


## A rope's finish: pale hemp, so it reads against the dark top as a thing and not a light.
static func rope_paint() -> StandardMaterial3D:
	if _rope_paint == null:
		_rope_paint = StandardMaterial3D.new()
		_rope_paint.albedo_color = Color(0.82, 0.74, 0.58)
		_rope_paint.roughness = 0.9
	return _rope_paint


# --- what the cards say ---------------------------------------------------------------------

## "3 BASS".
func title_of(track: int) -> String:
	var t := DAW.state.track(track, false)
	var name := t.display_name() if t != null else "Track %d" % track
	return "%d %s" % [number_of(track), name.to_upper()]


## "pan 20 L · -4.2 dB · width 60%", and MUTE or SOLO in words.
func readout_of(track: int) -> String:
	var t := DAW.state.track(track, false)
	if t == null:
		return ""
	var parts := [pan_words(t.pan), db_words(t.volume)]
	if DAW.can(DAWBackend.Capability.WIDTH):
		parts.append("width %d%%" % roundi(t.width * 100.0))
	var room := room_send_db(track)
	if room != -INF:
		parts.append("room %.1f dB" % room)
	for to in ropes_from(track):
		parts.append("rope to %s" % title_of(to))
	for from in ropes_into(track):
		parts.append("ducks under %s" % title_of(from))
	if t.mute:
		parts.append("MUTE")
	if t.solo:
		parts.append("SOLO")
	return " · ".join(parts)


func hint_of(track: int) -> String:
	var lines := ["drag: across is pan, back is quieter, off the back is -inf  ·  wheel 0.5 dB, Shift 0.1",
			"a ball under another: drag the name on its tag instead"]
	if DAW.can(DAWBackend.Capability.WIDTH):
		lines.append("wheel while held: width  ·  drag the ring: width  ·  double-click, Backspace or RESET: back to centre")
	else:
		lines.append("no width ring: this DAW cannot set a track's width  ·  double-click, Backspace or RESET: back to centre")
	if DAW.backend is ReaperBackend and (DAW.backend as ReaperBackend).stereo_panned.has(track):
		lines.append("pan mode set to stereo pan, for the width")
	lines.append(stalk_hint(track))
	lines.append(knot_hint(track))
	lines.append("L held over it: lean in, this track louder in your ears alone  ·  K held: muted while held, a tap latches"
			if Ears.can_lean() else "K held: muted while held, a tap latches  ·  " + Ears.CANNOT_LEAN)
	return "\n".join(lines)


## What a voice's stalk does, or why it does nothing yet.
func stalk_hint(track: int) -> String:
	var room := room_track()
	if room == 0:
		return "the stalk under it is its send to the room: no room yet, ROOM at the left end makes one"
	if room == track:
		return "this is the room the others send to"
	return "drag the stalk under it up: more of the room (%s)  ·  wheel 1 dB, Shift 0.1  ·  on the table, none" % title_of(room)


# --- building it ----------------------------------------------------------------------------

func _rebuild() -> void:
	_clear_built()
	voices.clear()
	tags.clear()
	_leads.clear()
	_levels.clear()
	_build_top()
	_build_rail()
	var shown := shown_tracks()
	var slot := (SIZE.x - 2.0 * RAIL_END) / PAGE
	for n in shown.size():
		var track: int = shown[n]
		var tag := Tag.new()
		tag.name = "Tag%d" % track
		tag.table = self
		tag.track = track
		tag.position = Vector3(-SIZE.x * 0.5 + RAIL_END + slot * (n + 0.5), 0, 0.004)
		tag.width = slot - 0.006
		tag.set_meta(&"stage_track", track)
		_rail.add_child(tag)
		tags[track] = tag
		var lead := MeshInstance3D.new()
		lead.name = "Lead%d" % track
		var line := BoxMesh.new()
		line.size = Vector3(0.0012, 0.0006, 1.0)
		lead.mesh = line
		lead.material_override = Materials.legend()
		lead.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Each a little higher than the last, so two that cross never lie in one plane.
		lead.set_meta(&"lift", 0.0015 + 0.0007 * n)
		_adopt(lead)
		_leads[track] = lead
	for track in shown:
		var voice := StageVoice.new()
		voice.name = "Voice%d" % track
		voice.table = self
		voice.track = track
		voice.set_meta(&"stage_track", track)
		_adopt(voice)
		voices[track] = voice
	_loose = MeshInstance3D.new()
	_loose.name = "LooseRope"
	_loose.material_override = rope_paint()
	_loose.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_loose.visible = false
	_adopt(_loose)
	rope_nodes.clear()
	_refresh_ropes()
	_empty_label.visible = shown.is_empty()
	_empty_label.text = {&"bank": "NO TRACKS", &"soloed": "NO TRACK SOLOED", &"selected": "NO TRACK SELECTED"}[showing]
	_refresh_range()


## The leader from a voice's tag, along the table to its foot: which ball is which track, read
## without colour.
func lead(voice: StageVoice) -> void:
	var line: MeshInstance3D = _leads.get(voice.track)
	var tag: Tag = tags.get(voice.track)
	if line == null or tag == null:
		return
	var lift: float = line.get_meta(&"lift", 0.0015)
	var from := Vector3(tag.position.x, lift, SIZE.y * 0.5 - 0.004)
	var to := Vector3(voice.position.x, lift, voice.position.z)
	var length := from.distance_to(to)
	if length < 0.001:
		line.visible = false
		return
	line.visible = true
	var b := Basis.looking_at(to - from, Vector3.UP)
	line.transform = Transform3D(b * Basis.from_scale(Vector3(1, 1, length)), (from + to) * 0.5)


func _refresh_range() -> void:
	if _range_label == null:
		return
	_range_label.text = range_text() if showing == &"bank" else ("%d SOLOED" % voices.size() if showing == &"soloed" else "%d SELECTED" % voices.size())
	_show_label.text = "SHOW\n%s" % String(showing).to_upper()


static var _baize: StandardMaterial3D


## The top's finish: dark and matte, so the voices and the lines are what is seen.
static func baize() -> StandardMaterial3D:
	if _baize == null:
		_baize = StandardMaterial3D.new()
		_baize.albedo_color = Color(0.075, 0.08, 0.095)
		_baize.roughness = 0.95
	return _baize


func _build_top() -> void:
	var top := MeshInstance3D.new()
	top.name = "Top"
	var slab := BoxMesh.new()
	slab.size = Vector3(SIZE.x, THICK, SIZE.y)
	top.mesh = slab
	top.position = Vector3(0, -THICK * 0.5, 0)
	top.material_override = baize()
	_adopt(top)
	# The lip behind the back edge, where a voice at -inf stands.
	var lip := MeshInstance3D.new()
	lip.name = "Lip"
	var lip_mesh := BoxMesh.new()
	lip_mesh.size = Vector3(SIZE.x, THICK, 0.035)
	lip.mesh = lip_mesh
	lip.position = Vector3(0, -THICK * 0.5 - 0.004, OFF_Z)
	lip.material_override = Materials.chassis()
	_adopt(lip)
	_flat_label("-inf", 40, Vector3(-SIZE.x * 0.5 + 0.03, 0.0002, OFF_Z), HORIZONTAL_ALIGNMENT_LEFT)
	_flat_label("-inf", 40, Vector3(SIZE.x * 0.5 - 0.03, 0.0002, OFF_Z), HORIZONTAL_ALIGNMENT_RIGHT)
	# The decibel lines across, 0 dB the strongest.
	for db in LINES_DB:
		var z := z_of_db(db)
		var line := MeshInstance3D.new()
		var bar := BoxMesh.new()
		bar.size = Vector3(SIZE.x - 0.14, 0.0008, 0.003 if db == 0.0 else 0.0012)
		line.mesh = bar
		# Clear of the top, and under the spine that crosses it: no two faces in one plane.
		line.position = Vector3(0, 0.0005, z)
		line.material_override = Materials.legend()
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_adopt(line)
		var words := "0 dB" if db == 0.0 else "%+d" % int(db)
		_flat_label(words, 44, Vector3(-SIZE.x * 0.5 + 0.012, 0.0005, z), HORIZONTAL_ALIGNMENT_LEFT)
		_flat_label(words, 44, Vector3(SIZE.x * 0.5 - 0.012, 0.0005, z), HORIZONTAL_ALIGNMENT_RIGHT)
	# The middle, front to back, and L C R along the front, with the half-way marks.
	var centre := MeshInstance3D.new()
	var spine := BoxMesh.new()
	spine.size = Vector3(0.0018, 0.0008, SIZE.y)
	centre.mesh = spine
	centre.position = Vector3(0, 0.0006, 0)
	centre.material_override = Materials.legend()
	_adopt(centre)
	for mark in [[-HALF_PAN, "L"], [-HALF_PAN * 0.5, "50 L"], [0.0, "C"], [HALF_PAN * 0.5, "50 R"], [HALF_PAN, "R"]]:
		_flat_label(mark[1], 56 if (mark[1] as String).length() == 1 else 36,
				Vector3(mark[0], 0.0005, SIZE.y * 0.5 - 0.035), HORIZONTAL_ALIGNMENT_CENTER)
	_flat_label("ACROSS IS PAN  ·  BACK IS QUIETER  ·  THE RING IS WIDTH  ·  A KNOT TIES A ROPE", 34,
			Vector3(0, 0.0005, -SIZE.y * 0.5 + 0.03), HORIZONTAL_ALIGNMENT_CENTER)
	_empty_label = _flat_label("", 60, Vector3(0, 0.0005, 0.1), HORIZONTAL_ALIGNMENT_CENTER)


## Lettering printed on the top, read from the front.
func _flat_label(words: String, size: int, at: Vector3, align: HorizontalAlignment) -> Label3D:
	var label := Label3D.new()
	label.text = words
	label.font_size = size
	label.pixel_size = 0.0004
	label.modulate = Color(0.74, 0.76, 0.8)
	label.horizontal_alignment = align
	label.rotation = Vector3(-PI * 0.5, 0, 0)
	label.position = at
	label.double_sided = false
	Lettering.range_to_legibility(label)
	_adopt(label)
	return label


## The rail along the front edge, sloped down toward the player like a desk's lip: the tags, and
## the keys at either end.
func _build_rail() -> void:
	_rail = Node3D.new()
	_rail.name = "Rail"
	# Its +Z up and toward the player, 35 degrees down from the top; its +Y up the slope.
	var b := Basis(Vector3.RIGHT, deg_to_rad(-55.0))
	_rail.transform = Transform3D(b, Vector3(0, 0, SIZE.y * 0.5) - b.y * RAIL_DEEP * 0.5)
	_adopt(_rail)
	var plate := MeshInstance3D.new()
	plate.name = "Plate"
	var box := BoxMesh.new()
	# A hair narrower than the top, so their ends are not one plane.
	box.size = Vector3(SIZE.x - 0.002, RAIL_DEEP, 0.012)
	plate.mesh = box
	plate.position = Vector3(0, 0, -0.006)
	plate.material_override = Materials.master_plate()
	_rail.add_child(plate)
	var left := -SIZE.x * 0.5 + RAIL_END * 0.5
	var right := SIZE.x * 0.5 - RAIL_END * 0.5
	_rail_label("BANK", 40, Vector3(left, 0.058, 0.001))
	_range_label = _rail_label("", 34, Vector3(left, 0.03, 0.001))
	var earlier := _key("<", Vector3(left - 0.02, -0.01, 0.004))
	earlier.describe_title = func() -> String: return "STAGE  EARLIER TRACKS"
	earlier.describe_value = func(_v: float) -> String: return range_text()
	earlier.says = "the eight tracks before these"
	earlier.pressed.connect(page.bind(-1))
	var later := _key(">", Vector3(left + 0.02, -0.01, 0.004))
	later.describe_title = func() -> String: return "STAGE  LATER TRACKS"
	later.describe_value = func(_v: float) -> String: return range_text()
	later.says = "the eight tracks after these"
	later.pressed.connect(page.bind(1))
	_room_label = _rail_label("", 26, Vector3(left, -0.034, 0.001))
	_room_key = _key("ROOM", Vector3(left, -0.058, 0.004))
	_room_key.describe_title = func() -> String: return "STAGE  ROOM" if room_track() > 0 else "STAGE  ADD ROOM"
	_room_key.describe_value = func(_v: float) -> String:
		return title_of(room_track()) if room_track() > 0 else "no room yet"
	_room_key.says = "with no room: ADD ROOM, a track ROOM with a reverb (one undo step)  ·  a voice's stalk, lifted, sends to it"
	_room_key.dwells = false
	_room_key.pressed.connect(add_room)
	_refresh_room()
	_show_label = _rail_label("", 34, Vector3(right, 0.04, 0.001))
	var shows := _key("SHOW", Vector3(right, -0.01, 0.004))
	shows.describe_title = func() -> String: return "STAGE  SHOW"
	shows.describe_value = func(_v: float) -> String: return String(showing).to_upper()
	shows.says = "the bank, the soloed tracks or the selected ones"
	shows.lit = showing != &"bank"
	shows.pressed.connect(step_show)
	_rail_label("STAGE TABLE", 30, Vector3(right, -0.05, 0.001))


func _rail_label(words: String, size: int, at: Vector3) -> Label3D:
	var label := Label3D.new()
	label.text = words
	label.font_size = size
	label.pixel_size = 0.0004
	label.modulate = Color(0.8, 0.82, 0.86)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = at
	Lettering.range_to_legibility(label)
	_rail.add_child(label)
	return label


func _key(glyph: String, at: Vector3, parent: Node3D = null) -> TableKey:
	var key := TableKey.new()
	key.position = at
	key.glyph = glyph
	(parent if parent != null else _rail).add_child(key)
	return key


## A key on the table's rail: a desk button with its legend on its face, which says what it does
## on the hover card and may take the wheel.
class TableKey extends PanelButton:
	var glyph := ""
	## What it does, for the card.
	var says := ""
	## (notches: int, fine: bool) -> bool, for a key the wheel works too (PAN < >).
	var wheel: Callable = Callable()
	var dwells := true

	func _ready() -> void:
		led_colour = Color(0.45, 0.68, 0.95)
		hit_pad = Vector2(1.6, 2.0)
		super()
		var face := Label3D.new()
		face.text = glyph
		face.font_size = 26 if glyph.length() > 1 else 40
		face.pixel_size = 0.0003
		# In front of the key's lamp (PanelButton.LAMP_OFFSET, whose face is at 4.55 mm).
		face.position = Vector3(0, 0, 0.0055)
		face.modulate = Color(0.92, 0.93, 0.95)
		Lettering.range_to_legibility(face)
		Lettering.fit(face, PanelButton.SIZE.x * 0.95, face.font_size, 12)
		add_child(face)

	func _on_nudge(notches: int, fine: bool) -> bool:
		return wheel.call(notches, fine) if wheel.is_valid() else false

	func dwell_activates() -> bool:
		return dwells

	func _default_readout() -> String:
		return ""

	func hint() -> String:
		return says


## A voice's tag on the rail: its number and name, a chip of its colour, what it is set to and
## whether it is muted or soloed in words, PAN < > keys and RESET.
class Tag extends Node3D:
	var table: StageTable
	var track := 0
	var width := 0.11
	var _name: Label3D
	var _state: Label3D
	var _readout: Label3D
	var _chip: MeshInstance3D

	func _ready() -> void:
		_name = _label(40, Vector3(0, 0.055, 0.001))
		_state = _label(30, Vector3(0, 0.036, 0.001))
		_readout = _label(26, Vector3(0, 0.019, 0.001))
		_chip = MeshInstance3D.new()
		var chip := BoxMesh.new()
		chip.size = Vector3(width * 0.8, 0.003, 0.002)
		_chip.mesh = chip
		_chip.position = Vector3(0, 0.072, 0.001)
		add_child(_chip)
		var left := table._key("<", Vector3(-0.03, -0.012, 0.0), self)
		left.describe_title = func() -> String: return "%s  PAN LEFT" % table.title_of(track)
		left.describe_value = func(_v: float) -> String: return table.readout_of(track)
		left.says = "a percent left a press  ·  wheel 5% a notch, Shift 1%"
		left.pressed.connect(func(): table.nudge_pan(track, -StageTable.PAN_STEP))
		left.wheel = _wheel_pan
		left.set_meta(&"stage_track", track)
		var right := table._key(">", Vector3(0.03, -0.012, 0.0), self)
		right.describe_title = func() -> String: return "%s  PAN RIGHT" % table.title_of(track)
		right.describe_value = func(_v: float) -> String: return table.readout_of(track)
		right.says = "a percent right a press  ·  wheel 5% a notch, Shift 1%"
		right.pressed.connect(func(): table.nudge_pan(track, StageTable.PAN_STEP))
		right.wheel = _wheel_pan
		right.set_meta(&"stage_track", track)
		_build_grip()
		var pan := _label(26, Vector3(0, -0.012, 0.001))
		pan.text = "PAN"
		var reset := table._key("RESET", Vector3(0, -0.048, 0.0), self)
		reset.describe_title = func() -> String: return "%s  RESET" % table.title_of(track)
		reset.describe_value = func(_v: float) -> String: return table.readout_of(track)
		reset.says = "back to centre, 0 dB and full width (one undo step)"
		reset.dwells = false
		reset.pressed.connect(func(): table.reset(track))
		reset.set_meta(&"stage_track", track)
		refresh()

	## The name, state and readout are a handle on the voice (NameGrip). The grip's own frame is
	## the voices': level with the table at their height, its +Z the table's up, so a held ray
	## moves in their plane (Interactor._plane_point). Its hit box is here on the sloped rail.
	func _build_grip() -> void:
		var grip := NameGrip.new()
		grip.name = "Grip"
		grip.table = table
		grip.track = track
		var on_table := table._rail.transform * transform
		grip.transform = on_table.affine_inverse() * Transform3D(Basis(Vector3.RIGHT, -PI * 0.5),
				Vector3(on_table.origin.x, StageVoice.LIFT, StageTable.SIZE.y * 0.5))
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(width, 0.068, 0.006)
		shape.shape = box
		shape.transform = grip.transform.affine_inverse() * Transform3D(Basis(), Vector3(0, 0.044, 0.002))
		grip.add_child(shape)
		add_child(grip)

	func _wheel_pan(notches: int, fine: bool) -> bool:
		return table.nudge_pan(track, notches * (StageTable.PAN_STEP if fine else StageTable.PAN_WHEEL))

	func _label(size: int, at: Vector3) -> Label3D:
		var label := Label3D.new()
		label.font_size = size
		label.pixel_size = 0.0003
		label.modulate = Color(0.86, 0.88, 0.92)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.position = at
		Lettering.range_to_legibility(label)
		add_child(label)
		return label

	func refresh() -> void:
		var t := DAW.state.track(track, false)
		if t == null or _name == null:
			return
		_name.text = table.title_of(track)
		Lettering.fit(_name, width, 40, 18)
		var words := []
		if t.mute:
			words.append("MUTE")
		if t.solo:
			words.append("SOLO")
		_state.text = "  ".join(words)
		var shown := [StageTable.pan_words(t.pan), StageTable.db_words(t.volume)]
		if DAW.can(DAWBackend.Capability.WIDTH):
			shown.append("%d%%" % roundi(t.width * 100.0))
		_readout.text = "  ".join(shown)
		Lettering.fit(_readout, width, 26, 12)
		_chip.material_override = Materials.track_glow(t.shown_colour())


## The name on a voice's tag, taken hold of: a handle on that voice from the rail, so a track
## whose ball stands under another's can still be placed, wheeled and reset. A drag moves the voice
## as far as the hand moves, from where it stands; the wheel is its level, or its width while held;
## two presses put it back. Hovered or held, its voice is raised over the rest (StageVoice.pick).
## One edit a drag, called a placing, as on the ball.
class NameGrip extends ControlAffordance:
	var table: StageTable
	var track := 0
	var _started := false

	func _init() -> void:
		edits_as_one = true
		describe_edit = func() -> String:
			var t := DAW.state.track(track, false)
			var who := t.display_name() if t != null else "Track %d" % track
			return "%s: %s" % [who, "place" if held_by != null else "level"]
		# A cassette pressed on the name pastes on its track at the playhead, as on the ball.
		pastes_onto = func() -> int: return track

	func _ready() -> void:
		collision_layer = 2
		collision_mask = 0
		set_meta(&"stage_track", track)
		hover_changed.connect(func(_on: bool) -> void: _pick())

	func voice() -> StageVoice:
		return table.voices.get(track) if table != null else null

	func _pick() -> void:
		var v := voice()
		if v != null and is_instance_valid(v):
			v.pick(is_hovered() or is_held())

	func _on_grab_begin(_at: Vector3) -> void:
		var v := voice()
		if v == null:
			return
		# Where the drag starts is taken from the first move, in the voices' plane: the press
		# itself lands on the rail, below it.
		_started = false
		v.steered = true
		_pick()

	func _on_grab_move(at: Vector3) -> void:
		var v := voice()
		if v == null:
			return
		var p := table.to_local(at)
		if not _started:
			_started = true
			v.begin_drag(Vector2(p.x, p.z))
			return
		v.drag_to(Vector2(p.x, p.z), held_by is Interactor and (held_by as Interactor).fine())

	func _on_grab_end() -> void:
		var v := voice()
		if v == null:
			return
		v.steered = false
		v.end_drag()
		_started = false
		# Once the let-go is through and it is no longer held.
		_pick.call_deferred()

	func _on_nudge(notches: int, fine: bool) -> bool:
		return table.nudge_voice(track, is_held(), notches, fine)

	func _default_title() -> String:
		return "%s  BALL" % table.title_of(track)

	func _default_readout() -> String:
		return table.readout_of(track)

	func hint() -> String:
		return "drag: moves this track's ball as far as you move  ·  wheel 0.5 dB, Shift 0.1, width while held  ·  double-click: back to centre"

	## Not dwellable, as the ball is not.
	func dwell_activates() -> bool:
		return false


## A rope between two voices (docs/spatial_loop.md slice 20): a key send from `from` into `to`, which
## ducks `to` under it. Drawn as a CableSweep tube from knot to knot, sagging when slack, lifted
## straight each time `to` ducks, by `ducking` (StageTable._process, from Sidechain's estimate) and
## as far as Ergonomics lets things move. Taken by its middle and pulled away from the line between
## its knots, it ducks harder (StageTable.pull): one edit a pull, so the send's level and the
## threshold are one undo step. The wheel pulls it too. Its frame is level with the table at its
## middle, +X along it and +Z up, so a held ray moves in the level plane through it; it is not moved
## while held, only its line.
class Rope extends ControlAffordance:
	var table: StageTable
	var from := 0
	var to := 0
	## Its drawn line, a sibling on the table.
	var line: MeshInstance3D
	## How far its track ducks now (dB), and how far that has lifted its middle (m).
	var ducking := 0.0
	var lifted := 0.0
	var _held_pull := -1.0
	var _grab_off := 0.0
	var _grab_pull := 0.0
	var _box: BoxShape3D
	var _drawn := PackedFloat32Array()
	## Its line's centre, in its line's space, and that line's length: what the beads ride
	## (SignalBeads), the key going from `from` to `to`.
	var _spine := PackedVector3Array()
	var _length := 0.0

	func _init() -> void:
		edits_as_one = true
		describe_edit = func() -> String:
			return "%s > %s: pull" % [table._name_of(from), table._name_of(to)] if table != null else "rope: pull"

	func _enter_tree() -> void:
		super()
		add_to_group(SignalBeads.CARRIERS)

	func signal_spine() -> PackedVector3Array:
		return line.global_transform * _spine if line != null and line.is_inside_tree() else PackedVector3Array()

	func signal_length() -> float:
		return _length

	## What the key send carries: the key track's level through the send.
	func signal_level() -> float:
		return SignalBeads.level_between(from, to)

	func signal_radius() -> float:
		return StageTable.ROPE_RADIUS

	func _ready() -> void:
		collision_layer = 2
		collision_mask = 0
		var shape := CollisionShape3D.new()
		_box = BoxShape3D.new()
		_box.size = Vector3(0.05, 0.03, 0.03)
		shape.shape = _box
		add_child(shape)

	## How far it is pulled (0..1): where the hand has it while held, else its threshold's.
	func pull() -> float:
		return _held_pull if _held_pull >= 0.0 else table.rope_pull(from, to)

	## Across the table from its line, toward the player: where a pull moves its middle.
	func _across() -> Vector3:
		var a := table.knot_point(from)
		var b := table.knot_point(to)
		var along := Vector3(b.x - a.x, 0, b.z - a.z)
		if along.length_squared() < 0.000001:
			return Vector3.BACK
		var side := Vector3.UP.cross(along.normalized())
		return side if side.z >= 0.0 else -side

	## How far `p` (the table's frame) is from the line between its knots, across the table.
	func _off(p: Vector3) -> float:
		var a := table.knot_point(from)
		var b := table.knot_point(to)
		var flat := Vector2(b.x - a.x, b.z - a.z)
		if flat.length_squared() < 0.000001:
			return Vector2(p.x - a.x, p.z - a.z).length()
		var n := Vector2(-flat.y, flat.x).normalized()
		return absf(Vector2(p.x - a.x, p.z - a.z).dot(n))

	## Its line and its hit, where its knots, its pull and its ducking have them. Only when they move.
	func shape() -> void:
		if table == null or line == null:
			return
		var a := table.knot_point(from)
		var b := table.knot_point(to)
		var p := pull()
		var slack := StageTable.sag_of(a, b, p)
		var tight := clampf(ducking / StageTable.DUCK_TAUT_DB, 0.0, 1.0) * Ergonomics.current.motion_scale \
				if Ergonomics.current != null else 0.0
		lifted = slack * tight
		var sag := slack - lifted
		var aside := _across() * p * StageTable.PULL_MOST
		var now := PackedFloat32Array([a.x, a.y, a.z, b.x, b.y, b.z, aside.x, aside.z, sag])
		if now.size() == _drawn.size():
			var same := true
			for i in now.size():
				if absf(now[i] - _drawn[i]) > 0.0004:
					same = false
					break
			if same:
				return
		_drawn = now
		_spine = StageTable.rope_spine(a, b, aside, sag)
		_length = SignalBeads.length_of(_spine)
		line.mesh = CableSweep.tube(_spine, StageTable.ROPE_RADIUS, 6)
		if is_held():
			return
		var mid := (a + b) * 0.5 + aside
		mid.y = maxf(mid.y - sag, StageTable.ROPE_RADIUS)
		var along := Vector3(b.x - a.x, 0, b.z - a.z)
		var x := along.normalized() if along.length_squared() > 0.000001 else Vector3.RIGHT
		transform = Transform3D(Basis(x, Vector3.UP.cross(x), Vector3.UP), mid)
		_box.size = Vector3(maxf(along.length() * 0.5, 0.03), 0.03, 0.03)

	func _on_grab_begin(at: Vector3) -> void:
		_grab_pull = pull()
		_grab_off = _off(table.to_local(at))
		_held_pull = _grab_pull

	func _on_grab_move(at: Vector3) -> void:
		var off := _off(table.to_local(at))
		_held_pull = clampf(_grab_pull + (off - _grab_off) / StageTable.PULL_MOST, 0.0, 1.0)
		table.pull(from, to, _held_pull)
		shape()

	func _on_grab_end() -> void:
		_held_pull = -1.0
		_drawn = PackedFloat32Array()

	func _on_nudge(notches: int, fine: bool) -> bool:
		var to_pull := clampf(pull() + notches * (StageTable.PULL_FINE if fine else StageTable.PULL_STEP), 0.0, 1.0)
		table.pull(from, to, to_pull)
		return true

	func _default_title() -> String:
		return "%s -> %s  ROPE" % [table.title_of(from), table.title_of(to)]

	func _default_readout() -> String:
		return table.rope_words(from, to)

	func hint() -> String:
		return "\n".join(["drag its middle away: ducks harder, the key send up and the threshold down (one undo step)",
				"wheel: a little more or less  ·  Backspace, or the X at %s's knot: cut" % table.title_of(from),
				"the patchbay shows it as a key send"])

	func dwell_activates() -> bool:
		return false
