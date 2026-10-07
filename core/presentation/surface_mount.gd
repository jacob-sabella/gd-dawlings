class_name SurfaceMount
extends Node3D

## Puts each surface where this particular viewer wants it, and nowhere else.
##
## The mount owns the three anchors a surface can hang from and does the reparenting. It is the
## only place in the project that reads a LayoutProfile, which is what lets every surface stay
## ignorant of presentation: a surface is a node, and a node's parent is not its business.
##
## Reparenting at runtime is the supported operation, not a trick. Someone at the desk pulls the
## console off their monitor and stands it in the room mid-session; the node moves from
## `screen_stage` to `room_anchor` and keeps every control, every grab, and its state cache.

@export var screen_stage: Node3D
@export var room_anchor: Node3D
@export var studio_set: Node3D

## {surface_id: Surface}
var _mounted: Dictionary = {}


func register(surface: Surface) -> void:
	_mounted[surface.surface_id] = surface
	apply(surface.surface_id)


## Re-anchor one surface according to the local profile.
func apply(surface_id: StringName) -> void:
	if not _mounted.has(surface_id):
		return
	var surface: Surface = _mounted[surface_id]
	var mode := Session.layout.mode_for(surface_id, surface.surface_kind)
	var target := _anchor_for(mode)
	if target == null:
		push_warning("SurfaceMount: no anchor for mode %s; leaving %s where it is." % [Presentation.MODE_NAMES.get(mode, mode), surface_id])
		return
	if surface.get_parent() != target:
		var xform := surface.transform
		surface.get_parent().remove_child(surface)
		target.add_child(surface)
		# Placement is per-mode: a console sized for arm's reach in the room is not the same
		# object on a monitor, so the transform comes from the profile rather than carrying over.
		surface.transform = Session.layout.transform_for(surface_id, xform)


func apply_all() -> void:
	for id in _mounted:
		apply(id)


## Move one surface to a different mode and remember it.
func set_mode(surface_id: StringName, mode: int) -> void:
	Session.layout.set_mode(surface_id, mode)
	apply(surface_id)
	Session.layout.save()


func _anchor_for(mode: int) -> Node3D:
	match mode:
		Presentation.Mode.SCREEN: return screen_stage
		Presentation.Mode.ROOM: return room_anchor
		Presentation.Mode.STUDIO: return studio_set
	return null
