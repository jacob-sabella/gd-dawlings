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

## {surface_id: int mode}
var modes: Dictionary = {}
## {surface_id: Transform3D} -- offsets for SCREEN and STUDIO placement only. ROOM placement is
## not stored here; see the class note.
var local_transforms: Dictionary = {}
var medium: int = Presentation.Medium.SCREEN


func mode_for(surface_id: StringName, surface_kind: StringName) -> int:
	if modes.has(surface_id):
		return modes[surface_id]
	return Presentation.default_mode(surface_kind, medium)


func set_mode(surface_id: StringName, mode: int) -> void:
	modes[surface_id] = mode


func transform_for(surface_id: StringName, fallback: Transform3D) -> Transform3D:
	return local_transforms.get(surface_id, fallback)


func set_transform(surface_id: StringName, xform: Transform3D) -> void:
	local_transforms[surface_id] = xform


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "medium", medium)
	for id in modes:
		cfg.set_value("modes", String(id), modes[id])
	for id in local_transforms:
		cfg.set_value("transforms", String(id), local_transforms[id])
	cfg.save(SAVE_PATH)


func load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	medium = cfg.get_value("profile", "medium", medium)
	if cfg.has_section("modes"):
		for key in cfg.get_section_keys("modes"):
			modes[StringName(key)] = cfg.get_value("modes", key)
	if cfg.has_section("transforms"):
		for key in cfg.get_section_keys("transforms"):
			local_transforms[StringName(key)] = cfg.get_value("transforms", key)
