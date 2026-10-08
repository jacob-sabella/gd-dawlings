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
## Where on the monitor this surface is framed, as the fraction of the view's height its
## top edge sits below the top of the frame -- or negative to centre it.
##
## Centred is right for a surface that IS the screen. It is wrong for a panel shown over the
## studio, because the middle of a seated view is the desk: a timeline framed dead centre lands
## on the strip names and pan knobs, the one row of the console that is only read and never
## leaned over. Hung from the top instead it fills the wall above the meters, which is where a
## studio puts its arrange screen anyway.
@export var screen_top := -1.0
## The most of the view's height a top-hung panel may take.
@export var screen_band := 0.33

## Emitted after geometry exists. The mount listens, because a surface framed to fill a screen
## has to be measured, and before the first build there is nothing to measure.
signal rebuilt()

## Drop the parts that are furniture rather than instrument.
##
## A rack in a room is a 19" box with blanking panels in the empty U, because that is what a
## rack IS and a part-filled bay with holes in it reads as a modelling mistake. A rack held at
## your hands is not furniture and has no empty U to explain -- the blanks are just a metre of
## nothing between you and the controls, and they are the entire reason the FX rack reports
## itself as too big to place at all.
##
## Set by whoever is presenting the surface, not by the surface, because the surface cannot know
## whether it is standing in a room or floating at someone's fingertips.
var compact := false:
	set(value):
		if compact == value:
			return
		compact = value
		mark_dirty()

## Nonzero when this surface is bent around the viewer, and the radius it is bent on.
##
## A flat surface is placed by putting its CENTRE at a distance. That stops working the moment
## the surface is wider than the person: a 90-track desk is 5.5m across, so its far end is 2.9m
## from someone standing at the middle of it -- out of reach, out of focus, and at a glancing
## angle that makes the lettering useless. No distance exists at which that desk works.
##
## A wrapped surface is placed by putting its CENTRE OF CURVATURE at the eye instead, which
## makes every part of it exactly `wrap_radius()` away. The width stops mattering; only the
## angle does, and angle is something a person can turn through.
func wrap_radius() -> float:
	return 0.0


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


## Told by the mount, before it is placed, whether it has a wide frame to fill -- a monitor --
## or a fixed one, like a stand built to its size. Not which mode: a surface does not branch on
## how it is being looked at, only on how much room it has been given.
func set_wide(_wide: bool) -> void:
	pass


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
## Taken out of the tree now, freed whenever the engine gets round to it.
##
## queue_free() alone is deferred to the end of the frame, so the old geometry is still a child
## for the whole of the rebuild that replaces it -- and anything that measures the surface in
## that window measures both builds at once. That is not hypothetical: the focus rig re-places
## a surface the moment it emits `rebuilt`, so a rack trimmed from twelve U to six measured as
## twelve U forever, and the trim looked like it had silently done nothing.
func _clear_built() -> void:
	for child in get_children():
		if child.get_meta("built", false):
			remove_child(child)
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
func _shown_within(node: Node) -> bool:
	var n := node
	while n != null and n != self:
		if n is Node3D and not (n as Node3D).visible:
			return false
		n = n.get_parent()
	return true


func content_aabb() -> AABB:
	var out := AABB()
	var first := true
	for node in framing_root().find_children("*", "VisualInstance3D", true, false):
		var vi := node as VisualInstance3D
		# Chrome hangs off the surface without being part of it. Two kinds qualify. The grab
		# handle, because measuring it would be circular: the handle is placed from this box,
		# so counting it would grow the box, which moves the handle, which grows the box. And
		# the carcass under a desk, because this box is what the camera frames and what the
		# legibility rig reads, and nobody has ever needed to read a plinth. Counting it put
		# the mix position half a metre low, staring into the console's own woodwork.
		if vi.is_in_group(&"presentation_chrome"):
			continue
		# Nor anything switched off. A part hidden until it is needed -- the timeline's lane
		# ladder, below sixteen tracks -- is not on screen to frame, and a hidden unit box
		# measured as a metre cube shrank a thirteen-track timeline to a third of the monitor.
		if not _shown_within(vi):
			continue
		var box := vi.get_aabb()
		# Into this surface's frame: a strip is rotated and offset inside the console, and its
		# own AABB says nothing about where the desk ends.
		var xform := global_transform.affine_inverse() * vi.global_transform
		var here := xform * box
		out = here if first else out.merge(here)
		first = false
	return out
