class_name RackStubs
extends Node3D

## The cables of the rack's patch that cannot be stood between two plugs, drawn as short stubs out of the
## plug that is there (docs/mods.md 6.2): red where the other end was a port its module has lost (a
## dangling cable), dull where it went to a module nobody here provides. Each stub has a small key at
## its end that takes the cable out of the case; the patch itself is the wall's, and is not changed here.

## A stub's key was pressed: pull the cable `from` -> `to`.
signal pull_asked(from: String, to: String)

const DANGLING := Color(0.95, 0.2, 0.2)
const ABSENT := Color(0.55, 0.55, 0.62)
## How far a stub sticks out of the panel and hangs, metres.
const OUT := 0.07
const DROP := 0.05
## How far a second stub on one plug stands further out, so they never share a face.
const FAN := 0.014

var _made: Array[Node] = []


## Stands the stubs for `patch`'s cables that have only one plug in `jacks` ({"id.port": RackJack}, an
## output's key with a ">" after it, as RackWall keeps them). `key` makes the small key:
## (legend, local position, what it says, what pressing does) -> Node3D. Replaces the last stubs.
func lay(patch: Dictionary, jacks: Dictionary, key: Callable) -> void:
	for n in _made:
		if is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.queue_free()
	_made.clear()
	if not is_inside_tree():
		return
	var fanned := {}
	for c: Array in patch["cables"]:
		var a: RackJack = jacks.get(String(c[0]) + ">")
		var b: RackJack = jacks.get(String(c[1]))
		if (a == null) == (b == null):
			continue
		var plug := a if a != null else b
		var path := String(c[0]) if a != null else String(c[1])
		var fan: int = fanned.get(path, 0)
		fanned[path] = fan + 1
		var from := plug.plug_transform()
		var out := from.basis.z.normalized()
		from.origin += out * FAN * fan
		var to := Transform3D(from.basis, from.origin + out * OUT + Vector3(0, -DROP, 0))
		var red := RackGaps.dangling(patch, c)
		var cable := PatchCable.create(from, to, DANGLING if red else ABSENT, hash(c))
		cable.name = "Stub_%s_%s" % [c[0], c[1]]
		cable.lit = red
		cable.thickness = 2.0
		cable.sag_ratio = 0.3
		add_child(cable)
		_made.append(cable)
		var says := "the cable %s to %s has nowhere to go: take it out" % [c[0], c[1]] if red \
				else "the cable %s to %s waits for a module that is not installed: take it out" % [c[0], c[1]]
		var k: Node3D = key.call("x", to_local(to.origin + out * 0.012 + Vector3(0, -0.02, 0)), says,
				func() -> void: pull_asked.emit(String(c[0]), String(c[1])))
		add_child(k)
		_made.append(k)
