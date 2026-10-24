# 2D interface loop

Goal: a full 2D DAW interface in gd-dawkit (`vendor/dawkit/addons/dawkit/ui/`), that dawlings can
toggle to. One slice per iteration. dawkit's half knows nothing of the game: it draws a
`DawKitProject` and asks a `DawKitHost` for every change. The game's half is `FlatHost`
(`core/flat/flat_host.gd`, the game's mix as a host, every edit through `DAW` so it is an edit at
the desk, replicated and undoable) and `FlatView` (`scenes/flat_view.gd`, F2, `--flat`). Every
slice: dawkit tests (`tools/test.sh`), the dawlings suite at 0 failed, a shot of what changed.

## Plan

1. [x] **Frame.** `DawKitHost`, `DawKitProjectHost`, `DawKitStudio` with the transport bar, the
   arrangement (ruler, grid, headers with M/S/R, clips with waves and notes, playhead, seek,
   drag clips across tracks, scroll and zoom, follow) and the mixer (strips, fader law, meters,
   pan, M/S/R, master). `FlatHost`, `FlatView`, F2 and `--flat`.
2. [x] **Editing clips.** Select (click, Shift or Ctrl to add, a box on an empty lane, Ctrl+A,
   Esc), split at the playhead (S), delete (Del), duplicate (Ctrl+D), trim either edge, fades by
   the handles at the name bar's corners, gain by the handle in its middle (a quarter dB a
   pixel), and a right-click menu; the selection is the desk's. Moving drags one clip, not the
   whole selection yet.
3. [x] **Tracks.** Add (the + over the headers, Ctrl+T, the track menu), remove, duplicate,
   rename (double-click the name), colour (a palette in the track menu), reorder by dragging the
   header (a folder moves with what is in it), into the folder above and out of a folder, folders
   shut and opened, every lane's height (Alt+wheel). The desk learned `move_track` for it
   (DAW.move_track, DAWBackend.move_plan; Reaper through the bridge's ReorderTracks, not yet run
   against a live Reaper).
4. [x] **Effects and sends.** Each strip's chain: + FX (the host's effects, then a list per
   plugin format), a light to bypass, click the name for its controls in the effect panel at the
   right (on, wet, every control with the effect's own words for its value where the host has
   them), right-click for earlier, later, remove, and drag a name onto another place or another
   strip's chain to move it. Sends: + SEND to a track, a level slider, right-click for before the
   fader, back to 0 dB and remove (a * marks one before the fader). The master's own chain is not
   shown yet. `--flat-fx T:N` opens an effect's controls at launch.
5. [x] **Piano roll.** Double-click a MIDI clip and its notes take the arrangement's place, with
   the whole height (the mixer comes back when it closes: its button or Esc). Drag on an empty
   row to draw a note, a note to move it in time and pitch, its right end to stretch it; right-
   click or Delete deletes, the arrows transpose the picked note (Shift an octave), a bar per note
   under them is its velocity, Q or QUANTIZE pulls every note onto the grid (1/4 to 1/32). The
   desk's note verbs take an index and a "by"; FlatHost turns an absolute move into
   transpose_note then move_note. `--flat-clip T:N` opens a clip's notes at launch.
6. [x] **The song.** The ruler (DawKitRuler, a child of the arrangement) has three rows. Markers
   and regions: double-click for a marker, drag one (a region by its middle or either end),
   double-click to rename, right-click for a region over the loop, loop this region, delete.
   Changes: the tempo's and the time signature's, double-click to set one or make a tempo change,
   drag along the song (a tempo to a beat, a signature to a bar line), right-click to add or
   delete. Bars: click to seek, drag to set the loop's range, drag its ends. COUNT 1/2 on the
   transport for the count-in. The host sends maps whole (set_tempo_points, set_meter_points);
   FlatHost names markers and regions by time, as the desk does, and sorts them for the 2D view.
7. [x] **Automation.** A track header's A lists what it can automate (volume, pan, mute, each
   send, each effect's switch and controls in a submenu; * marks the automated) and shows a lane
   for each one picked, under the track's clips (rows are as tall as their lanes now). Click a
   lane for a point (on the beat unless Alt), drag one to move it between its neighbours, right-
   click to delete; the lane's name says the value at the playhead; X hides it. Levels are drawn
   on the fader's law, pan left at the top, switches as steps (DawKitEnvelope). FlatHost renames
   lanes between the desk's (an effect by slot, a send by track index) and dawkit's. DawKitLane
   is taken by the native extension. `--flat-lane T:target[@s:v,...]` and `--flat-view N` for
   photographs.
8. [x] **Project.** FILE on the transport: new, open, open recent, save, save as, render the mix
   or a file a track (Ctrl+N, Ctrl+O, Ctrl+S, Ctrl+Shift+S), each asking before it throws away
   unsaved changes; Godot's own file dialog, filtered to .dawproject. The transport's title has a
   * for unsaved changes; the window's title is the project's while the 2D view is up and goes
   back after. A status line along the bottom says what the host says (`DawKitHost.said`: a
   save, a render, a file that would not open, and in the game everything Session.notice says,
   a guest's refusals among it) and the file and whether it is saved. New, open and save as are
   the host's (PROJECT_FILES); recent files are kept in user://recent_projects.cfg.
9. [x] **Polish.** Reaper's keys where it has one (R repeat, M marker, End, = and - zoom, besides
   the rest), and F1 lists them all (DawKitStudio.KEY_LIST, one table). Faders and pans say
   their values in their tooltips. The status line says what is under the pointer when nothing
   has just been said: a clip (track, name, where, notes or file, gain, muted, locked), a lane's
   value or point, a marker, region, change or the loop on the ruler, a note or velocity in the
   piano roll, each with what dragging or clicking it does. DawKitLook's signal colours and text
   size are settable (use_signals, set_text_scale); FlatView builds the view from the game's
   Ergonomics (its palette for the reader's colour vision, its text scale) and builds it again
   when they change, and the suite checks record, solo and mute, and the meter's three ranges,
   stay apart (separation > 0.30) under every simulated colour vision. The transport and the
   mixer scroll rather than push the window wider or the status line off at big text.
10. [x] **Headset.** The interface on a panel in the room: FlatPanel, a ControlAffordance
    holding a 1600x900 SubViewport with the DawKitStudio in it, drawn on a 1.44 x 0.81 m quad.
    Holding the menu button for XRRig.MENU_HOLD (0.8 s; a tap still escapes) or F2 puts it up
    1.1 m ahead of where you look, square to you, and puts it away. Whatever reaches into the
    room is the mouse on it: hovering moves the pointer (a white bead on the glass, since the
    glass is drawn over the room and the ray under it), a grab is the left button where the ray
    meets the glass, dragging drags, a press held still for 0.7 s is the right button (the
    menus, for a hand with one button), a nudge is the wheel. Put away, it is not drawn, not
    rendered and not in any ray's way. The suite checks the placing and facing, a point on the
    glass as a pixel and back, a press on LOOP looping the song, a held press opening the
    ruler's menu instead of clicking, and that it goes with the view. shots/flat11.png is
    it up in the simulated headset.

## Notes

- The room keeps rendering under the opaque 2D view. Hiding the 3D (`Viewport.disable_3d`, or the
  studio's visibility) would save the GPU, but has to be checked against 3D sound first: the
  venue's ambience and other players' voices are 3D players.
- FlatHost builds the whole project from the cache on the first read after any change. A drag
  is one rebuild a frame; if that shows up on 40 tracks, rebuild only the track that changed.
