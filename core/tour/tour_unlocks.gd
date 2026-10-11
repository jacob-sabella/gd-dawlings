class_name TourUnlocks
extends RefCounted

## What a run leaves behind: runs played, runs won, reputation, cosmetics unlocked. Its own
## file, its own format -- never mixed with `layout_profile.cfg` or a project.
##
## Modeled on `LayoutProfile`'s own `ConfigFile` save/load, down to the overridable `save_path`
## so a test can exercise this without writing over whoever is running the test's own unlocks.

const SAVE_PATH := "user://tour_unlocks.cfg"

var save_path := SAVE_PATH

var runs: int = 0
var wins: int = 0
var reputation: int = 0
var cosmetics: Array[StringName] = []


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("unlocks", "runs", runs)
	cfg.set_value("unlocks", "wins", wins)
	cfg.set_value("unlocks", "reputation", reputation)
	cfg.set_value("unlocks", "cosmetics", (cosmetics as Array).map(func(c): return String(c)))
	cfg.save(save_path)


func load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return
	runs = int(cfg.get_value("unlocks", "runs", runs))
	wins = int(cfg.get_value("unlocks", "wins", wins))
	reputation = int(cfg.get_value("unlocks", "reputation", reputation))
	var saved: Array = cfg.get_value("unlocks", "cosmetics", [])
	cosmetics.assign(saved.map(func(c): return StringName(c)))


## One run's end, recorded and saved at once. A win earns a point of reputation; a loss costs
## one, floored at 0 -- reputation never goes negative, so a band on a losing streak is never
## worse off than a band that has never played, only no better off.
func record_run(won: bool) -> void:
	runs += 1
	if won:
		wins += 1
		reputation += 1
	else:
		reputation = maxi(reputation - 1, 0)
	save()
