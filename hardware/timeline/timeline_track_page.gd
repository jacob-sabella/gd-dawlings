class_name TimelineTrackPage
extends TimelinePage

## Tracks added, removed and named, on the deck's TRACK page: ADD puts a new track after the
## picked one (or at the end), DUPLICATE a copy of the picked one after it, REMOVE removes the
## picked one, RENAME renames it. A track is picked
## by pressing its name. Removing is one undo away, like every edit. AUTO steps the picked track
## through read, touch and latch: in touch a control moved while the song plays writes its lane
## until it is let go, in latch until the transport stops. LANE shows the picked track's
## automation over its lane, one control after another (see TimelineSurface.lane_targets), and
## then none. INPUT steps the picked track through what it records from (`MixState.inputs`, then
## none chosen); saved with the project. COLOUR steps the picked track through PALETTE, its mark the
## track's colour. SCHEME gives every track that has no colour yet one of its own, round the wheel
## (TrackColours.scheme_colour), lit while there is a track it would colour. GROUP steps the picked
## track through the groups and out (DAW.GROUPS): grouped tracks' faders, mutes and solos move
## together; its light is the group's colour. With no track picked, AUTO and LANE are the master's.

var add: GlyphKey
var duplicate: GlyphKey
## Every item on the picked track selected.
var items: GlyphKey
var remove: GlyphKey
var rename: GlyphKey
var auto: GlyphKey
var lane: GlyphKey
var input: GlyphKey
var colour: GlyphKey
var scheme: GlyphKey
var group: GlyphKey
## Arms DAW.group_free: the next fader move is the picked track's alone.
var free: GlyphKey

## Each group's colour, for its light: group 1 is the first.
const GROUP_COLOURS := [Color(0.95, 0.62, 0.32), Color(0.45, 0.85, 0.75), Color(0.75, 0.55, 0.95), Color(0.95, 0.85, 0.4)]

## Twelve colours a track can be, round the wheel and readable on the dark desk. Shown in the
## venue's own twelve (TrackColours), stored as these.
const PALETTE := TrackColours.STANDARD

const MODE_NAMES := {0: "READ", 2: "TOUCH", 4: "LATCH"}


func _ready() -> void:
	tab_name = "TRACK"
	tab_glyph = &"track"
	add = _key("TrackAdd", &"add", Color(0.55, 0.85, 0.55), "TRACKS  ADD", _add,
			func() -> String:
				var picked: int = surface.picked_track
				return "a new track after %s" % _name_of(picked) if picked > 0 else "a new track at the end")
	duplicate = _key("TrackDuplicate", &"track_duplicate", Color(0.55, 0.85, 0.55), "TRACKS  DUPLICATE", _duplicate,
			func() -> String:
				var picked: int = surface.picked_track
				return "a copy of %s after it: its effects, sends, items and lanes" % _name_of(picked) \
						if picked > 0 else "press a track's name first")
	items = _key("TrackItems", &"track_items", Color(0.55, 0.7, 0.95), "TRACKS  SELECT ITEMS", _select_items,
			func() -> String:
				var picked: int = surface.picked_track
				return "every item on %s, and nothing else" % _name_of(picked) if picked > 0 else "press a track's name first")
	remove = _key("TrackRemove", &"remove", Color(0.95, 0.38, 0.34), "TRACKS  REMOVE",
			_remove,
			func() -> String:
				var picked: int = surface.picked_track
				return "%s, its items and the sends to it" % _name_of(picked) if picked > 0 else "press a track's name first")
	rename = _key("TrackName", &"rename", Color(0.45, 0.78, 0.95), "TRACKS  NAME",
			_rename,
			func() -> String:
				var picked: int = surface.picked_track
				if picked <= 0:
					return "press a track's name first"
				return "type a name for %s" % _name_of(picked) if surface.types_on_screen() \
						else "type a name for %s on the keypad" % _name_of(picked))
	colour = _key("TrackColour", &"colour", PALETTE[0], "TRACKS  COLOUR", _step_colour,
			func() -> String:
				var picked: int = surface.picked_track
				if picked <= 0 or not DAW.state.tracks.has(picked):
					return "press a track's name first"
				return "a new colour for %s" % _name_of(picked))
	scheme = _key("TrackScheme", &"scheme", TrackColours.STANDARD[6], "TRACKS  COLOUR SCHEME", _apply_scheme,
			func() -> String:
				var n := _uncoloured().size()
				return "every track already has a colour" if n == 0 \
						else "colour the %d track%s with none" % [n, "" if n == 1 else "s"])
	group = _key("TrackGroup", &"group", Color(0.62, 0.86, 1.0), "TRACKS  GROUP", _step_group, _group_text)
	free = _key("TrackGroupFree", &"group_free", Color(0.62, 0.86, 1.0), "TRACKS  GROUP  FREE",
			func() -> void: DAW.set_group_free(not DAW.group_free),
			func() -> String:
				return "the next fader move is one track's alone; press to take it back" if DAW.group_free \
						else "press, then move a fader: it moves alone, not with its group")
	DAW.group_free_changed.connect(func() -> void: free.lit = DAW.group_free)
	_group()
	input = _key("TrackInput", &"input", Color(0.95, 0.42, 0.38), "TRACKS  INPUT", _step_input,
			func() -> String:
				var picked: int = surface.picked_track
				if picked <= 0 or not DAW.state.tracks.has(picked):
					return "press a track's name first"
				return "%s records from %s: %s next" % [_name_of(picked),
						DAW.state.input_name(DAW.state.input_of(picked)), DAW.state.input_name(_next_input())])
	_group()
	auto = _key("TrackAuto", &"auto", Color(0.95, 0.6, 0.25), "TRACKS  AUTOMATION", _auto,
			func() -> String:
				var picked: int = surface.picked_track
				# With no track picked, the master's fader and pan.
				var who := _name_of(picked) if picked > 0 else "the master"
				var mode := _mode_of(picked)
				return "%s reads its lanes: %s next" % [who, MODE_NAMES[_next(mode)]] if mode == 0 \
						else "%s writes in %s: %s next" % [who, MODE_NAMES[mode], MODE_NAMES[_next(mode)]], true)
	lane = _key("TrackLane", &"lane", TimelineSurface.AUTOMATION_COLOUR, "TRACKS  AUTOMATION LANE", _lane,
			func() -> String:
				var picked: int = surface.picked_track
				# With no track picked, the master's lanes.
				var whose := "the master's " if picked <= 0 else ""
				var next := _next_lane()
				return "show %s%s" % [whose, TimelineSurface.lane_name(next).to_lower()] if next != "" else "hide the lane", true)
	DAW.track_changed.connect(_on_track_changed)
	DAW.master_changed.connect(_on_master_changed)
	refresh()


## The target after the one shown, or "" after the last.
func _next_lane() -> String:
	var targets := TimelineSurface.lane_targets(surface.picked_track)
	var at := targets.find(surface.shown_lane)
	if surface.shown_lane == "":
		return targets[0] if not targets.is_empty() else ""
	return targets[at + 1] if at >= 0 and at + 1 < targets.size() else ""


func _lane() -> void:
	if surface.picked_track == 0 or DAW.state.tracks.has(surface.picked_track):
		surface.show_lane(_next_lane())
		refresh()


func _on_master_changed(field: StringName) -> void:
	if field == &"automation_mode" and surface.picked_track == 0:
		refresh()


func _on_track_changed(index: int, field: StringName) -> void:
	if field in [&"automation_mode", &"input", &"colour", &"group"] and index == surface.picked_track:
		refresh()
	elif field == &"colour":
		scheme.lit = not _uncoloured().is_empty()


func _next(mode: int) -> int:
	return DAW.AUTOMATION_TOUCH if mode == DAW.AUTOMATION_READ \
			else DAW.AUTOMATION_LATCH if mode == DAW.AUTOMATION_TOUCH else DAW.AUTOMATION_READ


## The automation mode of a track, or of the master for 0.
func _mode_of(index: int) -> int:
	if index <= 0:
		return DAW.state.master.automation_mode
	return DAW.state.track(index).automation_mode if DAW.state.tracks.has(index) else 0


func _auto() -> void:
	var picked: int = surface.picked_track
	if picked == 0 or DAW.state.tracks.has(picked):
		DAW.set_track_automation_mode(picked, _next(_mode_of(picked)))


func refresh() -> void:
	add.lit = true
	var picked: bool = surface.picked_track > 0 and DAW.state.tracks.has(surface.picked_track)
	remove.lit = picked
	duplicate.lit = picked
	items.lit = picked
	rename.lit = picked
	lane.lit = surface.shown_lane != ""
	lane.caption = TimelineSurface.lane_name(surface.shown_lane) if surface.shown_lane != "" else ""
	var mode := _mode_of(surface.picked_track)
	auto.lit = mode != DAW.AUTOMATION_READ
	auto.caption = MODE_NAMES.get(mode, "READ") if mode != DAW.AUTOMATION_READ else ""
	input.lit = picked and DAW.state.input_of(surface.picked_track) != ""
	input.caption = DAW.state.input_name(DAW.state.input_of(surface.picked_track)).to_upper() \
			if input.lit else ""
	for key in [remove, duplicate, items, rename, input, colour, group, free]:
		key.available = picked
	var in_group: int = DAW.state.track(surface.picked_track).group if picked else 0
	group.led_colour = GROUP_COLOURS[in_group - 1] if in_group > 0 else Color(0.62, 0.86, 1.0)
	group.lit = in_group > 0
	if picked:
		colour.led_colour = DAW.state.track(surface.picked_track).shown_colour()
	# After the colour: setting lit repaints the key.
	colour.lit = picked
	scheme.lit = not _uncoloured().is_empty()
	notice = "%s" % _name_of(surface.picked_track).to_upper() if picked else "press a track's name to pick it  ·  AUTO and LANE: the master"


func _step_group() -> void:
	var picked: int = surface.picked_track
	if DAW.state.tracks.has(picked):
		DAW.set_track_group(picked, (DAW.state.track(picked).group + 1) % (DAW.GROUPS + 1))


func _group_text() -> String:
	var picked: int = surface.picked_track
	if not DAW.state.tracks.has(picked):
		return "press a track's name first"
	var now := DAW.state.track(picked).group
	var next := (now + 1) % (DAW.GROUPS + 1)
	var then := "group %d" % next if next > 0 else "no group"
	if now == 0:
		return "%s is in no group; press for %s" % [_name_of(picked), then]
	var mates: Array = DAW.group_mates(picked).map(func(j): return _name_of(j))
	var with := ", with " + ", ".join(mates) if not mates.is_empty() else ", alone so far"
	return "%s is in group %d%s; press for %s" % [_name_of(picked), now, with, then]


## The tracks nobody has coloured, by number.
func _uncoloured() -> Array:
	return DAW.state.track_indices().filter(func(i): return TrackColours.is_unset(DAW.state.track(i).colour))


## SCHM: a colour for every track that has none, by its place in the project, so neighbours
## differ. Tracks already coloured are left as they are.
func _apply_scheme() -> void:
	var order: Array = DAW.state.track_indices()
	for i in _uncoloured():
		DAW.set_track_colour(i, TrackColours.scheme_colour(order.find(i)))


## The palette's colour after the nearest one to `c`.
static func next_colour(c: Color) -> Color:
	var nearest := 0
	var best := INF
	for i in PALETTE.size():
		var p: Color = PALETTE[i]
		var d := Vector3(p.r - c.r, p.g - c.g, p.b - c.b).length_squared()
		if d < best:
			best = d
			nearest = i
	return PALETTE[(nearest + 1) % PALETTE.size()]


func _step_colour() -> void:
	var picked: int = surface.picked_track
	if picked > 0 and DAW.state.tracks.has(picked):
		DAW.set_track_colour(picked, next_colour(DAW.state.track(picked).colour))


## The input after the picked track's, round through none chosen.
func _next_input() -> String:
	var ids: Array = DAW.state.inputs.map(func(p): return p[0])
	ids.append("")
	var at := ids.find(DAW.state.input_of(surface.picked_track))
	return ids[(at + 1) % ids.size()]


func _step_input() -> void:
	var picked: int = surface.picked_track
	if picked > 0 and DAW.state.tracks.has(picked):
		DAW.set_track_input(picked, _next_input())


func _add() -> void:
	var picked: int = surface.picked_track
	var at: int = picked + 1 if picked > 0 else DAW.state.track_indices().size() + 1
	DAW.add_track(at, "")
	surface.pick_track(at)


func _select_items() -> void:
	var picked: int = surface.picked_track
	if picked > 0 and DAW.state.tracks.has(picked):
		DAW.select_track_items(picked)


func _duplicate() -> void:
	var picked: int = surface.picked_track
	if picked > 0 and DAW.state.tracks.has(picked):
		DAW.duplicate_track(picked)
		surface.pick_track(picked + 1)


func _remove() -> void:
	var picked: int = surface.picked_track
	if picked > 0 and DAW.state.tracks.has(picked):
		DAW.remove_track(picked)
		surface.pick_track(0)


func _rename() -> void:
	if surface.picked_track > 0:
		surface.ask_track_name(surface.picked_track)


func _name_of(index: int) -> String:
	return DAW.state.track(index).display_name() if DAW.state.tracks.has(index) else "track %d" % index
