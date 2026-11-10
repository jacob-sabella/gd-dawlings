extends RefCounted

## The control API's mods tools (docs/mcp_assistant.md), called from tests/run_tests.gd's `_test_control_mods`.

const Tools := preload("res://core/control/tools_mods.gd")
const TMP := "/tmp/dawlings_control_mods/"

var t: Node


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _manifest(id: String) -> String:
	return JSON.stringify({"format": "dawlings.mod", "api_version": 1, "id": id, "name": "Probe " + id, "version": "1.0.0",
			"licence": {"spdx": "MIT"}, "source": {"kind": "user_installed"}, "provides": [
				{"kind": "plugin", "plugin": {"format": "clap", "id": "org.example." + id.get_slice(".", 1)}, "display": {"title": "PROBE"}}]})


func _has_text(api: ControlApi, data: Variant, needle: String) -> bool:
	return JSON.stringify(data).contains(needle)


func run() -> void:
	var api := ControlTools.make_api()
	var kept := ModRegistry.current
	var reg_user := TMP + "user"
	OS.execute("rm", ["-rf", TMP.trim_suffix("/")])
	DirAccess.make_dir_recursive_absolute(reg_user)
	var reg := ModRegistry.new()
	reg.scan([ModRegistry.SHIPPED_ROOT, reg_user])
	ModRegistry.current = reg
	Tools.user_root = reg_user

	# Reading.
	var l := api.invoke("mods_list")
	var mods: Array = l["data"]["mods"] if l["ok"] else []
	var ids := mods.map(func(m: Dictionary) -> String: return m["id"])
	check("mods_list lists the builtin mods", l["ok"] and ids.has("builtin.core") and ids.has("builtin.presets")
			and ids.has("builtin.mutable") and ids.has("builtin.airwindows") and ids.any(func(i: String) -> bool: return i.contains("daisysp")))
	check("every mods_list entry has an id, a kind, an origin and enabled", mods.all(func(m: Dictionary) -> bool:
			return str(m["id"]) != "" and m.has("kind") and m.has("origin") and m.has("enabled")))
	var only := api.invoke("mods_list", {"origin": "user"})
	check("mods_list can filter by origin", only["ok"] and only["data"]["count"] == 0)
	var g := api.invoke("mods_get", {"id": "builtin.presets"})
	check("mods_get gives a known mod's licence, source and entries", g["ok"] and g["data"]["licence"].get("spdx") == "MIT"
			and g["data"]["origin"] == "builtin" and g["data"]["entry_count"] > 0 and g["data"]["entries"].size() > 0)
	check("mods_get of an unknown id refuses", not api.invoke("mods_get", {"id": "nope.nothing"})["ok"])
	check("mods_problems answers", api.invoke("mods_problems", {"limit": 5})["ok"])
	check("mods_reload answers with counts", api.invoke("mods_reload")["data"]["mods"] >= 5)

	# Builtin mods are fixed.
	var d := api.invoke("mods_disable", {"id": "builtin.core"})
	check("disabling a builtin mod refuses and says why", not d["ok"] and str(d["error"]).contains("builtin"))
	check("enabling a builtin mod refuses", not api.invoke("mods_enable", {"id": "builtin.core"})["ok"])
	check("removing a builtin mod refuses (confirmed or not)", not api.invoke("mods_remove", {"id": "builtin.core"}, 0, true)["ok"]
			and not api.invoke("mods_remove", {"id": "builtin.core"})["ok"])
	check("builtin.core is still there", ModRegistry.current.mod("builtin.core") != null)

	# Import refusals.
	check("mods_import of a missing path refuses", not api.invoke("mods_import", {"path": TMP + "nothing_here"})["ok"])
	var dd := api.invoke("mods_import", {"path": TMP + "user/../user"})
	check("mods_import of a path with .. refuses", not dd["ok"] and str(dd["error"]).contains(".."))
	check("mods_import of the game's own files refuses", not api.invoke("mods_import", {"path": "res://mods/builtin/core"})["ok"])
	_write(TMP + "notmod/readme.txt", "hello")
	check("mods_import of a folder with no mod.json refuses", not api.invoke("mods_import", {"path": TMP + "notmod"})["ok"])
	_write(TMP + "prog/mod.json", _manifest("test.prog"))
	_write(TMP + "prog/run.sh", "#!/bin/sh\n")
	var pr := api.invoke("mods_import", {"path": TMP + "prog"})
	check("mods_import refuses a mod carrying a program, and says why", not pr["ok"] and str(pr["error"]).contains("run.sh"))
	_write(TMP + "builtinid/mod.json", _manifest("builtin.sneaky"))
	check("mods_import refuses a builtin id", not api.invoke("mods_import", {"path": TMP + "builtinid"})["ok"])
	_write(TMP + "notzip.zip", "not a zip at all, not a zip at all, not a zip at all")
	check("mods_import refuses a bad zip", not api.invoke("mods_import", {"path": TMP + "notzip.zip"})["ok"])

	# A whole user mod's life: import, list, disable, enable, remove.
	_write(TMP + "good/mod.json", _manifest("test.probe"))
	var imp := api.invoke("mods_import", {"path": TMP + "good"})
	check("mods_import takes in a good folder", imp["ok"] and imp["data"]["id"] == "test.probe")
	var again := api.invoke("mods_import", {"path": TMP + "good"})
	check("importing it twice refuses", not again["ok"] and str(again["error"]).contains("already"))
	var u := api.invoke("mods_list", {"origin": "user"})
	check("the new mod is listed as a user mod, enabled", u["ok"] and u["data"]["count"] == 1
			and u["data"]["mods"][0]["id"] == "test.probe" and u["data"]["mods"][0]["enabled"] == true)
	var off := api.invoke("mods_disable", {"id": "test.probe"})
	check("a user mod can be disabled", off["ok"] and ModRegistry.current.mod("test.probe") == null)
	var after := api.invoke("mods_list", {"origin": "user"})
	check("a disabled mod is still listed, as not enabled", after["data"]["count"] == 1 and after["data"]["mods"][0]["enabled"] == false)
	check("mods_get reads a disabled mod", api.invoke("mods_get", {"id": "test.probe"})["data"]["enabled"] == false)
	var on := api.invoke("mods_enable", {"id": "test.probe"})
	check("and enabled again", on["ok"] and ModRegistry.current.mod("test.probe") != null)
	check("removing is destructive: it needs confirmation", not api.invoke("mods_remove", {"id": "test.probe"})["ok"]
			and ModRegistry.current.mod("test.probe") != null)
	var rm := api.invoke("mods_remove", {"id": "test.probe"}, 0, true)
	check("a confirmed remove takes the mod and its folder away", rm["ok"] and ModRegistry.current.mod("test.probe") == null
			and not DirAccess.dir_exists_absolute(reg_user + "/test.probe"))

	# A zip, with the usual single folder around the mod.
	var zp := ZIPPacker.new()
	zp.open(TMP + "zipped.zip")
	zp.start_file("zipped_mod/mod.json")
	zp.write_file(_manifest("test.zipped").to_utf8_buffer())
	zp.close_file()
	zp.close()
	var zi := api.invoke("mods_import", {"path": TMP + "zipped.zip"})
	check("mods_import takes in a zip", zi["ok"] and zi["data"]["id"] == "test.zipped" and ModRegistry.current.mod("test.zipped") != null)
	api.invoke("mods_remove", {"id": "test.zipped"}, 0, true)

	# Schema and bad arguments.
	check("mods tools refuse bad arguments", not api.invoke("mods_get", {})["ok"] and not api.invoke("mods_get", {"id": 3})["ok"]
			and not api.invoke("mods_import", {"path": "x", "extra": 1})["ok"] and not api.invoke("mods_list", {"origin": "mine"})["ok"])

	# Help.
	var s := api.invoke("help_search", {"query": "patchbay"})
	check("help_search finds the patchbay in the docs", s["ok"] and s["data"]["count"] > 0
			and s["data"]["hits"].any(func(h: Dictionary) -> bool: return h["kind"] == "doc" and str(h["path"]).begins_with("docs/") and str(h["snippet"]) != ""))
	var s2 := api.invoke("help_search", {"query": "rack", "limit": 5})
	check("help_search finds the rack", s2["ok"] and s2["data"]["hits"].size() >= 3)
	var s3 := api.invoke("help_search", {"query": "reverb"})
	check("help_search reaches module help", s3["ok"] and s3["data"]["hits"].any(func(h: Dictionary) -> bool: return h["kind"] == "module"))
	check("help_search of nothing refuses", not api.invoke("help_search", {"query": "  "})["ok"] and not api.invoke("help_search", {})["ok"])
	var out := api.invoke("help_get", {"path": "docs/mods.md"})
	check("help_get with no heading gives the outline", out["ok"] and out["data"]["outline"].size() > 5)
	var head: String = str(out["data"]["outline"][1]).strip_edges() if out["ok"] else ""
	var sec := api.invoke("help_get", {"path": "mods", "heading": head})
	check("help_get gives a section, bounded", sec["ok"] and str(sec["data"]["text"]).length() <= Tools.SECTION_MAX and str(sec["data"]["text"]) != "")
	var big := api.invoke("help_get", {"path": "docs/mods.md", "heading": "Design: mods"})
	check("help_get pages a long section with next_offset", not big["ok"] or not big["data"]["truncated"] or big["data"]["next_offset"] == Tools.SECTION_MAX)
	check("help_get refuses a path outside the docs", not api.invoke("help_get", {"path": "../project.godot"})["ok"]
			and not api.invoke("help_get", {"path": "docs/../project.godot"})["ok"])
	check("help_get refuses an unknown heading", not api.invoke("help_get", {"path": "docs/mods.md", "heading": "zzz no such zzz"})["ok"])
	var st := api.invoke("help_stations")
	check("help_stations lists the stations with their help", st["ok"] and st["data"]["count"] > 5
			and st["data"]["stations"].all(func(r: Dictionary) -> bool: return str(r["title"]) != "" and str(r["id"]) != ""))
	check("help_stations filters", api.invoke("help_stations", {"query": "wheel"})["data"]["count"] >= 1)
	var k := api.invoke("help_keys")
	check("help_keys gives the F1 pages", k["ok"] and k["data"]["pages"].size() == 3 and k["data"]["pages"][0]["items"].size() > 3)
	check("help_keys by page", api.invoke("help_keys", {"page": "ROOM"})["data"]["pages"].size() == 1 and not api.invoke("help_keys", {"page": "NOPE"})["ok"])
	var gm := api.invoke("help_game")
	var all_domains := true
	for dom in api.domains():
		all_domains = all_domains and _has_text(api, gm["data"], '"domain":"%s"' % dom)
	check("help_game names every domain the api has", gm["ok"] and all_domains and api.domains().has("mods") and api.domains().has("help"))
	var one := api.invoke("help_game", {"domain": "mods"})
	check("help_game of a domain lists its tools with summaries", one["ok"] and one["data"]["tools"].size() == 8)
	check("help_game of an unknown domain refuses", not api.invoke("help_game", {"domain": "zz"})["ok"])

	# Put things back.
	Tools.user_root = ""
	ModRegistry.current = kept
	OS.execute("rm", ["-rf", TMP.trim_suffix("/")])
	await t.get_tree().process_frame
