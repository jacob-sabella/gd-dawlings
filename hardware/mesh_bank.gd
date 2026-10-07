class_name MeshBank
extends MultiMeshInstance3D

## Many identical little boxes drawn as one object.
##
## A console is mostly repetition: ninety strips of the same three buttons, the same lamp in each
## one, the same plate behind them. Built the obvious way that is a `MeshInstance3D` apiece, and
## `tools/budget.sh` measured what the obvious way costs -- 4,911 draw calls for a 90-track
## session seen whole, of which 540 were button bodies and lamps alone.
##
## A MultiMesh draws any number of them in ONE call. The price is that an instance cannot carry
## its own material: everything in a bank shares one, and the only thing that can vary per
## instance is its transform and its colour. That is exactly the shape of a lamp, and it is why
## this is useful here and would not be useful for, say, the knobs.
##
## HOW IT IS USED
##
## Two phases, because a MultiMesh has to be told how many instances it holds before it can hold
## any. Callers `claim()` during construction and the owner calls `commit()` once everything is
## built; after that, `set_colour()` writes straight through. Claiming after a commit is a
## programming error and says so rather than silently drawing nothing.
##
## Nothing is REQUIRED to use a bank. A button with no bank builds its own meshes exactly as it
## used to -- which keeps the one-off buttons on the transport and the bank selector simple, and
## means a surface that has not been taught about banks still works.

## Lamps are unshaded: a little light adds to the room rather than taking from it, and unshaded
## renders identically under forward_plus and mobile, which every material here must.
static var _lamp_shader: Shader

var _transforms: Array[Transform3D] = []
## RETAINED after commit, not dropped, and that is the whole reason this is readable at all.
##
## A MultiMesh's instance buffer lives in the rendering server, and the headless server is a
## stub: set_instance_color writes quite happily and get_instance_color hands back black
## forever. So a bank that kept nothing would be a widget the test suite cannot see -- which is
## exactly how the first MultiMesh in this project (the VU meter) ended up needing its decision
## lifted into a static function. 16 bytes an instance, 4KB for a 90-track desk's worth of
## lamps, in exchange for being able to assert that a mute light is on.
var _colours: PackedColorArray = PackedColorArray()
var _committed := false


static func lamps(size: Vector3) -> MeshBank:
	var bank := _make(size)
	bank.material_override = _lamp_material()
	# A lamp is drawn above 1.0 to bloom, and a bloomed object that also casts a shadow reads as
	# a solid lump with a bright face. Lamps light, they do not occlude.
	bank.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return bank


## A bank of ordinary lit geometry -- button bodies, plates, fader slots. Everything in one of
## these shares a finish; only the transform and a tint vary.
##
## The material is DUPLICATED and has vertex-colour-as-albedo switched on, which is not an
## optimisation -- it is the only reason per-instance colour does anything at all. A
## StandardMaterial3D ignores COLOR unless told not to, so the first version of this silently
## drew every instance in the shared material's albedo and nobody noticed, because the only
## caller at the time claimed everything white. Duplicated because Materials hands out cached
## singletons: flipping the flag on the original would change every non-banked user of that
## finish somewhere else in the studio.
##
## Claim with `Color.WHITE` to get the material's own albedo unchanged; the tint multiplies.
static func parts(size: Vector3, material: Material) -> MeshBank:
	var bank := _make(size)
	var tintable := material.duplicate() as Material
	if tintable is StandardMaterial3D:
		(tintable as StandardMaterial3D).vertex_color_use_as_albedo = true
	bank.material_override = tintable
	return bank


## A bank of an AUTHORED part -- jacks, knob bodies, fader caps -- rather than a plain box.
##
## Returns null when the asset will not resolve, exactly as `Part.build` does, so a caller can
## fall back to loose parts rather than drawing nothing.
##
## A MultiMeshInstance3D has NO per-surface override: it is a GeometryInstance3D, not a
## MeshInstance3D, so the only material lever it has is `material_override`, which paints every
## surface the same. An authored part is two surfaces with two different finishes -- a jack is a
## brushed bezel around a dark bore -- so a single override would flatten exactly the detail the
## part was modelled for. The materials are therefore BAKED into a duplicate of the mesh. The
## duplicate matters: `Part.mesh()` caches one Mesh per asset and hands it to everyone, and
## painting the shared copy would repaint every loose jack in the studio.
##
## Two surfaces stay two draw calls, not two per jack. 180 jacks go from 360 to 2.
static func of(path: String, fallback: Material, named: Dictionary = {}) -> MeshBank:
	var source := Part.mesh(path)
	if source == null:
		return null
	var baked := source.duplicate() as ArrayMesh
	if baked == null:
		return null
	for i in baked.get_surface_count():
		baked.surface_set_material(i, Part.paint_for(source, i, fallback, named))
	var bank := MeshBank.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = baked
	bank.multimesh = mm
	return bank


static func _make(size: Vector3) -> MeshBank:
	var bank := MeshBank.new()
	var box := BoxMesh.new()
	box.size = size
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = box
	bank.multimesh = mm
	return bank


static func _lamp_material() -> ShaderMaterial:
	if _lamp_shader == null:
		_lamp_shader = Shader.new()
		_lamp_shader.code = """
shader_type spatial;
render_mode unshaded, shadows_disabled;

void fragment() {
	// COLOR is the MultiMesh per-instance colour. Values above 1 are deliberate: that is what
	// the glow pass picks up, and it is how a lit lamp reads as emitting rather than as merely
	// being a brighter shade of plastic. See Materials.lamp_colour.
	ALBEDO = COLOR.rgb;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _lamp_shader
	return m


## Reserve a slot. `at` is in THIS NODE'S space, so a caller sitting somewhere else in the tree
## has to convert -- `bank.to_local()` on a global transform, which is what `place()` is for.
func claim(at: Transform3D, colour: Color) -> int:
	assert(not _committed, "MeshBank: claimed after commit; the buffer is already sized.")
	_transforms.append(at)
	_colours.append(colour)
	return _transforms.size() - 1


## A claim for a node already in the tree, converted out of world space for you.
func place(node: Node3D, colour: Color) -> int:
	return claim(global_transform.affine_inverse() * node.global_transform, colour)


## Size the buffer and upload everything claimed. Idempotent, and a no-op on an empty bank --
## a surface should be able to call this unconditionally.
func commit() -> void:
	if _committed:
		return
	_committed = true
	multimesh.instance_count = _transforms.size()
	for i in _transforms.size():
		multimesh.set_instance_transform(i, _transforms[i])
		multimesh.set_instance_color(i, _colours[i])


func set_colour(index: int, colour: Color) -> void:
	if index < 0 or index >= _colours.size():
		return
	_colours[index] = colour
	if _committed:
		multimesh.set_instance_color(index, colour)


## Move a slot after the fact. A fader cap slides and a knob turns, so not everything in a bank
## is static -- but a bank is still sized once, so this never changes the instance COUNT.
##
## Not `set_transform`: that is Node3D's own, and quietly overriding it would mean moving the
## BANK whenever something meant to move one slot in it.
func move_slot(index: int, at: Transform3D) -> void:
	if index < 0 or index >= _transforms.size():
		return
	_transforms[index] = at
	if _committed:
		multimesh.set_instance_transform(index, at)


## What this slot was last told to be. Read from the retained copy rather than from the
## MultiMesh -- see `_colours`.
func colour_of(index: int) -> Color:
	return _colours[index] if index >= 0 and index < _colours.size() else Color.BLACK


## Where this slot sits, in the bank's own space.
func transform_of(index: int) -> Transform3D:
	return _transforms[index] if index >= 0 and index < _transforms.size() else Transform3D.IDENTITY


func count() -> int:
	return _transforms.size()
