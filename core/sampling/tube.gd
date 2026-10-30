class_name Tube
extends RefCounted

## YouTube for the sampling station's TV (docs/sampling_station.md): a search, a video fetched into
## the cache and its sound decoded to a WAV, all off the main thread, each answered on the main
## one through a signal.
##
## Nothing is streamed while it plays. `fetch` brings the whole video down (480p or less, H.264 and
## AAC in an MP4: a 30 s video in about 2 s) and decodes its sound once to a 48 kHz WAV beside it,
## which is what plays and the clock the picture follows (TubeFrames), so what is heard, seen and
## sampled are the same audio. Both are kept, keyed by the video's id, so a video watched again,
## or the same video fetched by every player in a room, is fetched once a machine.
##
## The tools are found by name on the PATH (`yt_dlp`, `ffmpeg`); the suite points them at
## stand-ins (tests/fixtures/tube) and so never touches the network. Missing, `missing_tool` says
## which, in words for the TV.

signal searched(query: String, results: Array, error: String)
signal fetched(id: String, ok: bool, error: String)

## Where videos and their sound are kept; the suite points it at a scratch folder.
static var dir := "user://tube"
## How many results a search lists.
const RESULTS := 8
## The video asked for: 480p or less, H.264 and AAC (Godot's own decoders aside, ffmpeg reads
## anything, but these are small and everywhere), else whatever is best under 480p, else best.
const FORMAT := "bv*[height<=480][vcodec^=avc1]+ba[ext=m4a]/b[height<=480]/b"
## Longest video fetched (s): an hour of 48 kHz stereo is 660 MB of WAV.
const LONGEST := 1800.0

static var yt_dlp := "yt-dlp"
static var ffmpeg := "ffmpeg"

var _threads: Array[Thread] = []


## The video's id in a link or a bare id: youtube.com/watch?v=ID, youtu.be/ID, /shorts/ID,
## /embed/ID, /live/ID, music.youtube.com; "" for anything else.
static func video_id(text: String) -> String:
	var t := text.strip_edges()
	var re := RegEx.create_from_string(
			"(?:youtube\\.com/(?:watch\\?(?:.*&)?v=|shorts/|embed/|live/|v/)|youtu\\.be/)([A-Za-z0-9_-]{11})")
	var m := re.search(t)
	if m != null:
		return m.get_string(1)
	# A bare id only when it could not be a word typed as a search: an id has a digit, '-', '_' or
	# a capital after its first letter; eleven lower-case letters are a search.
	if RegEx.create_from_string("^[A-Za-z0-9_-]{11}$").search(t) != null \
			and RegEx.create_from_string("[0-9A-Z_-]").search(t.substr(1)) != null:
		return t
	return ""


static func video_path(id: String) -> String:
	return ProjectSettings.globalize_path(dir.path_join(id + ".mp4"))


static func wav_path(id: String) -> String:
	return ProjectSettings.globalize_path(dir.path_join(id + ".wav"))


static func info_path(id: String) -> String:
	return ProjectSettings.globalize_path(dir.path_join(id + ".info.json"))


## Whether the video and its sound are here already.
static func cached(id: String) -> bool:
	return FileAccess.file_exists(video_path(id)) and FileAccess.file_exists(wav_path(id))


## What yt-dlp said about a fetched video: {title, seconds, channel}; empty if nothing.
static func info(id: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(info_path(id))
	var d: Variant = JSON.parse_string(text) if text != "" else null
	if not d is Dictionary:
		return {}
	return {"title": str(d.get("title", "")), "seconds": float(d.get("duration", 0.0)),
			"channel": str(d.get("channel", d.get("uploader", "")))}


## The tool not found on this machine, in words for the TV; "" when both are there.
static func missing_tool() -> String:
	for tool in [yt_dlp, ffmpeg]:
		if not _has(tool):
			return "%s is not installed" % tool.get_file()
	return ""


static func _has(tool: String) -> bool:
	if tool.is_absolute_path():
		return FileAccess.file_exists(tool)
	return OS.execute("sh", ["-c", "command -v '%s'" % tool], [], false) == 0


## Search YouTube for `query`; `searched` answers with up to RESULTS rows, each
## {id, title, seconds, channel}, or an error in words.
func search(query: String) -> void:
	var q := query.strip_edges()
	if q == "":
		searched.emit.call_deferred(query, [], "nothing to search for")
		return
	_run(func() -> void:
		var out: Array = []
		var code := OS.execute(yt_dlp, ["ytsearch%d:%s" % [RESULTS, q], "--flat-playlist", "-J",
				"--no-warnings"], out, true)
		var said: String = out[0] if not out.is_empty() else ""
		var rows: Array = []
		var error := ""
		var d: Variant = JSON.parse_string(said.substr(said.find("{"))) if said.contains("{") else null
		if code != 0 or not d is Dictionary:
			error = _why(said, "the search failed")
		else:
			for e in (d as Dictionary).get("entries", []):
				if e is Dictionary and str(e.get("id", "")) != "":
					rows.append({"id": str(e["id"]), "title": str(e.get("title", "")),
							"seconds": float(e.get("duration", 0.0) if e.get("duration") != null else 0.0),
							"channel": str(e.get("channel", e.get("uploader", "")) if e.get("channel") != null else "")})
		searched.emit.call_deferred(query, rows, error))


## Bring the video `id` here and decode its sound; `fetched` answers. At once, without a thread,
## when it is here already.
func fetch(id: String) -> void:
	if id == "":
		fetched.emit.call_deferred(id, false, "not a YouTube link")
		return
	if cached(id):
		fetched.emit.call_deferred(id, true, "")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_run(func() -> void:
		var error := _fetch_now(id)
		fetched.emit.call_deferred(id, error == "", error))


## The fetch itself, on the thread: "" or why not.
static func _fetch_now(id: String) -> String:
	var video := video_path(id)
	var out: Array = []
	var code := OS.execute(yt_dlp, ["--no-playlist", "--no-warnings", "-f", FORMAT, "--merge-output-format", "mp4",
			"--match-filter", "duration < %d" % int(LONGEST), "--write-info-json",
			"-o", video.get_basename() + ".%(ext)s", "https://www.youtube.com/watch?v=" + id], out, true)
	if code != 0 or not FileAccess.file_exists(video):
		return _why(out[0] if not out.is_empty() else "", "it could not be fetched (too long, private, or gone?)")
	# yt-dlp names its info file after the video's: <id>.info.json beside <id>.mp4.
	var wav := wav_path(id)
	var partial := wav + ".part.wav"
	out.clear()
	code = OS.execute(ffmpeg, ["-v", "error", "-y", "-i", video, "-vn", "-ac", "2", "-ar", "48000",
			"-c:a", "pcm_s16le", partial], out, true)
	if code != 0 or not FileAccess.file_exists(partial):
		DirAccess.remove_absolute(partial)
		return _why(out[0] if not out.is_empty() else "", "its sound could not be decoded")
	# Whole or not at all: a WAV half written by a quit is never taken for the sound.
	DirAccess.rename_absolute(partial, wav)
	return ""


## The last line a tool said that reads like a reason, else `fallback`.
static func _why(said: String, fallback: String) -> String:
	for line in said.split("\n", false):
		if line.begins_with("ERROR:"):
			return line.trim_prefix("ERROR:").strip_edges().left(160)
	return fallback


func _run(job: Callable) -> void:
	_reap()
	var t := Thread.new()
	_threads.append(t)
	t.start(job)


func _reap() -> void:
	for t in _threads.duplicate():
		if not t.is_alive():
			t.wait_to_finish()
			_threads.erase(t)


## Wait for every search and fetch under way (quitting, and the suite).
func finish() -> void:
	for t in _threads:
		t.wait_to_finish()
	_threads.clear()
