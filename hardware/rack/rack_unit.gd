class_name RackUnit
extends Node3D

## One FX plugin as one piece of rack-mount gear.
##
## 19 inches wide and 2U tall because that is what the thing it is standing in for would be, and
## because a rack whose units are arbitrary sizes stops reading as a rack. The knobs are the
## plugin's own first few parameters, in Reaper's order, with Reaper's names -- NOT a curated
## mapping. A curated mapping per plugin would look better and would be a lie about what is
## actually loaded, and would silently show the wrong four knobs the moment someone swaps ReaComp
## for a third-party compressor.
##
## Eight knobs is the ceiling on a faceplate this size. A plugin with forty parameters gets its
## first eight and a bank, which is the same compromise every real controller makes.

const RACK_WIDTH := 0.483
const U := 0.0445
const UNITS_TALL := 2
const MAX_KNOBS := 8
const MESH_PATH := "res://assets/hardware/rack_panel.glb"

var track_index: int = 0
var fx_index: int = 0

var _knobs: Array[Knob] = []
var _bypass: PanelButton
var _name_label: Label3D


static func create(track_idx: int, fx_idx: int) -> RackUnit:
	var u := RackUnit.new()
	u.track_index = track_idx
	u.fx_index = fx_idx
	u.name = "Rack_t%d_fx%d" % [track_idx, fx_idx]
	return u


func height() -> float:
	return U * UNITS_TALL


## The pre-Blender faceplate: a slab, two raised ear plates and four pegs. Kept so a missing
## asset is a plainer rack rather than knobs floating in mid air.
func _stand_in(h: float) -> Node3D:
	var holder := Node3D.new()

	var face := MeshInstance3D.new()
	var face_mesh := BoxMesh.new()
	face_mesh.size = Vector3(RACK_WIDTH, h - 0.002, 0.012)
	face.mesh = face_mesh
	face.position = Vector3(0, 0, -0.006)
	face.material_override = Materials.chassis()
	holder.add_child(face)

	for side in [-1.0, 1.0]:
		var ear := MeshInstance3D.new()
		var ear_mesh := BoxMesh.new()
		ear_mesh.size = Vector3(0.016, h - 0.004, 0.004)
		ear.mesh = ear_mesh
		ear.position = Vector3(side * (RACK_WIDTH * 0.5 - 0.009), 0, 0.002)
		ear.material_override = Materials.brushed_metal()
		holder.add_child(ear)
		for sy in [-1.0, 1.0]:
			var screw := MeshInstance3D.new()
			var screw_mesh := CylinderMesh.new()
			screw_mesh.top_radius = 0.0022
			screw_mesh.bottom_radius = 0.0022
			screw_mesh.height = 0.002
			screw_mesh.radial_segments = 8
			screw.mesh = screw_mesh
			screw.rotation_degrees = Vector3(90, 0, 0)
			screw.position = Vector3(side * (RACK_WIDTH * 0.5 - 0.009), sy * U * 0.5, 0.005)
			screw.material_override = Materials.cap_plastic(Color(0.3, 0.31, 0.33))
			holder.add_child(screw)
	return holder


func _ready() -> void:
	var h := height()

	# The faceplate, ears and mounting hardware as one authored part. The ears are not bolted
	# on: the ends of a rack panel ARE its ears, with oblong holes through them, which is what
	# the four raised plates this used to draw were getting wrong.
	var panel := Part.build(
		MESH_PATH,
		Materials.chassis(),
		{"screw": Materials.brushed_metal()},
	)
	if panel != null:
		# Modelled standing, so no correcting rotation -- only the shift that puts its front
		# face on z = 0, where every knob and label on this unit was laid out against.
		panel.position = Vector3(0, 0, -0.006)
		add_child(panel)
	else:
		add_child(_stand_in(h))

	_name_label = Label3D.new()
	_name_label.font_size = 52
	_name_label.pixel_size = 0.00019
	_name_label.position = Vector3(-RACK_WIDTH * 0.5 + 0.03, h * 0.5 - 0.016, 0.002)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_name_label.modulate = Color(0.85, 0.86, 0.88)
	Lettering.range_to_legibility(_name_label)
	add_child(_name_label)

	_bypass = PanelButton.new()
	_bypass.led_colour = Color(0.4, 0.95, 0.5)
	_bypass.position = Vector3(RACK_WIDTH * 0.5 - 0.035, h * 0.5 - 0.016, 0.004)
	_bypass.pressed.connect(func():
		var f := DAW.state.fx(track_index, fx_index)
		DAW.set_fx_enabled(track_index, fx_index, not f.enabled))
	add_child(_bypass)

	DAW.state.fx_changed.connect(_on_fx_changed)
	refresh()


func refresh() -> void:
	var f := DAW.state.fx(track_index, fx_index, false)
	if f == null:
		return
	var track := DAW.state.track(track_index)
	_name_label.text = "%s   %s" % [track.display_name().to_upper(), f.name]
	_bypass.lit = f.enabled

	var params: Array = f.params.keys()
	params.sort()
	var count: int = mini(params.size(), MAX_KNOBS)

	# Knobs are created once and then only re-pointed. Rebuilding them on every FX update would
	# drop a knob that is being turned, and FX updates arrive while you turn it.
	while _knobs.size() < count:
		var k := Knob.new()
		var slot := _knobs.size()
		k.position = Vector3(-RACK_WIDTH * 0.5 + 0.055 + slot * 0.052, -height() * 0.25, 0.005)
		var param_index: int = params[slot]
		k.turned.connect(func(v: float): DAW.set_fx_param(track_index, fx_index, param_index, v))
		add_child(k)
		_knobs.append(k)

		var caption := Label3D.new()
		caption.font_size = 36
		caption.pixel_size = 0.00018
		caption.position = k.position + Vector3(0, -0.016, 0)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.modulate = Color(0.66, 0.68, 0.7)
		caption.name = "Caption%d" % slot
		Lettering.range_to_legibility(caption)
		add_child(caption)

	for i in _knobs.size():
		if i < count:
			_knobs[i].visible = true
			_knobs[i].apply_remote(f.params[params[i]])
			var caption := get_node_or_null("Caption%d" % i)
			if caption:
				caption.text = str(f.param_names.get(params[i], "P%d" % params[i])).to_upper()
		else:
			_knobs[i].visible = false


func _on_fx_changed(t: int, fx: int) -> void:
	if t == track_index and fx == fx_index:
		refresh()
