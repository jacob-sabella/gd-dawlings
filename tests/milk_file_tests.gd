extends RefCounted

## The MilkDrop preset files' tests (docs/visuals.md), called from tests/run_tests.gd's `_test_milk_file_*`:
## the equation language read and run, per-pixel code made into a shader that compiles, `.milk` files read
## (hand-made fixtures in tests/fixtures/milk, none from any pack), the player's own folder listed, the
## pack's zip unpacked and removed (a zip built here: nothing touches the network), and a file preset
## playing on a screen.

const FIXTURES := "res://tests/fixtures/milk"
const ROOT := "user://milk_file_tests"

var t: Node


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


func close_to(label: String, a: float, b: float, epsilon := 0.0001) -> void:
	t.close_to(label, a, b, epsilon)


func _run(src: String, vars := {}) -> Dictionary:
	var err := MilkEel.run_on(src, vars)
	if err != "":
		vars["__error"] = err
	return vars


func eel_parses_and_evaluates() -> void:
	var v := _run("a = 1 + 2 * 3; b = (1 + 2) * 3; c = 2 ^ 3 ^ 2; d = -2 ^ 2; e = 10 - 4 - 3; f = 7 / 2;")
	check("eel: no error", not v.has("__error"))
	close_to("eel: * before +", v.a, 7.0)
	close_to("eel: parentheses", v.b, 9.0)
	close_to("eel: ^ binds right to left", v.c, 512.0)
	close_to("eel: unary minus is looser than ^", v.d, -4.0)
	close_to("eel: - is left to right", v.e, 3.0)
	close_to("eel: / is not integer division", v.f, 3.5)
	v = _run("a = b = c = 4; d += 2; d *= 3; d -= 1; d /= 5; e = 17; e %= 5; f = (g = 2) + 1;")
	close_to("eel: an assignment chain sets every one", v.a + v.b + v.c, 12.0)
	close_to("eel: += *= -= /=", v.d, 1.0)
	close_to("eel: %=", v.e, 2.0)
	close_to("eel: an assignment inside an expression", v.f + v.g, 5.0)
	v = _run("a = 1 / 0; b = 5 % 0; c = log(0); d = sqrt(-4); e = pow(-8, 0.5);")
	close_to("eel: a division by zero is 0", v.a, 0.0)
	close_to("eel: a modulo by zero is 0", v.b, 0.0)
	check("eel: nothing is NaN or infinite", [v.c, v.d, v.e].all(func(x: float) -> bool: return is_finite(x)))
	close_to("eel: sqrt of a negative takes its size", v.d, 2.0)
	v = _run("Zoom = 2; ZOOM += 1; q1 = zoom; rot = UNSET_VAR;", {"Bass": 3.0})
	close_to("eel: names are case blind", v.q1, 3.0)
	close_to("eel: an unset variable is 0", v.rot, 0.0)
	close_to("eel: a variable handed in is read", float(_run("x = bass * 2;", {"BASS": 1.5}).x), 3.0)
	v = _run("a = 12 & 10; b = 12 | 3; c = 5.7 & 7; d = band(1, 0); e = bor(0, 2); f = bnot(0);")
	close_to("eel: & is bitwise", v.a, 8.0)
	close_to("eel: | is bitwise", v.b, 15.0)
	close_to("eel: on the integer part", v.c, 5.0)
	check("eel: band, bor, bnot are logical", v.d == 0.0 and v.e == 1.0 and v.f == 1.0)
	v = _run("a = if(above(3, 2), 10, 20); b = if(below(3, 2), 10, 20); c = equal(0.1 + 0.2, 0.3); "
			+ "d = min(4, max(1, 2)); e = sqr(3) + abs(-1) + sign(-5); f = floor(2.7) + ceil(2.2) + int(-2.7); "
			+ "g = atan2(1, 1); h = sigmoid(0, 1); i = exp(0) + log10(100); j = rand(1); k = sin(0) + cos(0);")
	close_to("eel: if, above", v.a, 10.0)
	close_to("eel: if, below", v.b, 20.0)
	close_to("eel: equal is approximate", v.c, 1.0)
	close_to("eel: min and max", v.d, 2.0)
	close_to("eel: sqr, abs, sign", v.e, 9.0)
	close_to("eel: floor, ceil, int", v.f, 3.0)
	close_to("eel: atan2", v.g, PI / 4.0)
	close_to("eel: sigmoid", v.h, 0.5)
	close_to("eel: exp, log10", v.i, 3.0)
	close_to("eel: rand(1) is 0", v.j, 0.0)
	close_to("eel: sin, cos", v.k, 1.0)
	v = _run("// a comment\na = 1 /* inline */ + 1;\nb = 2\nc = a + b", {})
	check("eel: comments, and a line break as a separator", not v.has("__error") and v.c == 4.0)
	v = _run("a = if(1, (b = 2; b + 1), 0); c = exec2(d = 5, d * 2);")
	close_to("eel: a sequence in parentheses is worth its last", v.a, 3.0)
	close_to("eel: exec2", v.c, 10.0)
	check("eel: an unknown function is an error", not MilkEel.parse("a = megabuf(1);").ok)
	check("eel: a dangling operator is an error", not MilkEel.parse("a = 1 +;").ok)
	check("eel: assigning to a number is an error", not MilkEel.parse("3 = a;").ok)
	check("eel: empty code is fine", MilkEel.parse("").ok and MilkEel.parse(" ; ;\n").ok)


func per_pixel_compiles_to_a_shader() -> void:
	var src := "zoom = zoom + rad*0.05*q1; rot = rot + 0.02*sin(ang*3 + time); dx = if(above(x, 0.5), 0.01, -0.01); " \
			+ "mine = sqr(y - 0.5) + (x & 3) * 0.0; dy = dy + mine * bass;"
	var code := MilkPlayer.shader_code(src)
	check("per-pixel: translated", code != "")
	check("per-pixel: it reads the per-frame values and q vars", code.contains("float v_q1 = u_q[0];") and code.contains("v_bass"))
	check("per-pixel: the preset's own variables are locals", code.contains("float v_mine = 0.0;"))
	check("per-pixel: if becomes a conditional", code.contains("? 0.01 : (-0.01)"))
	var s := Shader.new()
	s.code = code
	var names := s.get_shader_uniform_list().map(func(u: Dictionary) -> String: return u.name)
	check("per-pixel: it compiles as a Godot shader", names.has("u_zoom") and names.has("u_q") and names.has("prev"))
	check("per-pixel: no code compiles too", MilkPlayer.shader_for("") != null)
	check("per-pixel: the shader is cached by its code", MilkPlayer.shader_for(src) == MilkPlayer.shader_for(src))
	check("per-pixel: an assignment inside an expression is refused, not mistranslated",
			MilkPlayer.shader_code("zoom = 1 + (q1 = rad);") == "")


func milk_files_parse() -> void:
	var m := MilkFile.load_path(FIXTURES.path_join("plain_tunnel.milk"))
	check("milk: a file is read", m != null and m.name == "plain_tunnel")
	var b := m.base()
	close_to("milk: fDecay is decay", b.decay, 0.96)
	close_to("milk: fZoomExponent is zoomexp", b.zoomexp, 1.3)
	close_to("milk: nWaveMode is wave_mode", b.wave_mode, 0.0)
	close_to("milk: bAdditiveWaves", b.wave_additive, 1.0)
	close_to("milk: echo", b.echo_alpha + b.echo_zoom + b.echo_orient, 0.3 + 1.2 + 1.0)
	close_to("milk: a border", b.ob_a, 0.5)
	close_to("milk: what the file leaves out is MilkDrop's default", b.mv_dx, 0.0)
	check("milk: per-frame lines joined in order", m.per_frame.find("wave_r") < m.per_frame.find("rot = rot"))
	check("milk: per-frame init", m.per_frame_init.contains("q8 = 3"))
	check("milk: per-pixel", m.per_pixel.split("\n").size() == 3)
	check("milk: no MilkDrop 2 shaders", not m.has_shaders())

	var c := MilkFile.load_path(FIXTURES.path_join("custom_wave_and_shape.milk"))
	close_to("milk: CRLF and spaces round a value", c.base().decay, 0.94)
	check("milk: an unknown word value and a line without = are skipped, not a problem", c.values.has("someunknownkey") == false and c.values.size() > 5)
	check("milk: one custom wave enabled", c.waves.size() == 1 and int(c.waves[0].cfg.samples) == 200)
	check("milk: its per-point lines", c.waves[0].per_point.split("\n").size() == 4)
	check("milk: a disabled shape is left out", c.shapes.size() == 1 and int(c.shapes[0].cfg.num_inst) == 3)
	check("milk: shape code", c.shapes[0].per_frame.contains("instance"))

	var d := MilkFile.load_path(FIXTURES.path_join("with_md2_shaders.milk"))
	check("milk: MilkDrop 2 shaders read, the backtick dropped", d.has_shaders() and d.warp_shader.begins_with("shader_body"))
	var pd := MilkPlayer.new(d)
	check("milk: and translated, both of them", pd.warp_md2 and pd.comp_shader != null and not pd.approx())

	var pc := MilkPlayer.new(c)
	check("milk: a clean file plays exactly", not pc.approx() and pc.waves.size() == 1 and pc.shapes.size() == 1)
	var f := MilkPresets.quiet(2.0)
	f["bass"] = 2.0
	var v := pc.step(f, 1.0 / 60.0, 1.8, Vector2i(512, 274))
	close_to("milk: the per-frame code ran (mixed-case names)", v.zoom, 0.99 - 0.02)
	var ink := MilkScreen.Ink.new()
	var glow := MilkScreen.Ink.new()
	var wave := PackedFloat32Array()
	wave.resize(96)
	for i in 96:
		wave[i] = sin(i * 0.4) * 0.6
	pc.draw(ink, glow, Vector2i(512, 274), wave, PackedFloat32Array(), null)
	var custom: Array = glow.strokes.filter(func(s: Array) -> bool: return int(s[3]) == 3)
	check("milk: the additive custom wave is drawn, 200 points with colours",
			custom.size() == 1 and (custom[0][0] as PackedVector2Array).size() == 200)
	check("milk: three instances of the shape, filled", ink.tri_points.size() >= 3 * 6 * 3)
	ink.free()
	glow.free()

	var bad := MilkPlayer.new(MilkFile.load_path(FIXTURES.path_join("needs_fallback.milk")))
	check("milk: code that will not compile is dropped and said", bad.approx() and not bad.pixel_ok and bad.waves.is_empty())
	var bv := bad.step(MilkPresets.quiet(1.0), 1.0 / 60.0, 1.8, Vector2i(512, 274))
	close_to("milk: it still plays its base values", bv.decay, 0.97)
	check("milk: a missing file is null", MilkFile.load_path(FIXTURES.path_join("nope.milk")) == null)


func md2_shaders_translate() -> void:
	var t := MilkHlsl.translate("float3 tint = float3(1, 0.5, 0);\nshader_body\n{\n  float3 c = tex2D(sampler_main, uv).xyz;\n  ret = lerp(c, tint, frac(time));\n  int n = 2;\n}")
	check("hlsl: a shader translates", t.ok)
	check("hlsl: a global is a constant, its type Godot's", t.header.contains("const vec3 h_tint"))
	check("hlsl: the preset's own names are prefixed, MilkDrop's kept",
			t.body.contains("vec3 h_c") and t.body.contains("_main_w(uv)") and t.body.contains("time"))
	check("hlsl: lerp, frac and int become Godot's (or a helper)",
			t.body.contains("_hmix(") and t.body.contains("fract(") and t.body.contains("float h_n = _v1(2.0)"))
	check("hlsl: an assignment is fitted to its target", t.body.contains("ret = _v3("))
	check("hlsl: no shader_body, no translation", not MilkHlsl.translate("ret = 1;").ok)
	check("hlsl: a sampler handed around is refused", not MilkHlsl.translate("shader_body { ret = f(sampler_main); }").ok)
	check("hlsl: a named texture is drawn as noise",
			MilkHlsl.translate("shader_body { ret = tex2D(sampler_clouds, uv).xyz; }").swapped)
	check("hlsl: the translated warp compiles", MilkPlayer.shader_for("", t) != null)
	check("hlsl: and as a composite", MilkPlayer.comp_for(t) != null)

	var own := MilkPlayer.new(MilkFile.load_path(FIXTURES.path_join("md2_own_shaders.milk")))
	check("hlsl: a file's warp (functions, matrices, noise, blur) plays translated", own.warp_md2 and not own.warp_dropped)
	check("hlsl: its composite (loops, int, pow and max of mixed sizes) too", own.comp_shader != null)
	check("hlsl: and nothing is said against it", not own.approx())
	var m := ShaderMaterial.new()
	m.shader = own.shader
	own.step(MilkPresets.quiet(1.0), 1.0 / 60.0, 1.8, Vector2i(512, 274))
	own.apply_warp(m, Vector2i(512, 274))
	check("hlsl: the noise is handed to it", m.get_shader_parameter(&"noise_lq") is ImageTexture
			and m.get_shader_parameter(&"noisevol") is ImageTexture3D)
	check("hlsl: and the buffer's size", m.get_shader_parameter(&"u_size") == Vector2(512, 274))

	var bad := MilkPlayer.new(MilkFile.load_path(FIXTURES.path_join("md2_untranslatable.milk")))
	check("hlsl: a warp that will not translate falls back to the plain warp, and says so",
			not bad.warp_md2 and bad.warp_dropped and bad.shader == MilkPlayer.shader_for("")
			and Array(bad.notes).any(func(s: String) -> bool: return s.begins_with("MilkDrop 2 warp shader not translated")))
	check("hlsl: a composite that will not, to the plain glass",
			bad.comp_shader == null and Array(bad.notes).any(func(s: String) -> bool: return s.begins_with("MilkDrop 2 composite")))
	var bm := ShaderMaterial.new()
	bm.shader = bad.shader
	bad.step(MilkPresets.quiet(1.0), 1.0 / 60.0, 1.8, Vector2i(512, 274))
	bad.apply_warp(bm, Vector2i(512, 274))
	check("hlsl: its dropped warp did the fading, so the plain one fades a little (fDecay 1 held below 1)",
			float(bm.get_shader_parameter(&"u_decay")) < 0.99)


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


## Points the library at this test's own root (never the player's user://milk), emptied.
func _use_root() -> String:
	var was := MilkLibrary.root
	MilkLibrary.root = ROOT
	MilkLibrary.reset()
	MilkDownload._remove_tree(MilkLibrary.own_dir())
	MilkDownload._remove_tree(MilkLibrary.pack_dir())
	return was


func _done_root(was: String) -> void:
	MilkDownload._remove_tree(MilkLibrary.own_dir())
	MilkDownload._remove_tree(MilkLibrary.pack_dir())
	MilkDownload._remove_tree(ROOT)
	MilkLibrary.root = was
	MilkLibrary.reset()


func library_indexes_own_folder() -> void:
	var was := _use_root()
	check("library: just the built-ins with nothing on disk", MilkLibrary.count() == MilkPresets.count())
	var plain := FileAccess.get_file_as_string(FIXTURES.path_join("plain_tunnel.milk"))
	_write(MilkLibrary.own_dir().path_join("Zeta.milk"), plain)
	_write(MilkLibrary.own_dir().path_join("alpha.MILK"), plain)
	_write(MilkLibrary.own_dir().path_join("deeper/nested/Mine.milk"), plain)
	_write(MilkLibrary.own_dir().path_join("notes.txt"), "not a preset")
	MilkLibrary.rescan()
	var n := MilkPresets.count()
	check("library: three own files found, any folder deep, any case of .milk", MilkLibrary.count() == n + 3)
	check("library: built-ins first", MilkLibrary.is_builtin(0) and not MilkLibrary.is_builtin(n))
	check("library: own files sorted by name", MilkLibrary.preset_name(n) == "alpha" and MilkLibrary.preset_name(n + 1) == "Zeta")
	check("library: a subfolder is its own category", MilkLibrary.category(n + 2) == MilkLibrary.OWN + " / deeper/nested")
	check("library: categories", MilkLibrary.categories()[0] == MilkLibrary.BUILT_IN and MilkLibrary.categories().has(MilkLibrary.OWN))
	check("library: a file is not read until shown", MilkLibrary.notes(n).is_empty() and MilkLibrary._players.is_empty())
	var pl := MilkLibrary.player(n)
	check("library: shown, it is read and played", pl != null and pl.file.name == "alpha")
	check("library: and kept", MilkLibrary.player(n) == pl)
	check("library: the finder searches it", MilkFinderScreen.search("zeta").size() == 1
			and MilkFinderScreen.search("", MilkLibrary.OWN).size() == 2)
	MilkLibrary.set_shuffle_pack(false, false)
	var picks := {}
	for i in 200:
		picks[MilkLibrary.pick_random(0)] = true
	check("library: the shuffle reaches own files and never repeats", picks.has(n) and not picks.has(0))
	_done_root(was)


func pack_unpacks_and_removes() -> void:
	var was := _use_root()
	DirAccess.make_dir_recursive_absolute(ROOT)
	var zip := MilkDownload.zip_path()
	var z := ZIPPacker.new()
	check("pack: a fixture zip is made", z.open(zip) == OK)
	var files := {
		"presets-cream-of-the-crop-master/README.md": "readme",
		"presets-cream-of-the-crop-master/Fractal/Spiral/One.milk": "[preset00]\nzoom=1.02\n",
		"presets-cream-of-the-crop-master/Fractal/Two.milk": "[preset00]\nzoom=0.98\n",
		"presets-cream-of-the-crop-master/Waveform/Three.milk": "[preset00]\nfDecay=0.9\n",
		"presets-cream-of-the-crop-master/Waveform/texture.jpg": "jpg",
		"presets-cream-of-the-crop-master/../escape.milk": "[preset00]\n",
	}
	for k in files:
		z.start_file(k)
		z.write_file(String(files[k]).to_utf8_buffer())
		z.close_file()
	z.close()
	var calls := [0]
	var n := MilkDownload.unpack(zip, MilkLibrary.pack_dir(), func(_d: int, _t: int) -> void: calls[0] += 1)
	check("pack: only the .milk files, none climbing out", n == 3)
	check("pack: progress was reported", calls[0] >= 1)
	var dest := MilkLibrary.pack_dir()
	check("pack: the top folder is stripped", FileAccess.file_exists(dest.path_join("Fractal/Spiral/One.milk"))
			and FileAccess.file_exists(dest.path_join("Waveform/Three.milk")))
	check("pack: nothing else comes out", not FileAccess.file_exists(dest.path_join("README.md"))
			and not FileAccess.file_exists(dest.path_join("Waveform/texture.jpg")))
	check("pack: nothing lands outside it", not FileAccess.file_exists(ROOT.path_join("escape.milk"))
			and not FileAccess.file_exists(dest.get_base_dir().path_join("escape.milk")))
	check("pack: a bad zip is -1", MilkDownload.unpack(ROOT.path_join("missing.zip"), dest) == -1)
	MilkLibrary.rescan()
	check("pack: listed after the built-ins", MilkDownload.installed() == 3 and MilkLibrary.count() == MilkPresets.count() + 3)
	check("pack: its folders are categories", MilkLibrary.categories().has("Fractal/Spiral") and MilkLibrary.categories().has("Waveform"))
	MilkLibrary.set_shuffle_pack(false, false)
	var picks := {}
	for i in 100:
		picks[MilkLibrary.pick_random(0)] = true
	check("pack: left out of the shuffle when asked", picks.keys().all(func(i: int) -> bool: return MilkLibrary.is_builtin(i)))
	MilkLibrary.set_shuffle_pack(true, false)
	MilkDownload.remove()
	check("pack: REMOVE deletes it", not DirAccess.dir_exists_absolute(dest) and MilkDownload.installed() == 0)
	check("pack: and the zip", not FileAccess.file_exists(zip))
	var d := MilkDownload.new()
	check("pack: never downloads by itself", d.state == MilkDownload.State.IDLE)
	d.free()
	_done_root(was)


func file_preset_plays_on_screen() -> void:
	var was := _use_root()
	_write(MilkLibrary.own_dir().path_join("Tunnel.milk"), FileAccess.get_file_as_string(FIXTURES.path_join("plain_tunnel.milk")))
	_write(MilkLibrary.own_dir().path_join("Shapes.milk"), FileAccess.get_file_as_string(FIXTURES.path_join("custom_wave_and_shape.milk")))
	_write(MilkLibrary.own_dir().path_join("Turned.milk"), FileAccess.get_file_as_string(FIXTURES.path_join("md2_own_shaders.milk")))
	MilkLibrary.rescan()
	var tier_was := VisualBudget.tier()
	VisualBudget.reset()
	VisualBudget.set_tier(VisualBudget.Tier.HIGH, false)
	var screen := MilkScreen.new()
	var a := AudioFeatures.new()
	a.bass = 1.5
	a.bass_att = 1.2
	screen.features = a
	t.add_child(screen)
	var n := MilkPresets.count()
	screen.use_preset(n + 1)
	check("screen: a file preset is chosen like a built-in", screen.preset_index == n + 1)
	for i in 3:
		screen.step_frame(0.5)
	var p := screen.params()
	var finite := not p.is_empty()
	for k in p:
		if p[k] is float and not is_finite(p[k]):
			finite = false
	check("screen: it plays with finite parameters", finite and p.has("decay"))
	close_to("screen: its own values (fDecay)", p.decay, 0.96)
	check("screen: its warp shader is on the buffer it wrote",
			(screen._rect[1 - screen._write].material as ShaderMaterial).shader == MilkLibrary.player(n + 1).shader)
	screen.use_preset(n)
	screen.step_frame(0.5)
	check("screen: the first half of a fade still plays the old one", screen.fading())
	screen.step_frame(1.6)
	check("screen: then the new one", not screen.fading() and screen.params().has("decay"))
	screen.use_preset(n + 2)
	screen.step_frame(2.1)
	check("screen: a MilkDrop 2 file's own composite is on the glass",
			screen._glass.material_override is ShaderMaterial
			and (screen._glass.material_override as ShaderMaterial).shader == MilkLibrary.player(n + 2).comp_shader)
	screen.use_preset(0)
	screen.step_frame(2.1)
	check("screen: back to a built-in, its own warp again", screen._rect[1 - screen._write].material == screen._warp[1 - screen._write])
	check("screen: and the plain glass", screen._glass.material_override == screen._comp)
	screen.queue_free()
	await t.get_tree().process_frame
	a.free()
	VisualBudget.reset()
	VisualBudget.set_tier(tier_was, false)
	_done_root(was)
