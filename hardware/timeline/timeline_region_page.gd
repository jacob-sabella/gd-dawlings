class_name TimelineRegionPage
extends TimelinePage

## The song's regions -- its named spans, verse, chorus, bridge -- on the deck's REGION page. ADD
## makes one of the loop range, named for the marker at its start if there is one; LOOP loops the
## region the playhead is in; REMOVE takes that region away; NAME renames it, on the keypad; FIT
## moves and resizes it to the loop range. Each an edit, one undo step. The list is a rail, one
## place along it for each region in order, that takes the playhead to the start of the one let
## go on. The regions themselves are drawn in the ruler's loop band (TimelineSurface).

const INK := Color(0.62, 0.85, 0.72)

var add: GlyphKey
var loop_it: GlyphKey
var remove: GlyphKey
var rename: GlyphKey
var fit: GlyphKey
## The regions in order, each a place along it.
var list: GlyphRail
## The region the playhead was in at the last refresh: the page follows it as the song plays.
var _was_in := -2


func _ready() -> void:
	tab_name = "REGION"
	tab_glyph = &"region"
	add = _key("RegionAdd", &"region_add", Color(0.55, 0.85, 0.55), "REGION  FROM THE LOOP", _add, _add_text)
	loop_it = _key("RegionLoop", &"loop", INK, "REGION  LOOP IT", _loop,
			func() -> String: return "loop \"%s\"" % _here()[2] if loop_it.lit else "put the playhead in a region")
	remove = _key("RegionRemove", &"remove", Color(0.95, 0.38, 0.34), "REGION  REMOVE", _remove,
			func() -> String: return "remove \"%s\"" % _here()[2] if remove.lit else "put the playhead in a region")
	rename = _key("RegionName", &"rename", INK, "REGION  NAME", _rename,
			func() -> String: return "rename \"%s\"" % _here()[2] if rename.lit else "put the playhead in a region")
	fit = _key("RegionFit", &"region_fit", INK, "REGION  FIT TO THE LOOP", _fit, _fit_text)
	list = _slider("RegionList", &"region_list", INK, func() -> String: return "REGION  GO TO", _list_text)
	list.value_committed.connect(_go_to)
	DAW.timeline_changed.connect(refresh)
	DAW.transport_changed.connect(refresh)
	refresh()


func refresh() -> void:
	if add == null:
		return
	var can := DAW.can(DAWBackend.Capability.MARKERS)
	add.lit = can and _loop_ok()
	var inside := not _here().is_empty()
	loop_it.lit = inside
	remove.lit = can and inside
	rename.lit = can and inside
	fit.lit = can and inside and _loop_ok() and not _fitted()
	var count := DAW.state.regions.size()
	list.available = count > 0
	var at := DAW.state.region_at(DAW.state.position_seconds)
	_was_in = at
	if at >= 0:
		list.snap_to(float(at) / (count - 1) if count > 1 else 0.0)
	notice = "" if can else "this DAW keeps no regions"


func _process(_delta: float) -> void:
	if add != null and DAW.state.region_at(DAW.state.position_seconds) != _was_in:
		refresh()


func _loop_ok() -> bool:
	var s := DAW.state
	return s.loop_end - s.loop_start >= DAWBackend.MIN_ITEM_SECONDS


## The region the playhead is in, [start, end, name], or empty.
func _here() -> Array:
	var i := DAW.state.region_at(DAW.state.position_seconds)
	return DAW.state.regions[i] if i >= 0 else []


## What ADD would call it: the section of the marker at the loop's start (its name without the
## harmony's brackets), or the next "Region N" when there is none or it is only brackets.
func next_name() -> String:
	var s := DAW.state
	var at := DAWBackend.marker_key(s.markers, s.loop_start)
	var section := Harmony.section_of(str(s.markers[at])) if not is_nan(at) else ""
	if section != "":
		return section
	var n := 1
	var taken: Array = s.regions.map(func(r): return str(r[2]))
	while "Region %d" % n in taken:
		n += 1
	return "Region %d" % n


func _add_text() -> String:
	if not add.lit:
		return "set a loop range first"
	return "\"%s\", %s to %s" % [next_name(), _clock(DAW.state.loop_start), _clock(DAW.state.loop_end)]


static func _clock(seconds: float) -> String:
	return DAW.state.bar_beat(seconds)


func _add() -> void:
	if _loop_ok():
		DAW.add_region(DAW.state.loop_start, DAW.state.loop_end, next_name())


func _loop() -> void:
	var r := _here()
	if not r.is_empty():
		DAW.set_loop_range(float(r[0]), float(r[1]))
		DAW.set_looping(true)


func _rename() -> void:
	var r := _here()
	if not r.is_empty() and surface != null:
		surface.ask_region_name(float(r[0]))


## Whether the region the playhead is in already is the loop range.
func _fitted() -> bool:
	var r := _here()
	return not r.is_empty() and absf(float(r[0]) - DAW.state.loop_start) < 0.001 \
			and absf(float(r[1]) - DAW.state.loop_end) < 0.001


func _fit_text() -> String:
	if _here().is_empty():
		return "put the playhead in a region"
	if not _loop_ok():
		return "set a loop range first"
	if _fitted():
		return "\"%s\" is the loop range already" % _here()[2]
	return "\"%s\" to %s - %s" % [_here()[2], _clock(DAW.state.loop_start), _clock(DAW.state.loop_end)]


func _fit() -> void:
	var r := _here()
	if not r.is_empty() and _loop_ok() and not _fitted():
		DAW.edit_region(float(r[0]), DAW.state.loop_start, DAW.state.loop_end, str(r[2]))


## The region a place along the list is, its index.
func list_index(v: float) -> int:
	return clampi(roundi(v * (DAW.state.regions.size() - 1)), 0, maxi(DAW.state.regions.size() - 1, 0))


func _list_text(v: float) -> String:
	var regions: Array = DAW.state.regions
	if regions.is_empty():
		return "no regions yet"
	var r: Array = regions[list_index(v)]
	return "%s, %s - %s, %d of %d" % [r[2], _clock(float(r[0])), _clock(float(r[1])), list_index(v) + 1, regions.size()]


func _go_to(v: float) -> void:
	if not DAW.state.regions.is_empty():
		DAW.seek(float(DAW.state.regions[list_index(v)][0]))


func _remove() -> void:
	var r := _here()
	if not r.is_empty():
		DAW.remove_region(float(r[0]))
