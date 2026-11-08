class_name ModPluginListing
extends RefCounted

## The `plugin` entries of the available mods as rows for the MODS screen and `tools/rack_describe.sh`
## (docs/mods.md 4.3): `{mod, format, id, title, has_skin, status, reason}`. `status` is `installed` when
## the plugin is on this machine (the built-in engine's own effects always are; a scanned plugin is when
## the catalogue finds `(format, id)`), else `missing` with the reason, which is also the registry's
## `plugin_not_found`: it is listed and changes nothing in the game.

const INSTALLED := "installed"
const MISSING := "missing"


## One row for each plugin entry of an available mod, in registry order. `catalogue` is the scanned
## plugins (PluginCatalogue.shared() by default; a test passes its own).
static func rows(reg: ModRegistry, catalogue: PluginCatalogue = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in reg.mods():
		if m.status != ModManifest.STATUS_OK:
			continue
		for e in m.entries:
			if e.get("kind") != "plugin":
				continue
			var p: Dictionary = e["plugin"]
			var d: Dictionary = e.get("display", {}) if e.get("display") is Dictionary else {}
			var why := _why_missing(str(p["format"]), str(p["id"]), catalogue)
			out.append({"mod": m.id, "format": str(p["format"]), "id": str(p["id"]),
					"title": str(d.get("title", p["id"])), "has_skin": d.get("skin") is Dictionary,
					"status": MISSING if why != "" else INSTALLED, "reason": why})
	return out


## The rows as text, tab separated: `status mod format id title skin reason`.
static func to_lines(rows_: Array[Dictionary]) -> PackedStringArray:
	var out := PackedStringArray()
	for r in rows_:
		out.append("\t".join([r["status"], r["mod"], r["format"], r["id"], r["title"], "skin" if r["has_skin"] else "-", r["reason"]]))
	return out


## Why the plugin is not here, or "" when it is.
static func _why_missing(format: String, id: String, catalogue: PluginCatalogue) -> String:
	if format == "godot":
		return "" if FXCatalogue.kinds().has(StringName(id)) else "the built-in engine has no effect '%s'" % id
	if not HostedPlugins.available() and catalogue == null:
		return "plugins are not hosted on this system"
	for info in (catalogue if catalogue != null else PluginCatalogue.shared()).plugins():
		if str(info["format"]).to_lower() == format and str(info["id"]) == id:
			return ""
	return "plugin_not_found: no %s plugin '%s' is installed here" % [format.to_upper(), id]
