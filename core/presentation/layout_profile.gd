class_name LayoutProfile
extends RefCounted

## One participant's answer to "where is each surface, for me".
##
## PER PARTICIPANT AND NEVER REPLICATED. This is the deliberate asymmetry at the centre of a
## hybrid session: the engineer at the desk has the console as a panel on a 32:9 monitor while
## the two people standing behind them see that same console as a physical object between them,
## and nobody is wrong. Replicating this would force one view on the room and delete the feature.
##
## What IS shared is the ROOM-mode placement of a surface, because that is a fact about the
## physical room rather than a preference -- if the console is agreed to be against the north
## wall, two people in passthrough must not disagree. Those transforms live in session space and
## are replicated through RoomAnchor; this profile only decides whether a given surface is
## ROOM-anchored FOR THIS VIEWER at all.

const SAVE_PATH := "user://layout_profile.cfg"

## Where this profile persists. Overridable so a test can exercise save/load without writing
## over the layout of whoever is running the test -- which, for a profile whose whole content
## is "where this person likes their gear", is a genuinely annoying thing to clobber.
var save_path := SAVE_PATH

## {surface_id: int mode}
var modes: Dictionary = {}
## {"surface_id/mode": Transform3D}. Keyed by MODE as well as surface, because the same console
## is a different object in each: furniture at arm's reach in the room, and a panel framed to
## fill a monitor. One transform per surface would mean every switch either arrived at the
## wrong size or threw away the placement the viewer set in the mode they just left.
##
## ROOM placement is still not a preference -- see the class note -- but it is stored here all
## the same, because a viewer who is not in the physical room has no shared frame to defer to
## and has to keep their own.
var local_transforms: Dictionary = {}
var medium: int = Presentation.Medium.SCREEN
## Which venue this participant stands in. Empty means the default. See core/venues/venue.gd.
var venue: StringName = &""


func mode_for(surface_id: StringName, surface_kind: StringName) -> int:
	if modes.has(surface_id):
		return modes[surface_id]
	return Presentation.default_mode(surface_kind, medium)


func set_mode(surface_id: StringName, mode: int) -> void:
	modes[surface_id] = mode


func transform_for(surface_id: StringName, mode: int, fallback: Transform3D) -> Transform3D:
	return local_transforms.get(_key(surface_id, mode), fallback)


func has_transform(surface_id: StringName, mode: int) -> bool:
	return local_transforms.has(_key(surface_id, mode))


func set_transform(surface_id: StringName, mode: int, xform: Transform3D) -> void:
	local_transforms[_key(surface_id, mode)] = xform


static func _key(surface_id: StringName, mode: int) -> String:
	return "%s/%d" % [surface_id, mode]


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "medium", medium)
	if venue != &"":
		cfg.set_value("profile", "venue", String(venue))
	for id in modes:
		cfg.set_value("modes", String(id), modes[id])
	for id in local_transforms:
		cfg.set_value("transforms", String(id), local_transforms[id])
	cfg.save(save_path)


func load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return
	medium = cfg.get_value("profile", "medium", medium)
	venue = StringName(cfg.get_value("profile", "venue", String(venue)))
	if cfg.has_section("modes"):
		for key in cfg.get_section_keys("modes"):
			modes[StringName(key)] = cfg.get_value("modes", key)
	if cfg.has_section("transforms"):
		for key in cfg.get_section_keys("transforms"):
			local_transforms[StringName(key)] = cfg.get_value("transforms", key)
