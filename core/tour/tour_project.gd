class_name TourProject
extends RefCounted

## Swapping the real project out for a run's throwaway one, and back again, exactly.
##
## Entirely through calls that already exist and that other code already uses for the same
## job: `ProjectBridge.capture`/`ProjectBridge.load` are exactly what `ProjectFiles.save`/
## `ProjectFiles.open` call, used here purely in memory, with no disk I/O at all.

## The band's tracks, in desk order. Track 1 is the keys stab lane the pocket flaw rides on
## (Tour.TIMING_TRACK): a MIDI lane played through the engine's own tine, its name chosen NOT to
## match a DemoSong role so its notes are all it plays. 2..11 are role-named so the built-in
## engine plays DemoSong's part on each (DemoSong.role_of).
const BAND := ["Keys", "Kick", "Snare", "Hat", "OH", "Bass DI", "Rhodes", "Gtr Amp", "Lead Vox",
		"Vox Dbl", "Strings"]
const KEYS_TRACK := 1 ## == Tour.TIMING_TRACK; _test_tour_song_has_a_playing_band asserts they agree.
const BARS := 2 * DemoSong.BARS ## 8 bars: two turns of the 4-bar loop, looped for the brief.

## One colour per role, by `BAND` name -- the same values OfflineBackend._populate paints the
## stand-in's own demo tracks with, so a rescue song's desk reads as the same band rather than
## twelve strips of the DawKitTrack default grey (a brief's whole timeline the one colour).
const TRACK_COLOUR := {
	"Keys": Color(0.82, 0.62, 0.28), "Kick": Color(0.86, 0.33, 0.28),
	"Snare": Color(0.88, 0.52, 0.24), "Hat": Color(0.84, 0.74, 0.3),
	"OH": Color(0.55, 0.72, 0.35), "Bass DI": Color(0.33, 0.66, 0.6),
	"Rhodes": Color(0.35, 0.56, 0.82), "Gtr Amp": Color(0.55, 0.45, 0.82),
	"Lead Vox": Color(0.82, 0.42, 0.66), "Vox Dbl": Color(0.74, 0.46, 0.74),
	"Strings": Color(0.46, 0.62, 0.78),
}


## A brief's rescue song: the full band, eight bars looped at `song_tempo`, with `flaws` baked
## in before it is loaded. Every track but the keys lane carries one demo item (no file, no
## notes), the same shape the stand-in's own song builds its tracks with (OfflineBackend.
## _populate); loaded with `band_parts()` (see `load`), the whole band plays.
static func song_for(brief: TourBrief, song_tempo: float, flaws: Array[TourFlaw],
		rng: RandomNumberGenerator) -> DawKitProject:
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
		var clip := DawKitClip.new()
		clip.start = 0.0
		clip.length = p.length
		clip.name = name
		if i == KEYS_TRACK - 1:
			clip.notes = stab_notes(song_tempo, BARS, 0.0)
		t.clips.append(clip)
	for f in flaws:
		f.bake(p, rng, song_tempo)
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
