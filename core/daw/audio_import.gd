class_name AudioImport
extends RefCounted

## Sound files from this machine into the project: the host's own, picked from a dialog or
## dropped on the window. Each is brought in by dawkit (DawKitAudioFile.bring_in) to where takes
## live, so every backend that places a recorded take places it the same way, and the project
## file carries it like one.

## What the file dialog offers. Anything else dropped is still tried, and says why it failed.
const EXTENSIONS := ["wav", "wave", "aif", "aiff", "aifc", "flac", "ogg", "mp3"]


## A name for the file among the takes: its own, as a WAV (which is what it becomes), with a
## number added when `taken` says that name is in use.
static func file_name_for(path: String, taken: Callable) -> String:
	var base := path.get_file().get_basename().validate_filename().strip_edges()
	if base.is_empty():
		base = "Audio"
	var name := base + ".wav"
	var n := 2
	while taken.call(name):
		name = "%s %d.wav" % [base, n]
		n += 1
	return name


## Where a file goes when nobody said: the track of the first selected item, else the first
## armed track, else the first track that is not a folder.
static func target_track(state: MixState) -> int:
	var picked: Array = state.selected_items()
	if not picked.is_empty():
		return picked[0][0]
	var order: Array = state.track_indices().filter(func(i): return state.in_project(i))
	for i in order:
		if state.track(i).rec_arm:
			return i
	for i in order:
		if state.track(i).folder_depth <= 0:
			return i
	return order[0] if not order.is_empty() else 0
