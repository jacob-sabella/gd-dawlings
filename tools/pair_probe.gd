extends Node
## Two processes on this machine: `PAIR=host` hosts a studio with the rack, `PAIR=guest` joins it and
## plays a note through the rack's source. The host says whether it heard it and the rack sounded.
## godot --headless --path . tools/pair_probe.tscn   (with PAIR=host / PAIR=guest in the environment)


func _ready() -> void:
	DAW.use(OfflineBackend.new())
	if OS.get_environment("PAIR") == "host":
		await _host()
	else:
		await _guest()
	get_tree().quit()


func _host() -> void:
	if not Session.host(47123):
		print("PAIR host: cannot host")
		return
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	var seen_held := false
	var peak := 0.0
	var meter := 0.0
	var frames_read := 0
	var waited := 0.0
	while waited < 50.0:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
		var voice: RackVoice = studio.rack_voice
		if voice != null and voice.source != null and voice.running():
			var frames := voice.source.read()
			frames_read += frames.size()
			for f in frames:
				peak = maxf(peak, absf(f.x))
			for id in voice.meters:
				meter = maxf(meter, float(voice.meters[id]))
		if voice != null and voice._held.has(60):
			if not seen_held:
				print("PAIR host: note arrived at %.1f s, running %s" % [waited, voice.running()])
			seen_held = true
		if voice != null and voice.running():
			for id in voice.meters:
				peak = maxf(peak, float(voice.meters[id]))
		if seen_held and (peak > 0.02 or meter > 0.02):
			break
	var v: RackVoice = studio.rack_voice
	print("PAIR host state: running %s track %d held-now %s level %.3f frames %d beat %.2f waited %.1f meters %s" % [v.running(), v.track, v._held, v.level, frames_read, v.engine.running_beat, waited, v.meters])
	print("PAIR host: guest's note held in the rack %s, rack's stream peaked %.3f, its meters %.3f, peers %d" % [seen_held, peak, meter, Session.participants.size()])


func _guest() -> void:
	if not Session.join("127.0.0.1", 47123):
		print("PAIR guest: cannot join")
		return
	var waited := 0.0
	while not Session._connected() and waited < 15.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	print("PAIR guest: connected %s" % Session._connected())
	await get_tree().create_timer(3.0).timeout
	Session.send_note(Session.Note.ON, 60, 100, 0.0, Modular.SOURCE)
	await get_tree().create_timer(14.0).timeout
	Session.send_note(Session.Note.OFF, 60, 0, 0.0, Modular.SOURCE)
	await get_tree().create_timer(0.5).timeout
