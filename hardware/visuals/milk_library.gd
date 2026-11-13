class_name MilkLibrary
extends RefCounted

## Every picture a MilkScreen can show, in one numbered list (docs/visuals.md): the built-in looks
## (MilkPresets) first, then the player's own `.milk` files from `user://milk/own/` (any folders deep),
## then the downloaded pack in `user://milk/cream-of-the-crop/` (MilkDownload), its folders kept as
## categories. Only names and paths are listed at start; a file is read and compiled when it is shown
## (`player`), and what was found then (approximate, broken) is remembered for the finder.
##
## The shuffle (a screen moving on by itself) draws from the built-ins and the player's own, and from the
## pack too unless the player turns that off in the finder (`set_shuffle_pack`, kept in user://visuals.cfg).

const BUILT_IN := "BUILT-IN"
const OWN := "YOUR OWN"
const OWN_DIR := "own"
const PACK_DIR := "cream-of-the-crop"

## Where the files live; a test points it somewhere of its own.
static var root := "user://milk"
## Each {name, category, path ("" for a built-in), builtin (its MilkPresets index, or -1), pack}.
static var _entries: Array[Dictionary] = []
static var _scanned := false
## path → notes (PackedStringArray) of a file already played; "broken" for one that would not load.
static var _notes := {}
static var _shuffle_pack := -1
## Players kept for the last few files shown, so going back is instant.
static var _players := {}
static var _player_order: Array[String] = []
const PLAYERS_KEPT := 6


static func own_dir() -> String:
	return root.path_join(OWN_DIR)


static func pack_dir() -> String:
	return root.path_join(PACK_DIR)


static func entries() -> Array[Dictionary]:
	if not _scanned:
		rescan()
	return _entries


## Lists everything again (after a download, a removal, or new files dropped in).
static func rescan() -> void:
	_scanned = true
	_entries.clear()
	for i in MilkPresets.count():
		_entries.append({"name": MilkPresets.preset_name(i), "category": BUILT_IN, "path": "", "builtin": i, "pack": false})
	var own: Array[Dictionary] = []
	_scan(own_dir(), "", own, false)
	own.sort_custom(_by_category_name)
	_entries.append_array(own)
	var pack: Array[Dictionary] = []
	_scan(pack_dir(), "", pack, true)
	pack.sort_custom(_by_category_name)
	_entries.append_array(pack)


static func _by_category_name(a: Dictionary, b: Dictionary) -> bool:
	if a.category != b.category:
		return String(a.category).naturalnocasecmp_to(b.category) < 0
	return String(a.name).naturalnocasecmp_to(b.name) < 0


static func _scan(dir: String, rel: String, out: Array[Dictionary], pack: bool) -> void:
	var d := DirAccess.open(dir.path_join(rel))
	if d == null:
		return
	d.include_hidden = false
	for f in d.get_files():
		if f.get_extension().to_lower() == "milk":
			var category := OWN if not pack else (rel if rel != "" else "PACK")
			if not pack and rel != "":
				category = OWN + " / " + rel
			out.append({"name": f.get_basename(), "category": category, "path": dir.path_join(rel).path_join(f),
					"builtin": -1, "pack": pack})
	for sub in d.get_directories():
		_scan(dir, rel.path_join(sub) if rel != "" else sub, out, pack)


static func count() -> int:
	return entries().size()


static func entry(i: int) -> Dictionary:
	var e := entries()
	return e[posmod(i, e.size())]


static func preset_name(i: int) -> String:
	return String(entry(i).name)


static func category(i: int) -> String:
	return String(entry(i).category)


static func is_builtin(i: int) -> bool:
	return int(entry(i).builtin) >= 0


## The categories, in list order: BUILT-IN, then the player's own, then the pack's folders.
static func categories() -> PackedStringArray:
	var out := PackedStringArray()
	for e in entries():
		if not out.has(e.category):
			out.append(e.category)
	return out


## How many of the list come from the pack.
static func pack_count() -> int:
	var n := 0
	for e in entries():
		if e.pack:
			n += 1
	return n


## What is known of picture `i`'s fidelity: notes from when it was played, or empty.
static func notes(i: int) -> PackedStringArray:
	var p := String(entry(i).path)
	return _notes.get(p, PackedStringArray()) if p != "" else PackedStringArray()


static func is_broken(i: int) -> bool:
	return notes(i).has("broken")


## The player for file picture `i`, made (read, compiled) if it is not kept; null for a built-in or a file
## that could not be read.
static func player(i: int) -> MilkPlayer:
	var e := entry(i)
	var p := String(e.path)
	if p == "":
		return null
	if _players.has(p):
		_player_order.erase(p)
		_player_order.append(p)
		return _players[p]
	var f := MilkFile.load_path(p)
	if f == null:
		_notes[p] = PackedStringArray(["broken"])
		return null
	var pl := MilkPlayer.new(f)
	_notes[p] = pl.notes
	_players[p] = pl
	_player_order.append(p)
	while _player_order.size() > PLAYERS_KEPT:
		_players.erase(_player_order.pop_front())
	return pl


## Whether the shuffle includes the downloaded pack.
static func shuffle_pack() -> bool:
	if _shuffle_pack < 0:
		var cfg := ConfigFile.new()
		_shuffle_pack = 1
		if cfg.load(VisualBudget.CONFIG) == OK:
			_shuffle_pack = 1 if bool(cfg.get_value("milk", "shuffle_pack", true)) else 0
	return _shuffle_pack == 1


static func set_shuffle_pack(on: bool, keep := true) -> void:
	_shuffle_pack = 1 if on else 0
	if keep:
		var cfg := ConfigFile.new()
		cfg.load(VisualBudget.CONFIG)
		cfg.set_value("milk", "shuffle_pack", on)
		cfg.save(VisualBudget.CONFIG)


## A picture for the shuffle other than `not_this`: any of the built-ins and the player's own, and the
## pack's when included; never one known to be broken.
static func pick_random(not_this: int) -> int:
	var e := entries()
	var n := e.size()
	if n <= 1:
		return 0
	var pool := n if shuffle_pack() else n - pack_count()
	for tries in 12:
		var i := randi() % maxi(pool, 1)
		if i != not_this and not is_broken(i):
			return i
	return posmod(not_this + 1, maxi(pool, 1))


## Forget everything (a test).
static func reset() -> void:
	_scanned = false
	_entries.clear()
	_notes.clear()
	_players.clear()
	_player_order.clear()
	_shuffle_pack = -1
