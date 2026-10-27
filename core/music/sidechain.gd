class_name Sidechain
extends RefCounted

## A sidechain as the stage table's rope is one (docs/spatial_loop.md slice 20, idea #18): a key
## send from one track (the kick) into another's key input (DAW.create_sidechain), and a compressor
## on that other track (the bass) listening to it. On the built-in engine every compressor on a
## keyed track listens to its key (GodotBackend.listen); on Reaper the bridge sets ReaComp's
## detector to the auxiliary input. Static and pure, so every machine reads a rope the same way.
##
## Neither engine says how far a compressor is turning its track down, so how hard a rope ducks is
## an estimate (`reduction`): the key's level at the compressor, which is the key track's meter
## and the key send's level, over the compressor's threshold, less what its ratio lets through.
## A hard knee, as Godot's AudioEffectCompressor and ReaComp at its default have.
##
## A rope's pull (0 slack to 1 as hard as it goes, StageTable.Rope) is two values that move
## together: the key send's level, SEND_SLACK_DB to SEND_TAUT_DB, and the compressor's threshold,
## THRESHOLD_SLACK_DB to THRESHOLD_TAUT_DB, both linear in dB.

## A compressor whose ratio nobody has said.
const RATIO_DEFAULT := 4.0
## How loud a kick is taken to hit (dB at its fader) before its meter has been seen to: what the
## card's estimate starts from while the song is stopped.
const HIT_DB := -6.0
## The key send's level and the compressor's threshold, slack and as hard as a rope pulls (dB).
const SEND_SLACK_DB := 0.0
const SEND_TAUT_DB := 6.0
const THRESHOLD_SLACK_DB := -30.0
const THRESHOLD_TAUT_DB := -60.0
## The built-in compressor's threshold and ratio parameters (FXCatalogue's "compressor"), which
## ReaComp has in the same places.
const THRESHOLD_PARAM := 0
const RATIO_PARAM := 1


## How far (dB) a compressor at `threshold_db` and `ratio` turns its track down while its key is at
## `key_db`: nothing under the threshold, and above it all but 1/ratio of what is over.
static func reduction(key_db: float, threshold_db: float, ratio: float) -> float:
	if is_nan(key_db) or key_db == -INF:
		return 0.0
	var over := key_db - threshold_db
	if over <= 0.0:
		return 0.0
	return over * (1.0 - 1.0 / maxf(ratio, 1.0))


## A rope's name, and its room row's key: the two tracks by their numbers in the project, so it is
## the same rope whichever bank a table is showing. "2>6".
static func rope_key(from_track: int, to_track: int) -> String:
	var off := DAW.state.bank_offset if DAW.state != null else 0
	return "%d>%d" % [off + from_track, off + to_track]


## Whether a plugin is a compressor, by its name: the built-in "Compressor", Reaper's "ReaComp".
## Any compressor: a key reaches only the ones `listens` says.
static func is_compressor(f: MixState.FXState) -> bool:
	if f == null:
		return false
	var n := f.name.to_lower()
	return n.contains("compressor") or n.contains("reacomp")


static func is_reacomp(f: MixState.FXState) -> bool:
	return f != null and f.name.to_lower().contains("reacomp")


## Which engine's compressors a key reaches, from the DAW's plugin choices, so a guest reads it as
## its host does: &"built_in" where the choices have FXCatalogue's "compressor" kind (only its
## AudioEffectCompressor listens, GodotBackend.listen; not a hosted plugin with the word in its
## name), &"reaper" where they have a ReaComp (only ReaComps listen, the bridge's `compressors`;
## not a third-party compressor), and &"" while there are no choices yet, when any compressor does.
static func engine() -> StringName:
	if DAW.state == null:
		return &""
	var reaper := false
	for c in DAW.state.fx_choices:
		var row := c as Array
		if row.is_empty():
			continue
		if str(row[0]) == "compressor":
			return &"built_in"
		if (str(row[0]) + " " + (str(row[1]) if row.size() > 1 else "")).to_lower().contains("reacomp"):
			reaper = true
	return &"reaper" if reaper else &""


## Whether a key send into its track reaches this plugin: the compressor `engine` keys.
static func listens(f: MixState.FXState) -> bool:
	match engine():
		&"built_in":
			return f != null and f.name == str(FXCatalogue.kinds()[&"compressor"]["name"])
		&"reaper":
			return is_reacomp(f)
	return is_compressor(f)


## The first compressor in `track`'s chain that a key reaches (its FX index), or -1 for none.
static func compressor_on(track: int) -> int:
	var t := DAW.state.track(track, false) if DAW.state != null else null
	if t == null:
		return -1
	for i in t.plugins():
		if listens(t.fx[i]):
			return i
	return -1


## The plugin a rope adds when the track it is tied to has none that listens: the built-in
## "compressor", Reaper's ReaComp (which the bridge's CreateSidechain would add itself), by its id;
## with neither, the first of the DAW's choices whose id or name says compressor.
static func compressor_choice() -> String:
	if DAW.state == null:
		return ""
	var which := engine()
	for c in DAW.state.fx_choices:
		var row := c as Array
		if row.size() < 2:
			continue
		var words := (str(row[0]) + " " + str(row[1])).to_lower()
		if which == &"built_in" and str(row[0]) == "compressor" or which == &"reaper" and words.contains("reacomp") \
				or which == &"" and (words.contains("compressor") or words.contains("reacomp")):
			return str(row[0])
	return ""


## Which of `from_track`'s sends is its key into `to_track` (its send number, 1 first), 0 for none.
static func key_send(from_track: int, to_track: int) -> int:
	var t := DAW.state.track(from_track, false) if DAW.state != null else null
	if t == null:
		return 0
	for n in t.sends:
		var send: MixState.SendState = t.sends[n]
		if send.key and send.resolve(DAW.state) == to_track:
			return int(n)
	return 0


## Every key send between two tracks in the cache, as [from, to] pairs in track order: every rope
## there is, whether a rope or the patchbay made it.
static func pairs() -> Array:
	var out: Array = []
	if DAW.state == null:
		return out
	for i in DAW.state.track_indices():
		var t: MixState.TrackState = DAW.state.tracks[i]
		var numbers: Array = t.sends.keys()
		numbers.sort()
		for n in numbers:
			var send: MixState.SendState = t.sends[n]
			var to := send.resolve(DAW.state)
			if send.key and to > 0 and to != i and DAW.state.tracks.has(to):
				out.append([i, to])
	return out


## The key send's level (dB), -inf for none.
static func send_db(from_track: int, to_track: int) -> float:
	var n := key_send(from_track, to_track)
	if n == 0:
		return -INF
	return FaderLaw.to_db((DAW.state.track(from_track).sends[n] as MixState.SendState).volume)


## A compressor's threshold in dB: the plugin's own words for it where they still describe the
## knob, else by the knob: ReaComp's runs as an amplitude (1 is 0 dB), the built-in one's as
## FXCatalogue has it (-60 to 0 dB).
static func threshold_db(f: MixState.FXState) -> float:
	if f == null:
		return 0.0
	var v := float(f.params.get(THRESHOLD_PARAM, 1.0))
	var said := _said(f, THRESHOLD_PARAM, v)
	if not is_nan(said):
		return said
	if is_reacomp(f):
		return linear_to_db(maxf(v, 0.000001))
	return (FXCatalogue.params(&"compressor")[THRESHOLD_PARAM] as FXCatalogue.Param).value_of(v)


## The knob's value (0..1) for a threshold of `db` on that compressor.
static func threshold_value(f: MixState.FXState, db: float) -> float:
	if is_reacomp(f):
		return clampf(db_to_linear(db), 0.0, 1.0)
	return (FXCatalogue.params(&"compressor")[THRESHOLD_PARAM] as FXCatalogue.Param).normalise(db)


## A compressor's ratio: its own words where they still describe the knob, else the built-in law
## (1 to 48 on a log curve), or RATIO_DEFAULT for a ReaComp nobody has read.
static func ratio_of(f: MixState.FXState) -> float:
	if f == null or not f.params.has(RATIO_PARAM):
		return RATIO_DEFAULT
	var v := float(f.params[RATIO_PARAM])
	var said := _said(f, RATIO_PARAM, v)
	if not is_nan(said):
		return maxf(said, 1.0)
	if is_reacomp(f):
		return RATIO_DEFAULT
	return (FXCatalogue.params(&"compressor")[RATIO_PARAM] as FXCatalogue.Param).value_of(v)


## The number in a plugin's own reading of a parameter ("-20.0 dB", "4.0:1"), while it was read at
## the value it has now; NAN when there is none.
static func _said(f: MixState.FXState, param: int, v: float) -> float:
	if not f.param_text.has(param) or not f.param_text_at.has(param) \
			or absf(float(f.param_text_at[param]) - v) > 0.0005:
		return NAN
	var words := str(f.param_text[param]).strip_edges()
	var number := ""
	for ch in words:
		if ch in "+-.0123456789":
			number += ch
		elif number != "":
			break
	return float(number) if number.is_valid_float() else NAN


## How hard a rope at `pull` (0..1) has it: [the key send's dB, the threshold's dB].
static func of_pull(pull: float) -> Vector2:
	var p := clampf(pull, 0.0, 1.0)
	return Vector2(lerpf(SEND_SLACK_DB, SEND_TAUT_DB, p), lerpf(THRESHOLD_SLACK_DB, THRESHOLD_TAUT_DB, p))


## The pull a threshold stands for (0..1): a compressor set higher than slack is slack.
static func pull_of(threshold: float) -> float:
	return clampf(inverse_lerp(THRESHOLD_SLACK_DB, THRESHOLD_TAUT_DB, threshold), 0.0, 1.0)


## How far the rope from `from_track` to `to_track` ducks with its key at `key_track_db` (the key
## track's level at its fader, dB): the key send's level is added, and the first compressor on
## `to_track` reads it. 0 with no key send or no compressor.
static func ducks(from_track: int, to_track: int, key_track_db: float) -> float:
	var comp := compressor_on(to_track)
	var send := send_db(from_track, to_track)
	if comp < 0 or send == -INF:
		return 0.0
	var f := DAW.state.fx(to_track, comp)
	return reduction(key_track_db + send, threshold_db(f), ratio_of(f))
