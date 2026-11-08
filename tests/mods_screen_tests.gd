extends RefCounted

## The MODS list (docs/mods.md section 5): `ModListing` rows, the F5 `ModsScreen`, and the registry's
## handling of a missing binary. A temporary root holds a good mod, a mod whose manifest is bad JSON, one
## whose manifest fails the schema, a folder with no manifest, a mod whose pinned binary is missing and a mod
## that needs that one; every one of them must be a row with a reason and none may stop the others.
## Called from the `_test_*` wrappers in tests/run_tests.gd.

const TMP := "user://mods_screen_test/"

var t: Node


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


func _mod(name: String, extra: Dictionary) -> Dictionary:
	var d := {"format": "dawlings.mod", "api_version": 1, "id": "test." + name, "name": name.capitalize(), "version": "1.2.3",
			"licence": {"spdx": "MIT"}, "source": {"kind": "data"},
			"provides": [{"kind": "rack_preset", "name": "test_" + name, "title": "T", "patch": {"modules": {}, "cables": []}}]}
	d.merge(extra, true)
	return d


func _write(folder: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(TMP.path_join(folder))
	var f := FileAccess.open(TMP.path_join(folder).path_join("mod.json"), FileAccess.WRITE)
	f.store_string(text)


## Writes the root the tests read.
func _make_root() -> String:
	_clear(TMP)
	_write("a_good", JSON.stringify(_mod("good", {})))
	_write("b_bad_json", "{ this is not json")
	var schema := _mod("noschema", {})
	schema.erase("licence")
	_write("c_bad_schema", JSON.stringify(schema))
	DirAccess.make_dir_recursive_absolute(TMP.path_join("d_no_manifest"))
	var bin := {"kind": "binary", "file": "bin/tool.so", "version": "2.0.0", "sha256": "a".repeat(64), "upstream": "https://example.com/tool"}
	_write("e_missing_binary", JSON.stringify(_mod("tool", {"source": bin, "licence": {"spdx": "MIT"}})))
	_write("f_needs_tool", JSON.stringify(_mod("needs", {"requires": [{"mod": "test.tool"}]})))
	_write("g_has_binary", JSON.stringify(_mod("present", {"source": bin})))
	DirAccess.make_dir_recursive_absolute(TMP.path_join("g_has_binary/bin"))
	var f := FileAccess.open(TMP.path_join("g_has_binary/bin/tool.so"), FileAccess.WRITE)
	f.store_string("x")
	return TMP


func _clear(path: String) -> void:
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	for d in DirAccess.get_directories_at(path):
		_clear(path.path_join(d))
		DirAccess.remove_absolute(path.path_join(d))


func _row(rows: Array[Dictionary], id: String) -> Dictionary:
	for r in rows:
		if r["id"] == id:
			return r
	return {}


func _registry() -> ModRegistry:
	var reg := ModRegistry.new()
	reg.scan([ModRegistry.SHIPPED_ROOT, _make_root()])
	return reg


## Every registry mod is a row with the fields; broken ones are unavailable rows with a reason.
func rows_list_every_mod_and_every_failure() -> void:
	var reg := _registry()
	var rows := ModListing.rows(reg)
	var keys := ["id", "name", "version", "licence", "source", "kind", "status", "reason", "notes", "folder"]
	check("every row has id, name, version, licence, source, kind, status, reason, notes and folder", rows.all(func(r: Dictionary) -> bool: return keys.all(func(k: String) -> bool: return r.has(k))))
	var daisy := _row(rows, "builtin.daisysp")
	check("a shipped mod shows its version, licence and submodule pin", daisy.get("status") == "ok" and daisy["version"] == reg.mod("builtin.daisysp").version
			and daisy["licence"] == "MIT" and daisy["source"] == "submodule vendor/daisysp @ 2c72eaf" and daisy["reason"] == "")
	check("and what it provides", str(daisy["kind"]).begins_with("rack_module x"))
	check("an in-tree mod shows its path", _row(rows, "builtin.effects")["source"] == "in_tree core/built_in")
	check("a good user mod is an ok row", _row(rows, "test.good")["status"] == "ok" and _row(rows, "test.good")["version"] == "1.2.3")
	var bad_json := _row(rows, "b_bad_json")
	check("a manifest that is not JSON is an unavailable row named for its folder, with the parser's words",
			bad_json.get("status") == "unavailable" and str(bad_json.get("reason")).begins_with("bad_json: line "))
	var bad_schema := _row(rows, "test.noschema")
	check("a manifest that breaks the schema is an unavailable row with the reason (%s)" % bad_schema.get("reason"),
			bad_schema.get("status") == "unavailable" and "licence" in str(bad_schema.get("reason")))
	var none := _row(rows, "d_no_manifest")
	check("a folder with no mod.json is listed too", none.get("status") == "unavailable" and str(none.get("reason")).begins_with("no_manifest"))
	var tool := _row(rows, "test.tool")
	check("a mod whose binary is missing is an unavailable row that says so (%s)" % tool.get("reason"),
			tool.get("status") == "unavailable" and str(tool.get("reason")).begins_with("binary_missing") and "bin/tool.so" in str(tool["reason"])
			and str(tool["source"]).begins_with("binary bin/tool.so 2.0.0 sha aaaaaaaa"))
	check("and the mod that needs it is unavailable, naming it", _row(rows, "test.needs").get("status") == "unavailable" and "test.tool" in str(_row(rows, "test.needs").get("reason")))
	check("a mod whose binary is there is ok", _row(rows, "test.present").get("status") == "ok")
	check("the unavailable ones' entries are not in the game", not reg.rack_preset_names().has(&"test_tool") and reg.rack_preset_names().has(&"test_good"))
	check("the count of unavailable rows is the four bad mods, the dependent and the empty folder", ModListing.unavailable_count(rows) == 5)
	check("the good mods still load after the broken ones", reg.is_available("test.good") and reg.is_available("test.present"))
	var lines := ModListing.to_lines(rows)
	check("as text, one tab-separated line per row, status first", lines.size() == rows.size() and lines[0].split("\t").size() == 7 and lines[0].begins_with("ok\tbuiltin."))
	check("an empty registry has no rows", ModListing.rows(ModRegistry.new()).is_empty())


func _labels(node: Node, out: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	if node is Label:
		out.append((node as Label).text)
	for c in node.get_children():
		_labels(c, out)
	return out


## F5 opens a read-only list that shows the rows and the reasons, for the host and a guest alike.
func the_screen_lists_the_rows_for_host_and_guest() -> void:
	var role := Session.role
	var reg := _registry()
	for as_guest in [false, true]:
		Session.role = Session.Role.GUEST if as_guest else Session.Role.HOST
		var screen := ModsScreen.new()
		screen.registry = reg
		t.add_child(screen)
		check("closed until asked (%s)" % ("guest" if as_guest else "host"), not screen.is_open())
		var key := InputEventKey.new()
		key.keycode = ModsScreen.TOGGLE_KEY
		key.pressed = true
		screen._unhandled_input(key)
		check("F5 opens it", screen.is_open())
		var words := _labels(screen)
		var joined := "\n".join(words)
		check("it lists the good mod and the bad ones by id", "test.good" in words and "b_bad_json" in words and "d_no_manifest" in words and "test.tool" in words)
		check("an unavailable mod's reason is on screen", "binary_missing: its binary bin/tool.so is not in the mod's folder" in joined.replace("      ", "") and "bad_json: line" in joined)
		check("the head counts them", "MODS  -  " in joined and "5 unavailable" in joined)
		check("the licence and the pin are on screen", "MIT" in words and "submodule vendor/daisysp @ 2c72eaf" in words)
		screen._unhandled_input(key)
		check("F5 closes it", not screen.is_open())
		screen.queue_free()
	Session.role = role
	_clear(TMP)


## `tools/rack_describe.sh` prints the same rows headless: the bad manifest and the missing binary are
## lines with their reasons, `--strict` exits 1 for them, and a clean registry exits 0.
func the_describe_script_prints_the_rows() -> void:
	var root := ProjectSettings.globalize_path(_make_root())
	var script := ProjectSettings.globalize_path("res://tools/rack_describe.sh")
	var out: Array = []
	var code := OS.execute("env", ["DAWLINGS_MODS=" + root, "bash", script, "--strict"], out, false)
	var lines: PackedStringArray = str(out[0]).split("\n", false) if not out.is_empty() else PackedStringArray()
	var by_id := {}
	for l in lines:
		if not l.begins_with("#") and not l.begins_with("plugin\t"):
			by_id[l.get_slice("\t", 1)] = l.split("\t")
	check("--strict exits 1 when a mod is unavailable (%d)" % code, code == 1)
	check("it prints the shipped mods, ok", by_id.has("builtin.daisysp") and by_id["builtin.daisysp"][0] == "ok" and by_id["builtin.daisysp"][4] == "submodule vendor/daisysp @ 2c72eaf")
	check("the bad manifest is a line with the parser's reason", by_id.has("b_bad_json") and by_id["b_bad_json"][0] == "unavailable" and by_id["b_bad_json"][6].begins_with("bad_json"))
	check("the missing binary is a line with its reason", by_id.has("test.tool") and by_id["test.tool"][0] == "unavailable" and by_id["test.tool"][6].begins_with("binary_missing"))
	check("it ends with a count", lines[lines.size() - 1] == "# 12 mods, 5 unavailable")
	code = OS.execute("bash", [script, "--strict"], out, false)
	check("a clean registry exits 0 (%d)" % code, code == 0)
	_clear(TMP)
