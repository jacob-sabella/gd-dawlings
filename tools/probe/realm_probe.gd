extends Node

## Two processes, one realm visited (docs/realms.md): a headless host ("Ada") and a headless guest ("Grace") over
## real ENet on this machine. Grace leaves an unsaved song at home, visits, takes Ada's rack and song, offers a song
## of her own (Ada says yes), goes home, and finds her song as she saved it. Run by tools/realm_probe.sh.
##
## Each side keeps its files in a folder of its own under user://realm_probe/, never the player's.

const DOOR := ""
var _port := 7352
var _role := "host"
var _checks := 0
var _failures := 0
var _notices: Array[String] = []
var _start := 0
var _dir := ""


func _ready() -> void:
	var argv := OS.get_cmdline_user_args()
	for i in argv.size():
		if argv[i] == "--as" and i + 1 < argv.size():
			_role = argv[i + 1]
		if argv[i] == "--port" and i + 1 < argv.size():
			_port = int(argv[i + 1])
	_dir = "user://realm_probe/%s" % _role
	_clean(_dir)
	RackUserPresets.dir_override = _dir.path_join("presets")
	Session.realm_copy.projects_dir = _dir.path_join("projects")
	Session.lobby.path = _dir.path_join("realm.cfg")
	Session.lobby.load_settings()
	Session.notice.connect(func(t: String) -> void: _notices.append(t))
	_start = Time.get_ticks_msec()
	if _role == "host":
		await _host()
	else:
		await _guest()
	print("\n[%s] %d realm checks, %d failed" % [_role, _checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("  %s  %s" % ["ok  " if ok else "FAIL", label])


func _until(seconds: float) -> void:
	while (Time.get_ticks_msec() - _start) / 1000.0 < seconds:
		await get_tree().process_frame


func _clean(dir: String) -> void:
	for sub in ["", "presets", "projects"]:
		var d := DirAccess.open(dir.path_join(sub))
		if d != null:
			for f in d.get_files():
				DirAccess.remove_absolute(dir.path_join(sub).path_join(f))
	DirAccess.make_dir_recursive_absolute(dir.path_join("projects"))


func _host() -> void:
	Session.local_name = "Ada"
	DAW.use(OfflineBackend.new())
	DAW.set_tempo(141.0)
	DAW.save_project_as(_dir.path_join("Ada Tune.dawproject"))
	Session.lobby.copy_rule = RealmLobby.COPY_ALWAYS
	check("hosts", Session.host(_port))
	Session.publish_room({RackPatch.ROW: {"patch": RackPatch.preset(&"acid_line"), "track": 0}, "venue": "control_room"})
	# Ada says yes to what is offered her.
	Session.realm_copy.asked.connect(func() -> void:
		if not Session.realm_copy.pending.is_empty():
			Session.realm_copy.decide.call_deferred(0, true))
	await _until(14.0)
	var kept := Session.realm_copy.own_projects()
	check("Grace's song arrived in my projects (%s)" % [kept.map(func(p: Dictionary) -> String: return p["title"])],
			kept.any(func(p: Dictionary) -> bool: return str(p["title"]).begins_with("Grace Tune (from Grace")))
	check("and it opens (%s)" % [_opens(kept)], _opens(kept) == "")
	check("I was told", _notices.any(func(n: String) -> bool: return n.contains("offers you their song")))
	Session.leave()
	await _until(15.0)


func _guest() -> void:
	Session.local_name = "Grace"
	Session.listen_choice = 0
	DAW.use(OfflineBackend.new())
	DAW.save_project_as(_dir.path_join("projects").path_join("Grace Tune.dawproject"))
	var home_file := DAW.project_file()
	DAW.set_tempo(99.0)
	check("my song has changes no save has kept", RealmHome.needs_asking())
	check("kept before going", RealmHome.save_home() == "" and not DAW.has_unsaved_changes())
	DAW.set_tempo(77.0)
	await _until(1.0)
	Session.home.set_aside()
	check("joins Ada's realm", Session.join("127.0.0.1", _port, DOOR))
	await _until(2.5)
	check("in, as a guest", Session.role == Session.Role.GUEST and Session.name_of(1) == "Ada")
	check("away from home, my song set aside", Session.home.away and Session.home.project == home_file)
	check("the guest's DAW is the host's mirror now", DAW.state.tempo == 141.0)

	check("asks for the rack", Session.realm_copy.ask(RealmCopy.RACK) == "")
	await _until(3.5)
	check("Ada's rack is among my presets", RackUserPresets.has("Ada's rack"))

	check("asks for the song", Session.realm_copy.ask(RealmCopy.SONG) == "")
	await _until(7.0)
	var kept := Session.realm_copy.own_projects()
	var theirs := kept.filter(func(p: Dictionary) -> bool: return str(p["title"]).ends_with("(from Ada)"))
	check("Ada's song arrived in my projects (%s)" % [kept.map(func(p: Dictionary) -> String: return p["title"])], theirs.size() == 1)
	check("and it opens (%s)" % [_opens(theirs)], _opens(theirs) == "")

	check("offers my song", Session.realm_copy.offer_song(home_file) == "")
	await _until(11.0)
	check("sent (%s)" % Session.realm_copy.status, Session.realm_copy.status.begins_with("Sent"))

	Session.leave()
	await _until(12.5)
	check("home again", Session.role == Session.Role.SOLO and not Session.home.away)
	check("my song is open again (%s)" % DAW.project_file(), DAW.project_file() == home_file)
	check("as it was saved, not as I left it (tempo %.0f)" % DAW.state.tempo, is_equal_approx(DAW.state.tempo, 99.0))
	await _until(15.0)


## Whether the first of `projects` opens on a stand-in of its own: "" when it does, else why not.
func _opens(projects: Array) -> String:
	if projects.is_empty():
		return "none"
	var b := OfflineBackend.new()
	add_child(b)
	var said := ProjectFiles.open(b, projects[0]["path"])
	b.queue_free()
	return "; ".join(said)
