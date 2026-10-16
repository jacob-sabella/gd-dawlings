class_name MixState
extends RefCounted

## The mix, as this process currently believes it to be.
##
## DAW-NEUTRAL BY CONSTRUCTION. Nothing in here is a Reaper concept: tracks with a level, a pan,
## three toggles and a colour; plugins with normalised parameters; sends named by destination;
## a transport. Every DAW this project could speak to has all of it, and the ones that have more
## can carry it as additional fields rather than as a second model. The translation from a
## particular DAW's wire vocabulary into this lives in that DAW's backend and nowhere else --
## see core/daw/daw_backend.gd.
##
## This is a CACHE, never a master copy. The DAW owns the mix; everything here arrived over the
## wire and may be stale by a frame. Nothing in the scene may treat a value here as committed:
## a fader that has been grabbed shows the hand's position and waits for Reaper to agree.
##
## Why a plain model with signals rather than nodes holding their own values: in a hybrid session
## the same track is drawn several times at once -- a channel strip on someone's monitor, the same
## strip in AR two metres away, a rack unit, and a node on the patchbay. One cache, many readers.

signal track_added(index: int)
signal track_changed(index: int, field: StringName)
signal transport_changed()
signal master_changed(field: StringName)
signal fx_changed(track_index: int, fx_index: int)
## The arrangement changed shape: items appeared or moved, or the project got longer. Separate
## from track_added because a timeline rebuilds on this and a console does not care.
signal timeline_changed()
## Which slice of the project the track indices currently mean.
signal bank_changed()
## A whole different project was opened in place of this one. Everything is new: a desk
## rebuilds, and a session host sends its guests the lot again.
signal project_replaced()
## The project's title or file name changed: it was saved somewhere, opened or started.
signal project_named()


class SendState extends RefCounted:
	var index: int = 0
	var dest_name: String = ""
	## The destination's track number, or -1 when only a name is known.
	##
	## Both, rather than one, because the two channels disagree about what a send points at.
	## OSC can only say the destination's NAME, which is ambiguous the moment a project has two
	## tracks called "Verb" -- and duplicate names are completely normal. The ReaScript bridge
	## says the index. Whoever draws a cable should prefer the index and fall back to the name,
	## so the bay is exact when the bridge is loaded and still roughly right when it is not.
	var dest_track: int = -1

	## The destination, best effort: the index when the bridge supplied one, else resolve the
	## name against `state`.
	func resolve(state) -> int:
		if dest_track > 0:
			return dest_track
		if dest_name == "":
			return -1
		for index in state.track_indices():
			if state.track(index).display_name() == dest_name:
				return index
		return -1

	var volume: float = 1.0
	var pan: float = 0.5
	## Into the destination's key input (channels 3/4) rather than its mix: a sidechain. Heard
	## by whatever plugin on that track listens for a key, and by nothing else.
	var key: bool = false
	## Taken before the track's fader and pan rather than after them: a cue or an effect send that
	## stays where it is when the track is pulled down in the mix. Reaper's "pre-fader (post-FX)".
	var pre_fader: bool = false


class FXState extends RefCounted:
	var index: int = 0
	var name: String = ""
	## What kind of plugin the DAW said it is -- "VST3", "JS" -- which `name` leaves off.
	var type: String = ""
	var enabled: bool = true
	## Normalised 0..1 by param index. Sparse on purpose: Reaper only reports the current
	## parameter bank, so a missing key means "not yet told", which is not the same as zero.
	var params: Dictionary = {}
	var param_names: Dictionary = {}
	## The plugin's own reading of each value -- "-12.0 dB", "4.0:1", "250 ms" -- as Reaper
	## formats it. Only Reaper knows a plugin's units; a 0..1 number shown as a percentage is
	## exact and still tells you nothing about the threshold you just moved.
	var param_text: Dictionary = {}
	## The normalised value each text was read at, where known. Text and value travel apart,
	## and this is how a reader tells whether the words still describe the knob.
	var param_text_at: Dictionary = {}
	## The plugin's own wet/dry, 0..1, where 1 is all plugin. Every plugin in Reaper has one,
	## outside its own parameters, which is why it is a field and not a param.
	var wet: float = 1.0
	## The preset it is on, by the plugin's own name for it. Empty when nobody has said.
	var preset: String = ""
	## How many presets the DAW itself holds for it, or -1 when nobody has said. A plugin can
	## have presets of its own the DAW cannot see: Neural DSP's live inside the plugin, and
	## Reaper reports none.
	var preset_count: int = -1
	## The plugin's real parameters, in its own order, once the DAW has listed them. A VST3 in
	## Reaper reports two thousand MIDI CC slots after its own couple of hundred controls, and
	## OSC only ever streams the first 32; this is the list worth showing. Empty until listed,
	## and then `params` is the list.
	var param_list: Array = []
	## The host's own handle on the plugin loaded for this slot (the built-in engine's
	## HostedPlugins), carried through moves and undo with the slot. Never on the wire.
	var host_key: String = ""

	## Every parameter there is to show, in order.
	func controls() -> Array:
		if not param_list.is_empty():
			return param_list
		var keys: Array = params.keys()
		for k in param_names:
			if not keys.has(k):
				keys.append(k)
		keys.sort()
		return keys


	## A plugin by the name a person calls it. Reaper's own lists say "VST3: Mantra (Neural DSP)"
	## and its OSC says "Mantra (Neural DSP)", and a tablet that found its plugin by name lost it
	## every time the other road reported.
	static func bare_name(raw: String) -> String:
		var colon := raw.find(": ")
		if colon > 0 and colon <= 6 and raw.substr(0, colon) in TYPE_PREFIXES:
			return raw.substr(colon + 2)
		return raw

	## The kind `bare_name` takes off, or "" when it has none.
	static func type_of(raw: String) -> String:
		var colon := raw.find(": ")
		if colon > 0 and colon <= 6 and raw.substr(0, colon) in TYPE_PREFIXES:
			return raw.substr(0, colon)
		return ""

	const TYPE_PREFIXES := ["VST", "VSTi", "VST3", "VST3i", "JS", "CLAP", "CLAPi", "AU", "AUi",
			"LV2", "LV2i", "DX", "DXi"]


## The master bus. Deliberately NOT a TrackState with a reserved index.
##
## Reaper addresses it as `/master/...`, not as a numbered track, and it has no mute, no solo, no
## record arm and no sends-to-anywhere. Folding it into the track dictionary would mean every
## loop over `track_indices()` -- the console's strips, the patchbay's two rows, the rack --
## having to remember to skip it, and the one that forgets puts a MASTER jack on the patchbay.
class MasterState extends RefCounted:
	var volume: float = 0.716
	var volume_db: float = 0.0
	var pan: float = 0.5
	var vu_l: float = 0.0
	var vu_r: float = 0.0
	## As TrackState.automation, for "volume" and "pan" only. Track 0 to `DAW.set_automation`.
	var automation: Dictionary = {}
	## As TrackState.automation_mode. `/master/automode`; track 0 to `DAW.set_track_automation_mode`.
	var automation_mode: int = 0


## One block of audio or MIDI on the timeline.
##
## Deliberately thin. A DAW's item has takes, stretch markers, fades, envelopes and a source
## file; none of that is drawable at the size a lane is rendered, and carrying it would mean a
## second model to keep in sync for no pixel gained. What the timeline draws is where a thing
## starts, how long it is, what it is called and whether it is muted.
class ItemState extends RefCounted:
	var index: int = 0
	## Seconds from the start of the project. Seconds and not bars: tempo can change, and a
	## position stored in bars would move whenever it did.
	var start: float = 0.0
	var length: float = 0.0
	var name: String = ""
	var muted: bool = false
	## Locked: it cannot be moved, trimmed, faded, cut, deleted or reshaped until it is unlocked
	## (Reaper's item lock, C_LOCK). Muting, selecting and copying it are still allowed.
	var locked: bool = false
	## The take lane it is on, 0 the first (DawKitClip.lane); see TrackState.comp.
	var lane: int = 0
	## Selected in the DAW: what a split or a move acts on. The DAW's own selection, not this
	## desk's, so a click in Reaper's window and a click on the desk are the same selection.
	var selected: bool = false
	## A MIDI item's notes, flat: [on, off, pitch, velocity, channel] repeating, seconds from
	## the item's left edge so that moving the item moves its notes. Empty for audio, and for a
	## backend that cannot read an item's contents. See MidiTake.
	var notes := PackedFloat32Array()
	## A recorded take's file, by name, in the host's AudioTake.DIR; empty for anything else. A
	## name and not a path, so a guest holding the item learns nothing about the host's disk.
	var source: String = ""
	## Seconds into the file at the item's left edge: not zero once the item has been split. For
	## a reversed item, seconds into the reversed sound.
	var source_offset: float = 0.0
	## Played backwards (Reaper's take reverse). Its `peaks` are the reversed sound's, so it is
	## drawn as it sounds.
	var reversed: bool = false
	## The file's overview, AudioTake.PEAKS_PER_SECOND bytes a second, for drawing.
	var peaks := PackedByteArray()
	## Linear fade lengths at each end, in seconds, and the clip's own gain.
	var fade_in: float = 0.0
	var fade_out: float = 0.0
	## How the fade in runs and how the fade out does: DawKitClip's FADE_ shapes.
	var fade_shape: int = DawKitClip.FADE_LINEAR
	var fade_out_shape: int = DawKitClip.FADE_LINEAR
	var gain_db: float = 0.0
	## A looped item plays its file between these two points (seconds into the file) for as
	## long as it lasts. Not looped when loop_end is not after loop_start.
	var loop_start: float = 0.0
	var loop_end: float = 0.0

	func has_clip_shape() -> bool:
		return fade_in != 0.0 or fade_out != 0.0 or gain_db != 0.0 or loop_end > loop_start \
				or fade_shape != DawKitClip.FADE_LINEAR or fade_out_shape != DawKitClip.FADE_LINEAR

	## The loudest the item's sound gets before its own gain, 0-1 of full scale, from the file's
	## overview; 0 for an item with none (MIDI, or a file nobody drew). The part of the file it
	## plays: the loop's range when looped, else from its offset for its length.
	func sound_peak() -> float:
		if peaks.is_empty():
			return 0.0
		var from := loop_start if is_looped() else source_offset
		var to := loop_end if is_looped() else source_offset + length
		var rate := float(AudioTake.PEAKS_PER_SECOND)
		var loudest := 0
		for n in range(maxi(int(floor(from * rate)), 0), mini(int(ceil(to * rate)), peaks.size())):
			loudest = maxi(loudest, peaks[n])
		return float(loudest) / 255.0

	func is_looped() -> bool:
		return loop_end > loop_start

	## The item's own level at song position `seconds`, in dB: its gain, and its fades, from
	## silence to full in a straight line in amplitude, or a quarter sine when equal-power -- as
	## the engine plays them (dawkit's lane).
	func level_db(seconds: float) -> float:
		var through := 1.0
		if fade_in > 0.0:
			through = minf(through, DawKitClip.fade_gain((seconds - start) / fade_in, fade_shape))
		if fade_out > 0.0:
			through = minf(through, DawKitClip.fade_gain((end() - seconds) / fade_out, fade_out_shape))
		return gain_db + linear_to_db(clampf(through, 0.0001, 1.0))

	## Seconds into the file that sound at song position `seconds`.
	func file_time(seconds: float) -> float:
		var at := source_offset + seconds - start
		if is_looped() and at >= loop_end:
			at = loop_start + fposmod(at - loop_start, loop_end - loop_start)
		return at

	func end() -> float:
		return start + length

	func contains(seconds: float) -> bool:
		return seconds > start and seconds < start + length


class TrackState extends RefCounted:
	var index: int = 0
	var name: String = ""
	## The DAW's normalised fader position, 0..1 -- NOT a gain multiplier and NOT dB. Converting it
	## for display is a control's business; storing it converted would lose the round trip.
	var volume: float = 0.716
	var volume_db: float = 0.0
	var pan: float = 0.5
	var mute: bool = false
	var solo: bool = false
	var rec_arm: bool = false
	## Input monitoring: 0 off, 1 on, 2 auto. Reaper's I_RECMON, and what `/track/N/monitor` says.
	var monitor: int = 0
	## What it records from: one of the DAW's `MixState.inputs` by id, or "" for whatever the
	## recorder is set to. Saved with the project. `/track/N/input`.
	var input: String = ""
	## The demo song's part this track plays (DemoSong.ROLES), set when the stand-in's song is
	## made and kept whatever the track is renamed; "" for any other track.
	var part: String = ""
	## How the track's controls and their automation meet, Reaper's I_AUTOMODE numbers: 0 read
	## (the lanes move the controls), 2 touch (a control moved while playing writes its lane until
	## it is let go), 4 latch (until the transport stops). `/track/N/automode`.
	var automation_mode: int = 0
	var selected: bool = false
	var colour: Color = Color(0.55, 0.57, 0.6)
	## The track group it is in, 1 to DAW.GROUPS, or 0 for none: the tracks of a group move
	## together, faders by the same decibels and mutes and solos as one (DAW.group_mates).
	## Saved with the project. `/track/N/group`.
	var group: int = 0
	## Reaper's I_FOLDERDEPTH on this track: 1 opens a folder, 0 stays at the current level, and
	## a negative number closes that many. It is a DELTA, not a level -- the level is the running
	## sum over the tracks before it, which is what `MixState.folder_level` works out.
	var folder_depth: int = 0
	## Peak 0..1 per channel. Decayed by the meter that draws it, not by Reaper.
	var vu_l: float = 0.0
	var vu_r: float = 0.0
	var fx: Dictionary = {}
	var sends: Dictionary = {}
	## ItemState, in start order. Empty when the backend cannot report an arrangement at all,
	## which is not the same as a track with nothing on it -- see DAWBackend.Capability.
	var items: Array = []
	## Which take lane sounds where, [start, end, lane] in seconds (DawKitTrack.comp). Empty: no
	## comp, and the items sound as they lie, a newer one over an older.
	var comp: Array = []
	## A frozen track (DAWBackend._locally_freeze): empty, or what it was -- "items" and "comp" as
	## MixWire packs them and "fx_on", whether each plugin slot ran -- while `items` is the one
	## rendered item and the plugins are bypassed. Held by the host (and saved with the project);
	## guests are not sent it.
	var frozen: Dictionary = {}
	## Automated controls: target -> [[seconds, value, shape], ...], as DawKitAutomation's, except
	## that a send is "send:<destination track index>". Read while the song plays.
	var automation: Dictionary = {}

	func is_frozen() -> bool:
		return not frozen.is_empty()

	## The plugin slots that hold a plugin, in chain order. Reaper's OSC reports every slot its
	## device is configured for -- sixteen here -- and the empty ones arrive with empty names.
	func plugins() -> Array:
		var out: Array = []
		var order: Array = fx.keys()
		order.sort()
		for i in order:
			if (fx[i] as FXState).name != "":
				out.append(i)
		return out

	func display_name() -> String:
		return name if name != "" else "Track %d" % index

	## The colour this track is drawn in: its own, read in the venue's palette. See TrackColours.
	func shown_colour() -> Color:
		return TrackColours.shown(colour, index)


var tracks: Dictionary = {}
var master := MasterState.new()
var playing: bool = false
var recording: bool = false
var position_seconds: float = 0.0
var position_string: String = "1.1.00"
## The clock as the DAW spells it in minutes and seconds, when it says. Bar/beat is the one a
## desk shows; this is for the readout that wants both.
var time_string: String = ""
var tempo: float = 120.0
## The tempo's changes, as DawKitTempoMap's points ([beat, bpm, shape], the first at beat 0);
## empty for a song at one tempo. `tempo` is the first point's tempo, and changing it changes
## that and nothing after it.
var tempo_points: Array = []:
	set(v):
		tempo_points = v
		_map = null
var _map: DawKitTempoMap = null
var _map_tempo := 0.0
## The most bars a count-in may be.
const COUNT_IN_MAX := 8


## Whether recording now would count in first.
func counts_in() -> bool:
	return count_in_bars > 0 and metronome


## Whether playing now, from a standstill, would count in first.
func counts_in_playing() -> bool:
	return count_in_play and counts_in()


## Whether the transport is counting in, to a recording or to playback: the click, and the song
## only with pre-roll.
func counting_in() -> bool:
	return playing and count_in_to >= 0.0 and position_seconds < count_in_to


## Whether the song is silent for now: counting in without pre-roll.
func song_held() -> bool:
	return counting_in() and not pre_roll


## Whether what is played now is being recorded: recording, past any count-in, and inside the
## punch range when punching.
func taking() -> bool:
	return recording and playing and takes_at(position_seconds)


## Whether a recording takes what is heard at `seconds` of the song: past any count-in, and
## inside the punch range when punching. Takes ask this of the moment they hear, which is behind
## the playhead by the output's latency (and a guest's by the network's too), so their edges are
## where the song is, not where the playhead was when it got there.
func takes_at(seconds: float) -> bool:
	return (count_in_to < 0.0 or seconds >= count_in_to) and in_punch(seconds)


## Whether a recording would take at `seconds`: anywhere, unless punching to a range.
func in_punch(seconds: float) -> bool:
	return not (punch and has_loop_range()) or (seconds >= loop_start and seconds < loop_end)


## Where a count-in to `at` starts: `count_in_bars` bars of the tempo there earlier. Before the
## song's start, at the first tempo.
func count_in_start(at: float) -> float:
	var map := tempo_map()
	var m := meter()
	return map.seconds_at(m.beat_of_bar(m.bar_at(map.beat_at(at)) - float(count_in_bars)))


## Where the next bar begins at or after `at`: `at` itself if it already sits on one, through
## whatever tempo and time signature changes lie between -- the same two maps `count_in_start`
## reads, run the other way round.
func next_bar_start(at: float) -> float:
	var map := tempo_map()
	var m := meter()
	return map.seconds_at(m.beat_of_bar(ceil(m.bar_at(map.beat_at(at)))))


## The song's time signature: counts in a bar, and the note value of one. Reaper's OSC surface
## does not send it; its bridge does. `/timesig`.
var beats_per_bar: int = 4
var beat_unit: int = 4
## The signature's changes, as DawKitMeter's points ([beat, numerator, denominator], the first at
## beat 0); empty for one signature throughout. `/timesig/map`.
var time_signature_points: Array = []
var _meter: DawKitMeter = null
var _meter_key := ""


## Where every bar begins, through the signature's changes (dawkit's DawKitMeter).
func meter() -> DawKitMeter:
	var key := "%d/%d/%s" % [beats_per_bar, beat_unit, time_signature_points]
	if _meter == null or key != _meter_key:
		_meter = DawKitMeter.from_array(time_signature_points, maxi(beats_per_bar, 1), maxi(beat_unit, 1))
		if not time_signature_points.is_empty():
			_meter.set_point(0.0, maxi(beats_per_bar, 1), maxi(beat_unit, 1))
		_meter_key = key
	return _meter


## Bars from the song's start to `seconds`, 0 at the start, with the fraction of the bar.
func bar_at(seconds: float) -> float:
	return meter().bar_at(beat_at(seconds))
## Whether the click is on. Reaper's metronome, which is a transport setting there as here.
var metronome: bool = false
## The inputs a track can record from on this DAW, [id, name] each: the built-in engine's are
## the machine's input devices and its keys, Reaper's its input channels and MIDI. "" is none
## chosen. `/inputs`.
var inputs: Array = []
## The plugins a track's chain can be given on this DAW, [id, name] each: the built-in engine's
## Godot effects, Reaper's own stock plugins. `/fxchoices`.
var fx_choices: Array = []


## The input a track records from, or "" for none chosen or no such track.
func input_of(index: int) -> String:
	var t := track(index, false) if index > 0 else null
	return t.input if t != null else ""


## A track input's name, or the id itself for one this DAW does not list.
func input_name(id: String) -> String:
	if id == "":
		return "as the recorder is set"
	for pair in inputs:
		if pair[0] == id:
			return pair[1]
	return id


## Bars of click before recording starts, 0 for none. As in Reaper, a count-in is the metronome's:
## with the click off, recording starts at once.
var count_in_bars: int = 0
## Where a counted-in recording begins, kept until the transport stops: the transport runs from
## `count_in_bars` before it with the click alone, recording but not yet taking. Kept past it, as
## what is heard reaches it later than the playhead does. -1 for a recording not counted in. Reaper does
## the same, its playhead running up to the record point from before it.
var count_in_to: float = -1.0
## The count-in before playback too, as Reaper's "Count-in before playback": playing from a
## standstill runs the same bars of click first, and the song starts where the transport stood.
var count_in_play: bool = false
## Pre-roll: the count-in plays the song under the click, from that many bars before, as Reaper's
## "Pre-roll" does, rather than the click alone. Recording still takes from where it stood.
var pre_roll: bool = false
## Punching in and out: a recording takes only inside the loop range (Reaper's time selection
## auto-punch, the loop range there being the time selection). With no range, all of it.
var punch: bool = false
## Whether playback wraps round the loop range. Reaper calls it repeat.
var looping: bool = false
## The loop range, in seconds. In Reaper this is the time selection when the two are linked,
## which is how almost everyone runs it, so one pair stands for both. Equal ends mean no range.
var loop_start: float = 0.0
var loop_end: float = 0.0
## How many steps there are to undo and redo, when the backend knows. -1: it does not say.
var undo_depth: int = -1
var redo_depth: int = -1
## What each step of history is called, oldest first: the `undo_depth` done ones, then the ones
## to redo, the next first. Empty when the backend does not say.
var undo_names: Array = []
## Seconds. How far the ruler has to run, which is NOT derivable from the items: a project can
## be longer than its last item, and a timeline that ends at the last block cannot be scrolled
## into the empty bars you are about to record into.
var project_length: float = 0.0
## {position_seconds: String name}, in no particular order.
var markers: Dictionary = {}
## Named spans: [start, end, name] in seconds, in order of their starts.
var regions: Array = []


## The region the playhead (or `seconds`) is in, as its index in `regions`, or -1: the latest to
## start at or before it, of those that have not ended.
func region_at(seconds: float) -> int:
	var found := -1
	for i in regions.size():
		if float(regions[i][0]) <= seconds + 0.0005 and seconds < float(regions[i][1]) - 0.0005:
			found = i
	return found

## How many of the project's tracks come BEFORE the one this cache calls index 1.
##
## The uncomfortable fact this models: a control surface protocol streams a BANK of tracks, not
## a project. Reaper's bank is 64 wide, so in a 90-track session the indices in this cache mean
## tracks 1..64 or tracks 65..90 depending on where the bank is, and nothing in the message
## itself says which. Without this, a 90-track project silently looks like a 64-track one and
## the fader labelled KICK moves something else after a bank change.
var bank_offset: int = 0
## How wide the bank is -- how many tracks the surface can see at once.
var bank_size: int = 64
## Tracks in the whole project, or -1 when nothing has said. -1 is not zero: "I have not been
## told how big this project is" and "this project has no tracks" want opposite things drawn.
var project_track_count: int = -1
## What the host's project is called, and the name of its file (only the name: a guest learns
## nothing of the host's disk), empty when it was never saved. Both empty where the DAW does not say.
var project_title: String = ""
var project_file: String = ""


## Where every beat falls, kept until the tempo or its changes do.
func tempo_map() -> DawKitTempoMap:
	if _map == null or _map_tempo != tempo:
		_map = DawKitTempoMap.new(maxf(tempo, 1.0)) if tempo_points.is_empty() \
				else DawKitTempoMap.from_array(tempo_points)
		if not tempo_points.is_empty():
			_map.set_point(0.0, maxf(tempo, 1.0), tempo_points[0][2])
		_map_tempo = tempo
	return _map


## The beat `seconds` into the song falls on, counted from 0, through the tempo's changes.
func beat_at(seconds: float) -> float:
	return tempo_map().beat_at(seconds)


func seconds_at_beat(beat: float) -> float:
	return tempo_map().seconds_at(beat)


## `seconds` as bar.count.hundredths, counted from bar 1, through the tempo's and the time
## signature's changes: a count is a quarter in x/4, an eighth in x/8.
func bar_beat(seconds: float) -> String:
	var at: Array = meter().position(tempo_map().beat_at(maxf(seconds, 0.0)))
	return "%d.%d.%02d" % [at[0], at[1], mini(int(float(at[2]) * 100.0), 99)]


## Seconds at the start of `bar` (1-based).
func bar_to_seconds(bar: float) -> float:
	return tempo_map().seconds_at(meter().beat_of_bar(bar - 1.0))


func has_loop_range() -> bool:
	return loop_end > loop_start + 0.001


## The project-wide number of a track this cache calls `index`. What a human reads off a desk.
func absolute_track_number(index: int) -> int:
	return bank_offset + index


## Whether `index` is a track that exists. Reaper's OSC reports every slot of its bank, so a
## 40-track session in a 64-wide bank arrives with 24 more tracks that are not there -- named
## "Track 41", faders at -inf -- and a desk that drew them was a desk 47 strips wide that lied
## about the session in front of it. Unknown project size admits everything.
func in_project(index: int) -> bool:
	return project_track_count <= 0 or absolute_track_number(index) <= project_track_count


## Drop whatever the cache holds past the end of the project. For when the project's size
## arrives after the bank's slots already have.
func trim_to_project() -> void:
	var gone := false
	for index in tracks.keys():
		if not in_project(index):
			tracks.erase(index)
			gone = true
	if gone:
		bank_changed.emit()


## True when there is more project than this bank can show.
func has_more_banks() -> bool:
	return project_track_count > bank_size


## Which tracks this cache is holding, out of how many exist, or "" when it holds them all.
##
## Here rather than in each surface because THREE things now have to say it and they must not
## drift: a console that says "17-32 OF 90" beside a timeline that says "17-32 of 90 tracks" is
## two different facts as far as anyone reading the room is concerned.
##
## Measured from what is HELD, not from bank_size. has_more_banks() asks whether the project is
## bigger than a bank, which is a different question and not always the same answer -- the
## offline stand-in at 90 tracks caches all 90 and a caption derived from bank_size would have
## read "TRACKS 1-64 OF 90" over ninety drawn lanes. A caption that disagrees with the thing it
## is captioning is worse than none, since the whole job here is to be believed about what is
## missing. The range therefore comes from the keys actually in the cache.
##
## Empty string for "nothing to say", which is the case a caller must handle: a session that
## fits needs no caption, and a caption that is always present teaches people to stop reading
## it exactly when it starts mattering.
func bank_caption() -> String:
	var held := tracks.size()
	if project_track_count <= 0 or held <= 0 or held >= project_track_count:
		return ""
	return "TRACKS %d-%d OF %d" % [bank_offset + 1, bank_offset + held, project_track_count]


func set_bank(offset: int, size: int = -1) -> void:
	var new_size := size if size > 0 else bank_size
	if offset == bank_offset and new_size == bank_size:
		return
	bank_offset = offset
	bank_size = new_size
	# The indices now mean different tracks, so everything keyed by index is wrong rather than
	# stale. Dropping it is the only honest move: keeping it would leave the previous bank's
	# names on this bank's faders until each one happened to be re-sent.
	tracks.clear()
	bank_changed.emit()


## Replace one track's arrangement wholesale.
##
## Wholesale and not per item, because the only honest unit of change is the lane: a DAW that
## reports items at all reports them as a list, and diffing to find the three that moved costs
## more than redrawing twelve rectangles.
## The comp of a track's takes, as [start, end, lane] stretches (see TrackState.comp).
func set_track_comp(index: int, comp: Array) -> void:
	track(index).comp = comp
	timeline_changed.emit()


func set_track_items(index: int, items: Array) -> void:
	var t := track(index)
	t.items = items
	t.items.sort_custom(func(a, b): return a.start < b.start)
	# An item's index is its place in the lane, left to right -- which is also how Reaper
	# numbers a track's items -- so it is renumbered after every sort rather than trusted.
	for i in t.items.size():
		t.items[i].index = i
	timeline_changed.emit()


## Every selected item as [track_index, item_index], in lane order.
func selected_items() -> Array:
	var out: Array = []
	for index in track_indices():
		for item in track(index).items:
			if item.selected:
				out.append([index, item.index])
	return out


func item(track_index: int, item_index: int) -> ItemState:
	if not tracks.has(track_index):
		return null
	var items: Array = tracks[track_index].items
	return items[item_index] if item_index >= 0 and item_index < items.size() else null


func set_project_length(seconds: float) -> void:
	if is_equal_approx(project_length, seconds):
		return
	project_length = seconds
	timeline_changed.emit()


## The length the ruler should actually draw: whatever the DAW says, but never shorter than the
## last thing on the timeline, and never zero -- a ruler of length zero divides by it.
func timeline_length() -> float:
	var out := project_length
	for index in tracks:
		var t: TrackState = tracks[index]
		if not t.items.is_empty():
			out = maxf(out, t.items[-1].end())
	return maxf(out, 1.0)


func track(index: int, create: bool = true) -> TrackState:
	if tracks.has(index):
		return tracks[index]
	if not create:
		return null
	var t := TrackState.new()
	t.index = index
	tracks[index] = t
	track_added.emit(index)
	return t


## How deep in the folder tree a track sits, counting from 0.
##
## Reaper stores the DELTA on each track rather than the level, because that is what a .RPP
## records -- so the level only exists as a running sum, and only in track order. Computed on
## demand rather than cached: the alternative is a cache invalidated by every structure poll,
## every bank change and every track insert, which is three chances to show the wrong grouping.
func folder_level(index: int) -> int:
	var level := 0
	for i in track_indices():
		if i >= index:
			break
		level = maxi(level + track(i).folder_depth, 0)
	return level


## True when `index` starts a new group. This is what a console puts a gap at.
##
## NOT simply "the level changed", which is the obvious rule and the wrong one. A folder's
## parent sits at the OUTER level -- that is what makes it the parent -- so a level-change rule
## cuts between the bus and its own children and leaves the bus lumped in with whatever
## happened to precede it. On the demo project that put the VOX bus in with the guitars.
##
## So: a group starts where a track OPENS a folder (the parent heads its group, the way a track
## panel draws it) or where the level DROPS back out of one. A rise immediately under a parent
## is not a break, because the parent already started that group.
func starts_group(index: int) -> bool:
	var order := track_indices()
	var at := order.find(index)
	if at <= 0:
		return at == 0
	if track(index).folder_depth > 0:
		return true
	return folder_level(index) < folder_level(order[at - 1])


func track_indices() -> Array:
	var keys := tracks.keys()
	keys.sort()
	return keys


func set_track_field(index: int, field: StringName, value: Variant) -> void:
	var t := track(index)
	if t.get(field) == value:
		return
	t.set(field, value)
	track_changed.emit(index, field)


func set_master_field(field: StringName, value: Variant) -> void:
	if master.get(field) == value:
		return
	master.set(field, value)
	master_changed.emit(field)


func fx(track_index: int, fx_index: int, create: bool = true) -> FXState:
	var t := track(track_index)
	if t.fx.has(fx_index):
		return t.fx[fx_index]
	if not create:
		return null
	var f := FXState.new()
	f.index = fx_index
	t.fx[fx_index] = f
	fx_changed.emit(track_index, fx_index)
	return f


func send(track_index: int, send_index: int, create: bool = true) -> SendState:
	var t := track(track_index)
	if t.sends.has(send_index):
		return t.sends[send_index]
	if not create:
		return null
	var s := SendState.new()
	s.index = send_index
	t.sends[send_index] = s
	return s
