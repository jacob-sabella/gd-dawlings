class_name Wardrobe
extends Node3D

## A little board beside a mirror for dressing your ghost: body, eyes, hat and gloves, each a row
## with a button either side that steps through the choices. You see the result straight away in
## the glass, which is why it lives here and not in a menu.
##
## It only holds a look and says when it changed (`look_changed`); whoever builds the studio
## tells the session, which keeps the look and passes it on to everyone else. The buttons are
## personal: what I press on my wardrobe is nobody else's business, so they are never claimed
## or pointed at across the session (ControlAffordance.personal).

signal look_changed(look: Dictionary)

const WIDTH := 0.42
const ROW := 0.1
const BOARD_DEPTH := 0.018

var look: Dictionary = GhostLook.default_look():
	set(v):
		look = GhostLook.clean(v)
		_refresh()
## The board's face, so a venue can make it its own.
var board_material: Material = null
var ink := Color(0.92, 0.9, 0.84)
var accent := Color(0.95, 0.75, 0.4)
## What the small row names fade toward: the board's own tone, so they sit back from the values.
var board_ink_fade := Color(0.4, 0.4, 0.42)

var _values: Dictionary = {}
var _swatch: StandardMaterial3D
var _buttons: Array[Choice] = []


func _ready() -> void:
	var rows := GhostLook.KINDS.size()
	var height := ROW * rows + 0.09
	var board := MeshInstance3D.new()
	board.name = "Board"
	var box := BoxMesh.new()
	box.size = Vector3(WIDTH, height, BOARD_DEPTH)
	board.mesh = box
	if board_material == null:
		var plain := StandardMaterial3D.new()
		plain.albedo_color = Color(0.11, 0.11, 0.13)
		plain.roughness = 0.55
		board_material = plain
	board.material_override = board_material
	board.position = Vector3(0, -height * 0.5 + 0.04, -BOARD_DEPTH * 0.5)
	add_child(board)

	var title := _label("WARDROBE", 30, accent)
	title.position = Vector3(0, 0.014, 0.002)

	for i in rows:
		var kind: String = GhostLook.KINDS[i]
		var y := -0.045 - ROW * i
		var name_tag := _label(kind.to_upper(), 18, ink.lerp(board_ink_fade, 0.45))
		name_tag.position = Vector3(0, y + 0.026, 0.002)
		var value := _label("", 30, ink)
		value.position = Vector3(0, y - 0.01, 0.002)
		_values[kind] = value
		for step in [-1, 1]:
			var button := Choice.new()
			button.kind = kind
			button.step = step
			button.colour = accent
			button.name = "%s%s" % [kind.capitalize(), "Next" if step > 0 else "Back"]
			button.position = Vector3(step * (WIDTH * 0.5 - 0.035), y, 0.0)
			button.pressed.connect(_on_pressed.bind(kind, step))
			add_child(button)
			_buttons.append(button)
		if kind == "body":
			var blob := SphereMesh.new()
			blob.radius = 0.014
			blob.height = 0.028
			_swatch = StandardMaterial3D.new()
			var dot := MeshInstance3D.new()
			dot.mesh = blob
			dot.material_override = _swatch
			dot.position = Vector3(-0.115, y - 0.01, 0.01)
			add_child(dot)
	_refresh()


func _label(text: String, size: int, colour: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.001
	label.modulate = colour
	label.outline_size = 0
	label.double_sided = false
	label.shaded = false
	add_child(label)
	return label


func _on_pressed(kind: String, step: int) -> void:
	look = GhostLook.stepped(look, kind, step)
	look_changed.emit(look)


func _refresh() -> void:
	for kind in _values:
		(_values[kind] as Label3D).text = GhostLook.label(look, kind)
	if _swatch != null:
		_swatch.albedo_color = GhostLook.body_colour(look)


## Press a row's button as a hand would, for the suite and the shot harness.
func press(kind: String, step: int) -> void:
	for button in _buttons:
		if button.kind == kind and button.step == step:
			var hand := Node.new()
			button.grab_begin(hand, button.global_position)
			button.grab_end(hand)
			hand.free()
			return


## A chunky arrow on a round cap that sinks when it is pressed and pops back with a bounce.
class Choice extends ControlAffordance:
	signal pressed()

	const RADIUS := 0.027

	var kind := ""
	var step := 1
	var colour := Color(0.95, 0.75, 0.4)

	var _cap := Node3D.new()
	var _depth := 0.0
	var _speed := 0.0

	func _ready() -> void:
		collision_layer = 2
		collision_mask = 0
		add_child(_cap)
		var disc := CylinderMesh.new()
		disc.top_radius = RADIUS
		disc.bottom_radius = RADIUS * 1.08
		disc.height = 0.012
		disc.radial_segments = 24
		disc.rings = 1
		var body := MeshInstance3D.new()
		body.mesh = disc
		body.rotation.x = PI * 0.5
		body.position.z = 0.006
		var plastic := StandardMaterial3D.new()
		plastic.albedo_color = Color(0.2, 0.2, 0.23)
		plastic.roughness = 0.4
		body.material_override = plastic
		_cap.add_child(body)
		var prism := PrismMesh.new()
		prism.size = Vector3(0.026, 0.024, 0.004)
		var arrow := MeshInstance3D.new()
		arrow.mesh = prism
		# Apex pointing the way it steps.
		arrow.rotation.z = -step * PI * 0.5
		arrow.position.z = 0.0135
		var lit := StandardMaterial3D.new()
		lit.albedo_color = colour
		lit.emission_enabled = true
		lit.emission = colour * 0.35
		arrow.material_override = lit
		_cap.add_child(arrow)
		var shape := CollisionShape3D.new()
		var hit := BoxShape3D.new()
		hit.size = Vector3(RADIUS * 2.6, RADIUS * 2.6, 0.03)
		shape.shape = hit
		shape.position.z = 0.01
		add_child(shape)

	func personal() -> bool:
		return true

	func dwell_activates() -> bool:
		return true

	func _default_title() -> String:
		return "%s  %s" % [kind.to_upper(), "NEXT" if step > 0 else "BACK"]

	func _default_readout() -> String:
		var parent := get_parent() as Wardrobe
		return GhostLook.label(parent.look, kind) if parent != null else ""

	func hint() -> String:
		return "click to change what your ghost wears"

	func _on_grab_begin(_at: Vector3) -> void:
		_speed -= 0.35
		pressed.emit()

	func _foley_contact() -> AudioStream:
		return Foley.button_click()

	func _process(delta: float) -> void:
		var dt := minf(delta, 0.05)
		_speed += (-_depth * 900.0 - _speed * 24.0) * dt
		_depth += _speed * dt
		_cap.position.z = clampf(_depth, -0.008, 0.004)
