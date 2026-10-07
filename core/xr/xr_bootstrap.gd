class_name XRBootstrap
extends Node

## Decide, per launch, what this participant is looking through -- and keep a failed headset from
## costing them the session.
##
## A desktop launch with no runtime, a tethered PC-VR headset, and a standalone passthrough
## headset are all first-class here, so initialisation is allowed to fail and MUST degrade to a
## working screen session rather than an error. The common mistake is to treat XR as the happy
## path and the monitor as a fallback; in a hybrid room they are peers.

signal medium_decided(medium: int)

var medium: int = Presentation.Medium.SCREEN
var xr_interface: XRInterface = null
var passthrough_active := false


## Returns the medium that was actually achieved, which may not be the one asked for.
func start(want_xr: bool, want_passthrough: bool) -> int:
	medium = Presentation.Medium.SCREEN
	if not want_xr:
		medium_decided.emit(medium)
		return medium

	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface == null or not xr_interface.is_initialized():
		if xr_interface != null and not xr_interface.initialize():
			xr_interface = null
	if xr_interface == null:
		push_warning("XRBootstrap: no OpenXR runtime; continuing as a screen participant.")
		medium_decided.emit(medium)
		return medium

	# The main viewport renders to the headset from here on. Vsync must go off: the XR runtime
	# owns frame pacing, and leaving the desktop compositor's vsync in the loop fights it.
	get_viewport().use_xr = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	medium = Presentation.Medium.VR
	if want_passthrough and _supports_passthrough():
		medium = Presentation.Medium.AR
	medium_decided.emit(medium)
	return medium


## Passthrough is an OpenXR extension, and which one depends on the vendor; it is also the single
## thing that decides whether this participant is in the ROOM or in the SET, so a silent failure
## here puts someone in a virtual studio while everyone else is pointing at real furniture.
##
## Asked BEFORE the studio exists, because the medium decides what the studio builds -- there is
## no point constructing a floor and four walls and then discovering the headset can see the real
## ones. ALPHA_BLEND is the mode a passthrough runtime reports; its absence is what distinguishes
## an opaque headset from one that can see the room.
func _supports_passthrough() -> bool:
	if xr_interface == null or not xr_interface.has_method("get_supported_environment_blend_modes"):
		return false
	var modes: Array = xr_interface.get_supported_environment_blend_modes()
	if XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND in modes:
		return true
	push_warning("XRBootstrap: this headset is opaque. Joining as a VR participant.")
	return false


## Switch the compositor over. Separate from start() and called by the studio once its
## WorldEnvironment is in the tree, because the blend mode is only half of passthrough -- the
## other half is the renderer not painting a background of its own, and there is no background
## to clear until the studio has built one. Doing both in start() is the ordering bug this
## used to have: the environment was always null that early, so passthrough never engaged.
func apply_passthrough() -> bool:
	if xr_interface == null:
		return false
	var env := get_viewport().world_3d.environment
	if env == null:
		push_warning("XRBootstrap: no environment to clear; passthrough not engaged.")
		return false
	env.background_mode = Environment.BG_CLEAR_COLOR
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))

	passthrough_active = xr_interface.set_environment_blend_mode(
			XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND)
	if not passthrough_active:
		push_warning("XRBootstrap: runtime refused alpha-blend at the last moment; staying opaque.")
	return passthrough_active
