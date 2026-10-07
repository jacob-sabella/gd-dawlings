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
	if want_passthrough and _try_passthrough():
		medium = Presentation.Medium.AR
	medium_decided.emit(medium)
	return medium


## Passthrough is an OpenXR extension, and which one depends on the vendor; it is also the single
## thing that decides whether this participant is in the ROOM or in the SET, so a silent failure
## here puts someone in a virtual studio while everyone else is pointing at real furniture.
func _try_passthrough() -> bool:
	var env := get_viewport().world_3d.environment
	if env == null:
		push_warning("XRBootstrap: passthrough needs a transparent environment background.")
		return false
	# The scene is composited over the real world, so the renderer must not paint one of its own.
	env.background_mode = Environment.BG_CLEAR_COLOR
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))

	if xr_interface.has_method("set_environment_blend_mode"):
		# ALPHA_BLEND is the standard mode a passthrough runtime reports; its absence is what
		# distinguishes an opaque headset from one that can see the room.
		var ok: bool = xr_interface.set_environment_blend_mode(XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND)
		passthrough_active = ok
		if not ok:
			push_warning("XRBootstrap: runtime refused alpha-blend; this headset is opaque. Joining as a VR participant.")
		return ok
	return false
