# xr-simulator

zoyter's Godot XR Simulator, vendored unmodified from
https://github.com/zoyter/godot-xr-simulator (commit 5f12705, MIT, Godot 4.7). It drives the
`XRCamera3D` and two `XRController3D` nodes from the mouse and keyboard so the VR and AR layouts
can be tried on a desktop with no headset. It only works when run from the editor binary
(`OS.has_feature("editor")`), never in an export.

dawlings adds it only when launched with `--xr-sim` (see `core/xr/xr_bootstrap.gd`):

    godot --path . -- --xr-sim --built-in          simulated VR headset
    godot --path . -- --xr-sim --ar --built-in     simulated passthrough headset: no virtual set

Mouse looks around; scroll changes height. Hold Q (left) or E (right) to move that controller
with the mouse (left button = trigger, right button = grip, scroll = reach, Shift = rotate);
WASD and the arrow keys are the two thumbsticks; 1-8, -, = and Enter are the face buttons.
Escape frees the mouse.
