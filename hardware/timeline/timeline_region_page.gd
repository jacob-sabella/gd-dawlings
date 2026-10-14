class_name TimelineRegionPage
extends TimelinePage

## The song's regions -- its named spans, verse, chorus, bridge -- on the deck's REGION page. ADD
## makes one of the loop range, named for the marker at its start if there is one; LOOP loops the
## region the playhead is in; REMOVE takes that region away. Each an edit, one undo step. The
## regions themselves are drawn in the ruler's loop band (TimelineSurface).

const INK := Color(0.62, 0.85, 0.72)

var add: GlyphKey
var loop_it: GlyphKey
var remove: GlyphKey


func _ready() -> void:
	tab_name = "REGION"
	tab_glyph = &"region"
	add = _key("RegionAdd", &"region_add", Color(0.55, 0.85, 0.55), "REGION  FROM THE LOOP", _add, _add_text)
	loop_it = _key("RegionLoop", &"loop", INK, "REGION  LOOP IT", _loop,
			func() -> String: return "loop \"%s\"" % _here()[2] if loop_it.lit else "put the playhead in a region")
	remove = _key("RegionRemove", &"remove", Color(0.95, 0.38, 0.34), "REGION  REMOVE", _remove,
			func() -> String: return "remove \"%s\"" % _here()[2] if remove.lit else "put the playhead in a region")
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
	notice = "" if can else "this DAW keeps no regions"


func _loop_ok() -> bool:
	var s := DAW.state
	return s.loop_end - s.loop_start >= DAWBackend.MIN_ITEM_SECONDS


## The region the playhead is in, [start, end, name], or empty.
func _here() -> Array:
	var i := DAW.state.region_at(DAW.state.position_seconds)
	return DAW.state.regions[i] if i >= 0 else []


## What ADD would call it: the marker at the loop's start, or the next "Region N".
func next_name() -> String:
	var s := DAW.state
	var at := DAWBackend.marker_key(s.markers, s.loop_start)
	if not is_nan(at) and str(s.markers[at]) != "":
		return str(s.markers[at])
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


func _remove() -> void:
	var r := _here()
	if not r.is_empty():
		DAW.remove_region(float(r[0]))
