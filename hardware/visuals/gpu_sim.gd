class_name GpuSim
extends Node3D

## A simulation that runs on the graphics card (docs/visuals.md): the base of the fluid tank, the
## physarum sheet and the particle-life pane. It builds the object around the picture (glass, a frame),
## and when compute shaders can run here it keeps the simulation's textures and buffers on the main
## RenderingDevice and shows its picture through a Texture2DRD.
##
## Every RenderingDevice call is made on the render thread (`RenderingServer.call_on_render_thread`) by
## a Kernel, a RefCounted the sim hands its work to. A queued job holds the kernel, not the node, so a
## sim freed while a job is still queued leaves nothing dangling, and the kernel frees what it made.
##
## Each frame it asks VisualBudget whether it may run (`ask`, with how far it is from the eye, INF off
## screen) and steps at most `rate_hz(distance)` times a second. Not granted, nothing is dispatched and
## the last picture stays. With no compute (headless, the OFF tier, the compatibility renderer) only the
## object and a dim stand-in for the picture are built, and no RenderingDevice is touched.

## The room's mood colour: what the picture is coloured around.
var tint := Color(0.35, 0.6, 1.0):
	set(v):
		tint = v
		_tinted()
## For a budget run: each step's GPU work is bracketed with RenderingDevice timestamps named after the sim.
static var measure := false

## Whether the simulation stepped this frame, and how many times it has: for a test.
var stepping := false
var steps := 0
## Whether this one runs on the graphics card (decided when built).
var compute := false

## The picture, for the material: a Texture2DRD on the kernel's display texture once it exists.
var display := Texture2DRD.new()
## The surface the picture is shown on, and its material (the dim stand-in without compute).
var screen := MeshInstance3D.new()
var screen_material := StandardMaterial3D.new()

var _kernel: Kernel = null
var _notifier := VisibleOnScreenNotifier3D.new()
var _since := 0.0
var _shown := false
var _built := false


## Whether a sim granted (`granted`) this far away (`distance`, m, INF off screen), `since_last` s after
## it last stepped, steps now: only granted and on screen, and no oftener than VisualBudget.rate_hz.
static func should_step(granted: bool, distance: float, since_last: float) -> bool:
	if not granted or not is_finite(distance):
		return false
	# A hair of slack, so a 60 Hz screen whose frames come a little early still steps every frame.
	return since_last + 0.002 >= 1.0 / VisualBudget.rate_hz(distance)


func _ready() -> void:
	build()


## Build the object, and the simulation when it can run. Safe to call twice.
func build() -> void:
	if _built:
		return
	_built = true
	_choose_sizes()
	_build_static()
	screen.name = "Picture"
	screen.material_override = screen_material
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(screen)
	_notifier.name = "OnScreen"
	_notifier.aabb = _bounds()
	add_child(_notifier)
	compute = VisualBudget.can_compute()
	if not compute:
		_fallback()
		return
	screen_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen_material.albedo_color = Color(0, 0, 0)
	screen_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_kernel = _make_kernel()
	var shaders := {}
	for key in _shader_paths():
		var file := load(_shader_paths()[key]) as RDShaderFile
		shaders[key] = file.get_spirv() if file != null else null
	var k := _kernel
	var setup := _kernel_setup()
	RenderingServer.call_on_render_thread(func() -> void: k.start(shaders, setup))


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	# Parts made up front but never built in (a sim freed unbuilt) are not children, so go by hand.
	for part in _parts():
		if is_instance_valid(part) and part.get_parent() == null:
			part.free()
	if _kernel != null:
		display.texture_rd_rid = RID()
		var k := _kernel
		RenderingServer.call_on_render_thread(func() -> void: k.free_all())
		_kernel = null


func _process(delta: float) -> void:
	stepping = false
	if not compute or _kernel == null:
		return
	if not _shown:
		if not _kernel.ready:
			return
		_shown = true
		display.texture_rd_rid = _kernel.display
		screen_material.albedo_color = Color(1, 1, 1)
		screen_material.albedo_texture = display
	_since += delta
	var d := _distance()
	if not should_step(VisualBudget.ask(self, d), d, _since):
		return
	var dt := minf(_since, 1.0 / 15.0)
	_since = 0.0
	var params := _frame(dt)
	var k := _kernel
	if measure:
		var label: String = "sim:" + str((get_script() as Script).get_global_name())
		RenderingServer.call_on_render_thread(func() -> void:
			k.rd.capture_timestamp(label + ":a")
			k.step(params)
			k.rd.capture_timestamp(label + ":b"))
	else:
		RenderingServer.call_on_render_thread(func() -> void: k.step(params))
	stepping = true
	steps += 1


## The nodes made with the sim rather than in `build`: freed with it even if it was never built.
func _parts() -> Array[Node]:
	return [screen, _notifier]


## How far the eye is (m), or INF when this is not on screen.
func _distance() -> float:
	if not _notifier.is_on_screen():
		return INF
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam == null:
		return INF
	return cam.global_position.distance_to(global_transform * _bounds().get_center())


## For a subclass: its sizes and counts from VisualBudget.pick, before anything is built.
func _choose_sizes() -> void:
	pass


## For a subclass: the glass, the frame and the base, and `screen.mesh` placed where the picture goes.
func _build_static() -> void:
	pass


## For a subclass: the box (local) the whole object fills, for the on-screen test and the distance.
func _bounds() -> AABB:
	return AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)


## For a subclass: its kernel.
func _make_kernel() -> Kernel:
	return Kernel.new()


## For a subclass: the shaders its kernel needs, name -> res:// path of a `#[compute]` .glsl.
func _shader_paths() -> Dictionary:
	return {}


## For a subclass: what its kernel needs to build (sizes, counts), handed over once.
func _kernel_setup() -> Dictionary:
	return {}


## For a subclass: one step's parameters (the music, read here on the main thread), handed to the kernel.
func _frame(_dt: float) -> Dictionary:
	return {}


## The dim stand-in for the picture where nothing can be computed: the mood colour, barely lit.
func _fallback() -> void:
	screen_material.albedo_color = Color(0.02, 0.02, 0.025)
	screen_material.emission_enabled = true
	screen_material.roughness = 0.3
	_tinted()


func _tinted() -> void:
	if _built and not compute:
		screen_material.emission = tint
		screen_material.emission_energy_multiplier = 0.12


## Glass: nearly clear, a sharp highlight.
static func glass_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.7, 0.8, 0.85, 0.07)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.04
	m.metallic = 0.0
	m.metallic_specular = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func metal_material(colour := Color(0.09, 0.09, 0.1)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.35
	m.metallic = 0.85
	return m


## The render-thread half of a sim: every RenderingDevice call it makes is made here, on the render
## thread. It keeps every RID it makes and frees them in `free_all`.
class Kernel extends RefCounted:
	var rd: RenderingDevice
	## The texture the sim's picture is in, for the Texture2DRD.
	var display := RID()
	## Set (on the render thread) once everything is made.
	var ready := false
	var _sets: Array[RID] = []
	var _pipelines: Array[RID] = []
	var _shaders: Array[RID] = []
	var _resources: Array[RID] = []
	var _samplers: Array[RID] = []
	var _failed := false

	func start(spirv: Dictionary, setup: Dictionary) -> void:
		rd = RenderingServer.get_rendering_device()
		if rd == null:
			return
		build(spirv, setup)
		ready = not _failed and display.is_valid()

	## For a subclass: make the textures, buffers, pipelines and uniform sets, and `display`.
	func build(_spirv: Dictionary, _setup: Dictionary) -> void:
		pass

	## For a subclass: one step, dispatched.
	func step(_p: Dictionary) -> void:
		pass

	func free_all() -> void:
		ready = false
		if rd == null:
			return
		# Sets and pipelines first (each may already be gone with what it was made from), then the rest.
		for r in _sets:
			if rd.uniform_set_is_valid(r):
				rd.free_rid(r)
		for r in _pipelines:
			if rd.compute_pipeline_is_valid(r):
				rd.free_rid(r)
		for list in [_shaders, _resources, _samplers]:
			for r in list:
				if r.is_valid():
					rd.free_rid(r)
		_sets.clear()
		_pipelines.clear()
		_shaders.clear()
		_resources.clear()
		_samplers.clear()

	## A compute pipeline from compiled SPIR-V, or an invalid RID (and the kernel marked failed).
	func pipeline(spirv: RDShaderSPIRV) -> RID:
		if spirv == null or spirv.compile_error_compute != "":
			push_error("GpuSim: shader did not compile: %s" % (spirv.compile_error_compute if spirv else "missing"))
			_failed = true
			return RID()
		var shader := rd.shader_create_from_spirv(spirv)
		if not shader.is_valid():
			_failed = true
			return RID()
		_shaders.append(shader)
		var p := rd.compute_pipeline_create(shader)
		_pipelines.append(p)
		return p

	func shader_of(p: RID) -> RID:
		return _shaders[_pipelines.find(p)]

	## A 2D texture the shaders read and write (and the material can sample), cleared to zero.
	func texture(w: int, h: int, format := RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT) -> RID:
		var tf := RDTextureFormat.new()
		tf.width = w
		tf.height = h
		tf.format = format
		tf.usage_bits = (RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
				| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT)
		var t := rd.texture_create(tf, RDTextureView.new())
		if not t.is_valid():
			_failed = true
			return t
		rd.texture_clear(t, Color(0, 0, 0, 0), 0, 1, 0, 1)
		_resources.append(t)
		return t

	func storage_buffer(data: PackedByteArray) -> RID:
		var b := rd.storage_buffer_create(data.size(), data)
		_resources.append(b)
		return b

	func uniform_buffer(data: PackedByteArray) -> RID:
		var b := rd.uniform_buffer_create(data.size(), data)
		_resources.append(b)
		return b

	## A uniform set (set 0) for `pipeline_rid`'s shader: `bindings` in order, each a texture (an image),
	## or [buffer, true] for a storage buffer, or [buffer, false] for a uniform buffer.
	func uniform_set(pipeline_rid: RID, bindings: Array) -> RID:
		var list: Array[RDUniform] = []
		for i in bindings.size():
			var u := RDUniform.new()
			u.binding = i
			var b: Variant = bindings[i]
			if b is Array:
				u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER if b[1] else RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
				u.add_id(b[0])
			else:
				u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
				u.add_id(b)
			list.append(u)
		var s := rd.uniform_set_create(list, shader_of(pipeline_rid), 0)
		if not s.is_valid():
			_failed = true
		_sets.append(s)
		return s

	## One pass inside an open compute list: the pipeline, the set, the push constants (floats, padded
	## to 16 bytes), `groups` workgroups, then a barrier so the next pass sees what this one wrote.
	func pass_(list: int, pipeline_rid: RID, set_rid: RID, push: PackedFloat32Array, groups: Vector3i) -> void:
		rd.compute_list_bind_compute_pipeline(list, pipeline_rid)
		rd.compute_list_bind_uniform_set(list, set_rid, 0)
		while push.size() % 4 != 0:
			push.append(0.0)
		var bytes := push.to_byte_array()
		rd.compute_list_set_push_constant(list, bytes, bytes.size())
		rd.compute_list_dispatch(list, groups.x, groups.y, groups.z)
		rd.compute_list_add_barrier(list)
