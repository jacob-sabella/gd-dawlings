class_name MilkDownload
extends Node

## Fetches projectM's "Cream of the Crop" MilkDrop preset pack, only when the player asks (the finder's
## MORE PICTURES), into `user://milk/cream-of-the-crop/` (docs/visuals.md). The presets are their authors'
## work and carry no licence: they are fetched to this computer and never shipped with the game or kept in
## its repository.
##
## The steps: `start` downloads GitHub's zip of the pack's default branch to user://milk/cream.zip
## (HTTPRequest, a generic User-Agent, nothing about the player sent), the bytes counted as they come
## (GitHub sends no length); then `unpack` takes out only the `.milk` files, without the zip's top folder,
## on a thread so the game keeps running; then the zip is deleted and MilkLibrary rescans. A failure
## (offline, cut off, a bad zip) says so in `message` and `start` tries again. `remove` deletes the pack.

const URL := "https://codeload.github.com/projectM-visualizer/presets-cream-of-the-crop/zip/refs/heads/master"
const USER_AGENT := "Mozilla/5.0 (compatible; GodotEngine)"
const ZIP_NAME := "cream.zip"

enum State { IDLE, DOWNLOADING, UNPACKING, DONE, FAILED }

signal changed

var state: int = State.IDLE
## What to tell the player now.
var message := ""
var bytes := 0
var unpacked := 0
var to_unpack := 0
## How many presets the last unpack wrote.
var count := 0

var _http: HTTPRequest = null
var _thread: Thread = null
var _mutex := Mutex.new()
var _progress := Vector2i.ZERO


static func zip_path() -> String:
	return MilkLibrary.root.path_join(ZIP_NAME)


## Whether the pack is on this computer, and how many presets it holds.
static func installed() -> int:
	MilkLibrary.entries()
	return MilkLibrary.pack_count()


func start() -> void:
	if state == State.DOWNLOADING or state == State.UNPACKING:
		return
	DirAccess.make_dir_recursive_absolute(MilkLibrary.root)
	if _http == null:
		_http = HTTPRequest.new()
		_http.use_threads = true
		_http.request_completed.connect(_on_downloaded)
		add_child(_http)
	_http.download_file = zip_path()
	bytes = 0
	var err := _http.request(URL, PackedStringArray(["User-Agent: " + USER_AGENT]))
	if err != OK:
		_fail("Could not start the download (error %d). Check the connection and try again." % err)
		return
	state = State.DOWNLOADING
	message = "Downloading..."
	changed.emit()


func cancel() -> void:
	if state == State.DOWNLOADING and _http != null:
		_http.cancel_request()
		DirAccess.remove_absolute(zip_path())
		state = State.IDLE
		message = "Cancelled."
		changed.emit()


func _process(_delta: float) -> void:
	match state:
		State.DOWNLOADING:
			if _http != null:
				var b := _http.get_downloaded_bytes()
				if b != bytes:
					bytes = b
					message = "Downloading... %s" % String.humanize_size(bytes)
					changed.emit()
		State.UNPACKING:
			_mutex.lock()
			var p := _progress
			_mutex.unlock()
			if p.x != unpacked or p.y != to_unpack:
				unpacked = p.x
				to_unpack = p.y
				message = "Unpacking... %d of %d files" % [unpacked, to_unpack]
				changed.emit()
			if _thread != null and not _thread.is_alive():
				var n: int = _thread.wait_to_finish()
				_thread = null
				DirAccess.remove_absolute(zip_path())
				if n < 0:
					_fail("The download was not a readable zip. Try again.")
					return
				count = n
				MilkLibrary.rescan()
				state = State.DONE
				message = "Done: %d presets." % n
				changed.emit()


func _on_downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		DirAccess.remove_absolute(zip_path())
		var why := "no connection" if result in [HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE] \
				else ("the server said %d" % code if result == HTTPRequest.RESULT_SUCCESS else "it was cut off (%d)" % result)
		_fail("The download failed: %s. Try again." % why)
		return
	bytes = maxi(bytes, _http.get_downloaded_bytes())
	state = State.UNPACKING
	message = "Unpacking..."
	_progress = Vector2i.ZERO
	changed.emit()
	_thread = Thread.new()
	_thread.start(_unpack_thread)


func _unpack_thread() -> int:
	return unpack(zip_path(), MilkLibrary.pack_dir(), func(done: int, total: int) -> void:
		_mutex.lock()
		_progress = Vector2i(done, total)
		_mutex.unlock())


func _fail(why: String) -> void:
	state = State.FAILED
	message = why
	changed.emit()


func _exit_tree() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null


## Takes the `.milk` files out of the zip at `zip` into `dest`, each under its path without the zip's
## top folder; anything else, and any path that would climb out of `dest`, is left. `progress` is called
## as (done, total). Returns how many were written, or -1 if the zip cannot be read. Safe on a thread.
static func unpack(zip: String, dest: String, progress := Callable()) -> int:
	var z := ZIPReader.new()
	if z.open(zip) != OK:
		return -1
	var files := z.get_files()
	var wanted: Array[String] = []
	for f in files:
		if f.get_extension().to_lower() == "milk":
			wanted.append(f)
	var n := 0
	for i in wanted.size():
		var f := wanted[i]
		var parts := f.split("/", false)
		if parts.size() < 2:
			continue
		var rel := "/".join(parts.slice(1))
		if rel.begins_with("/") or ".." in rel.split("/") or "\\" in rel or ":" in rel:
			continue
		var out := dest.path_join(rel)
		DirAccess.make_dir_recursive_absolute(out.get_base_dir())
		var w := FileAccess.open(out, FileAccess.WRITE)
		if w != null:
			w.store_buffer(z.read_file(f))
			w.close()
			n += 1
		if progress.is_valid() and (i % 50 == 0 or i == wanted.size() - 1):
			progress.call(i + 1, wanted.size())
	z.close()
	return n


## Deletes the pack (and a leftover zip) from this computer.
static func remove() -> void:
	_remove_tree(MilkLibrary.pack_dir())
	DirAccess.remove_absolute(zip_path())
	MilkLibrary.rescan()


static func _remove_tree(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.include_hidden = true
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_remove_tree(dir.path_join(sub))
	DirAccess.remove_absolute(dir)
