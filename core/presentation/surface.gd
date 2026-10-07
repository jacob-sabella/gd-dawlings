class_name Surface
extends Node3D

## A piece of hardware: the console, the tape deck, a rack, the patchbay.
##
## A surface reads MixState and builds geometry from it. It is rebuilt when the project's
## SHAPE changes -- a track added, an FX inserted -- and never rebuilt for a VALUE change, which
## is the job of the individual controls it spawned. Rebuilding on value change would destroy and
## recreate a fader while a hand is holding it.
##
## A surface does not know its presentation mode, does not know who is looking at it, and does
## not know whether this process is the host. If you find yourself needing any of those three
## inside a surface, the need belongs one layer out. See core/presentation/presentation.gd.

## Stable identity, used as the key in a LayoutProfile. Must survive restarts, so it is not the
## node path -- moving a surface between mounts would otherwise lose its placement.
@export var surface_id: StringName = &""
## What family of thing this is: console, rack, transport, patchbay, timeline. Drives the default
## presentation mode for a given medium.
@export var surface_kind: StringName = &""
## How far to pitch this surface back when it is a panel on a monitor rather than furniture.
##
## Zero for anything whose working face is its own +Z, which is most of them -- the patchbay's
## eighteen-degree lean and the rack's yaw are PLACEMENT, written by the studio, and screen mode
## discards placement by definition. What this compensates for is INTRINSIC tilt: a console's
## panel is laid back sixty degrees inside the console itself, and viewed dead on that is a desk
## seen edge first.
@export var screen_pitch_degrees := 0.0

## Emitted after geometry exists. The mount listens, because a surface framed to fill a screen
## has to be measured, and before the first build there is nothing to measure.
signal rebuilt()

var _dirty := true


func _ready() -> void:
	if surface_id == &"":
		surface_id = StringName(name.to_snake_case())
	var state := DAW.state
	state.track_added.connect(_on_shape_changed)
	state.fx_changed.connect(_on_fx_shape_changed)
	DAW.connection_changed.connect(_on_connection_changed)
	_dirty = true


func _process(_delta: float) -> void:
	# Rebuilds are batched to a frame boundary. Reaper announces a 30-track project as 30
	# separate track messages inside a few milliseconds; rebuilding per message would build and
	# throw away 29 consoles.
	if _dirty:
		_dirty = false
		_rebuild()
		rebuilt.emit()


func mark_dirty() -> void:
	_dirty = true


func _on_shape_changed(_index: int) -> void:
	mark_dirty()


func _on_fx_shape_changed(_track_index: int, _fx_index: int) -> void:
	mark_dirty()


func _on_connection_changed() -> void:
	mark_dirty()


## Build or rebuild geometry from DAW.state. Override this.
func _rebuild() -> void:
	pass


## Clear previously built geometry. Children added by a rebuild must be marked with the
## `built` meta so that hand-authored children of a surface scene survive.
func _clear_built() -> void:
	for child in get_children():
		if child.get_meta("built", false):
			child.queue_free()


func _adopt(node: Node) -> void:
	node.set_meta("built", true)
	add_child(node)


## The part of this surface worth putting in front of someone, which is not all of it. A
## console is a metre of desk carcass under thirty centimetres of controls; framing the whole
## bounding box on a monitor spends two thirds of the screen on a black box.
##
## A fact about the gear rather than about presentation -- which face is the working one does
## not change with who is looking -- so a surface is allowed to answer it.
func framing_root() -> Node3D:
	return self


## The space this surface's working face occupies, in the surface's own local frame.
##
## Measured rather than declared, because every surface in this project sizes itself from the
## project: a 6-track console and a 48-track one are different pieces of furniture, and a
## hard-coded extent would frame one of them wrongly. Returns an empty AABB before the first
## build, which the caller must treat as "not yet known" rather than as "zero-sized".
func content_aabb() -> AABB:
	var out := AABB()
	var first := true
	for node in framing_root().find_children("*", "VisualInstance3D", true, false):
		var vi := node as VisualInstance3D
		var box := vi.get_aabb()
		# Into this surface's frame: a strip is rotated and offset inside the console, and its
		# own AABB says nothing about where the desk ends.
		var xform := global_transform.affine_inverse() * vi.global_transform
		var here := xform * box
		out = here if first else out.merge(here)
		first = false
	return out
