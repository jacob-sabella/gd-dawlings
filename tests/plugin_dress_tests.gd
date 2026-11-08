extends RefCounted

## docs/mods.md 4.3 for `plugin` entries: `display.skin` is validated and reaches a RackUnit's faceplate, a slot
## whose plugin this machine lacks shows the unavailable plate (and still saves as it came), and the MODS
## list has a row for each plugin entry that says whether it is here. A temporary root holds the mod.
## Called from the `_test_*` wrappers in tests/run_tests.gd.

const TMP := "user://plugin_dress_test/"
const SKIN := {"face": "#1A2A44", "accent": "#5BC0FF", "pattern": "bars", "tagline": "TEST TAGLINE"}

var t: Node


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


func _mod(plugins: Array) -> Dictionary:
	return {"format": "dawlings.mod", "api_version": 1, "id": "test.looks", "name": "Looks", "version": "1.0.0",
			"licence": {"spdx": "MIT"}, "source": {"kind": "data"}, "provides": plugins}


func _registry(plugins: Array) -> ModRegistry:
	DirAccess.make_dir_recursive_absolute(TMP.path_join("looks"))
	var f := FileAccess.open(TMP.path_join("looks/mod.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(_mod(plugins)))
	f.close()
	var reg := ModRegistry.new()
	reg.scan([ModRegistry.SHIPPED_ROOT, TMP])
	return reg


func _plugin(id: String, display: Variant) -> Dictionary:
	var e := {"kind": "plugin", "plugin": {"format": "clap", "id": id}}
	if display != null:
		e["display"] = display
	return e


func _unit_names(unit: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for c in unit.get_children():
		out.append(str(c.name))
	return out


func _problems(entry: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for p in ModEntryCheck.check(entry, 0, "test.looks"):
		out.append(p.message)
	return out


## `display.skin` is checked like a module's skin; a bad one makes the entry unavailable, not the mod.
func skins_are_validated() -> void:
	var errs := _problems(_plugin("a.b", {"title": "X", "skin": SKIN}))
	check("a plugin entry with a good display.skin is clean (%s)" % [errs], errs.is_empty())
	for bad in [{"skin": "red"}, {"skin": {"face": "red", "accent": "#5BC0FF", "pattern": "bars", "tagline": "T"}},
			{"skin": {"face": "#1A2A44", "accent": "#5BC0FF", "pattern": "bars"}}, {"title": ""}]:
		errs = _problems(_plugin("a.b", bad))
		check("a bad display %s is refused (%s)" % [bad, errs], not errs.is_empty())
	errs = _problems(_plugin("a.b", "text"))
	check("a display that is not an object is refused", not errs.is_empty())


## RackSkin.of_plugin reads the available mod's skin, case-insensitively on the format; PluginRef names slots.
func skins_and_refs_resolve() -> void:
	var saved := ModRegistry.current
	ModRegistry.current = _registry([_plugin("org.example.synth", {"title": "Example Synth", "skin": SKIN}), _plugin("org.example.plain", {"title": "Plain"})])
	var skin := RackSkin.of_plugin("CLAP", "org.example.synth")
	check("a dressed plugin has its skin as [face, accent, pattern, tagline]", skin.size() == 4 and skin[0] == Color.html("#1A2A44")
			and skin[2] == &"bars" and skin[3] == "TEST TAGLINE")
	check("an undressed one and an unknown one have none", RackSkin.of_plugin("clap", "org.example.plain").is_empty() and RackSkin.of_plugin("clap", "nope").is_empty())
	var lost := MixState.FXState.new()
	lost.name = "synth"
	lost.set_meta(&"unhosted", {"plugin_format": "CLAP", "plugin_id": "org.example.synth"})
	var ref := PluginRef.of(lost, null)
	check("a slot the project kept as it came is a missing plugin, format lower case", ref == {"format": "clap", "id": "org.example.synth", "name": "synth", "missing": true})
	var eq := MixState.FXState.new()
	eq.name = FXCatalogue.kinds()[&"eq"]["name"]
	check("a built-in effect's slot is godot:<kind>", PluginRef.of(eq, null).get("id") == "eq" and PluginRef.of(eq, null).get("format") == "godot")
	var other := MixState.FXState.new()
	other.name = "No Such Thing"
	check("any other slot is not the registry's to name", PluginRef.of(other, null).is_empty() and PluginRef.of(null, null).is_empty())
	check("a missing plugin's plate is the unavailable plate; a dressed one's is its skin", RackUnitDress.skin_of(ref)[1] == RackUnitDress.MISSING_ACCENT
			and RackUnitDress.skin_of({"format": "clap", "id": "org.example.synth", "name": "s", "missing": false})[3] == "TEST TAGLINE"
			and RackUnitDress.skin_of({}).is_empty())
	check("it says what is missing", RackUnitDress.missing_words(ref) == PackedStringArray(["UNAVAILABLE", "CLAP EXAMPLE SYNTH is not installed here"]))
	ModRegistry.current = saved
	_clear(TMP)


## A rack unit gets the skin's band and tagline, and a slot with a missing plugin the unavailable plate.
func rack_units_wear_the_skin_and_the_unavailable_plate() -> void:
	var saved := ModRegistry.current
	ModRegistry.current = _registry([_plugin("org.example.synth", {"title": "Example Synth", "skin": SKIN})])
	DAW.use(OfflineBackend.new())
	var plain := RackUnit.create(2, 0)
	t.add_child(plain)
	check("an undressed unit has no band, tagline or plate", not "SkinBand" in _unit_names(plain) and not "UnavailableTitle" in _unit_names(plain))
	plain.queue_free()
	var dressed := RackUnit.create(2, 0)
	t.add_child(dressed)
	RackUnitDress.add_to(dressed, {"format": "clap", "id": "org.example.synth", "name": "s", "missing": false}, RackSkin.of_plugin("clap", "org.example.synth"), dressed.height())
	var names := _unit_names(dressed)
	check("a skin adds its pattern, band and tagline (%s)" % [names], "SkinPrint" in names and "SkinBand" in names and "SkinTagline" in names and not "UnavailableTitle" in names)
	check("the tagline is the skin's", (dressed.get_node("SkinTagline") as Label3D).text == "TEST TAGLINE")
	dressed.queue_free()
	var fx := DAW.state.fx(2, 0)
	fx.set_meta(&"unhosted", {"plugin_format": "clap", "plugin_id": "org.example.synth"})
	fx.name = "synth"
	var gone := RackUnit.create(2, 0)
	t.add_child(gone)
	names = _unit_names(gone)
	check("a slot whose plugin is gone shows the unavailable plate without crashing (%s)" % [names], "UnavailableTitle" in names and "UnavailableWhy" in names and "SkinBand" in names)
	check("it names the plugin from the mod's title", (gone.get_node("UnavailableWhy") as Label3D).text == "CLAP EXAMPLE SYNTH is not installed here")
	gone._process(0.0)
	gone.queue_free()
	ModRegistry.current = saved
	_clear(TMP)


## The plugin rows: a built-in effect is installed; a scanned plugin is when the catalogue has it, else missing with a reason.
func plugin_rows_say_whether_each_is_here() -> void:
	var reg := _registry([_plugin("org.example.synth", {"title": "Example Synth", "skin": SKIN}), _plugin("org.example.plain", {"title": "Plain"})])
	var catalogue := PluginCatalogue.new()
	var rows := ModPluginListing.rows(reg, catalogue)
	var by_id := {}
	for r in rows:
		by_id[r["id"]] = r
	check("every plugin entry of an ok mod is a row (%d)" % rows.size(), by_id.has("org.example.synth") and by_id.has("org.example.plain") and by_id.has("eq"))
	check("a built-in effect is installed", by_id["eq"]["status"] == "installed" and by_id["eq"]["reason"] == "" and by_id["eq"]["format"] == "godot")
	var s: Dictionary = by_id["org.example.synth"]
	check("a plugin this machine lacks is missing, with the registry's reason (%s)" % s["reason"], s["status"] == "missing" and s["reason"].begins_with("plugin_not_found")
			and s["title"] == "Example Synth" and s["has_skin"] and not by_id["org.example.plain"]["has_skin"])
	check("as text, one line per row, status first", ModPluginListing.to_lines(rows).size() == rows.size() and ModPluginListing.to_lines(rows)[0].split("\t").size() == 7)
	_clear(TMP)


func _clear(path: String) -> void:
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	for d in DirAccess.get_directories_at(path):
		_clear(path.path_join(d))
		DirAccess.remove_absolute(path.path_join(d))
