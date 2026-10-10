class_name TourProject
extends RefCounted

## Swapping the real project out for a run's throwaway one, and back again, exactly.
##
## Entirely through calls that already exist and that other code already uses for the same
## job: `ProjectBridge.capture`/`ProjectBridge.load` are exactly what `ProjectFiles.save`/
## `ProjectFiles.open` call, used here purely in memory, with no disk I/O at all.

## A blank throwaway project for one brief: a handful of tracks at a common tempo, the same
## shape `ProjectFiles.blank()` builds for a brand new project.
static func blank_for(brief: TourBrief) -> DawKitProject:
	var p := DawKitProject.new()
	p.title = "Tour: %s" % brief.title
	p.tempo = 120.0
	p.length = maxf(brief.seconds, 30.0)
	for i in 4:
		p.add_track("Track %d" % (i + 1))
	return p


## In-memory snapshot of everything `ProjectBridge.capture` round-trips: the project and the
## path/title it was known by, so `restore` can put both back.
static func capture(backend: OfflineBackend) -> Dictionary:
	return {"project": ProjectBridge.capture(backend), "path": backend.project_path}


## Replaces the backend's project with `snapshot`'s, and restores the path/title it had. The
## same `ProjectBridge.load` every other "swap the whole project" moment in this codebase uses,
## so this is an exact restore of everything a `DawKitProject` represents.
static func restore(backend: OfflineBackend, snapshot: Dictionary) -> void:
	ProjectBridge.load(snapshot["project"], backend)
	backend.project_path = snapshot["path"]
	backend.name_project()
