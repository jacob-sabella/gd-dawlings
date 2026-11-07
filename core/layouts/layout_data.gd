class_name LayoutData
extends RefCounted

## A parsed and checked layout file (docs/layouts.md section 5): one room's, or one fragment's, shell
## choice, mood, zones, pieces, groups and wiring. `parse` never throws: whatever is wrong becomes a
## LayoutProblem and `status` says whether the layout can be used. Pure data; nothing here is placed or
## built (LayoutResolver, step 3) and the game does not read layouts yet. A file is turned into the
## room it describes by LayoutSet.resolve, which merges its `extends` fragments and one variant.

const FORMAT := "dawlings.layout"
const VERSION := 1
## docs/refactor_loop.md decision 7.
const MAX_PIECES := 64
const STATUS_OK := &"ok"
const STATUS_INVALID := &"invalid"
## The keys of a layout body: what fragments and variants merge (LayoutMerge).
const BODY_KEYS: Array[String] = ["shell", "mood", "zones", "pieces", "groups", "wiring"]
## What a variant may carry beside its title.
const VARIANT_KEYS: Array[String] = ["title", "zones", "pieces", "groups", "wiring"]
const TOP_KEYS: Array[String] = ["$schema", "format", "version", "id", "title", "extends", "order",
		"shell", "mood", "zones", "pieces", "groups", "wiring", "variants"]
## Dotted ids allowed, so `common.live_room` is a layout id.
const _ID_RE := "^[a-z][a-z0-9_-]{0,39}(\\.[a-z][a-z0-9_-]{0,39})*$"

var id := ""
var title := ""
## Position in the venue cycle, or -1 for a room that is not cycled (`"order": null` or absent).
var order := -1
## Ids of the fragments this layout extends, in merge order (later wins).
var extends_ids: Array[String] = []
## shell, mood, zones, pieces, groups, wiring: the parts that were present, as written.
var body: Dictionary = {}
## The variants as written: each `{title, zones?, pieces?, groups?, wiring?}`.
var variants: Array[Dictionary] = []
## STATUS_OK or STATUS_INVALID (a body is only kept when the layout is ok).
var status: StringName = STATUS_INVALID
## The file this came from, or "" when parsed from memory.
var path := ""
## Which variant a resolved layout has applied (0 for a file as parsed).
var variant := 0
## The ids merged into a resolved layout, in order, ending with its own.
var chain: Array[String] = []
## Every problem found, in order.
var problems: Array[LayoutProblem] = []


## Reads and parses a file. A missing file is `no_file` and unreadable JSON is `bad_json`; both give
## an invalid layout, never null.
static func load_file(file: String) -> LayoutData:
	var label := file.get_file().trim_suffix(".layout.json")
	if not FileAccess.file_exists(file):
		return _failed(file, label, &"no_file", "no such file")
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(file)) != OK or not json.data is Dictionary:
		var why := "line %d: %s" % [json.get_error_line(), json.get_error_message()] \
				if json.data == null else "the top level must be an object"
		return _failed(file, label, &"bad_json", why)
	return parse(json.data, file)


## Checks `data` (a decoded layout file). `source` is the path it came from, for messages.
static func parse(data: Dictionary, source: String = "") -> LayoutData:
	var l := LayoutData.new()
	l.path = source
	var label: String = data["id"] if data.get("id") is String and not str(data["id"]).is_empty() \
			else source.get_file().trim_suffix(".layout.json")
	l.id = label
	var c := LayoutCheck.new(label, l.problems)
	if not (data.get("format") is String and data["format"] == FORMAT):
		c.bad("format", "format must be \"%s\"" % FORMAT)
		return l
	if not (data.get("version") is float or data.get("version") is int) or int(data["version"]) < 1:
		c.bad("version", "version must be an integer of at least 1")
		return l
	if int(data["version"]) != VERSION:
		c.bad("version", "made for layout format %d; this game reads %d" % [int(data["version"]), VERSION], &"version_unsupported")
		return l
	l._read_identity(data, c)
	c.unknown_keys(data, TOP_KEYS, "")
	l._read_body(data, c, "", BODY_KEYS)
	l._read_variants(data, c)
	if l.problems.any(func(p: LayoutProblem) -> bool: return p.is_error()):
		l.body = {}
		l.variants = []
	else:
		l.status = STATUS_OK
	return l


## True when the problems include `code`.
func has_problem(code: StringName) -> bool:
	return problems.any(func(p: LayoutProblem) -> bool: return p.code == code)


## The problems of error severity.
func errors() -> Array[LayoutProblem]:
	return problems.filter(func(p: LayoutProblem) -> bool: return p.is_error())


## The pieces as written, or after resolving, the placed ones.
func pieces() -> Array:
	return body.get("pieces", [])


## One piece entry by its id, or an empty dictionary.
func piece(piece_id: StringName) -> Dictionary:
	for p: Dictionary in pieces():
		if p.get("id") == str(piece_id):
			return p
	return {}


## The zones, id -> {min, size, grow}.
func zones() -> Dictionary:
	return body.get("zones", {})


## The names of the variants, or this layout's title when it declares none.
func variant_titles() -> Array[String]:
	var out: Array[String] = []
	for v in variants:
		out.append(str(v["title"]))
	if out.is_empty():
		out.append(title)
	return out


## The file form of what was parsed, for tools and tests.
func to_dict() -> Dictionary:
	var out := {"format": FORMAT, "version": VERSION, "id": id, "title": title}
	if not extends_ids.is_empty():
		out["extends"] = extends_ids.duplicate()
	if order >= 0:
		out["order"] = order
	out.merge(body.duplicate(true))
	if not variants.is_empty():
		out["variants"] = variants.duplicate(true)
	return out


static func _failed(file: String, label: String, code: StringName, why: String) -> LayoutData:
	var l := LayoutData.new()
	l.path = file
	l.id = label
	l.problems.append(LayoutProblem.make(code, label, why))
	return l


func _read_identity(data: Dictionary, c: LayoutCheck) -> void:
	if c.text(data.get("id"), _ID_RE, "id", "id"):
		id = data["id"]
	if data.get("title") is String and not str(data["title"]).is_empty() and str(data["title"]).length() <= 60:
		title = data["title"]
	else:
		c.bad("title", "title must be 1 to 60 characters")
	if data.has("order") and data["order"] != null:
		if (data["order"] is float or data["order"] is int) and int(data["order"]) >= 0 and float(data["order"]) == int(data["order"]):
			order = int(data["order"])
		else:
			c.bad("order", "order must be a whole number from 0, or null")
	if data.has("extends"):
		var e: Variant = data["extends"]
		if e is Array and (e as Array).all(func(x: Variant) -> bool: return x is String):
			for x: String in e:
				if RegEx.create_from_string(_ID_RE).search(x) == null:
					c.bad("extends", "'%s' is not a layout id" % x.left(40))
				extends_ids.append(x)
		else:
			c.bad("extends", "extends must be a list of layout ids")


## Checks the body keys present in `src` and keeps them; `where` prefixes the paths.
func _read_body(src: Dictionary, c: LayoutCheck, where: String, keys: Array[String]) -> Dictionary:
	var out := {}
	for key in keys:
		if not src.has(key):
			continue
		var at := (where + "." + key) if where != "" else key
		var v: Variant = src[key]
		match key:
			"shell":
				c.shell(v, at)
			"mood":
				c.mood(v, at)
			"zones":
				c.zones(v, at)
			_:
				_read_list(key, v, c, at)
		out[key] = v.duplicate(true) if v is Array or v is Dictionary else v
	if where == "":
		body = out
	return out


func _read_list(key: String, v: Variant, c: LayoutCheck, at: String) -> void:
	if not v is Array:
		c.bad(at, "must be a list")
		return
	var seen := {}
	for i in (v as Array).size():
		var entry: Variant = v[i]
		var here := "%s[%d]" % [at, i]
		match key:
			"pieces":
				c.piece(entry, here)
			"groups":
				c.group(entry, here)
			_:
				c.wire(entry, here)
		var k := LayoutMerge.identity(key, entry)
		if k != "" and seen.has(k):
			c.bad(here, "'%s' is listed twice" % k, &"duplicate_id")
		seen[k] = true


func _read_variants(data: Dictionary, c: LayoutCheck) -> void:
	if not data.has("variants"):
		return
	var v: Variant = data["variants"]
	if not (v is Array and not (v as Array).is_empty()):
		c.bad("variants", "variants must be a list with at least one entry")
		return
	for i in (v as Array).size():
		var at := "variants[%d]" % i
		var entry: Variant = v[i]
		if not entry is Dictionary:
			c.bad(at, "must be an object")
			continue
		if not (entry.get("title") is String and not str(entry["title"]).is_empty()):
			c.bad(at + ".title", "a variant needs a title")
		c.unknown_keys(entry, VARIANT_KEYS, at)
		var kept := _read_body(entry, c, at, ["zones", "pieces", "groups", "wiring"])
		kept["title"] = entry.get("title", "")
		variants.append(kept)
