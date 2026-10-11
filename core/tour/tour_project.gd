class_name TourProject
extends RefCounted

## Swapping the real project out for a run's throwaway one, and back again, exactly.
##
## Entirely through calls that already exist and that other code already uses for the same
## job: `ProjectBridge.capture`/`ProjectBridge.load` are exactly what `ProjectFiles.save`/
## `ProjectFiles.open` call, used here purely in memory, with no disk I/O at all.

## The band's tracks, in desk order. Track 1 is Stage, the one lane every played part lands on
## (Tour.STAGE_TRACK): armed, MIDI input, no clip of its own, its name chosen NOT to match a
## DemoSong role -- both HitRecorder and GuestMidi land a take on the first armed track, so this
## is the only lane that can ever take one (see docs/loop_backlog.md's "Tour" section on why).
## Track 2 is the keys stab lane the pocket flaw rides on (Tour.TIMING_TRACK), same reasoning.
## 3..12 are role-named so the built-in engine plays DemoSong's part on each (DemoSong.role_of).
const BAND := ["Stage", "Keys", "Kick", "Snare", "Hat", "OH", "Bass DI", "Rhodes", "Gtr Amp",
		"Lead Vox", "Vox Dbl", "Strings"]
const STAGE_TRACK := 1 ## == Tour.STAGE_TRACK; _test_tour_song_has_a_stage_lane asserts they agree.
const KEYS_TRACK := 2 ## == Tour.TIMING_TRACK; _test_tour_song_has_a_playing_band asserts they agree.
const BARS := 2 * DemoSong.BARS ## 8 bars: two turns of the 4-bar loop, looped for the brief.

## One colour per role, by `BAND` name -- the same values OfflineBackend._populate paints the
## stand-in's own demo tracks with, so a rescue song's desk reads as the same band rather than
## twelve strips of the DawKitTrack default grey (a brief's whole timeline the one colour). Stage
## gets a hot amber of its own: the one lane every played part shares, not a role at all.
const TRACK_COLOUR := {
	"Stage": Color(0.95, 0.55, 0.08),
	"Keys": Color(0.82, 0.62, 0.28), "Kick": Color(0.86, 0.33, 0.28),
	"Snare": Color(0.88, 0.52, 0.24), "Hat": Color(0.84, 0.74, 0.3),
	"OH": Color(0.55, 0.72, 0.35), "Bass DI": Color(0.33, 0.66, 0.6),
	"Rhodes": Color(0.35, 0.56, 0.82), "Gtr Amp": Color(0.55, 0.45, 0.82),
	"Lead Vox": Color(0.82, 0.42, 0.66), "Vox Dbl": Color(0.74, 0.46, 0.74),
	"Strings": Color(0.46, 0.62, 0.78),
}


## Character FX Rig Roulette can land: not utility FX (EQ, compressor, limiter are a mix move,
## not a "constraint" a band plays around) -- the ones with a voice of their own.
const RIG_FX: Array[StringName] = [&"distortion", &"chorus", &"reverb", &"delay", &"phaser"]


## How many tracks a brief's own rig roulette touches: none at all for a duo or less (so the
## smallest bands stay simple), growing with the band the same shape `TourFlaws.count_for` grows
## flaws with, just a beat behind it -- this is variety on top of the brief, not something fixed
## or judged, so it asks for less of a crowded card than a flaw does.
static func rig_count_for(band_size: int) -> int:
	return 0 if band_size <= 2 else 1 if band_size <= 4 else 2 if band_size <= 6 else 3


## A brief's rescue song: the full band, eight bars looped at `song_tempo`, with `flaws` baked
## in before it is loaded. Every track but the keys lane carries one demo item (no file, no
## notes), the same shape the stand-in's own song builds its tracks with (OfflineBackend.
## _populate); loaded with `band_parts()` (see `load`), the whole band plays. `band_size` and
## `brief_index` (1 by default, "not the first brief" -- the same default a bare `0` would break,
## so every existing call that never heard of rig roulette keeps landing none) drive whether a
## seeded pedal or two rides along -- see `rig_count_for`.
static func song_for(brief: TourBrief, song_tempo: float, flaws: Array[TourFlaw],
		rng: RandomNumberGenerator, band_size: int = 1, brief_index: int = 1) -> DawKitProject:
	var p := DawKitProject.new()
	p.title = "Tour: %s" % brief.title
	p.tempo = song_tempo
	p.length = BARS * 4.0 * 60.0 / song_tempo
	p.loop_on = true
	p.loop_start = 0.0
	p.loop_end = p.length
	for i in BAND.size():
		var name: String = BAND[i]
		var t := p.add_track(name)
		t.colour = TRACK_COLOUR.get(name, t.colour)
		if i == STAGE_TRACK - 1:
			# No clip: it starts empty, and every played part lands its own notes on it.
			t.armed = true
			t.input = "midi"
			continue
		var clip := DawKitClip.new()
		clip.start = 0.0
		clip.length = p.length
		clip.name = name
		if i == KEYS_TRACK - 1:
			clip.notes = stab_notes(song_tempo, BARS, 0.0)
		t.clips.append(clip)
	for f in flaws:
		f.bake(p, rng, song_tempo)
	if brief_index > 0:
		var claimed := {}
		for f in flaws:
			if f.track != "":
				claimed[f.track] = true
		var eligible: Array[String] = []
		for i in BAND.size():
			if i == STAGE_TRACK - 1 or claimed.has(BAND[i]):
				continue
			eligible.append(BAND[i])
		for i in range(eligible.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp := eligible[i]
			eligible[i] = eligible[j]
			eligible[j] = tmp
		for i in mini(rig_count_for(band_size), eligible.size()):
			var t := TourFlaws._dk_track_named(p, eligible[i])
			if t == null:
				continue
			var kind: StringName = RIG_FX[rng.randi() % RIG_FX.size()]
			var fx := DawKitEffect.new()
			fx.kind = String(kind)
			fx.name = FXCatalogue.kinds()[kind]["name"]
			fx.enabled = true
			fx.wet = 1.0
			fx.values.assign(Array(FXCatalogue.defaults(kind)))
			t.effects.append(fx)
	return p


## The keys lane's stabs: one on beats 0 and 2 of every bar, all three tones of that bar's chord
## (DemoSong.CHORDS) an octave up, 0.45 beat long. `late_beats` (the dragging flaw's 0.22, 0.0
## for a clean lane) shifts every on and off by the same amount, seconds relative to the clip --
## OfflineBackend._comping's layout, [on, off, pitch, velocity, channel].
static func stab_notes(song_tempo: float, bars: int, late_beats: float) -> PackedFloat64Array:
	var beat := 60.0 / song_tempo
	var out := PackedFloat64Array()
	for k in bars:
		var chord: Array = DemoSong.CHORDS[k % DemoSong.CHORDS.size()]
		for b: float in [0.0, 2.0]:
			var on: float = (k * 4.0 + b + late_beats) * beat
			var off: float = on + 0.45 * beat
			for note in chord:
				out.append_array([on, off, note + 12, 96, 0])
	return out


## The part each of `BAND`'s tracks plays, by track index: its DemoSong role, by name, the way
## the stand-in names its own (OfflineBackend._populate). The keys lane has none, so its notes
## are all it plays.
static func band_parts() -> Dictionary:
	var parts := {}
	for i in BAND.size():
		var role := DemoSong.role_of(BAND[i])
		if role != "":
			parts[i + 1] = role
	return parts


## Loads a rescue song (`song_for`) with its band's parts, so the built-in engine plays them.
static func load(p: DawKitProject, backend: OfflineBackend) -> PackedStringArray:
	return ProjectBridge.load(p, backend, band_parts())


## In-memory snapshot of everything `ProjectBridge.capture` round-trips -- the project, the
## path/title it was known by -- and the part each track plays, which a `DawKitProject` does
## not carry: without it the stand-in's own song came back from a run silent.
static func capture(backend: OfflineBackend) -> Dictionary:
	var parts := {}
	for index in backend.state.track_indices():
		parts[index] = backend.state.tracks[index].part
	return {"project": ProjectBridge.capture(backend), "path": backend.project_path, "parts": parts}


## Replaces the backend's project with `snapshot`'s, and restores the path/title it had and
## its tracks' parts. The same `ProjectBridge.load` every other "swap the whole project" moment
## in this codebase uses, so this is an exact restore of everything a `DawKitProject`
## represents, and of the parts besides.
static func restore(backend: OfflineBackend, snapshot: Dictionary) -> void:
	ProjectBridge.load(snapshot["project"], backend, snapshot.get("parts", {}))
	backend.project_path = snapshot["path"]
	backend.name_project()
