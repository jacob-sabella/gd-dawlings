extends RefCounted

## docs/mods.md section 13: a host's user mod travels to a guest as plain data (offer, accept or decline, chunks, hash,
## checks, install) and the plate becomes the live module; the plugin marker (format, id, name) reaches a guest.
## Two `ModSend` nodes stand in for the two machines, wired to each other, each with its own mods folder.
## Called from the `_test_*` wrappers in tests/run_tests.gd.

const TMP := "user://mod_share_test/"
const PLUCK := "res://mods_examples/dawlings.sample.pluck"
const PLUCK_ID := "dawlings.sample.pluck"

var t: Node


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


## A host and a guest `ModSend`, each over a folder of its own; the host has the pluck mod installed.
func _pair(with_pluck := true) -> Dictionary:
	ModShare.remove_tree(TMP.trim_suffix("/"))
	var files := ModShare.read_folder(PLUCK)["files"] as Dictionary
	if with_pluck:
		ModShare.install(files, PLUCK_ID, TMP + "host")
	DirAccess.make_dir_recursive_absolute(TMP + "host")
	DirAccess.make_dir_recursive_absolute(TMP + "guest")
	var host := ModSend.new()
	var guest := ModSend.new()
	host.mods_root = TMP + "host"
	guest.mods_root = TMP + "guest"
	host.registry = ModRegistry.new()
	host.registry.scan([ModRegistry.SHIPPED_ROOT, TMP + "host"])
	guest.registry = ModRegistry.new()
	guest.registry.scan([ModRegistry.SHIPPED_ROOT, TMP + "guest"])
	host.wire = func(_peer: int, method: StringName, args: Array) -> void:
		guest.callv(method, args + ([1] if method == &"offered" else []))
	guest.wire = func(_peer: int, method: StringName, args: Array) -> void:
		host.callv(method, args + [2])
	t.add_child(host)
	t.add_child(guest)
	return {"host": host, "guest": guest, "files": files}


## Host and guest frames until neither has anything left to do (or `frames` pass).
func _pump(pair: Dictionary, frames := 400) -> void:
	for i in frames:
		pair["host"]._process(0.0)
		pair["guest"]._process(0.0)
		if pair["host"].queued() == 0 and pair["host"]._serving.is_empty():
			return


func _done(pair: Dictionary) -> void:
	pair["host"].queue_free()
	pair["guest"].queue_free()
	ModShare.remove_tree(TMP.trim_suffix("/"))


func offer_accept_install_and_the_plate_becomes_the_module() -> void:
	var pair := _pair()
	var host: ModSend = pair["host"]
	var guest: ModSend = pair["guest"]
	check("the host offers its user mods only (not the builtin ones): %s" % [host.shareable()], host.shareable() == [PLUCK_ID])
	host.offer_all_to(2)
	_pump(pair, 3)
	check("the guest sees one offer naming the mod, version, licence and size", guest.pending().size() == 1
			and guest.pending()[0]["meta"]["id"] == PLUCK_ID and guest.pending()[0]["meta"]["size"] > 0
			and guest.pending()[0]["meta"]["licence"] != "" and guest.pending()[0]["meta"]["version"] != "")
	check("nothing is on the guest's disk before it answers", DirAccess.get_directories_at(TMP + "guest").is_empty())
	# The patch the host sent, as the guest's rack reads it: the plate before, the module after.
	var saved := ModRegistry.current
	ModRegistry.current = guest.registry
	RackCatalogue._forget()
	var raw := {"modules": {"pl": {"type": PLUCK_ID, "at": [3, 0], "w": 1, "knobs": {}}}, "uses": {PLUCK_ID: "Pluck"}}
	check("before accepting the module is the unavailable plate", RackPatch.is_missing(RackPatch.sanitize(raw), "pl"))
	var offer_id: int = guest.pending()[0]["offer"]
	guest.accept(offer_id)
	_pump(pair)
	check("accepting installs it under the guest's own mods folder", guest.inbox[0]["state"] == ModSend.INSTALLED
			and FileAccess.file_exists(TMP + "guest/" + PLUCK_ID + "/mod.json"))
	var got := ModShare.read_folder(TMP + "guest/" + PLUCK_ID)["files"] as Dictionary
	check("every file arrived byte for byte", ModShare.digest(got) == ModShare.digest(pair["files"]))
	check("the guest's registry has it live", guest.registry.mod(PLUCK_ID) != null and guest.registry.mod(PLUCK_ID).status == ModManifest.STATUS_OK)
	check("after accepting the plate is the module", not RackPatch.is_missing(RackPatch.sanitize(raw), "pl"))
	check("nothing was left half written", DirAccess.get_directories_at(TMP + "guest") == PackedStringArray([PLUCK_ID]))
	ModRegistry.current = saved
	RackCatalogue._forget()
	_done(pair)


func declining_changes_nothing() -> void:
	var pair := _pair()
	var host: ModSend = pair["host"]
	var guest: ModSend = pair["guest"]
	host.offer_all_to(2)
	_pump(pair, 3)
	guest.decline(guest.pending()[0]["offer"])
	_pump(pair)
	check("a declined offer is declined on both ends and nothing is installed", guest.inbox[0]["state"] == ModSend.DECLINED
			and DirAccess.get_directories_at(TMP + "guest").is_empty() and guest.registry.mod(PLUCK_ID) == null and host.served == 0)
	host.offer_all_to(2)
	check("a declined mod is not asked again this session", host.queued() == 0)
	_done(pair)


func a_guest_who_has_the_mod_is_not_asked() -> void:
	var pair := _pair()
	var guest: ModSend = pair["guest"]
	ModShare.install(pair["files"], PLUCK_ID, TMP + "guest")
	guest.registry.reload()
	pair["host"].offer_all_to(2)
	_pump(pair, 3)
	check("a mod the guest has is noted, not offered", guest.pending().is_empty() and guest.inbox.size() == 1 and guest.inbox[0]["state"] == ModSend.HAVE)
	_done(pair)


## A file set offered, then received with a change: the hash, the paths, the kinds and the sizes refuse it.
func bad_sets_are_refused_whole() -> void:
	var good: Dictionary = ModShare.read_folder(PLUCK)["files"]
	check("the sample mod passes the checks", ModShare.check(good, PLUCK_ID) == "")
	var tampered := good.duplicate()
	tampered["extra.txt"] = "x".to_utf8_buffer()
	check("a changed set has another hash", ModShare.digest(tampered) != ModShare.digest(good))
	for path in ["../evil.json", "/abs/evil.json", "a//b.json", "a\\b.json", ".hidden.json", "c:/x.json", "a/../../b.json"]:
		var set := good.duplicate()
		set[path] = "{}".to_utf8_buffer()
		check("the path %s rejects the whole mod" % path, ModShare.check(set, PLUCK_ID) != "")
	for path in ["lib.so", "run.sh", "x.exe", "noext", "x.gd", "x.dll", "x.dylib", "x.PNG.bin"]:
		var set := good.duplicate()
		set[path] = "x".to_utf8_buffer()
		check("the file %s rejects the whole mod" % path, ModShare.check(set, PLUCK_ID) != "")
	var elf := good.duplicate()
	elf["notes.txt"] = PackedByteArray([0x7f, 0x45, 0x4c, 0x46, 2, 1, 1, 0])
	check("a binary called .txt is refused by its first bytes", ModShare.check(elf, PLUCK_ID) != "")
	var big := good.duplicate()
	big["a.wav"] = PackedByteArray()
	big["a.wav"].resize(ModShare.MAX_FILE_BYTES + 1)
	check("one file over the cap rejects the mod", ModShare.check(big, PLUCK_ID) != "")
	var wide := good.duplicate()
	for i in ModShare.MAX_FILES:
		wide["f%d.txt" % i] = "x".to_utf8_buffer()
	check("too many files rejects the mod", ModShare.check(wide, PLUCK_ID) != "")
	var heavy := good.duplicate()
	for i in 3:
		var b := PackedByteArray()
		b.resize(ModShare.MAX_FILE_BYTES - 1)
		heavy["h%d.wav" % i] = b
	check("a set over the total cap rejects the mod", ModShare.check(heavy, PLUCK_ID) != "")
	var m: Dictionary = JSON.parse_string((good["mod.json"] as PackedByteArray).get_string_from_utf8())
	var native := good.duplicate()
	m["source"] = {"kind": "binary", "path": "x.json"}
	native["mod.json"] = JSON.stringify(m).to_utf8_buffer()
	check("a manifest with a binary source is refused", ModShare.check(native, PLUCK_ID) != "")
	var builtin := good.duplicate()
	m["source"] = {"kind": "data"}
	m["id"] = "builtin.fake"
	builtin["mod.json"] = JSON.stringify(m).to_utf8_buffer()
	check("a builtin id is refused", ModShare.check(builtin, "builtin.fake") != "")
	check("an id other than the one offered is refused", ModShare.check(good, "some.other") != "")
	check("an empty set is refused", ModShare.check({}) != "")


## The guest receives files that are not the ones offered: nothing is installed, the failure is shown.
func a_wrong_hash_or_a_bad_file_installs_nothing() -> void:
	var pair := _pair()
	var host: ModSend = pair["host"]
	var guest: ModSend = pair["guest"]
	host.offer_all_to(2)
	_pump(pair, 3)
	var e: Dictionary = guest.pending()[0]
	e["meta"]["hash"] = "0".repeat(64)
	guest.accept(e["offer"])
	_pump(pair)
	check("a hash that does not match fails the offer and installs nothing", e["state"] == ModSend.FAILED and "hash" in e["why"]
			and DirAccess.get_directories_at(TMP + "guest").is_empty() and DirAccess.get_files_at(TMP + "guest").is_empty())
	_done(pair)
	# A host that sends a path out of the folder.
	pair = _pair()
	guest = pair["guest"]
	var set: Dictionary = {"mod.json": pair["files"]["mod.json"], "../x.json": "{}".to_utf8_buffer()}
	guest.offered(7, {"id": PLUCK_ID, "name": "P", "version": "1", "licence": "MIT", "size": 100, "count": 2, "hash": ModShare.digest(set)}, 1)
	guest.accept(7)
	for path in set:
		guest.file_began(7, path, (set[path] as PackedByteArray).size())
		guest.slice(7, set[path])
	guest.ended(7)
	check("a traversal path is refused and nothing is written", guest.inbox[0]["state"] == ModSend.FAILED
			and not FileAccess.file_exists(TMP + "x.json") and DirAccess.get_directories_at(TMP + "guest").is_empty())
	_done(pair)


func a_bad_offer_is_ignored() -> void:
	var pair := _pair()
	var guest: ModSend = pair["guest"]
	var meta := {"id": "ok.mod", "name": "N", "version": "1", "licence": "MIT", "size": 10, "count": 1, "hash": "a".repeat(64)}
	for change in [{"id": "builtin.x"}, {"id": "../x"}, {"size": ModShare.MAX_TOTAL_BYTES + 1}, {"count": 999}, {"hash": "nothex"}, {"size": "10"}]:
		var m := meta.duplicate()
		m.merge(change, true)
		guest.offered(1, m, 1)
	check("offers with a bad id, size, count or hash never reach the prompt", guest.inbox.is_empty())
	guest.offered(2, meta, 1)
	check("a good one does", guest.inbox.size() == 1)
	_done(pair)


## Solo and a host with nobody to offer to: nothing is queued, nothing is sent.
func solo_is_unaffected() -> void:
	var pair := _pair()
	var host: ModSend = pair["host"]
	var sent: Array = []
	host.wire = func(peer: int, method: StringName, _args: Array) -> void: sent.append([peer, method])
	host.offer_used([PLUCK_ID])
	host.forget_peer(2)
	_pump(pair, 5)
	check("a solo session (not a host) offers nothing", host.queued() == 0 and sent.is_empty())
	check("a guest's inbox starts empty and its prompt is hidden", pair["guest"].inbox.is_empty()
			and not ModOfferPrompt.new(pair["guest"]).visible)
	_done(pair)


## The prompt: a card per offer, with the real buttons.
func the_prompt_has_accept_and_decline() -> void:
	var pair := _pair()
	var guest: ModSend = pair["guest"]
	pair["host"].offer_all_to(2)
	_pump(pair, 3)
	var prompt := ModOfferPrompt.new(guest)
	t.add_child(prompt)
	prompt.refresh()
	var card := prompt.get_node_or_null("Offer_" + PLUCK_ID.replace(".", "_"))
	check("an offer shows as a card with ACCEPT and DECLINE", prompt.visible and card != null and card.find_child("Accept", true, false) != null
			and card.find_child("Decline", true, false) != null and prompt.has_pending())
	(card.find_child("Accept", true, false) as Button).pressed.emit()
	_pump(pair)
	check("pressing ACCEPT installs the mod", guest.registry.mod(PLUCK_ID) != null and not prompt.has_pending())
	check("sizes read in words", ModOfferPrompt.size_words(812) == "812 B" and ModOfferPrompt.size_words(3500) == "3.4 KB")
	prompt.queue_free()
	_done(pair)


## The plugin marker: format, id and display name, never binary or state; a guest lacking the plugin sees the unavailable plate.
func the_plugin_marker_reaches_a_guest() -> void:
	var saved_catalogue := PluginCatalogue.shared()
	PluginCatalogue.use_only([])
	var host_state := MixState.new()
	var fx := host_state.fx(0, 0)
	fx.name = "Synth X"
	fx.set_meta(&"unhosted", {"plugin_format": "CLAP", "plugin_id": "org.example.synth"})
	var msgs := MixWire.snapshot(host_state)
	var found := []
	for m in msgs:
		if str(m[0]).ends_with("/fx/0/plugin"):
			found = m[1]
	check("the snapshot carries [format, id, name] for a plugin slot: %s" % [found], found.size() == 3 and found[1] == "org.example.synth")
	var guest_state := MixState.new()
	for m in msgs:
		MixWire.apply(guest_state, m[0], m[1])
	var ref := PluginRef.of(guest_state.fx(0, 0), null)
	check("the guest has the slot's plugin, and lacking it says missing: %s" % [ref], ref.get("id") == "org.example.synth" and ref.get("missing") == true)
	check("so it shows the unavailable plate", RackUnitDress.skin_of(ref)[1] == RackUnitDress.MISSING_ACCENT)
	var guest_ref := {"format": "clap", "id": "org.example.synth", "name": "Synth X", "missing": false}
	check("a guest that has it shows no plate", RackUnitDress.skin_of(guest_ref).is_empty() or RackUnitDress.skin_of(guest_ref)[1] != RackUnitDress.MISSING_ACCENT)
	MixWire.apply(guest_state, "/track/0/fx/0/name", ["Renamed"])
	check("renaming the slot forgets the marker", PluginRef.of(guest_state.fx(0, 0), null).is_empty() or PluginRef.of(guest_state.fx(0, 0), null).get("id") != "org.example.synth")
	PluginCatalogue.use_only(saved_catalogue.plugins())
