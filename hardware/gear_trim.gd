class_name GearTrim
extends RefCounted

## Edging along a piece of furniture's top and upright edges, in `Materials.trim()`: steel in the
## studio, a lit line wherever the venue's `GearStyle` makes the trim glow. The one place the
## gear's outline is drawn, so a venue that wants neon edges, brass corners or a road case's
## aluminium extrusion gets it from the same eight strips.

## How thick a strip is, and how far it stands proud of the faces it runs between, so it is never
## drawn in the same plane as them.
const THICK := 0.013


## Eight strips round `box` (a MeshInstance3D with a BoxMesh): its four top edges and four
## uprights. Not the bottom four, which sit on the floor or a plinth where nobody sees them.
## Again on a box already trimmed, after it has been resized, replaces the old strips.
static func edges(box: MeshInstance3D) -> void:
	for old in box.get_children():
		if old.has_meta(&"gear_trim"):
			box.remove_child(old)
			old.queue_free()
	var size: Vector3 = (box.mesh as BoxMesh).size
	var h := size * 0.5
	# Three thicknesses, not one: strips of one size meeting at a corner put their outer faces in
	# the same planes, and two faces in one plane are drawn in whichever order the depth buffer's
	# rounding picks that frame. The uprights also stop short of the bottom face for the same
	# reason, and stop short of the top so their ends sit inside the top strips rather than flush
	# with the box's own top face.
	var along_x := THICK
	var along_z := THICK * 0.94
	var upright := THICK * 0.88
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_strip(box, Vector3(upright, size.y - 0.008, upright), Vector3(sx * h.x, 0, sz * h.z))
	for sz in [-1.0, 1.0]:
		_strip(box, Vector3(size.x + along_x, along_x, along_x), Vector3(0, h.y, sz * h.z))
	for sx in [-1.0, 1.0]:
		_strip(box, Vector3(along_z, along_z, size.z + along_z * 0.9), Vector3(sx * h.x, h.y, 0))


static func _strip(box: MeshInstance3D, size: Vector3, at: Vector3) -> void:
	var strip := MeshInstance3D.new()
	strip.name = "Trim"
	strip.set_meta(&"gear_trim", true)
	var mesh := BoxMesh.new()
	mesh.size = size
	strip.mesh = mesh
	strip.position = at
	strip.material_override = Materials.trim()
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	box.add_child(strip)
