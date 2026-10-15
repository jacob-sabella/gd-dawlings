class_name ReaperPluginWindow
extends PluginWindow

## A plugin's floating window in Reaper, read off the X display and worked from here.
##
## The reading is native/plugin_view.c, a few hundred lines of Xlib run as a child process: it
## finds the window by its title, answers each "f" on its stdin with the picture, and passes
## clicks, drags and the wheel back into the window under the point. The window can be on a
## workspace nobody is looking at -- it is read, not looked at -- and nothing is ever clicked at
## the real pointer, so the desktop is never touched by mistake.
##
## A thread does the asking and the reading, because a picture is three megabytes and arrives
## when the helper has it. The frame lands in an Image under a lock; `poll` on the main thread
## turns the newest one into the texture. Pointer input queues the same way, and the thread
## passes it on before it next asks for a picture, so a click is never stuck behind a frame.
##
## Linux and X only, which is where Reaper's plugin windows are on this desk (Reaper itself,
## and Windows plugins under yabridge, are XWayland windows on a Wayland session). Elsewhere
## `available` says no and the tablet keeps its knobs.

## How often a picture is asked for. A plugin's meters move at about this rate on its own screen.
const FRAME_MSEC := 50
const SOURCE := "res://native/plugin_view.c"
const BUILT := "user://bin/plugin_view"

static var _helper := ""
static var _helper_checked := false

var _pid := -1
var _io: FileAccess
var _thread: Thread
var _lock := Mutex.new()
var _running := false
var _queue: PackedStringArray = []
var _frame: Image
var _fresh := false
var _size := Vector2i.ZERO
var _on_close: Callable


## Whether a Reaper running on this machine works its own windows from sent clicks: it was started
## with native/reaper_pointer.c preloaded (tools/reaper_rig.sh does), which it then has mapped.
## Without it ReaEQ and the rest show here but ignore the tablet's hand. Looked up again after a
## few seconds, since Reaper can be restarted under a running game.
static func reaper_takes_clicks() -> bool:
	var now := Time.get_ticks_msec()
	if _takes_clicks_at >= 0 and now - _takes_clicks_at < 3000:
		return _takes_clicks
	_takes_clicks_at = now
	_takes_clicks = false
	if OS.get_name() != "Linux":
		return false
	for pid in DirAccess.get_directories_at("/proc"):
		if not pid.is_valid_int() or _first_line("/proc/%s/comm" % pid) != "reaper":
			continue
		var maps := FileAccess.open("/proc/%s/maps" % pid, FileAccess.READ)
		if maps == null:
			continue
		while not maps.eof_reached():
			if maps.get_line().ends_with("/reaper_pointer.so"):
				_takes_clicks = true
				return true
	return false


static var _takes_clicks := false
static var _takes_clicks_at := -1


static func _first_line(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_line().strip_edges() if f != null else ""


## Whether plugin windows can be shown here at all: an X display, and the helper built.
static func available() -> bool:
	return OS.get_name() == "Linux" and OS.get_environment("DISPLAY") != "" and helper() != ""


## The helper's path, built from source the first time it is wanted and again whenever the
## source is newer, or "" when it cannot be: no C compiler, or no X11 headers.
static func helper() -> String:
	if _helper_checked:
		return _helper
	_helper_checked = true
	var source := ProjectSettings.globalize_path(SOURCE)
	var built := ProjectSettings.globalize_path(BUILT)
	if not FileAccess.file_exists(source):
		return ""
	if FileAccess.file_exists(built) \
			and FileAccess.get_modified_time(built) >= FileAccess.get_modified_time(source):
		_helper = built
		return _helper
	DirAccess.make_dir_recursive_absolute(built.get_base_dir())
	var out: Array = []
	if OS.execute("cc", ["-O2", "-o", built, source, "-lX11", "-lpthread"], out, true) == 0:
		_helper = built
	else:
		push_warning("plugin windows: could not build the helper: %s" % str(out))
	return _helper


## A window not yet found: `start` it with the title once the DAW has said what that is.
## `on_close` is called once, when this is closed.
static func opening(on_close: Callable) -> ReaperPluginWindow:
	var w := ReaperPluginWindow.new()
	w._on_close = on_close
	return w


## Look for the window whose title has `title` in it, and keep showing it. Nothing once closed.
func start(title: String) -> void:
	if not _open or _running or title.is_empty():
		return
	var path := helper()
	var started: Dictionary = OS.execute_with_pipe(path, [title], true) if path != "" else {}
	if started.is_empty():
		close()
		return
	_pid = int(started["pid"])
	_io = started["stdio"]
	_running = true
	_thread = Thread.new()
	_thread.start(_read_frames)


func poll() -> void:
	var frame: Image = null
	_lock.lock()
	if _fresh:
		frame = _frame
		_fresh = false
	_lock.unlock()
	if frame == null:
		return
	if _texture != null and _texture.get_size() == Vector2(frame.get_size()):
		_texture.update(frame)
	else:
		_texture = ImageTexture.create_from_image(frame)


func pixel_size() -> Vector2i:
	_lock.lock()
	var s := _size
	_lock.unlock()
	return s


func is_open() -> bool:
	return _open


func close() -> void:
	if not _open:
		return
	_open = false
	_lock.lock()
	_queue.append("q")
	_running = false
	_lock.unlock()
	if _thread != null:
		_thread.wait_to_finish()
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	if _on_close.is_valid():
		_on_close.call()


func _send(kind: StringName, at: Vector2i, extra: int) -> void:
	if not _open:
		return
	var line := ""
	match kind:
		&"move": line = "m %d %d" % [at.x, at.y]
		&"down": line = "d %d %d %d" % [at.x, at.y, extra]
		&"up": line = "u %d %d %d" % [at.x, at.y, extra]
		&"wheel": line = "w %d %d %d" % [at.x, at.y, extra]
	_lock.lock()
	_queue.append(line)
	_lock.unlock()


func _read_frames() -> void:
	var next := 0
	while true:
		_lock.lock()
		var lines := _queue
		_queue = []
		var running := _running
		_lock.unlock()
		if not lines.is_empty():
			_io.store_string("\n".join(lines) + "\n")
			_io.flush()
		if not running:
			return
		var now := Time.get_ticks_msec()
		if now < next:
			OS.delay_msec(mini(5, next - now))
			continue
		next = now + FRAME_MSEC
		if not _read_one():
			_lock.lock()
			_running = false
			_lock.unlock()
			return


## One frame, asked for and read. False when the helper has gone.
func _read_one() -> bool:
	_io.store_string("f\n")
	_io.flush()
	var head := _exactly(16)
	if head.size() < 16 or head.slice(0, 4).get_string_from_ascii() != "PV02":
		return false
	var w := head.decode_u32(4)
	var h := head.decode_u32(8)
	var same := head.decode_u32(12) == 1
	if w == 0 or h == 0 or same:
		_lock.lock()
		_size = Vector2i(w, h) if same else Vector2i.ZERO
		_lock.unlock()
		return true
	var pixels := _exactly(w * h * 4)
	if pixels.size() < w * h * 4:
		return false
	var image := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, pixels)
	# Here, off the main thread: a tablet across the room shows a plugin a few hundred pixels
	# wide, and without the smaller copies its lettering sparkles.
	image.generate_mipmaps()
	_lock.lock()
	_frame = image
	_fresh = true
	_size = Vector2i(w, h)
	_lock.unlock()
	return true


## `n` bytes from the helper, however many reads they take; fewer only if it has gone.
func _exactly(n: int) -> PackedByteArray:
	var out := PackedByteArray()
	while out.size() < n:
		var got := _io.get_buffer(n - out.size())
		if got.is_empty():
			break
		out.append_array(got)
	return out
