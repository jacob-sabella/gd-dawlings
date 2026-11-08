class_name PluginRef
extends RefCounted

## Which plugin a chain slot holds, as the mod registry names plugins: `{format, id, name, missing}`
## (docs/mods.md 4.3). A slot of the built-in engine's own effect is `godot:<kind>`; a hosted
## third-party plugin is what the host loaded for it; a plugin this machine lacks (the project kept it
## as it came, `unhosted`) is `missing: true`. Anything else, such as a slot Reaper holds or a guest
## sees on the wire without the host's marker, is `{}`: the registry has nothing to say about it. Formats are lower case.


## The plugin in slot state `f`, asked of `backend` (the DAW's), or `{}`.
static func of(f: MixState.FXState, backend: Object) -> Dictionary:
	if f == null:
		return {}
	if f.has_meta(&"unhosted"):
		var kept: Dictionary = f.get_meta(&"unhosted")
		return {"format": str(kept.get("plugin_format", f.type)).to_lower(), "id": str(kept.get("plugin_id", "")),
				"name": f.name, "missing": true}
	if f.host_key != "" and backend is GodotBackend and (backend as GodotBackend).hosted.has(f.host_key):
		var info: Dictionary = (backend as GodotBackend).hosted.info(f.host_key)
		return {"format": str(info.get("format", "")).to_lower(), "id": str(info.get("id", "")), "name": f.name, "missing": false}
	if f.has_meta(&"plugin_ref"):
		# A guest: the host told it which plugin this is; missing when this machine does not have it.
		var told: Dictionary = f.get_meta(&"plugin_ref")
		return {"format": told["format"], "id": told["id"], "name": told["name"], "missing": not installed(told["format"], told["id"])}
	for kind in FXCatalogue.kinds():
		if FXCatalogue.kinds()[kind]["name"] == f.name:
			return {"format": "godot", "id": String(kind), "name": f.name, "missing": false}
	return {}


## Whether this machine has the plugin `format` (any case) calls `id` in its scan.
static func installed(format: String, id: String) -> bool:
	for pl: Dictionary in PluginCatalogue.shared().plugins():
		if str(pl["format"]).to_lower() == format.to_lower() and pl["id"] == id:
			return true
	return false
