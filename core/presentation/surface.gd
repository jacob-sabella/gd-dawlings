class_name Surface
extends Node3D

## A piece of hardware: the console, the tape deck, a rack, the patchbay.
##
## A surface reads ReaperState and builds geometry from it. It is rebuilt when the project's
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

var _dirty := true


func _ready() -> void:
	if surface_id == &"":
		surface_id = StringName(name.to_snake_case())
	var state := Reaper.state
	state.track_added.connect(_on_shape_changed)
	state.fx_changed.connect(_on_fx_shape_changed)
	Reaper.connection_changed.connect(_on_connection_changed)
	_dirty = true


func _process(_delta: float) -> void:
	# Rebuilds are batched to a frame boundary. Reaper announces a 30-track project as 30
	# separate track messages inside a few milliseconds; rebuilding per message would build and
	# throw away 29 consoles.
	if _dirty:
		_dirty = false
		_rebuild()


func mark_dirty() -> void:
	_dirty = true


func _on_shape_changed(_index: int) -> void:
	mark_dirty()


func _on_fx_shape_changed(_track_index: int, _fx_index: int) -> void:
	mark_dirty()


func _on_connection_changed() -> void:
	mark_dirty()


## Build or rebuild geometry from Reaper.state. Override this.
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
