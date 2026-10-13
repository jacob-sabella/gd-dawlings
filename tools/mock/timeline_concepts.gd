extends SceneTree
## Throwaway mockups for the timeline redesign: three spatial ideas, one demo song's shape.
##   godot --path . -s tools/mock/timeline_concepts.gd -- a|b|c out.png [cam_variant]
## Not shipped; it exists so a choice can be made by looking.

const TRACKS := ["Drums","Kick","Snare","Hat","OH L/R","Bass DI","Rhodes","Gtr Amp","Vox","Lead Vox","Vox Dbl","Strings","Verb Rtn"]
const COLS := [Color("ff7a5c"),Color("ffa24a"),Color("ffc14a"),Color("c9d65a"),Color("5ccf9a"),Color("4fb8e0"),Color("7a8cf0"),Color("b080f0"),Color("e870c0"),Color("f06a8a"),Color("ff9a9a"),Color("9ac0d0"),Color("a0a0b8")]
# [first bar, last bar] per track, from the demo arrangement
const SPANS := [[], [[9,89]], [[9,89]], [[9,73]], [[25,57],[73,89]], [[9,89]], [[1,25],[41,57],[73,89]], [[25,89]], [], [[25,73]], [[25,41],[57,73]], [[1,9],[25,41],[73,89]], []]
const BARS := 96.0
var mode := "a"
var out := "/tmp/mock.png"
var variant := "0"
var vp: SubViewport

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	mode = a[0]; out = a[1]
	if a.size() > 2: variant = a[2]
	vp = SubViewport.new(); vp.size = Vector2i(1280, 720); vp.msaa_3d = Viewport.MSAA_4X; vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.03, 0.045)
	e.ambient_light_color = Color(0.25, 0.28, 0.4); e.ambient_light_energy = 0.5
	e.glow_enabled = true; e.glow_intensity = 0.6; e.glow_bloom = 0.05; e.glow_hdr_threshold = 1.4
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true; e.fog_light_color = Color(0.05,0.06,0.1); e.fog_density = 0.02
	env.environment = e; vp.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, 20, 0); sun.light_energy = 0.7
	sun.shadow_enabled = true; vp.add_child(sun)
	var floor_m := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(60, 60); floor_m.mesh = pm
	floor_m.material_override = _mat(Color(0.07,0.06,0.07), 0.0, 0.5, 0.35)
	floor_m.position.y = -0.01; vp.add_child(floor_m)
	var cam := Camera3D.new(); cam.fov = 70; vp.add_child(cam)
	match mode:
		"a": _highway(cam)
		"b": _tiers(cam)
		"c": _strata(cam)
	for i in 20: await process_frame
	vp.get_texture().get_image().save_png(out)
	print("SAVED ", out)
	quit()

func _mat(c: Color, emit := 0.0, rough := 0.4, metal := 0.0, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, alpha); m.roughness = rough; m.metallic = metal
	if emit > 0.0: m.emission_enabled = true; m.emission = c; m.emission_energy_multiplier = emit
	if alpha < 1.0: m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

func _box(parent: Node, pos: Vector3, size: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); var b := BoxMesh.new(); b.size = size; mi.mesh = b
	mi.material_override = m; mi.position = pos; parent.add_child(mi); return mi

func _label(parent: Node, txt: String, pos: Vector3, px: float, col := Color.WHITE, rot := Vector3.ZERO) -> void:
	var l := Label3D.new(); l.text = txt; l.pixel_size = px; l.position = pos; l.modulate = col
	l.outline_size = 8; l.rotation = rot; l.font_size = 64; parent.add_child(l)

func _light(parent: Node, pos: Vector3, col: Color, energy: float, rng: float) -> void:
	var o := OmniLight3D.new(); o.position = pos; o.light_color = col; o.light_energy = energy; o.omni_range = rng; parent.add_child(o)

# ---- A: HIGHWAY. Tracks are lanes side by side; time runs AWAY from you; the playhead is a lit gate. ----
func _highway(cam: Camera3D) -> void:
	var laneW := 0.30; var n := TRACKS.size(); var barLen := 0.42   # metres per bar
	var x0 := -laneW * (n - 1) * 0.5
	var head_bar := 17.0
	_box(vp, Vector3(0, -0.02, -barLen * 24), Vector3(laneW * n + 0.2, 0.04, barLen * 50), _mat(Color(0.05,0.05,0.07), 0, 0.2, 0.6))
	for i in n:
		var x := x0 + i * laneW
		_box(vp, Vector3(x - laneW*0.5, 0.005, -barLen * 24), Vector3(0.006, 0.01, barLen * 50), _mat(COLS[i], 0.8))
		_label(vp, TRACKS[i], Vector3(x, 0.02, 0.55), 0.0022, COLS[i], Vector3(-PI/2, 0, 0))
		for sp in SPANS[i]:
			var z0: float = -(sp[0] - head_bar) * barLen
			var z1: float = -(sp[1] + 1 - head_bar) * barLen
			if z0 > 0.4: z0 = 0.4
			if z1 > 0.4: continue
			var len := absf(z1 - z0)
			_box(vp, Vector3(x, 0.05, (z0 + z1) * 0.5), Vector3(laneW * 0.84, 0.10, len - 0.01), _mat(COLS[i], 0.7, 0.25, 0.1))
	for b in range(int(head_bar), int(head_bar) + 40, 4):
		var z := -(b - head_bar) * barLen
		_box(vp, Vector3(0, 0.003, z), Vector3(laneW * n, 0.004, 0.012), _mat(Color(0.8,0.85,1.0), 0.6))
		_label(vp, str(b), Vector3(x0 - laneW, 0.02, z), 0.003, Color(0.85,0.9,1), Vector3(-PI/2, 0, 0))
	# playhead: a lit gate
	_box(vp, Vector3(0, 0.25, 0), Vector3(laneW * n + 0.1, 0.5, 0.012), _mat(Color(1,0.95,0.7), 1.2, 0.2, 0, 0.22))
	_light(vp, Vector3(0, 0.4, 0.1), Color(1,0.92,0.7), 0.6, 3.0)
	if variant == "1": cam.position = Vector3(0, 1.1, 1.5); cam.look_at(Vector3(0, 0.0, -4.0))
	else: cam.position = Vector3(0, 0.9, 1.6); cam.look_at(Vector3(0, 0.0, -2.2))

# ---- B: TIERS. A curved amphitheatre: tracks are terraces, tiers rise away; time runs left-right along the arc. ----
func _tiers(cam: Camera3D) -> void:
	var n := TRACKS.size(); var arc := deg_to_rad(120.0); var r0 := 2.0; var dr := 0.22; var rise := 0.19
	var head_bar := 17.0; var span_bars := 48.0
	for i in n:
		var r := r0 + i * dr; var y := i * rise
		var segs := 48
		for s in segs:
			var t0 := float(s) / segs; var t1 := float(s + 1) / segs
			var a0 := lerpf(-arc*0.5, arc*0.5, t0); var a1 := lerpf(-arc*0.5, arc*0.5, t1)
			var am := (a0 + a1) * 0.5
			var p := Vector3(sin(am) * r, y, -cos(am) * r)
			var chord := 2.0 * r * sin((a1 - a0) * 0.5)
			var tile := _box(vp, p + Vector3(0, -0.02, 0), Vector3(chord, 0.04, dr * 0.92), _mat(Color(0.09,0.09,0.12) * (1.0 + 0.2 * (i % 2)), 0, 0.3, 0.5))
			tile.rotation.y = -am
		# clips
		for sp in SPANS[i]:
			var b0 := clampf((sp[0] - head_bar + 8.0) / span_bars, 0, 1)
			var b1 := clampf((sp[1] + 1 - head_bar + 8.0) / span_bars, 0, 1)
			if b1 <= b0: continue
			var cs := 10
			for s in cs:
				var t0 := lerpf(b0, b1, float(s)/cs); var t1 := lerpf(b0, b1, float(s+1)/cs)
				var a0 := lerpf(-arc*0.5, arc*0.5, t0); var a1 := lerpf(-arc*0.5, arc*0.5, t1)
				var am := (a0 + a1) * 0.5
				var chord := 2.0 * r * sin((a1 - a0) * 0.5) + 0.004
				var blk := _box(vp, Vector3(sin(am) * r, y + 0.06, -cos(am) * r), Vector3(chord, 0.12, dr * 0.78), _mat(COLS[i], 0.6, 0.25, 0.1))
				blk.rotation.y = -am
		var am0 := -arc * 0.5 - 0.04
		_label(vp, TRACKS[i], Vector3(sin(am0) * r, y + 0.05, -cos(am0) * r), 0.0028, COLS[i], Vector3(0, -am0 + PI * 0.0 + deg_to_rad(-90)*0 , 0))
	# playhead: blade of light sweeping through the arc at the head position
	var ph := (8.0) / span_bars; var aph := lerpf(-arc*0.5, arc*0.5, ph)
	var rmid := r0 + n * dr * 0.5; var hh := n * rise
	var blade := _box(vp, Vector3(sin(aph) * rmid, hh * 0.5, -cos(aph) * rmid), Vector3(0.025, hh + 0.4, n * dr + 0.3), _mat(Color(1,0.95,0.7), 1.2, 0.2, 0, 0.25))
	blade.rotation.y = -aph
	_light(vp, Vector3(sin(aph) * rmid, hh + 0.5, -cos(aph) * rmid), Color(1,0.92,0.7), 0.8, 5.0)
	if variant == "1": cam.position = Vector3(0, 1.0, 0.4); cam.look_at(Vector3(0, 1.3, -3.0))
	else: cam.position = Vector3(0, 1.3, 1.0); cam.look_at(Vector3(0, 1.2, -4.0))

# ---- C: STRATA. Time runs left-right; tracks are glass layers stacked in DEPTH, nearest = picked track pulled forward. ----
func _strata(cam: Camera3D) -> void:
	var n := TRACKS.size(); var W := 3.2; var step := 0.26; var picked := 9
	var head_bar := 17.0; var span_bars := 48.0
	for i in n:
		var z := -i * step - (0.0 if i != picked else -0.0)
		var lift := 0.18 if i == picked else 0.0
		var pull := 0.35 if i == picked else 0.0
		var y0 := 0.8 + i * 0.045 + lift
		_box(vp, Vector3(0, y0 - 0.06, z + pull), Vector3(W, 0.01, 0.34), _mat(COLS[i].darkened(0.6), 0.15, 0.2, 0.2, 0.55))
		_box(vp, Vector3(-W*0.5, y0 - 0.06, z + pull), Vector3(0.012, 0.012, 0.34), _mat(COLS[i], 1.5))
		_label(vp, TRACKS[i], Vector3(-W*0.5 - 0.35, y0 + 0.02, z + pull), 0.0034, COLS[i])
		for sp in SPANS[i]:
			var b0 := clampf((sp[0] - head_bar + 8.0) / span_bars, 0, 1)
			var b1 := clampf((sp[1] + 1 - head_bar + 8.0) / span_bars, 0, 1)
			if b1 <= b0: continue
			var x0 := -W*0.5 + b0 * W; var x1 := -W*0.5 + b1 * W
			_box(vp, Vector3((x0 + x1) * 0.5, y0 + 0.02, z + pull), Vector3(x1 - x0 - 0.006, 0.10 if i == picked else 0.075, 0.26), _mat(COLS[i], 0.9 if i == picked else 0.5, 0.2, 0.1))
	var xph := -W*0.5 + (8.0 / span_bars) * W
	_box(vp, Vector3(xph, 1.1, -n*step*0.5), Vector3(0.02, 1.0, n*step + 0.4), _mat(Color(1,0.95,0.7), 1.2, 0.2, 0, 0.22))
	_light(vp, Vector3(xph, 1.5, -n*step*0.5), Color(1,0.92,0.7), 0.8, 4.0)
	cam.position = Vector3(0.3, 1.6, 2.4); cam.look_at(Vector3(0, 0.9, -1.6))
	if variant == "1": cam.position = Vector3(-1.6, 2.2, 1.2); cam.look_at(Vector3(0.2, 1.0, -1.6))
