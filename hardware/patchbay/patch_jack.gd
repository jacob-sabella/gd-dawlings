class_name PatchJack
extends ControlAffordance

## One port on the patch wall (PatchWallSurface): a row of a node's box that can be taken hold of.
## Press on it and a cable comes out of its jack and follows the hand; let go over a port of the
## other kind to patch the two, or over one it is already patched to, to cut that cable. The wall
## does the patching; a jack only says where the drag went (the same three signals as PatchPoint).
## The whole row is the target, not the jack's dot: a dot is an aiming test, not a routing one.

signal drag_began(from: ControlAffordance, at: Vector3)
signal drag_moved(from: ControlAffordance, at: Vector3, over: ControlAffordance)
signal drag_finished(from: ControlAffordance, over: ControlAffordance)

## How the row is lit: plain, as somewhere a carried cable could go, as the place it goes if let go
## now, or as a patch it would cut.
enum Light { PLAIN, CANDIDATE, TARGET, CUT }

## "node:port", as `pw-link` names it.
var port := ""
var is_output := true
var tint := Color(0.6, 0.6, 0.65)
## The row, centred on this node.
var size := Vector2(1.7, 0.12)
## How many patches this port is in.
var patches := 0

var _glow := MeshInstance3D.new()
var _material := StandardMaterial3D.new()
var _light: int = Light.PLAIN


static func create(port_name: String, output: bool, colour: Color, row: Vector2) -> PatchJack:
	var j := PatchJack.new()
	j.port = port_name
	j.is_output = output
	j.tint = colour
	j.size = row
	j.name = "Jack_%s_%s" % ["out" if output else "in", port_name.validate_node_name()]
	return j


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	var quad := QuadMesh.new()
	quad.size = size
	_glow.mesh = quad
	_glow.position.z = -0.002
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow.material_override = _material
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glow)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, size.y, 0.04)
	shape.shape = box
	shape.position.z = 0.02
	add_child(shape)
	hover_changed.connect(func(_on: bool): _paint())
	_paint()


func light() -> int:
	return _light


func set_light(how: int) -> void:
	if how != _light:
		_light = how
		_paint()


func _paint() -> void:
	match _light:
		Light.CANDIDATE:
			_material.albedo_color = Color(tint, 0.22)
		Light.TARGET:
			_material.albedo_color = Color(tint, 0.6)
		Light.CUT:
			_material.albedo_color = Color(0.95, 0.3, 0.25, 0.55)
		_:
			_material.albedo_color = Color(1, 1, 1, 0.10) if is_hovered() else Color(1, 1, 1, 0.0)


func _on_grab_begin(at: Vector3) -> void:
	drag_began.emit(self, at)


func _on_grab_move(at: Vector3) -> void:
	drag_moved.emit(self, at, _under_hand())


func _on_grab_end() -> void:
	drag_finished.emit(self, _under_hand())


func _under_hand() -> ControlAffordance:
	if held_by is Interactor:
		return (held_by as Interactor).hovered
	return null


func _default_title() -> String:
	return PipeGraph.label_of(port).to_upper()


func _default_readout() -> String:
	if patches == 0:
		return "not patched"
	return "patched to %d" % patches


func hint() -> String:
	return "drag to a %s to patch it; onto one it is patched to, to cut that cable" % ("input" if is_output else "output")
