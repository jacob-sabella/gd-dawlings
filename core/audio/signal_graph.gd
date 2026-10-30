class_name SignalGraph
extends RefCounted

## The audio path of the mix, stage by stage, with a level at every stage and, where the sound
## stops, why (docs/spatial_loop.md part three). Pure: built from a MixState and the room's sources,
## so a host, a guest and the suite build the same graph from the same cache, and nothing here knows
## a node in the room. The signal view (SignalView) draws it; "why can't I hear this" is `trace`.
##
## THE STAGES, per track N: `tN:play` (what the track itself plays, its items), `tN:in` (what
## arrives at it: its items and takes, a live input, its folder's children), `tN:fxK` a plugin slot
## in chain order, `tN:fader` (the fader, pan, mute and solo, and the master or folder send), and
## `tN:sendS` a send slot. Then `master` and `out`, the speakers. A room source is `src:<id>`. The
## main road from a track is its input, its plugins, its fader, then its folder's input or the
## master. A send branches from the fader, or from the last plugin when it is pre-fader, into its
## destination's input; a key send (a sidechain) is a branch to a detector, never toward the ears.
##
## LEVELS are dBFS. Measured where the DAW measures them (MixState.TrackState.meter_peak and the
## rest: the built-in engine's probes at every stage; on Reaper only the fader and the plugins' gain
## reduction), estimated where it does not -- a send from the track's meter and the send's level --
## and marked so (`estimated`, said with `≈`). A stage nothing measures or estimates is
## `not measured`, and never claimed silent.

const FLOOR_DB := -60.0
## Amber from here, red past CLIP_DB.
const HOT_DB := -3.0
const CLIP_DB := 0.0
## The top of a pipe's thickness range.
const TOP_DB := 6.0
## What a send set by the SEND fix sits at (dB).
const SEND_FIX_DB := -12.0

enum Kind { SOURCE, INPUT, PLUGIN, FADER, SEND, MASTER, OUT }

## The reasons a stage stops the sound.
const MUTED := &"muted"
const SOLOED_OUT := &"soloed_out"
const FADER_SILENT := &"fader_silent"
const SEND_SILENT := &"send_silent"
const MONITOR_OFF := &"monitor_off"
const NOT_ARMED := &"not_armed"
const NO_INPUT := &"no_input"
const PLUGIN_SILENT := &"plugin_silent"
const INSTRUMENT_BYPASSED := &"instrument_bypassed"
const NO_ROUTE := &"no_route"
const FOLDER_MUTED := &"folder_muted"
const STOPPED := &"stopped"
const EMPTY := &"empty"
const NO_TRACK := &"no_track"
const LOCAL := &"local"
const MASTER_SILENT := &"master_silent"
## Each reason as a sign's heading.
const HEADINGS := {
	MUTED: "MUTED", SOLOED_OUT: "SOLOED OUT", FADER_SILENT: "FADER AT −∞", SEND_SILENT: "SEND AT −∞",
	MONITOR_OFF: "MONITORING OFF", NOT_ARMED: "NOT ARMED", NO_INPUT: "NO RECORD INPUT",
	PLUGIN_SILENT: "PLUGIN SILENT", INSTRUMENT_BYPASSED: "INSTRUMENT BYPASSED", NO_ROUTE: "ROUTED NOWHERE",
	FOLDER_MUTED: "FOLDER MUTED", STOPPED: "TRANSPORT STOPPED", EMPTY: "NOTHING TO PLAY",
	NO_TRACK: "NO TRACK", LOCAL: "YOUR EARS ONLY", MASTER_SILENT: "MASTER AT −∞",
}

## What a room source is (`build`'s `sources`): an instrument (heard live on MONITOR, onto a track
## when recorded), the mic (a track's live input), notes on a track (the music box), or a sound
## heard in one player's ears only.
const NOTES := &"notes"
const VOICE := &"voice"
const PLAYBACK := &"playback"
const LOCAL_SOURCE := &"local"


class Stage extends RefCounted:
	var id := ""
	var kind: int = Kind.INPUT
	var track := 0
	## The plugin's or the send's slot, -1 for neither.
	var slot := -1
	## What it is called on a sign: "BASS DI fader".
	var title := ""
	var peak_db := -INF
	var rms_db := -INF
	## A plugin's gain reduction (dB, 0 or less), NAN where nothing reports one.
	var gr_db := NAN
	var gr_derived := false
	var measured := false
	var estimated := false
	## An effect bypassed: the sound passes dry. No break.
	var bypassed := false
	## The next stage on the main road, "" at the end of it (OUT, or a break with nowhere to go).
	var next := ""
	## The sends and keys that branch from here.
	var branches: Array[String] = []
	## For a send: whether it is a key (a sidechain) and pre-fader.
	var key := false
	var pre := false
	## Why the sound stops here, "" where it goes on; the sentence on the sign; the one-press fix.
	var halt: StringName = &""
	var why := ""
	var fix := {}

	## The figure a sign or a card shows: "−6.0 dBFS", "≈ −12.3 dBFS", "not measured".
	func level_words() -> String:
		if not measured and not estimated:
			return "not measured"
		var figure := "−∞" if peak_db <= -120.0 else "%s%.1f" % ["+" if peak_db > 0.0 else ("−" if peak_db < 0.0 else ""), absf(peak_db)]
		var out := ("≈ " if estimated else "") + figure + " dBFS"
		if not is_nan(gr_db) and gr_db < -0.05:
			out += " · GR %.1f dB%s" % [gr_db, " (derived)" if gr_derived else ""]
		return out

	func health() -> StringName:
		return SignalGraph.health(peak_db) if measured or estimated else &"unknown"


class Trace extends RefCounted:
	## From the first stage to the last reached, a break's stage included.
	var stages: Array[Stage] = []
	## The stage that stops it, or null when it reaches OUT.
	var broke_at: Stage = null
	var reason: StringName = &""
	var words := ""
	var fix := {}

	func heard() -> bool:
		return broke_at == null and not stages.is_empty() and stages[-1].kind == Kind.OUT


var stages := {}
var playing := false


## The graph `state` describes, with `sources` ({id, title, track, kind, jacked}) feeding the
## tracks they reach.
static func build(state: MixState, sources: Array = []) -> SignalGraph:
	var g := SignalGraph.new()
	g.playing = state.playing
	var parents := state._folder_parents()
	var master := g._add("master", Kind.MASTER, 0, "MASTER")
	master.next = "out"
	master.peak_db = FaderLaw.to_db(maxf(state.master.vu_l, state.master.vu_r))
	master.measured = true
	if state.master.volume <= 0.0:
		g._stop(master, MASTER_SILENT, "the master fader is at −∞", {"label": "MASTER TO 0 dB",
				"verb": &"set_master_volume", "args": [FaderLaw.to_taper(0.0)], "step": "Master to 0 dB"})
	var out := g._add("out", Kind.OUT, 0, "OUT")
	out.peak_db = master.peak_db
	out.measured = true
	for index: int in state.track_indices():
		g._add_track(state, index, parents)
	for row: Dictionary in sources:
		g._add_source(state, row)
	return g


func stage(id: String) -> Stage:
	return stages.get(id)


func _add(id: String, kind: int, track: int, title: String) -> Stage:
	var s := Stage.new()
	s.id = id
	s.kind = kind
	s.track = track
	s.title = title
	stages[id] = s
	return s


func _stop(s: Stage, reason: StringName, why: String, fix := {}) -> void:
	if s.halt != &"":
		return
	s.halt = reason
	s.why = why
	s.fix = fix


static func play_id(track: int) -> String: return "t%d:play" % track
static func in_id(track: int) -> String: return "t%d:in" % track
static func fx_id(track: int, slot: int) -> String: return "t%d:fx%d" % [track, slot]
static func fader_id(track: int) -> String: return "t%d:fader" % track
static func send_id(track: int, slot: int) -> String: return "t%d:send%d" % [track, slot]
static func source_id(id: String) -> String: return "src:" + id


func _add_track(state: MixState, index: int, parents: Dictionary) -> void:
	var t := state.track(index)
	var name := t.display_name().to_upper()
	var plugins: Array = t.plugins()
	var measured := t.meter_peak.size() == plugins.size() + 1
	var at := func(arr: PackedFloat32Array, i: int) -> float:
		return arr[i] if i < arr.size() else -INF
	# What the track itself plays: its items, with the transport rolling.
	var play := _add(play_id(index), Kind.SOURCE, index, "%s playback" % name)
	play.next = in_id(index)
	var live := t.rec_arm and t.monitor != 0
	# A folder plays what its children do: it has no items of its own, and is not empty for it.
	var folder := parents.values().has(index)
	if t.items.is_empty() and not live and not folder:
		_stop(play, EMPTY, "nothing on %s to play" % name)
	elif not state.playing and not live:
		_stop(play, STOPPED, "the transport is stopped", {"label": "PLAY", "verb": &"transport_play", "args": [], "step": ""})
	var input := _add(in_id(index), Kind.INPUT, index, "%s input" % name)
	if measured:
		input.peak_db = t.meter_peak[0]
		input.rms_db = at.call(t.meter_rms, 0)
		input.measured = true
	play.peak_db = input.peak_db
	play.rms_db = input.rms_db
	play.measured = input.measured
	var last := input
	for n in plugins.size():
		var slot: int = plugins[n]
		var f := state.fx(index, slot)
		var s := _add(fx_id(index, slot), Kind.PLUGIN, index, "%s · %s" % [name, f.name.to_upper()])
		s.slot = slot
		last.next = s.id
		if measured:
			s.peak_db = t.meter_peak[n + 1]
			s.rms_db = at.call(t.meter_rms, n + 1)
			s.measured = true
		if n < t.meter_gr.size() and not is_nan(t.meter_gr[n]):
			s.gr_db = t.meter_gr[n]
			# The built-in engine works it out from its probes; Reaper's plugins report their own.
			s.gr_derived = measured
		if not f.enabled:
			s.bypassed = true
			if f.type.ends_with("i"):
				_stop(s, INSTRUMENT_BYPASSED, "the instrument %s is bypassed: it plays nothing" % f.name,
						{"label": "BYPASS OFF", "verb": &"set_fx_enabled", "args": [index, slot, true],
						"step": "%s: bypass off" % t.display_name()})
		elif measured and last.peak_db > FLOOR_DB and s.peak_db <= FLOOR_DB:
			_stop(s, PLUGIN_SILENT, "%s takes sound in and puts out silence" % f.name)
		last = s
	var fader := _add(fader_id(index), Kind.FADER, index, "%s fader" % name)
	last.next = fader.id
	fader.peak_db = FaderLaw.to_db(maxf(t.vu_l, t.vu_r))
	fader.measured = true
	if not t.meter_rms.is_empty() and t.volume > 0.0:
		fader.rms_db = t.meter_rms[-1] + FaderLaw.to_db(t.volume)
	var parent := int(parents.get(index, 0))
	fader.next = in_id(parent) if parent > 0 else "master"
	if t.mute:
		_stop(fader, MUTED, "muted", {"label": "UNMUTE", "verb": &"set_track_mute", "args": [index, false],
				"step": "Unmute %s" % t.display_name()})
	var blocker := soloed_out(state, index)
	if blocker > 0:
		_stop(fader, SOLOED_OUT, "soloed out: %s is soloed" % state.track(blocker).display_name(),
				{"label": "UNSOLO", "verb": &"clear_solos", "args": [], "step": "Unsolo all"})
	if t.volume <= 0.0:
		_stop(fader, FADER_SILENT, "the fader is at −∞", {"label": "FADER TO 0 dB", "verb": &"set_track_volume",
				"args": [index, FaderLaw.to_taper(0.0)], "step": "%s to 0 dB" % t.display_name()})
	if not t.main_send:
		_stop(fader, NO_ROUTE, "routed nowhere: no %s send" % ("folder" if parent > 0 else "master"),
				{"label": "SEND TO MASTER", "verb": &"set_track_main_send", "args": [index, true],
				"step": "%s: master send on" % t.display_name()})
		fader.next = ""
	var slots: Array = t.sends.keys()
	slots.sort()
	for n in slots.size():
		var sd: MixState.SendState = t.sends[slots[n]]
		var dest := sd.resolve(state)
		var dest_name := state.track(dest).display_name().to_upper() if dest > 0 and state.tracks.has(dest) else sd.dest_name.to_upper()
		var s := _add(send_id(index, slots[n]), Kind.SEND, index, "%s → %s %s" % [name, dest_name, "key" if sd.key else "send"])
		s.slot = slots[n]
		s.key = sd.key
		s.pre = sd.pre_fader
		s.next = in_id(dest) if dest > 0 and state.tracks.has(dest) else ""
		(last if sd.pre_fader else fader).branches.append(s.id)
		var level := send_level(t, slots[n])
		s.peak_db = level.x
		s.measured = level.z == MEASURED
		s.estimated = level.z == ESTIMATED
		if sd.volume <= 0.0:
			_stop(s, SEND_SILENT, "the send is at −∞", {"label": "SEND TO %d dB" % int(SEND_FIX_DB), "verb": &"set_send_volume",
					"args": [index, slots[n], FaderLaw.to_taper(SEND_FIX_DB)], "step": "%s: send up" % t.display_name()})
		elif s.next == "":
			_stop(s, NO_ROUTE, "it sends to %s, which is not in the project" % (sd.dest_name if sd.dest_name != "" else "nothing"))


func _add_source(state: MixState, row: Dictionary) -> void:
	var id := str(row.get("id", ""))
	if id == "":
		return
	var track := int(row.get("track", 0))
	var kind: StringName = row.get("kind", NOTES)
	var s := _add(source_id(id), Kind.SOURCE, track, str(row.get("title", id)).to_upper())
	s.peak_db = float(row.get("level_db", -INF))
	s.measured = row.has("level_db")
	var t := state.track(track, false) if track > 0 else null
	if kind == LOCAL_SOURCE:
		_stop(s, LOCAL, "heard in your ears only: it reaches a track as a cassette pasted onto one")
		return
	if t == null:
		_stop(s, NO_TRACK if kind != NOTES else NOT_ARMED,
				"no track is armed, so nothing records it (it plays live on this machine's MONITOR)" if kind == NOTES
				else "there is no track for it")
		return
	s.next = in_id(track) if kind != PLAYBACK else play_id(track)
	if kind == PLAYBACK:
		return
	if kind == VOICE:
		if not t.rec_arm:
			_stop(s, NOT_ARMED, "%s is not armed" % t.display_name(), {"label": "ARM", "verb": &"set_track_rec_arm",
					"args": [track, true], "step": "Arm %s" % t.display_name()})
		elif t.monitor == 0:
			_stop(s, MONITOR_OFF, "monitoring is off on %s" % t.display_name(), {"label": "MONITOR ON",
					"verb": &"set_track_monitor", "args": [track, 1], "step": "%s: monitor on" % t.display_name()})
		elif t.input == "none":
			_stop(s, NO_INPUT, "%s has no record input: pick one on its track page (F2)" % t.display_name())
		elif t.input != "" and not state.inputs.is_empty() and not state.inputs.any(func(p): return p[0] == t.input):
			_stop(s, NO_INPUT, "%s records from %s, which this DAW does not have: pick its input on its track page (F2)" % [t.display_name(), t.input])
		return
	# An instrument: its jack's track whether armed or not, else the armed one.
	if not bool(row.get("jacked", false)) and not t.rec_arm:
		_stop(s, NOT_ARMED, "%s is not armed, so nothing records it (it plays live on this machine's MONITOR)" % t.display_name(),
				{"label": "ARM", "verb": &"set_track_rec_arm", "args": [track, true], "step": "Arm %s" % t.display_name()})


## What a level is, in `send_level`'s and `fader_level`'s third figure.
const UNKNOWN := 0.0
const MEASURED := 1.0
const ESTIMATED := 2.0


## Track `t`'s post-fader level: Vector3(peak dBFS, RMS dBFS or NAN, MEASURED), nothing while it
## is muted (its meter may still show what it would play). The fader is measured on every DAW (the
## vu), so the routing bay's row meters read what the graph's fader stage does. Allocates nothing: the bay calls it for each row it shows, 30 times a second.
static func fader_level(t: MixState.TrackState) -> Vector3:
	var rms := NAN
	if not t.meter_rms.is_empty() and t.volume > 0.0 and is_finite(t.meter_rms[t.meter_rms.size() - 1]):
		rms = t.meter_rms[t.meter_rms.size() - 1] + FaderLaw.to_db(t.volume)
	return Vector3(FaderLaw.to_db(maxf(t.vu_l, t.vu_r)) if not t.mute else -INF, rms if not t.mute else NAN, MEASURED)


## Send slot `slot` of track `t` as heard where it leaves: Vector3(peak dBFS, 0, MEASURED or
## ESTIMATED). Measured where the backend meters each send (the built-in engine's send buses,
## `meter_sends`, in slot order); estimated otherwise from the track's own meter and the send's
## level -- post-fader, the track's peak plus the send; pre-fader, the last stage before the fader
## plus the send where the chain is metered, else (Reaper's meter is post-fader) less the fader too.
## Allocates nothing.
static func send_level(t: MixState.TrackState, slot: int) -> Vector3:
	var sd: MixState.SendState = t.sends.get(slot)
	if sd == null:
		return Vector3(-INF, 0.0, UNKNOWN)
	var n := 0
	for k in t.sends:
		if int(k) < slot:
			n += 1
	if n < t.meter_sends.size():
		return Vector3(t.meter_sends[n], 0.0, MEASURED)
	# A muted track's meter may still show what it would play; its sends carry nothing.
	if t.mute:
		return Vector3(-INF, 0.0, ESTIMATED)
	var send_db := FaderLaw.to_db(sd.volume)
	var plugins := 0
	for k in t.fx:
		if (t.fx[k] as MixState.FXState).name != "":
			plugins += 1
	var chain := t.meter_peak.size() == plugins + 1
	if sd.pre_fader and chain:
		return Vector3(t.meter_peak[t.meter_peak.size() - 1] + send_db, 0.0, ESTIMATED)
	var post := FaderLaw.to_db(maxf(t.vu_l, t.vu_r))
	return Vector3(post + send_db - (FaderLaw.to_db(t.volume) if sd.pre_fader and t.volume > 0.0 else 0.0), 0.0, ESTIMATED)


## Every send into track `dest`, added: Vector3(peak dBFS, how many sends, MEASURED or ESTIMATED)
## -- ESTIMATED where any of them is. The peaks are added as amplitudes, the worst case (peaks
## that land together), so a return fed by four sends none of which is hot can still say it would
## pass 0 dBFS. Key sends (sidechains) go to a detector, never the ears, and are left out.
static func arrival_level(state: MixState, dest: int) -> Vector3:
	var amp := 0.0
	var count := 0
	var how := MEASURED
	for index in state.tracks:
		if index == dest:
			continue
		var t: MixState.TrackState = state.tracks[index]
		for k in t.sends:
			var sd: MixState.SendState = t.sends[k]
			if sd.key or sd.resolve(state) != dest:
				continue
			var level := send_level(t, int(k))
			count += 1
			if level.z == ESTIMATED:
				how = ESTIMATED
			if is_finite(level.x):
				amp += db_to_linear(level.x)
	if count == 0:
		return Vector3(-INF, 0.0, UNKNOWN)
	return Vector3(linear_to_db(amp) if amp > 0.0 else -INF, float(count), how)


## A level in words, as a sign and a hover card say it: "−6.0 dBFS", "≈ −9.1 dBFS", "−∞ dBFS",
## "not measured".
static func db_words(db: float, how := MEASURED) -> String:
	if how == UNKNOWN:
		return "not measured"
	var figure := "−∞" if db <= -120.0 or not is_finite(db) else "%s%.1f" % ["+" if db > 0.0 else ("−" if db < 0.0 else ""), absf(db)]
	return ("≈ " if how == ESTIMATED else "") + figure + " dBFS"


## The soloed track that leaves `index` out, or 0 when it is heard: solo-in-place, as the built-in
## engine plays it (GodotBackend.audible). A soloed track's folders and the tracks it sends to stay up.
static func soloed_out(state: MixState, index: int) -> int:
	var t := state.track(index, false)
	if t == null or t.solo:
		return 0
	var soloed: Array = state.track_indices().filter(func(i): return state.tracks[i].solo)
	if soloed.is_empty():
		return 0
	var parents := state._folder_parents()
	for s: int in soloed:
		var up := int(parents.get(index, 0))
		while up > 0:
			if up == s:
				return 0
			up = int(parents.get(up, 0))
		up = int(parents.get(s, 0))
		while up > 0:
			if up == index:
				return 0
			up = int(parents.get(up, 0))
		for send in (state.tracks[s] as MixState.TrackState).sends.values():
			if (send as MixState.SendState).resolve(state) == index:
				return 0
	return soloed[0]


## The road from `from_id` to OUT along the main path, a stage at a time, stopping after the first
## break. A folder that stops what one of its children plays is said as the folder's.
func trace(from_id: String) -> Trace:
	var out := Trace.new()
	var at := stage(from_id)
	var seen := {}
	var from_track := at.track if at != null else 0
	while at != null and not seen.has(at.id):
		seen[at.id] = true
		out.stages.append(at)
		if at.halt != &"":
			out.broke_at = at
			out.reason = at.halt
			out.words = at.why
			out.fix = at.fix
			if at.halt == MUTED and at.track != from_track and from_track > 0:
				out.reason = FOLDER_MUTED
				out.words = "its folder %s is muted" % at.title.trim_suffix(" fader")
			return out
		if at.next == "":
			break
		at = stage(at.next)
	return out


## Every pipe: [from id, to id, the stage whose level it carries], the main roads and the branches.
func roads() -> Array:
	var out: Array = []
	for s: Stage in stages.values():
		if s.next != "" and stages.has(s.next):
			out.append([s.id, s.next, s])
		for b in s.branches:
			out.append([s.id, b, stages[b]])
	return out


## The stages over 0 dBFS, loudest first.
func clips() -> Array[Stage]:
	var out: Array[Stage] = []
	for s: Stage in stages.values():
		if (s.measured or s.estimated) and s.peak_db > CLIP_DB and s.kind != Kind.OUT:
			out.append(s)
	out.sort_custom(func(a: Stage, b: Stage) -> bool: return a.peak_db > b.peak_db)
	return out


static func clip_words(s: Stage) -> String:
	return "CLIPPING %s+%.1f dB at %s" % ["≈ " if s.estimated else "", s.peak_db, s.title]


## A level's health: &"silent" under FLOOR_DB, &"ok", &"hot" from HOT_DB, &"clip" over CLIP_DB.
static func health(peak_db: float) -> StringName:
	if peak_db > CLIP_DB:
		return &"clip"
	if peak_db >= HOT_DB:
		return &"hot"
	if peak_db <= FLOOR_DB:
		return &"silent"
	return &"ok"


## How thick a pipe is at `peak_db`, 0 (silent) to 1 (TOP_DB and over), even in decibels.
static func thickness(peak_db: float) -> float:
	return clampf((peak_db - FLOOR_DB) / (TOP_DB - FLOOR_DB), 0.0, 1.0)


## Do a stage's fix, as one step in the history (DAW.open_edit), through DAW so a guest's is an
## intent the host carries out. False for no fix.
static func apply_fix(fix: Dictionary) -> bool:
	if fix.is_empty() or not fix.has("verb"):
		return false
	var verb: StringName = fix["verb"]
	var step := str(fix.get("step", ""))
	if step != "":
		DAW.open_edit(step)
	DAW.callv(verb, fix.get("args", []))
	if step != "":
		DAW.close_edit()
	return true
