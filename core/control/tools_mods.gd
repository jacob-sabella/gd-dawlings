extends RefCounted

## Control tools: mods and help. See core/control/control_tools.gd and docs/mcp_assistant.md.
##
## `mods_*`: what ModRegistry holds, and the few things the player may do to the mods they installed (turn one off,
## take one away, bring one in). A mod is data only (docs/mods.md rule 1): nothing here writes a manifest or any
## file of a mod, `mods_import` only copies a folder or zip that ModShare.check accepts, and the shipped (builtin)
## mods are read-only here.
##
## A turned-off mod is its folder renamed with a dot in front (`.off_<name>`) in the player's mods folder, which
## the registry skips; so no registry change was needed and the mod's files stay where they were.
##
## `help_*`: what the game ships to read: docs/*.md (when the build has them), module help cards, the stations'
## help lines, the F1 card's pages, and an overview of these tools generated from the registry.

const OFF := ".off_"
const DOC_ROOT := "res://docs"
const SECTION_MAX := 6000
const ENTRIES_MAX := 120

## Where user mods live; "" is the player's own folder (DataHome "mods"). The suite points it at a scratch folder.
static var user_root := ""
## docs path -> [{level, heading, from, to}] lines, built on first use.
static var _docs: Dictionary = {}
static var _doc_text: Dictionary = {}


static func register(api: ControlApi) -> void:
	_register_mods(api)
	_register_help(api)


# --- mods -----------------------------------------------------------------------------------------

static func _register_mods(api: ControlApi) -> void:
	api.add(ControlTool.make("mods_list",
			"List every mod: id, name, version, author, kind (what it provides, e.g. 'rack_module x3'), origin ('builtin' = shipped with the game, read-only; 'user' = installed by the player; 'external' = from a development folder), enabled (false for a mod the player turned off), status ('ok' or 'unavailable') and problems (a count). Mods are data only: rack modules, presets, skins, plugin names.",
			{"origin": ControlTool.str_p("only mods of this origin", ["builtin", "user", "external"])}, [], ControlTool.READ, _list))
	api.add(ControlTool.make("mods_get",
			"One mod in full: manifest fields, licence, source, what it provides (entries, up to %d), the mods it requires and its problems." % ENTRIES_MAX,
			{"id": ControlTool.str_p("the mod's id from mods_list, e.g. 'builtin.presets'")}, ["id"], ControlTool.READ, _get_mod))
	api.add(ControlTool.make("mods_enable",
			"Turn a user mod back on after mods_disable. Builtin mods are always on and are refused.",
			{"id": ControlTool.str_p("the mod's id")}, ["id"], ControlTool.EDIT, _enable))
	api.add(ControlTool.make("mods_disable",
			"Turn a user mod off: the game stops seeing it (a patch that uses its modules loses them) until mods_enable. Its files are kept. Builtin mods cannot be disabled.",
			{"id": ControlTool.str_p("the mod's id")}, ["id"], ControlTool.EDIT, _disable))
	api.add(ControlTool.make("mods_remove",
			"Delete a user mod and its files from the player's mods folder. Builtin mods cannot be removed.",
			{"id": ControlTool.str_p("the mod's id")}, ["id"], ControlTool.DESTRUCTIVE, _remove))
	api.add(ControlTool.make("mods_import",
			"Install a mod from a folder or a .zip the player named. It goes through the same checks as a mod received in a session: data files only (json, png, jpg, ogg, wav, glb, txt, md), small, a valid mod.json that is not a builtin id, and the registry must accept it; a mod with problems is refused and the reason says why. Nothing is run.",
			{"path": ControlTool.str_p("absolute path of a mod folder or a .zip of one; no '..'")}, ["path"], ControlTool.EDIT, _import))
	api.add(ControlTool.make("mods_problems",
			"The problems the last scan of the mods found (a bad manifest, a missing file, an id used twice, a missing dependency...), each with code, mod, entry, severity and message.",
			{"mod": ControlTool.str_p("only this mod's id"), "limit": ControlTool.int_p("at most this many (default 50)", 1, 500)}, [], ControlTool.READ, _problems))
	api.add(ControlTool.make("mods_reload",
			"Scan the mod folders again (after the player edited a mod by hand). Says how many mods and problems there are.",
			{}, [], ControlTool.EDIT, _reload))


static func _reg() -> ModRegistry:
	return ModRegistry.ensure_current()


static func _root() -> String:
	var r := user_root if user_root != "" else DataHome.dir("mods")
	return r.trim_suffix("/")


## 'builtin', 'user' or 'external' for the mod folder `folder`.
static func _origin(folder: String) -> String:
	var reg := _reg()
	for s in reg.shipped_roots:
		if folder.begins_with(s):
			return "builtin"
	var root := _root()
	if root != "" and folder.begins_with(root + "/"):
		return "user"
	return "external"


static func _problem_row(p: ModProblem) -> Dictionary:
	return {"code": String(p.code), "mod": p.mod, "entry": p.entry, "severity": String(p.severity), "message": p.message}


static func _row(m: ModManifest, reason: String, enabled: bool) -> Dictionary:
	return {"id": m.id, "name": m.mod_name, "version": m.version, "author": m.author, "kind": ModListing.kind_text(m),
			"origin": _origin(m.folder) if enabled else "user", "enabled": enabled,
			"status": ModListing.OK if reason == "" else ModListing.UNAVAILABLE, "reason": reason,
			"problems": m.problems.size()}


## The mods the player turned off: [ManifestOfFolder] in the user root.
static func _disabled() -> Array[ModManifest]:
	var out: Array[ModManifest] = []
	var root := _root()
	if root == "":
		return out
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	dir.include_hidden = true
	var names := Array(dir.get_directories())
	names.sort()
	for n in names:
		if str(n).begins_with(OFF):
			out.append(ModManifest.load_folder(root.path_join(n)))
	return out


static func _find_off(id: String) -> ModManifest:
	for m in _disabled():
		if m.id == id:
			return m
	return null


static func _list(a: Dictionary) -> Dictionary:
	var out: Array = []
	var want := str(a.get("origin", ""))
	for r in ModListing.rows(_reg()):
		var folder := str(r.get("folder", ""))
		var m: ModManifest = _reg().mod(str(r["id"]))
		var origin := _origin(folder)
		if want != "" and origin != want:
			continue
		out.append({"id": r["id"], "name": r["name"], "version": r["version"], "author": m.author if m != null else "",
				"kind": r["kind"], "origin": origin, "enabled": true, "status": r["status"], "reason": r["reason"],
				"problems": m.problems.size() if m != null else 1})
	if want == "" or want == "user":
		for m in _disabled():
			out.append(_row(m, "", false))
	return ControlTool.ok({"mods": out, "count": out.size()})


static func _get_mod(a: Dictionary) -> Dictionary:
	var id := str(a["id"])
	var m: ModManifest = _reg().mod(id)
	var enabled := true
	if m == null:
		m = _find_off(id)
		enabled = false
	if m == null:
		return ControlTool.fail("no mod '%s'; mods_list shows the ids" % id)
	var entries: Array = []
	for e in m.entries:
		if entries.size() >= ENTRIES_MAX:
			break
		entries.append(e)
	var rejected := false
	for r in _reg().rejected():
		if (r["manifest"] as ModManifest) == m:
			rejected = true
	return ControlTool.ok({"id": m.id, "name": m.mod_name, "version": m.version, "author": m.author, "description": m.description,
			"origin": _origin(m.folder) if enabled else "user", "enabled": enabled,
			"status": String(m.status), "rejected": rejected,
			"licence": m.licence, "source": m.source, "requires": m.requires, "min_game_version": m.min_game_version,
			"kind": ModListing.kind_text(m), "entries": entries, "entry_count": m.entries.size(),
			"problems": m.problems.map(func(p: ModProblem) -> Dictionary: return _problem_row(p))})


## The user mod `id` as {ok, folder, enabled} or a refusal that says why not.
static func _user_mod(id: String, verb: String) -> Dictionary:
	var m: ModManifest = _reg().mod(id)
	if m != null:
		match _origin(m.folder):
			"builtin":
				return ControlTool.fail("%s is a builtin mod, always on and part of the game; only mods the player installed can be %s" % [id, verb])
			"external":
				return ControlTool.fail("%s comes from a development folder (DAWLINGS_MODS), not the player's mods folder; it cannot be %s from here" % [id, verb])
		return {"ok": true, "folder": m.folder, "enabled": true}
	var off := _find_off(id)
	if off != null:
		return {"ok": true, "folder": off.folder, "enabled": false}
	return ControlTool.fail("no mod '%s'; mods_list shows the ids" % id)


static func _disable(a: Dictionary) -> Dictionary:
	var id := str(a["id"])
	var u := _user_mod(id, "disabled")
	if not u["ok"]:
		return u
	if not u["enabled"]:
		return ControlTool.ok({"id": id, "enabled": false, "note": "it was already off"})
	var folder: String = u["folder"]
	var to := folder.get_base_dir().path_join(OFF + folder.get_file())
	if DirAccess.dir_exists_absolute(to):
		return ControlTool.fail("a turned-off copy of %s is already there; remove it first" % folder.get_file())
	if DirAccess.rename_absolute(folder, to) != OK:
		return ControlTool.fail("this machine could not turn %s off" % id)
	_reg().reload()
	return ControlTool.ok({"id": id, "enabled": false})


static func _enable(a: Dictionary) -> Dictionary:
	var id := str(a["id"])
	var u := _user_mod(id, "enabled")
	if not u["ok"]:
		return u
	if u["enabled"]:
		return ControlTool.ok({"id": id, "enabled": true, "note": "it was already on"})
	var folder: String = u["folder"]
	var to := folder.get_base_dir().path_join(folder.get_file().trim_prefix(OFF))
	if DirAccess.dir_exists_absolute(to):
		return ControlTool.fail("a folder called %s is already there; the mod cannot come back until it is moved" % to.get_file())
	if DirAccess.rename_absolute(folder, to) != OK:
		return ControlTool.fail("this machine could not turn %s on" % id)
	_reg().reload()
	var m: ModManifest = _reg().mod(id)
	var why := ""
	if m == null:
		why = "the registry did not take it in; mods_problems says why"
	return ControlTool.ok({"id": id, "enabled": m != null, "note": why})


static func _remove(a: Dictionary) -> Dictionary:
	var id := str(a["id"])
	var u := _user_mod(id, "removed")
	if not u["ok"]:
		return u
	var folder: String = u["folder"]
	ModShare.remove_tree(folder)
	if DirAccess.dir_exists_absolute(folder):
		return ControlTool.fail("this machine could not delete all of %s" % id)
	_reg().reload()
	return ControlTool.ok({"id": id, "removed": true})


static func _problems(a: Dictionary) -> Dictionary:
	var out: Array = []
	var only := str(a.get("mod", ""))
	var cap := int(a.get("limit", 50))
	var total := 0
	for p in _reg().problems():
		if only != "" and p.mod != only:
			continue
		total += 1
		if out.size() < cap:
			out.append(_problem_row(p))
	return ControlTool.ok({"problems": out, "count": total})


static func _reload(_a: Dictionary) -> Dictionary:
	var reg := _reg()
	reg.reload()
	return ControlTool.ok({"mods": reg.mods().size(), "rejected": reg.rejected().size(), "problems": reg.problems().size()})


## Why `path` may not be imported, or "".
static func _path_problem(path: String) -> String:
	if path.strip_edges() == "":
		return "no path"
	var p := path.replace("\\", "/")
	if ".." in p.split("/"):
		return "a path with '..' is refused"
	if p.begins_with("res://"):
		return "the game's own files are not an import source"
	return ""


static func _import(a: Dictionary) -> Dictionary:
	var path := str(a["path"]).strip_edges()
	var bad := _path_problem(path)
	if bad != "":
		return ControlTool.fail(bad)
	var is_dir := DirAccess.dir_exists_absolute(path)
	var is_zip := not is_dir and FileAccess.file_exists(path) and path.get_extension().to_lower() == "zip"
	if not is_dir and not is_zip:
		if FileAccess.file_exists(path):
			return ControlTool.fail("%s is a file but not a .zip; give a mod folder or a .zip of one" % path)
		return ControlTool.fail("nothing at %s; give the path of a mod folder or a .zip" % path)
	var files := {}
	if is_dir:
		var read := ModShare.read_folder(path)
		if str(read["why"]) != "":
			return ControlTool.fail("this folder cannot be a mod: %s" % read["why"])
		files = read["files"]
	else:
		var z := _read_zip(path)
		if not z["ok"]:
			return z
		files = z["files"]
	var why := ModShare.check(files)
	if why != "":
		return ControlTool.fail("not a mod the game will take in: %s" % why)
	var info := ModShare.describe(files)
	var id := str(info["id"])
	var reg := _reg()
	if reg.mod(id) != null or _find_off(id) != null:
		return ControlTool.fail("a mod with id %s is already installed; mods_remove it first to replace it" % id)
	var root := _root()
	if root == "":
		return ControlTool.fail("this machine has no mods folder to install into")
	var err := ModShare.install(files, id, root)
	if err != "":
		return ControlTool.fail(err)
	reg.reload()
	var m: ModManifest = reg.mod(id)
	var reasons: Array[String] = []
	for r in reg.rejected():
		if (r["manifest"] as ModManifest).id == id:
			reasons.append(str(r["reason"]))
	if m == null or not reasons.is_empty() or m.status != ModManifest.STATUS_OK:
		for p in reg.problems():
			if p.mod == id and p.is_error():
				reasons.append(p.message)
		ModShare.remove_tree(root.path_join(id))
		reg.reload()
		return ControlTool.fail("the mod %s was refused and nothing was installed: %s" % [id, "; ".join(reasons) if not reasons.is_empty() else "the registry did not take it in"])
	var warnings: Array = []
	for p in m.problems:
		warnings.append(p.message)
	return ControlTool.ok({"id": id, "name": info["name"], "version": info["version"], "files": info["count"], "warnings": warnings})


## A zip as a file set, `{ok: true, files}`, judged by the central directory's sizes before any file is inflated.
static func _read_zip(path: String) -> Dictionary:
	var sizes := _zip_sizes(path)
	if sizes.has("error"):
		return ControlTool.fail(str(sizes["error"]))
	if sizes.size() > ModShare.MAX_FILES:
		return ControlTool.fail("the zip holds more than %d files" % ModShare.MAX_FILES)
	var total := 0
	for n: String in sizes:
		if int(sizes[n]) > ModShare.MAX_FILE_BYTES:
			return ControlTool.fail("%s in the zip is over %d MB" % [n.left(40), ModShare.MAX_FILE_BYTES / (1024 * 1024)])
		total += int(sizes[n])
	if total > ModShare.MAX_TOTAL_BYTES:
		return ControlTool.fail("the zip is over %d MB unpacked" % (ModShare.MAX_TOTAL_BYTES / (1024 * 1024)))
	var zr := ZIPReader.new()
	if zr.open(path) != OK:
		return ControlTool.fail("%s cannot be opened as a zip" % path)
	var names: Array[String] = []
	for n in zr.get_files():
		if not str(n).ends_with("/"):
			names.append(str(n))
	# One top folder around the mod (how a zipped folder usually comes) is taken off.
	var prefix := ""
	if not names.has("mod.json"):
		var top := names[0].get_slice("/", 0) + "/" if not names.is_empty() else ""
		var all_under := top != "/" and top != ""
		for n in names:
			all_under = all_under and n.begins_with(top)
		if all_under and names.has(top + "mod.json"):
			prefix = top
	var files := {}
	for n in names:
		files[n.trim_prefix(prefix)] = zr.read_file(n)
	zr.close()
	return {"ok": true, "files": files}


## name -> uncompressed size, from the zip's central directory; or {error}.
static func _zip_sizes(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"error": "%s cannot be read" % path}
	var size := f.get_length()
	var tail := mini(size, 65557)
	f.seek(size - tail)
	var buf := f.get_buffer(tail)
	var at := -1
	for i in range(buf.size() - 22, -1, -1):
		if buf.decode_u32(i) == 0x06054b50:
			at = i
			break
	if at < 0:
		return {"error": "%s is not a zip" % path}
	var count := buf.decode_u16(at + 10)
	var off := buf.decode_u32(at + 16)
	if count == 0xFFFF or off == 0xFFFFFFFF:
		return {"error": "a zip64 file is not accepted"}
	if count > 4096:
		return {"error": "the zip holds more than %d files" % ModShare.MAX_FILES}
	f.seek(off)
	var out := {}
	for i in count:
		var head := f.get_buffer(46)
		if head.size() < 46 or head.decode_u32(0) != 0x02014b50:
			return {"error": "the zip's directory is damaged"}
		var usize := head.decode_u32(24)
		var nlen := head.decode_u16(28)
		var skip := head.decode_u16(30) + head.decode_u16(32)
		var nm := f.get_buffer(nlen).get_string_from_utf8()
		f.seek(f.get_position() + skip)
		if not nm.ends_with("/"):
			if usize == 0xFFFFFFFF:
				return {"error": "a zip64 file is not accepted"}
			out[nm] = usize
	return out


# --- help -----------------------------------------------------------------------------------------

static func _register_help(api: ControlApi) -> void:
	api.add(ControlTool.make("help_search",
			"Search what the game ships to read: the docs (docs/*.md by heading and text) and the rack's module help cards (by name and description). Returns titles, doc paths and short snippets; read one with help_get. Use it to answer 'how does X work' before guessing.",
			{"query": ControlTool.str_p("words, all of which must appear"), "limit": ControlTool.int_p("at most this many hits (default 10)", 1, 40)},
			["query"], ControlTool.READ, _search))
	api.add(ControlTool.make("help_get",
			"Read part of a doc: the section under a heading (with its subsections) of a doc from help_search, at most %d characters; pass offset to read on. Without a heading it gives the doc's outline." % SECTION_MAX,
			{"path": ControlTool.str_p("a doc from help_search, e.g. 'docs/rack.md' or just 'rack'"),
					"heading": ControlTool.str_p("a heading of that doc (exact, or part of it)"),
					"offset": ControlTool.int_p("characters to skip, to read on (default 0)", 0)},
			["path"], ControlTool.READ, _get_doc))
	api.add(ControlTool.make("help_stations",
			"The stations (instruments and gear in the room): id, title, where, and what each is for, with the mouse-and-keys help and the hands-and-buttons help the game shows for it.",
			{"query": ControlTool.str_p("only stations whose title or help has these words")}, [], ControlTool.READ, _stations))
	api.add(ControlTool.make("help_keys",
			"The controls help the game shows on F1: pages START, TOGETHER and ROOM as name/text lines (the PLAY page is the station list: help_stations).",
			{"page": ControlTool.str_p("only this page", ["START", "TOGETHER", "ROOM"])}, [], ControlTool.READ, _keys))
	api.add(ControlTool.make("help_game",
			"Orient yourself: what this tool API covers, by domain, with each domain's tool names. Pass domain for that domain's tools with their summaries. Start here.",
			{"domain": ControlTool.str_p("one domain, e.g. 'rack'")}, [], ControlTool.READ, func(a: Dictionary) -> Dictionary: return _game(api, a)))


static func _doc_paths() -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(DOC_ROOT):
		if str(f).get_extension() == "md":
			out.append(DOC_ROOT.path_join(f))
	for d in DirAccess.get_directories_at(DOC_ROOT):
		for f in DirAccess.get_files_at(DOC_ROOT.path_join(d)):
			if str(f).get_extension() == "md":
				out.append(DOC_ROOT.path_join(d).path_join(f))
	out.sort()
	return out


## The lines of a doc and its headings [{level, heading, line}], cached.
static func _doc(path: String) -> Dictionary:
	if _docs.has(path):
		return {"lines": _doc_text[path], "heads": _docs[path]}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var lines := f.get_as_text().split("\n")
	var heads: Array = []
	var fenced := false
	for i in lines.size():
		var l := lines[i]
		if l.begins_with("```"):
			fenced = not fenced
		elif not fenced and l.begins_with("#"):
			var lvl := 0
			while lvl < l.length() and l[lvl] == "#":
				lvl += 1
			if lvl <= 6 and l.substr(lvl).begins_with(" "):
				heads.append({"level": lvl, "heading": l.substr(lvl).strip_edges(), "line": i})
	_docs[path] = heads
	_doc_text[path] = lines
	return {"lines": lines, "heads": heads}


static func _short(p: String) -> String:
	return p.trim_prefix("res://")


## The doc `ref` names ('docs/rack.md', 'res://docs/rack.md', 'rack'), from the docs the build has, or "".
static func _resolve_doc(ref: String) -> String:
	var r := ref.strip_edges().trim_prefix("res://")
	for p in _doc_paths():
		var s := _short(p)
		if s == r or s == r + ".md" or s == "docs/" + r or s == "docs/" + r + ".md":
			return p
	return ""


static func _snippet(text: String, words: PackedStringArray) -> String:
	var low := text.to_lower()
	var at := -1
	for w in words:
		var i := low.find(w)
		if i >= 0 and (at < 0 or i < at):
			at = i
	if at < 0:
		return text.left(160).strip_edges()
	var from := maxi(at - 60, 0)
	var s := text.substr(from, 180).replace("\n", " ").strip_edges()
	return ("..." if from > 0 else "") + s + ("..." if from + 180 < text.length() else "")


static func _search(a: Dictionary) -> Dictionary:
	var words := str(a["query"]).to_lower().split(" ", false)
	if words.is_empty():
		return ControlTool.fail("give at least one word to search for")
	var cap := int(a.get("limit", 10))
	var hits: Array = []
	for path in _doc_paths():
		var d := _doc(path)
		if d.is_empty():
			continue
		var lines: PackedStringArray = d["lines"]
		var heads: Array = d["heads"]
		for h in range(heads.size()):
			var from: int = heads[h]["line"]
			var to: int = heads[h + 1]["line"] if h + 1 < heads.size() else lines.size()
			var body := "\n".join(lines.slice(from + 1, to))
			var title := str(heads[h]["heading"])
			var hay := (title + "\n" + body).to_lower()
			var score := 0
			var all := true
			for w in words:
				if not hay.contains(w):
					all = false
					break
				if title.to_lower().contains(w):
					score += 10
				score += mini(hay.count(w), 5)
			if all:
				hits.append({"score": score, "kind": "doc", "title": title, "path": _short(path),
						"heading": title, "snippet": _snippet(body if body.strip_edges() != "" else title, words)})
	hits.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["score"] > y["score"])
	var out: Array = []
	for h in hits:
		if out.size() >= cap:
			break
		h.erase("score")
		out.append(h)
	for type in RackCatalogue.types():
		if out.size() >= cap + 10:
			break
		var spec := RackCatalogue.spec(type)
		var hay := ("%s %s %s %s" % [type, spec.get("title", ""), spec.get("group", ""), spec.get("blurb", "")]).to_lower()
		var all := true
		for w in words:
			if not hay.contains(w):
				all = false
		if all:
			out.append({"kind": "module", "title": str(spec.get("title", type)), "type": type,
					"snippet": str(spec.get("blurb", "")).left(160), "path": "", "heading": ""})
	return ControlTool.ok({"hits": out, "count": out.size(), "docs_available": not _doc_paths().is_empty()})


static func _get_doc(a: Dictionary) -> Dictionary:
	var path := _resolve_doc(str(a["path"]))
	if path == "":
		return ControlTool.fail("no doc '%s' in this build; help_search finds them" % str(a["path"]))
	var d := _doc(path)
	if d.is_empty():
		return ControlTool.fail("%s cannot be read" % _short(path))
	var lines: PackedStringArray = d["lines"]
	var heads: Array = d["heads"]
	var want := str(a.get("heading", "")).strip_edges().to_lower().lstrip("# ")
	var offset := int(a.get("offset", 0))
	if want == "":
		var outline: Array = []
		for h in heads:
			outline.append("%s%s" % ["  ".repeat(maxi(int(h["level"]) - 1, 0)), h["heading"]])
		return ControlTool.ok({"path": _short(path), "outline": outline, "note": "pass heading to read a section"})
	var pick := -1
	for i in heads.size():
		if str(heads[i]["heading"]).to_lower() == want:
			pick = i
			break
	if pick < 0:
		for i in heads.size():
			if str(heads[i]["heading"]).to_lower().contains(want):
				pick = i
				break
	if pick < 0:
		return ControlTool.fail("no heading like '%s' in %s; call help_get with only the path for its outline" % [want, _short(path)])
	var lvl: int = heads[pick]["level"]
	var end := lines.size()
	for j in range(pick + 1, heads.size()):
		if int(heads[j]["level"]) <= lvl:
			end = heads[j]["line"]
			break
	var text := "\n".join(lines.slice(heads[pick]["line"], end))
	var total := text.length()
	var part := text.substr(offset, SECTION_MAX)
	var more := offset + SECTION_MAX < total
	return ControlTool.ok({"path": _short(path), "heading": heads[pick]["heading"], "text": part, "chars": total,
			"truncated": more, "next_offset": offset + SECTION_MAX if more else -1})


static func _stations(a: Dictionary) -> Dictionary:
	var words := str(a.get("query", "")).to_lower().split(" ", false)
	var out: Array = []
	for r: Dictionary in Stations.ALL + Stations.HELD:
		var area := StringName(r.get("area", &""))
		var hay := ("%s %s %s" % [r.get("title", ""), r.get("desk", ""), r.get("hands", "")]).to_lower()
		var all := true
		for w in words:
			if not hay.contains(w):
				all = false
		if not all:
			continue
		out.append({"id": str(r.get("id", "")), "title": r.get("title", ""),
				"where": Stations.AREA_TITLES.get(area, ""), "with_mouse_and_keys": r.get("desk", ""),
				"with_hands": r.get("hands", "")})
	return ControlTool.ok({"stations": out, "count": out.size()})


static func _keys(a: Dictionary) -> Dictionary:
	var pages := {"START": WelcomeCard.START, "TOGETHER": WelcomeCard.TOGETHER, "ROOM": WelcomeCard.ROOM}
	var out: Array = []
	for p: String in pages:
		if str(a.get("page", "")) not in ["", p]:
			continue
		var rows: Array = []
		for r: Array in pages[p]:
			rows.append({"name": r[0], "text": r[1]})
		out.append({"page": p, "items": rows})
	return ControlTool.ok({"pages": out, "note": "the PLAY page lists the stations: help_stations"})


const ABOUT := {
	"project": "the song file: open, save, tempo, time signatures, markers, regions, lyrics",
	"transport": "play, stop, record, seek, loop, metronome, punch",
	"track": "tracks: add, name, colour, order, arm, input, monitor, freeze",
	"mix": "volume, pan, width, mute, solo, groups, sends, sidechain, the master",
	"fx": "the plugin chain of a track: add, remove, move, bypass, parameters, presets",
	"item": "clips and takes on the timeline, and their MIDI notes and controller lanes",
	"note": "MIDI notes inside a clip",
	"automation": "automation lanes of controls",
	"rack": "the modular rack: modules, cables, knobs, presets, the module catalogue and finder, module help",
	"room": "the 3D studio: venue, layout, pieces, stations, items, weather",
	"mods": "the mods installed (data only: rack modules, presets, plugin names): list, enable, disable, import, remove",
	"look": "read-only views: screenshots, meters, scope and spectrum, where the player is",
	"help": "the game's own docs, module help, stations and key lists",
	"requests": "writing down a feature request, bug or idea for the developers, and listing those written",
	"changes": "the change sets made through this API, and undoing the newest",
	"tools": "finding tools by words",
	"batch": "many calls in one change set",
}


static func _game(api: ControlApi, a: Dictionary) -> Dictionary:
	var want := str(a.get("domain", ""))
	if want != "":
		var rows: Array = []
		var names := api.tools.keys()
		names.sort()
		for n in names:
			var t: ControlTool = api.tools[n]
			if t.domain == want:
				rows.append({"name": t.name, "tier": ["read", "edit", "destructive"][t.tier], "summary": t.summary})
		if rows.is_empty():
			return ControlTool.fail("no domain '%s'; the domains are: %s" % [want, ", ".join(api.domains())])
		return ControlTool.ok({"domain": want, "about": ABOUT.get(want, ""), "tools": rows})
	var domains: Array = []
	for d in api.domains():
		var names: Array = []
		var keys := api.tools.keys()
		keys.sort()
		for n in keys:
			if (api.tools[n] as ControlTool).domain == d:
				names.append(n)
		domains.append({"domain": d, "about": ABOUT.get(d, ""), "tool_count": names.size(), "tools": names})
	return ControlTool.ok({"overview": "Tools are named <domain>_<op> (list, get, add, set, remove, or an action). Tracks, FX, modules and items are addressed by name or '#number' as the list tools show them. Tier 'destructive' tools ask the player first. Use batch for many calls, changes_undo to take back the last change set, help_search to read the game's docs.",
			"tool_count": api.tools.size(), "domains": domains})
