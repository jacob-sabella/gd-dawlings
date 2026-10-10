class_name TourDeck
extends RefCounted

## The gear draft: three boons (two of the three weighted to show up, with a chance one rides
## in cursed) offered after every brief. `apply` on the card chosen is the only place any of
## this touches the DAW, and only through `DAW`'s own verbs.

## Boons the draft offers. A card with no DAW effect (`loose_tempo`) is pure run-state.
static func all_cards() -> Array[TourCard]:
	var out: Array[TourCard] = []

	var extra_track := TourCard.new()
	extra_track.id = &"extra_track"
	extra_track.title = "Extra Track"
	extra_track.description = "One more track on the desk, free and clear."
	extra_track.is_curse = false
	extra_track._effect = func(_run: TourRun) -> void:
		DAW.add_track(DAW.state.track_indices().size() + 1, "Tour Gear")
	out.append(extra_track)

	var free_effect := TourCard.new()
	free_effect.id = &"free_effect"
	free_effect.title = "Free Effect"
	free_effect.description = "A plugin on the house, dropped on your first track."
	free_effect.is_curse = false
	free_effect._effect = func(_run: TourRun) -> void:
		var tracks := DAW.state.track_indices()
		if tracks.is_empty() or DAW.state.fx_choices.is_empty():
			return
		var plugin: String = DAW.state.fx_choices[0][0]
		DAW.add_fx(tracks[0], plugin, -1)
	out.append(free_effect)

	var loose_tempo := TourCard.new()
	loose_tempo.id = &"loose_tempo"
	loose_tempo.title = "Loose Tempo"
	loose_tempo.description = "The pocket check's beat window opens up, for the rest of the run."
	loose_tempo.is_curse = false
	loose_tempo._effect = func(run: TourRun) -> void:
		run.tempo_tolerance_mult *= 1.5
	out.append(loose_tempo)

	var tight_tempo := TourCard.new()
	tight_tempo.id = &"tight_tempo"
	tight_tempo.title = "Tight Tempo"
	tight_tempo.description = "A curse: the pocket check's beat window closes in."
	tight_tempo.is_curse = true
	tight_tempo._effect = func(run: TourRun) -> void:
		run.tempo_tolerance_mult *= 0.6
	out.append(tight_tempo)

	var muted_track := TourCard.new()
	muted_track.id = &"muted_track"
	muted_track.title = "Muted Track"
	muted_track.description = "A curse: one of your tracks goes quiet."
	muted_track.is_curse = true
	# One of the tracks still sounding: muting one already muted is no curse at all, and was
	# the one roll that made this card do nothing (and its test flake) now and then.
	muted_track._effect = func(_run: TourRun) -> void:
		var tracks := DAW.state.track_indices().filter(
				func(i: int) -> bool: return not DAW.state.track(i).mute)
		if tracks.is_empty():
			return
		var rng := RandomNumberGenerator.new()
		DAW.set_track_mute(tracks[rng.randi() % tracks.size()], true)
	out.append(muted_track)

	var shorter_clock := TourCard.new()
	shorter_clock.id = &"shorter_clock"
	shorter_clock.title = "Shorter Clock"
	shorter_clock.description = "A curse: the next brief's clock runs down faster."
	shorter_clock.is_curse = true
	shorter_clock._effect = func(run: TourRun) -> void:
		run.next_brief_seconds_mult *= 0.75
	out.append(shorter_clock)

	return out


## Three cards for the draft: never one `exclude` already names (a run never offers a card it
## already holds), weighted toward gear, with a chance one of the three rides in as a curse --
## matching "curses can ride along".
static func draw(rng: RandomNumberGenerator, exclude: Array[StringName]) -> Array[TourCard]:
	var pool: Array[TourCard] = []
	for c in all_cards():
		if not (c.id in exclude):
			pool.append(c)
	var boons: Array[TourCard] = pool.filter(func(c: TourCard) -> bool: return not c.is_curse)
	var curses: Array[TourCard] = pool.filter(func(c: TourCard) -> bool: return c.is_curse)
	_shuffle(boons, rng)
	_shuffle(curses, rng)

	var curse_slot := not curses.is_empty() and rng.randf() < 0.4
	var boon_slots := 3 - (1 if curse_slot else 0)
	var picked: Array[TourCard] = []
	for c in boons:
		if picked.size() >= boon_slots:
			break
		picked.append(c)
	if curse_slot:
		picked.append(curses[0])
	# Backfill from whatever is left, without a duplicate, so a thin pool (a run that has
	# already drafted most of the deck) still offers three where it can.
	if picked.size() < 3:
		for c in boons + curses:
			if picked.size() >= 3:
				break
			if not (c in picked):
				picked.append(c)
	_shuffle(picked, rng)
	return picked


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
