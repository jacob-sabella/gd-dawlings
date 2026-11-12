class_name SingerHost
extends RefCounted

## The vocal booth's singer in the studio (CHIMERA's voice, docs/singer.md). This file:
## - stands its station (SingerBooth: the head on its pedestal and its desk) in every venue's vocal booth (`stand`);
## - runs the voice on the host (Singer, an engine process like the modular room's rack), set as the room's row
##   `singer` says (SingerRow) and fed the song's lyrics and its vocal part, the notes of the MIDI track the row
##   names (`part`);
## - catches what it sings onto its track while the song records;
## - answers the asks of the row and the moments (`ask`, `answer`, the room verb `singer`);
## - shows guests the host's singer through the volatile entry `/singer/live` (SingerLive).
## The room's lights follow its level (`level`) as they follow the mix and the rack.

## How often the vocal part is read from the song again (s): notes edited are sung within a second.
const PART_EVERY := 1.0
## A player this near the booth (m) starts the voice, so a key pressed there sounds at once.
const NEAR := 3.5
## The creature's voice sleeps after this long without a stone struck (s): it costs a core's fifth while it runs.
const CREATURE_SLEEP := 20.0
## Where the creature's perch stands in the booth (its frame, as `spot_in`'s): against the far wall from the
## door, turned to face into the booth.
const PERCH_AT := Vector3(-1.2, 0.0, 0.35)

var studio: Studio
var _part_age := 99.0
var _auto_take := false
var _live_sent := false
var _live_ticks := 0
var _words := ""
## Where the syllable being sung is on the lyric board (VocalPart.sung_span), and what it was found from.
var _span := PackedInt32Array()
var _span_of := []
## The prompter's lyrics, parsed when they change, and every syllable's place on them (VocalPart.spans).
var _prompt_lrc := "(none read yet)"
var _prompt_lyrics := Lyrics.new()
var _marks: Array[PackedInt32Array] = []
var _marks_of := []
## How many notes the PART has, as sung (one voice).
var _part_notes := 0
## The venue's creature (Bestiary): its perch in the booth, and its voice on the host, woken by a stone and put
## to sleep again when no stone has been struck for CREATURE_SLEEP.
var perch: CreaturePerch
var creature: Creature
var _creature_idle := 0.0
var _lit_stone := -1
var _lit_for := 0.0


func _init(of: Studio) -> void:
	studio = of


## The station into the venue's vocal booth (none where there is no booth, nor in AR). After the venue's pieces.
func stand() -> void:
	if studio.singer_booth != null and is_instance_valid(studio.singer_booth):
		studio.singer_booth.queue_free()
	studio.singer_booth = null
	if studio.venue == null or studio.medium == Presentation.Medium.AR:
		return
	var zones: Dictionary = studio.venue.zones()
	if not zones.has(&"vocals"):
		return
	var booth := SingerBooth.new()
	booth.name = "SingerBooth"
	booth.transform = spot_in(zones[&"vocals"])
	booth.asked.connect(ask)
	booth.speak_asked.connect(speak)
	booth.lyrics_asked.connect(edit_lyrics)
	booth.rec_asked.connect(record)
	booth.names_tracks_with(func(i: int) -> String:
		var t: MixState.TrackState = DAW.state.tracks.get(i) if DAW.state != null else null
		return t.display_name() if t != null else str(i))
	studio.venue.add_child(booth)
	studio.singer_booth = booth
	booth.show_row(studio.singer_row)
	booth.head.moved.connect(func(n: String, cm: float) -> void: ask("grab", [n, cm]))
	booth.head.let_go.connect(func(names: PackedStringArray) -> void:
		for n in names:
			ask("grab", [n, -1000.0]))
	_stand_perch(zones[&"vocals"])
	casts_none(booth)
	if perch != null:
		casts_none(perch)
	# the venue's lettering on the booth, the perch and the lyric board (readable whatever the venue)
	var look := SingerStyle.of(studio.venue.venue_id())
	booth.apply_style(look)
	if perch != null:
		perch.apply_style(look)
	if studio.lyric_board != null and is_instance_valid(studio.lyric_board):
		studio.lyric_board.apply_style(look)


## Nothing under `root` casts a shadow. The booth's keys, labels and desk and the perch's stones are small and lit by
## their own lamps; in the sun's cascades they cost a draw each per cascade, about 600 draws at 90 tracks in the
## wide pose (tools/budget.sh), for shadows nobody could see.
static func casts_none(root: Node) -> void:
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The venue's creature on its perch in booth `box`.
func _stand_perch(box: AABB) -> void:
	if perch != null and is_instance_valid(perch):
		perch.queue_free()
	perch = CreaturePerch.new(Bestiary.of(studio.venue.venue_id()))
	perch.name = "CreaturePerch"
	perch.transform = perch_spot(box)
	perch.struck.connect(func(n: int) -> void: ask("strike", [n]))
	studio.venue.add_child(perch)
	if creature != null and is_instance_valid(creature):
		creature.be(int(perch.spec["beast"]))


## Where the perch stands in a booth `box`: PERCH_AT from its middle, facing +X (into the booth).
static func perch_spot(box: AABB) -> Transform3D:
	var c := box.get_center()
	var at := Vector3(c.x + maxf(PERCH_AT.x, -box.size.x * 0.5 + 0.45), box.position.y, c.z + PERCH_AT.z)
	return Transform3D(Basis(Vector3.UP, PI * 0.5), at)


## Where the station stands in a booth `box` (the venue's `vocals` zone, venue frame): back from the mic toward
## the booth's +Z wall, inside it, its desk turned to the singer at the mic.
static func spot_in(box: AABB) -> Transform3D:
	var c := box.get_center()
	var at := Vector3(c.x + clampf(box.size.x * 0.1, -0.2, 0.2), box.position.y, minf(c.z + 0.55, box.end.z - 0.45))
	var mic := Vector3(c.x + ZoneKit.MIC_AT.x - 0.4, box.position.y, c.z + ZoneKit.MIC_AT.z)
	var to := mic - at
	to.y = 0.0
	var yaw := atan2(to.x, to.z) if to.length() > 0.01 else 0.0
	return Transform3D(Basis(Vector3.UP, yaw), at)


## An ask from the booth (or a test): the row changed or a moment played. Done on the host; a guest's goes to the
## host, its row change shown at once.
func ask(op: String, args: Array) -> void:
	if Session.is_authority():
		answer(op, args, Session.local_peer_id)
		return
	if SingerRow.is_moment(op):
		Session.ask_room(SingerRow.VERB, [StringName(op), args])
		return
	var row := studio.singer_row.duplicate(true)
	var refusal := SingerRow.answer(row, op, args, _tracks_for(op))
	if refusal != "":
		Session.notice.emit(refusal)
		return
	if studio.room_rows._predict(SingerRow.VERB, [StringName(op), args]) > 0:
		_show(row)


## The host's answer: the row changed (and the room told) or the moment played on the voice.
func answer(op: String, args: Array, _from: int) -> void:
	var row := studio.singer_row
	var tracks := _tracks_for(op)
	if op == "track" and args.is_empty() and int(row["track"]) <= 0:
		# the first press: the song's Singer track, made if there is none
		var made := _singer_track()
		args = [made]
		if not tracks.has(made):
			tracks.append(made)
	var refusal := SingerRow.answer(row, op, args, tracks)
	if refusal != "":
		if _from == Session.local_peer_id:
			Session.notice.emit(refusal)
		return
	if SingerRow.is_moment(op):
		_play_moment(op, args)
		return
	_show(row)
	if op == "part":
		# the new part (or none) sung from the next frame, not within the second
		_part_age = PART_EVERY
	if studio.singer != null and is_instance_valid(studio.singer):
		studio.singer.apply_row(row)
	studio.player_host._publish_room_soon()


func _tracks() -> Array:
	return DAW.state.track_indices() if DAW.state != null else []


## The tracks an ask steps through: PART, only those with notes to sing; the rest, every track.
func _tracks_for(op: String) -> Array:
	if op != "part" or DAW.state == null:
		return _tracks()
	return _tracks().filter(func(i: int) -> bool: return not VocalPart.notes_of(DAW.state, i).is_empty())


## The track the singer records on when none is chosen: the song's track named Singer, or a new one at the end.
func _singer_track() -> int:
	var indices := _tracks()
	for i: int in indices:
		var t: MixState.TrackState = DAW.state.tracks.get(i)
		if t != null and t.name.strip_edges().to_lower() == "singer":
			return i
	var at := indices.size() + 1
	DAW.add_track(at, "Singer")
	return at


## REC at the booth: the song records (onto the singer's TRACK, chosen first if it has none), or stops.
func record() -> void:
	if DAW.state == null:
		return
	if DAW.state.recording:
		DAW.transport_stop()
		return
	if int(studio.singer_row["track"]) <= 0:
		ask("track", [])
	DAW.transport_record()


## LYRICS at the booth: all the song's lyrics to edit, in the session panel's LYRICS box at a desk (paste a whole
## song); in a headset, a line typed on the pad, or several split by " / ", added at the end.
func edit_lyrics() -> void:
	var booth := studio.singer_booth
	if booth != null and is_instance_valid(booth) and booth.get_viewport() != null and booth.get_viewport().use_xr:
		var old := booth.get_node_or_null("TypingPad")
		if old != null:
			old.queue_free()
		var pad := TypingPad.ask(booth, "LYRICS: OK adds the line at the end (\" / \" between lines)", "",
				Transform3D(Basis(Vector3.RIGHT, SingerBooth.DESK_TILT), SingerBooth.DESK_AT + Vector3(0, -0.12, 0.3)))
		pad.answered.connect(func(words: String) -> void:
			var lines := PackedStringArray()
			for w in words.split(" / ", false):
				if w.strip_edges() != "":
					lines.append(w.strip_edges())
			if lines.is_empty() or DAW.state == null:
				return
			var now := DAW.state.lyrics.strip_edges()
			DAW.set_lyrics((now + "\n" if now != "" else "") + "\n".join(lines)))
		return
	if studio.lyrics_edit_asked.get_connections().is_empty():
		Session.notice.emit("M opens the session panel: its LYRICS box has the song's lyrics.")
		return
	studio.lyrics_edit_asked.emit()


func _play_moment(op: String, args: Array) -> void:
	if op == "strike":
		_strike(int(args[0]))
		return
	if not _wake():
		return
	var s := studio.singer
	match op:
		"say":
			s.say(String(args[0]), args.size() > 1 and args[1] == true)
		"hit":
			s.beat_hit(String(args[0]), int(args[1]) if args.size() > 1 else 0)
		"grab":
			var cm := float(args[1])
			if cm < -100.0:
				s.grab(String(args[0]), -1.0)
			else:
				s.engine.say("text %s.artic %s =%.4f" % [Singer.ID, String(args[0]), cm])
		"play":
			s.play(int(args[0]), bool(args[1]))
		"cry":
			s.cry(int(args[0]))


## Stone `n` of the perch struck: the creature's call on its note (the host), the stone lit.
func _strike(n: int) -> void:
	if perch == null or not is_instance_valid(perch) or not Session.is_authority():
		return
	if creature == null or not is_instance_valid(creature):
		creature = Creature.new()
		creature.name = "Creature"
		studio.add_child(creature)
	if not creature.running() and not creature.start():
		return
	creature.be(int(perch.spec["beast"]))
	creature.call_at(int(perch.spec["call"]), perch.note_of(n))
	_creature_idle = 0.0
	_light_stone(n)


func _light_stone(n: int) -> void:
	if _lit_stone >= 0:
		perch.light(_lit_stone, false)
	_lit_stone = n
	_lit_for = 0.4
	perch.light(n, true)


## The creature's perch, about 30 times a second: how loud it is, the struck stone let go, its voice to sleep.
func _follow_perch(delta: float) -> void:
	if perch == null or not is_instance_valid(perch):
		return
	if _lit_stone >= 0:
		_lit_for -= delta
		if _lit_for <= 0.0:
			perch.light(_lit_stone, false)
			_lit_stone = -1
	var on := creature != null and is_instance_valid(creature) and creature.running()
	perch.sound(clampf(creature.level * 3.0, 0.0, 1.0) if on else 0.0)
	if on:
		_creature_idle += delta
		if _creature_idle > CREATURE_SLEEP:
			creature.shutdown()


## The row shown on this machine's booth.
func _show(row: Dictionary) -> void:
	studio.singer_row = SingerRow.sanitize(row)
	if studio.singer_booth != null and is_instance_valid(studio.singer_booth):
		studio.singer_booth.show_row(studio.singer_row)


## The room's row from the host (a guest): with its own unanswered asks on top.
func show_room(raw: Variant) -> void:
	var row := SingerRow.sanitize(raw)
	for p in studio._predictions:
		if p["verb"] == SingerRow.VERB:
			SingerRow.answer(row, String(p["args"][0]), p["args"][1], _tracks())
	_show(row)


## SPEAK: a line to say, typed on a pad under the head in a headset, in a prompt at a desk.
func speak() -> void:
	var said := func(text: String) -> void:
		if text.strip_edges() != "":
			# /slashes/ around it: IPA
			var t := text.strip_edges()
			var ipa := t.begins_with("/") and t.ends_with("/") and t.length() > 2
			ask("say", [t.trim_prefix("/").trim_suffix("/") if ipa else t, ipa])
	var booth := studio.singer_booth
	if booth != null and is_instance_valid(booth) and booth.get_viewport() != null and booth.get_viewport().use_xr:
		var old := booth.get_node_or_null("TypingPad")
		if old != null:
			old.queue_free()
		var pad := TypingPad.ask(booth, "SPEAK: OK says it (/slashes/ for IPA)", "",
				Transform3D(Basis(Vector3.RIGHT, SingerBooth.DESK_TILT), SingerBooth.DESK_AT + Vector3(0, -0.12, 0.3)))
		pad.limit = SingerRow.SAY_MOST
		pad.answered.connect(said)
		return
	var prompt := NamePrompt.ask(studio, "SPEAK: Enter says it, Escape leaves it (/slashes/ for IPA)", "", SingerRow.SAY_MOST)
	prompt.answered.connect(said)


## The voice, started if the row allows (the host only); false when it cannot run.
func _wake() -> bool:
	if not Session.is_authority() or not bool(studio.singer_row.get("power", true)):
		return false
	if studio.singer == null or not is_instance_valid(studio.singer):
		studio.singer = Singer.new()
		studio.singer.name = "Singer"
		studio.add_child(studio.singer)
	if not studio.singer.running():
		if not studio.singer.start():
			return false
		studio.singer.apply_row(studio.singer_row)
		_words = ""
	return true


## Whether the voice is wanted now: someone at the booth, or a part to sing while the song plays.
func _wanted() -> bool:
	if not bool(studio.singer_row.get("power", true)) or studio.singer_booth == null or not is_instance_valid(studio.singer_booth):
		return false
	# A part to sing keeps it awake, playing or not: woken only when the song rolled, it spent the part's first
	# notes starting (the engine, the dictionary, the plan) and came in a bar or two late.
	if int(studio.singer_row["part"]) > 0:
		return true
	var cam := studio.get_viewport().get_camera_3d() if studio.get_viewport() != null else null
	return cam != null and cam.global_position.distance_to(studio.singer_booth.global_position) < NEAR


## About 30 times a second (ViewHost): the host's voice fed and shown, a guest's booth shown from the host's.
func follow(delta: float) -> void:
	_follow_perch(delta)
	var booth := studio.singer_booth
	if booth == null or not is_instance_valid(booth):
		return
	if Session.role == Session.Role.GUEST:
		var live := SingerLive.fresh(DAW.state.singer_live if DAW.state != null else {})
		booth.show_voice(VoiceTele.read(live.get("tele", PackedFloat32Array())), live.get("frame", {}),
				String(live.get("sung", "")), int(live.get("step", -1)), "")
		_span = live.get("span", PackedInt32Array())
		_lend_board()
		_prompt(PackedStringArray(), "the host's singer" if not live.is_empty() else "the host's singer is quiet")
		return
	if _wanted():
		_wake()
	var s := studio.singer
	if s == null or not is_instance_valid(s) or not s.running():
		_span = PackedInt32Array()
		_publish(false)
		booth.show_voice({}, {}, "", -1, "")
		_prompt(PackedStringArray(), "power off" if not bool(studio.singer_row["power"]) else "step up to the booth to wake the singer")
		return
	if DAW.state != null:
		s.set_lyrics(DAW.state.lyrics)
		_part_age += delta
		if _part_age >= PART_EVERY:
			_part_age = 0.0
			var part := int(studio.singer_row["part"])
			var notes := VocalPart.notes_of(DAW.state, part) if part > 0 else []
			_part_notes = VocalPart.monophonic(notes).size()
			s.sing_part(notes, DAW.state.tempo)
	var syl := s.syllables()
	var k := s.sung()
	var sung := syl[k] if k >= 0 and k < syl.size() else ""
	var step := int(s.steps.get(Singer.ID, -1))
	booth.show_voice(s.body(), s.frame(), sung, step, "")
	_find_span(syl, k)
	_lend_board()
	_prompt(syl, _status(syl.size()))
	_record()
	_publish(true)


## The syllable `k` of `syl` placed on the lyrics' lines, found again only when it or the lyrics change. None
## while the voice is quiet: the board lights what is being sung, not what was.
func _find_span(syl: PackedStringArray, k: int) -> void:
	var lrc := DAW.state.lyrics if DAW.state != null else ""
	var b := studio.singer.body()
	if k < 0 or (float(b.get("gate", 0.0)) < 0.5 and float(b.get("rms", 0.0)) < 0.002):
		_span = PackedInt32Array()
		return
	var key := [lrc.hash(), syl.size(), k]
	if key == _span_of:
		return
	_span_of = key
	_span = VocalPart.sung_span(lrc, syl, k)


## The lyric board told where the singer is (it asks each frame).
func _lend_board() -> void:
	var board := studio.lyric_board
	if board != null and is_instance_valid(board) and not board.sung_source.is_valid():
		board.sung_source = func() -> PackedInt32Array: return _span


## The syllable being sung on the lyric board: [line, first character, characters], empty for none.
func sung_span() -> PackedInt32Array:
	return _span


## The prompter's words: the line sung now (or, quiet, the line the song is on), its syllables marked when the voice
## is here to say them (`syl`), the one sung lit, the next line, and `words` under them.
func _prompt(syl: PackedStringArray, words: String) -> void:
	var booth := studio.singer_booth
	var lrc := DAW.state.lyrics if DAW.state != null else ""
	if lrc != _prompt_lrc:
		_prompt_lrc = lrc
		_prompt_lyrics = Lyrics.parse(lrc)
		_marks_of = []
	var lyr := _prompt_lyrics
	if lyr.is_empty():
		booth.show_prompt("No lyrics yet", Vector2i(-1, 0), "LYRICS on the desk adds them", words)
		return
	var order := lyr.sequence()
	var line := int(_span[0]) if _span.size() == 3 else lyr.at(DAW.state.position_seconds)
	if lyr.place(line) < 0:
		line = order[0] if not order.is_empty() else -1
	if line < 0:
		booth.show_prompt("♪", Vector2i(-1, 0), "", words)
		return
	var key := [syl.size(), syl[0] if not syl.is_empty() else ""]
	if not syl.is_empty() and key != _marks_of:
		_marks_of = key
		_marks = VocalPart.spans(lrc, syl)
	var text := String(lyr.lines[line]["text"])
	var shown := VocalPart.marked(text, line, _marks if not syl.is_empty() else ([] as Array[PackedInt32Array]), _span)
	var k := lyr.place(line)
	var next := String(lyr.lines[order[k + 1]]["text"]).strip_edges() if k + 1 < order.size() else ""
	booth.show_prompt(String(shown[0]), shown[1], next, words)


func _status(syllables: int) -> String:
	var row := studio.singer_row
	var mode := int(row["mode"])
	match mode:
		SingerRow.Mode.SING:
			var then := "" if int(row["track"]) > 0 else "  ·  TRACK or REC to record it"
			if int(row["part"]) > 0:
				return _fit(_part_notes, syllables) + then
			if syllables == 0:
				return "no lyrics: it sings 'ah'  ·  LYRICS adds them"
			return "%d syllables  ·  PART picks a MIDI track to sing, or play the pads" % syllables + then
		SingerRow.Mode.VOWEL:
			return "the pad moves the tongue and jaw · grab the head's mouth"
		SingerRow.Mode.BEAT:
			return "pads beatbox · steps make the pattern · SEQ plays it with the song"
	return "the %s · pads 1-4 its calls, the last four choose the animal" % SingerRow.BEASTS[int(row["beast"])]


## The song recording catches the singer on its track: begun with the take, kept when it ends.
func _record() -> void:
	var s := studio.singer
	if DAW.state == null or int(studio.singer_row["track"]) <= 0:
		return
	if DAW.state.recording and DAW.state.playing and not s.recording():
		_auto_take = s.record_start(s.song_seconds())
	elif not DAW.state.recording and s.recording() and _auto_take:
		var took := s.record_stop()
		if String(took.get("error", "")) != "":
			push_warning("singer: the take was not kept: %s" % took["error"])
		_auto_take = false


func _publish(running: bool) -> void:
	if not Session.is_authority() or Session.participants.size() <= 1 or DAW.backend == null:
		return
	if not running:
		if _live_sent:
			_live_sent = false
			DAW.backend.record_for_replication(SingerLive.ADDRESS, [false])
		return
	_live_sent = true
	_live_ticks += 1
	var s := studio.singer
	var v: Dictionary = s.engine.voices.get(Singer.ID, {})
	var syl := s.syllables()
	var k := s.sung()
	DAW.backend.record_for_replication(SingerLive.ADDRESS, SingerLive.pack(true, v.get("tele", PackedFloat32Array()),
			s.frame() if _live_ticks % 2 == 0 else {}, syl[k] if k >= 0 and k < syl.size() else "", int(s.steps.get(Singer.ID, -1)),
		_span))


## How loud the singer is now, 0..1: the host's own, the host's as sent on a guest.
func level() -> float:
	if Session.role == Session.Role.GUEST:
		var live := SingerLive.fresh(DAW.state.singer_live if DAW.state != null else {})
		var t: PackedFloat32Array = live.get("tele", PackedFloat32Array())
		return clampf(t[6] * 8.0, 0.0, 1.0) if t.size() > 6 else 0.0
	var s := studio.singer
	return s.level if s != null and is_instance_valid(s) and s.running() else 0.0


## How the words fit the notes, said: a syllable a note, and what happens to the rest.
static func _fit(notes: int, syllables: int) -> String:
	if notes == 0:
		return "the PART has no notes yet"
	if syllables == 0:
		return "%d notes, no lyrics: it sings 'ah'  ·  LYRICS adds them" % notes
	if notes == syllables:
		return "%d notes  ·  %d syllables: every word sung" % [notes, syllables]
	if notes < syllables:
		return "%d notes  ·  %d syllables: the last %d not sung" % [notes, syllables, syllables - notes]
	return "%d notes  ·  %d syllables: the words start again at note %d" % [notes, syllables, syllables + 1]
