// plugin_view: show a plugin's own window somewhere else, and pass clicks back into it.
//
//   plugin_view "<the window's title, or part of it>" [--in-place]
//
// Reads commands on stdin, one per line, and answers frames on stdout:
//   f            a frame: "PV02", width, height, same (u32 little-endian each), then -- unless
//                `same` is 1, the picture unchanged since the last one -- width*height RGBA
//                bytes. Width and height are 0 while no window has that title.
//   m X Y        the pointer moves to X,Y (picture pixels)
//   d X Y B      button B (1 left, 2 middle, 3 right) goes down at X,Y
//   u X Y B      and up
//   w X Y N      the wheel turns N notches at X,Y (positive is up)
//   q            quit
//
// The window is read with XGetImage, which works on a window nobody is looking at -- the plugin's
// window can sit on a workspace nobody is on -- and input is SENT to the window under the point
// rather than faked at the pointer, so nothing else on the desktop is ever clicked by mistake.
//
// The picture is the plugin's own part of the window: Reaper wraps it in a strip of its own
// (preset menu, parameter menu, routing), which is the tablet's job to replace, not to show.
//
// A plugin's menus and dropdowns are windows of their own; see "Menus" below.
//
// Built on demand by core/reaper/reaper_plugin_window.gd:
//   cc -O2 -o plugin_view plugin_view.c -lX11 -lpthread
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/Xutil.h>
#include <X11/keysym.h>
#include <ctype.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <spawn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

extern char **environ;

static Display *dpy;
static Window top;
static Window target;
static const char *wanted;
static unsigned char *last;
static size_t last_size;

// The title says `wanted`, and not as the start of a longer number: "Track 1" is not "Track 12".
static int says(const char *title) {
	const char *at = title;
	size_t n = strlen(wanted);
	while ((at = strstr(at, wanted)) != NULL) {
		if (!isdigit((unsigned char)at[n])) return 1;
		at++;
	}
	return 0;
}

static int title_has(Window w) {
	Atom net_name = XInternAtom(dpy, "_NET_WM_NAME", False);
	Atom utf8 = XInternAtom(dpy, "UTF8_STRING", False);
	Atom type; int fmt; unsigned long n, after; unsigned char *data = NULL;
	if (XGetWindowProperty(dpy, w, net_name, 0, 1024, False, utf8, &type, &fmt, &n, &after, &data) == Success && data) {
		int hit = says((char *)data);
		XFree(data);
		if (hit) return 1;
	}
	char *name = NULL;
	int hit = 0;
	if (XFetchName(dpy, w, &name) && name) {
		hit = says(name);
		XFree(name);
	}
	return hit;
}

static Window find(Window w, int depth) {
	if (title_has(w)) return w;
	if (depth > 3) return 0;
	Window root, parent, *kids = NULL; unsigned int n = 0;
	if (!XQueryTree(dpy, w, &root, &parent, &kids, &n)) return 0;
	Window found = 0;
	for (unsigned int i = 0; i < n && !found; i++) found = find(kids[i], depth + 1);
	if (kids) XFree(kids);
	return found;
}

// The biggest child, when it is most of the window: the plugin's own part of Reaper's.
static Window content(Window top) {
	XWindowAttributes a;
	if (!XGetWindowAttributes(dpy, top, &a)) return top;
	Window root, parent, *kids = NULL; unsigned int n = 0;
	if (!XQueryTree(dpy, top, &root, &parent, &kids, &n)) return top;
	Window best = top; long area = (long)a.width * a.height / 2;
	for (unsigned int i = 0; i < n; i++) {
		XWindowAttributes k;
		if (XGetWindowAttributes(dpy, kids[i], &k) && k.map_state == IsViewable && (long)k.width * k.height > area) {
			best = kids[i];
			area = (long)k.width * k.height;
		}
	}
	if (kids) XFree(kids);
	return best;
}

static int ignore_errors(Display *d, XErrorEvent *e) { (void)d; (void)e; return 0; }

// Where the plugin's window is kept while it is shown: a window of ours, far off every screen,
// that it is reparented into -- what Reaper itself does to dock a plugin in its FX chain. The
// compositor then has no top-level window to put on the desktop, and the plugin neither knows nor
// minds: it is still mapped, so it still draws, and XGetImage still reads it.
static Window holder;
// Whether to keep the window in `holder`; "--in-place" leaves it where the DAW put it.
static int keep = 1;

static Window entered;

// Where the holder is put: off every screen, for as long as the compositor leaves it there.
#define HOLDER_X (-30000)

// Where the kept window was last told it is.
static int told, told_x, told_y;

// A window manager tells a window where it is on the screen whenever it moves it, and Reaper's own
// windows (SWELL, on GDK) believe that over anything else: a click's screen position is turned
// back into a point in the window by subtracting where the window last heard it was. Moved into
// the holder without being told, Reaper's window still thinks it is wherever the desktop had it,
// and every click lands that far away. So it is told, the way a window manager would -- and told
// again whenever that is no longer true: the compositor may move the holder later, and the window
// inside it hears nothing of that. What it is told is the truth, which a plugin under Wine needs
// as much as Reaper does: yabridge passes it on, and Wine works its own clicks out from it.
static void tell_where(Window w) {
	XWindowAttributes a;
	int rx = 0, ry = 0;
	Window child;
	if (!XGetWindowAttributes(dpy, w, &a)) return;
	XTranslateCoordinates(dpy, w, DefaultRootWindow(dpy), 0, 0, &rx, &ry, &child);
	if (told && rx == told_x && ry == told_y) return;
	XEvent e; memset(&e, 0, sizeof e);
	e.xconfigure.type = ConfigureNotify;
	e.xconfigure.display = dpy;
	e.xconfigure.event = w;
	e.xconfigure.window = w;
	e.xconfigure.x = rx; e.xconfigure.y = ry;
	e.xconfigure.width = a.width; e.xconfigure.height = a.height;
	XSendEvent(dpy, w, False, StructureNotifyMask, &e);
	told = 1; told_x = rx; told_y = ry;
	entered = 0;
}

static void adopt(Window w) {
	XWindowAttributes a;
	if (!w || !XGetWindowAttributes(dpy, w, &a)) return;
	Window root, parent, *kids = NULL; unsigned int n = 0;
	if (XQueryTree(dpy, w, &root, &parent, &kids, &n)) {
		if (kids) XFree(kids);
		if (holder && parent == holder) return;
	}
	XSetWindowAttributes at; memset(&at, 0, sizeof at);
	at.override_redirect = True;
	if (holder) XDestroyWindow(dpy, holder);
	holder = XCreateWindow(dpy, DefaultRootWindow(dpy), HOLDER_X, 0, a.width > 0 ? a.width : 1, a.height > 0 ? a.height : 1,
			0, CopyFromParent, InputOutput, CopyFromParent, CWOverrideRedirect, &at);
	XMapWindow(dpy, holder);
	// If this process ever goes without saying so, the window goes back to the desktop rather
	// than being destroyed with its holder.
	XAddToSaveSet(dpy, w);
	XReparentWindow(dpy, w, holder, 0, 0);
	XMapWindow(dpy, w);
	XSync(dpy, False);
	told = 0;
	tell_where(w);
}

// Gives the window back to the desktop, so closing the tablet's view leaves it as it was.
static void release(Window w) {
	if (w && holder) {
		XReparentWindow(dpy, w, DefaultRootWindow(dpy), 0, 0);
		XRemoveFromSaveSet(dpy, w);
		XDestroyWindow(dpy, holder);
		XSync(dpy, False);
		holder = 0;
	}
}

// --- Menus ---------------------------------------------------------------------------------------
//
// A plugin's dropdown or right-click menu is a window of its own on the desktop. One that maps just
// after a click sent here, from the program drawing the plugin (Reaper, or yabridge's Wine host),
// and is not a window of its own (an ordinary one or a dialog, with a title bar: those stay on the
// desktop, to be used there) is drawn over the picture where it opened, and the pointer goes to it.
// A click outside it closes it, as on a desktop.
//
// It is left where it is: a menu taken out of the window manager's hands closes (Wine works out it
// moved; SWELL loses the focus). An override-redirect menu is where the plugin put it, as far off
// the screen as the plugin's window. One the window manager places would be in the middle of the
// desktop, so on Hyprland a rule, on only while the plugin is being clicked, sends Reaper's menus
// and Wine's untitled ones to a special workspace nobody looks at, without the focus. Elsewhere
// those are left on the desktop.

#define MAX_POPUPS 8
// How soon after a press a window opening is taken as the menu it opened.
#define MENU_WITHIN 2.0

typedef struct {
	Window window;
	int x, y, width, height; // in the picture
} Popup;

static Popup popups[MAX_POPUPS];
static int n_popups;
static double last_press = -1e9;
static int press_x, press_y;
static int swallowing; // the release of a click outside an open menu, which only closed it
static int in_menu; // whether the last `under` found an open menu
static int pointer_x = -1, pointer_y = -1;
static double last_motion;
static int nudged;

// Where each new window asked to be, before any window manager placed it.
typedef struct { Window w; int x, y; double at; } Asked;
static Asked asked[64];

static double seconds(void) {
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec + t.tv_nsec / 1e9;
}

static long pid_of(Window w) {
	static Atom pid_atom;
	if (!pid_atom) pid_atom = XInternAtom(dpy, "_NET_WM_PID", False);
	Atom type; int format; unsigned long n, after; unsigned char *data = NULL;
	long pid = 0;
	if (XGetWindowProperty(dpy, w, pid_atom, 0, 1, False, XA_CARDINAL, &type, &format, &n, &after, &data) == Success
			&& data && n == 1 && format == 32)
		pid = (long)*(unsigned long *)data;
	if (data) XFree(data);
	return pid;
}

// Whether `pid` draws in `w` or the windows a few levels under it.
static int draws_in(Window w, long pid, int depth) {
	if (pid_of(w) == pid) return 1;
	if (depth >= 4) return 0;
	Window root, parent, *kids = NULL; unsigned int n = 0;
	if (!XQueryTree(dpy, w, &root, &parent, &kids, &n)) return 0;
	int found = 0;
	for (unsigned int i = 0; i < n && !found; i++) found = draws_in(kids[i], pid, depth + 1);
	if (kids) XFree(kids);
	return found;
}

// The first window under `w` drawn by another program than the one whose window it is: yabridge's
// Wine host's, in Reaper's. 0 for Reaper's own plugins.
static Window first_of_another(Window w, long owner, int depth) {
	long p = pid_of(w);
	if (p && p != owner) return w;
	if (depth >= 4) return 0;
	Window root, parent, *kids = NULL, found = 0; unsigned int n = 0;
	if (!XQueryTree(dpy, w, &root, &parent, &kids, &n)) return 0;
	for (unsigned int i = 0; i < n && !found; i++) found = first_of_another(kids[i], owner, depth + 1);
	if (kids) XFree(kids);
	return found;
}

// Whether `w` asks for no title bar or frame (Motif's hints, which Wine and GTK set for menus).
static int undecorated(Window w) {
	static Atom motif;
	if (!motif) motif = XInternAtom(dpy, "_MOTIF_WM_HINTS", False);
	Atom type; int format; unsigned long n, after; unsigned char *data = NULL;
	int bare = 0;
	if (XGetWindowProperty(dpy, w, motif, 0, 5, False, AnyPropertyType, &type, &format, &n, &after, &data) == Success
			&& data && format == 32 && n >= 3) {
		unsigned long *hints = (unsigned long *)data;
		bare = (hints[0] & 2) && hints[2] == 0;
	}
	if (data) XFree(data);
	return bare;
}

// An ordinary window or a dialog with a title bar: a window of its own.
static int of_its_own(Window w) {
	static Atom type_atom, normal, dialog;
	if (!type_atom) {
		type_atom = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE", False);
		normal = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE_NORMAL", False);
		dialog = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE_DIALOG", False);
	}
	Atom type; int format; unsigned long n, after; unsigned char *data = NULL;
	int own = 0;
	if (XGetWindowProperty(dpy, w, type_atom, 0, 8, False, XA_ATOM, &type, &format, &n, &after, &data) == Success
			&& data && format == 32 && n > 0) {
		Atom first = (Atom)((unsigned long *)data)[0];
		own = first == normal || first == dialog;
	}
	if (data) XFree(data);
	if (!own) return 0;
	// SWELL's menus say they are ordinary windows; they are titled "menu".
	char *name = NULL;
	int menu = XFetchName(dpy, w, &name) && name && strcmp(name, "menu") == 0;
	if (name) XFree(name);
	return !menu && !undecorated(w);
}

// --- Hyprland ---

static int on_hyprland(void) {
	static int on = -1;
	if (on < 0) on = getenv("HYPRLAND_INSTANCE_SIGNATURE") && !getenv("DAWLINGS_NO_HYPRLAND_RULE");
	return on;
}

static const char *HYPR_MENU_RULE =
	"if not dawlings_menu_rules then\n"
	"  dawlings_menu_rules = {\n"
	"    hl.window_rule({ name = 'dawlings-reaper-menus', match = { class = [[^REAPER$]], title = [[^menu$]] },\n"
	"      workspace = 'special:dawkit silent', no_initial_focus = true, no_anim = true }),\n"
	"    hl.window_rule({ name = 'dawlings-wine-menus', match = { class = [[^.*\\.exe$]], title = [[^(menu)?$]], xwayland = true },\n"
	"      workspace = 'special:dawkit silent', no_initial_focus = true, no_anim = true }),\n"
	"  }\n"
	"end\n"
	"for _, r in ipairs(dawlings_menu_rules) do r:set_enabled(true) end\n"
	"dawlings_menu_turn = (dawlings_menu_turn or 0) + 1\n"
	"local turn = dawlings_menu_turn\n"
	"hl.timer(function()\n"
	"  if dawlings_menu_turn == turn then for _, r in ipairs(dawlings_menu_rules) do r:set_enabled(false) end end\n"
	"end, { timeout = 4000, type = 'oneshot' })\n";

static double hypr_renewed = -1e9;

// The rule on (again) for the next few seconds, at most once a second; waited for, since the press
// it comes before may open a menu. It switches itself off, so a helper that dies leaves nothing on.
static void keep_menus_hidden(void) {
	if (!on_hyprland() || seconds() - hypr_renewed < 1.0) return;
	hypr_renewed = seconds();
	char *argv[] = { "hyprctl", "eval", (char *)HYPR_MENU_RULE, NULL };
	posix_spawn_file_actions_t quiet;
	posix_spawn_file_actions_init(&quiet);
	posix_spawn_file_actions_addopen(&quiet, 0, "/dev/null", O_RDONLY, 0);
	posix_spawn_file_actions_addopen(&quiet, 1, "/dev/null", O_WRONLY, 0);
	posix_spawn_file_actions_addopen(&quiet, 2, "/dev/null", O_WRONLY, 0);
	pid_t pid;
	if (posix_spawnp(&pid, "hyprctl", &quiet, NULL, argv, environ) == 0) waitpid(pid, NULL, 0);
	else hypr_renewed = 1e18;
	posix_spawn_file_actions_destroy(&quiet);
}

static int menus_stay_put(void) {
	return on_hyprland() && hypr_renewed < 1e17 && seconds() - hypr_renewed < 4.0;
}

// --- The active window ---
//
// Wine takes the window the window manager last named active to be the one in front, and a plugin
// whose window is not in front closes its menus as they open. The plugin's window is never really
// focused -- the game's is -- so from just before a press until its menus close, Wine's window is
// named active. The window manager names its own again as each menu maps, and Wine reads that
// within a millisecond, so a thread on a connection of its own names the plugin's again as soon as
// it changes. (Reaper's own windows are told they have the focus by native/reaper_pointer.c.)

static pthread_mutex_t active_lock = PTHREAD_MUTEX_INITIALIZER;
static Window active_window;
static double active_until;

static void name_active(Display *d, Window w) {
	Atom a = XInternAtom(d, "_NET_ACTIVE_WINDOW", False);
	unsigned long v = w;
	XChangeProperty(d, DefaultRootWindow(d), a, XA_WINDOW, 32, PropModeReplace, (unsigned char *)&v, 1);
	XFlush(d);
}

static void *keep_active(void *unused) {
	(void)unused;
	Display *d = XOpenDisplay(NULL);
	if (!d) return NULL;
	Atom a = XInternAtom(d, "_NET_ACTIVE_WINDOW", False);
	XSelectInput(d, DefaultRootWindow(d), PropertyChangeMask);
	XFlush(d);
	struct pollfd fd = { ConnectionNumber(d), POLLIN, 0 };
	for (;;) {
		poll(&fd, 1, 200);
		int changed = 0;
		while (XPending(d)) {
			XEvent e;
			XNextEvent(d, &e);
			changed |= e.type == PropertyNotify && e.xproperty.atom == a;
		}
		pthread_mutex_lock(&active_lock);
		Window w = active_window;
		int holding = seconds() < active_until;
		pthread_mutex_unlock(&active_lock);
		if (!changed || !holding || !w) continue;
		Atom type; int format; unsigned long n, after; unsigned char *data = NULL;
		unsigned long now = 0;
		if (XGetWindowProperty(d, DefaultRootWindow(d), a, 0, 1, False, XA_WINDOW, &type, &format, &n, &after, &data) == Success
				&& data && n == 1)
			now = *(unsigned long *)data;
		if (data) XFree(data);
		if (now != w) name_active(d, w);
	}
	return NULL;
}

static void hold_active(double for_seconds) {
	if (!top) return;
	Window w = first_of_another(top, pid_of(top), 0);
	if (!w) return;
	static int started;
	if (!started) {
		started = 1;
		pthread_t t;
		pthread_create(&t, NULL, keep_active, NULL);
		pthread_detach(t);
	}
	pthread_mutex_lock(&active_lock);
	int again = active_window == w && seconds() < active_until;
	active_window = w;
	active_until = seconds() + for_seconds;
	pthread_mutex_unlock(&active_lock);
	if (!again) name_active(dpy, w);
}

// --- Taking menus in ---

static void window_created(XCreateWindowEvent *c) {
	int slot = 0;
	double oldest = 1e18;
	for (int i = 0; i < 64; i++) {
		if (!asked[i].w) { slot = i; break; }
		if (asked[i].at < oldest) { oldest = asked[i].at; slot = i; }
	}
	asked[slot] = (Asked){ c->window, c->x, c->y, seconds() };
}

static void window_mapped(Window w) {
	int ax = 0, ay = 0, have = 0;
	for (int i = 0; i < 64; i++) {
		if (asked[i].w == w) { ax = asked[i].x; ay = asked[i].y; have = 1; asked[i].w = 0; }
	}
	if (!keep || !top || !target || w == holder || seconds() - last_press > MENU_WITHIN) return;
	for (int i = 0; i < n_popups; i++) if (popups[i].window == w) return;
	if (n_popups >= MAX_POPUPS || of_its_own(w)) return;
	long pid = pid_of(w);
	if (!pid || !draws_in(top, pid, 0)) return;
	XWindowAttributes a;
	if (!XGetWindowAttributes(dpy, w, &a)) return;
	// One a window manager places is left alone without the rule: it would be moved to keep it.
	if (!a.override_redirect && !menus_stay_put()) return;
	int ex = 0, ey = 0, mx = 0, my = 0;
	Window child;
	XTranslateCoordinates(dpy, target, DefaultRootWindow(dpy), 0, 0, &ex, &ey, &child);
	if (have) { mx = ax; my = ay; }
	else XTranslateCoordinates(dpy, w, DefaultRootWindow(dpy), 0, 0, &mx, &my, &child);
	XWindowAttributes t;
	XGetWindowAttributes(dpy, target, &t);
	Popup p = { w, mx - ex, my - ey, a.width, a.height };
	// Where the plugin put it when that is over its window, else at the click; inside the picture.
	if (p.x + p.width <= 0 || p.y + p.height <= 0 || p.x >= t.width || p.y >= t.height) {
		p.x = press_x;
		p.y = press_y;
	}
	if (p.x > t.width - p.width) p.x = t.width - p.width;
	if (p.y > t.height - p.height) p.y = t.height - p.height;
	if (p.x < 0) p.x = 0;
	if (p.y < 0) p.y = 0;
	popups[n_popups++] = p;
	entered = 0;
}

static int viewable(Window w, XWindowAttributes *a) {
	return XGetWindowAttributes(dpy, w, a) && a->map_state == IsViewable;
}

// Menus closed and gone are let go of; ones still open keep their size.
static void tidy_popups(void) {
	int kept = 0;
	for (int i = 0; i < n_popups; i++) {
		XWindowAttributes a;
		if (!viewable(popups[i].window, &a)) continue;
		popups[i].width = a.width;
		popups[i].height = a.height;
		popups[kept++] = popups[i];
	}
	n_popups = kept;
}

static Popup *open_popup_at(int x, int y) {
	for (int i = n_popups - 1; i >= 0; i--) {
		Popup *p = &popups[i];
		XWindowAttributes a;
		if (x >= p->x && y >= p->y && x < p->x + p->width && y < p->y + p->height && viewable(p->window, &a)) return p;
	}
	return NULL;
}

static Popup *open_popup(void) {
	for (int i = n_popups - 1; i >= 0; i--) {
		XWindowAttributes a;
		if (viewable(popups[i].window, &a)) return &popups[i];
	}
	return NULL;
}

// Every event on the display's root window: windows made and mapped.
static void root_events(void) {
	while (XPending(dpy)) {
		XEvent e;
		XNextEvent(dpy, &e);
		if (e.type == CreateNotify && e.xcreatewindow.parent == DefaultRootWindow(dpy)) window_created(&e.xcreatewindow);
		else if (e.type == MapNotify && e.xmap.event == DefaultRootWindow(dpy)) window_mapped(e.xmap.window);
	}
}

static void put_u32(uint32_t v) { fwrite(&v, 4, 1, stdout); }

static void header(uint32_t w, uint32_t h, uint32_t same) {
	fwrite("PV02", 4, 1, stdout); put_u32(w); put_u32(h); put_u32(same);
}

static void frame(void) {
	XWindowAttributes a;
	if (!top || !XGetWindowAttributes(dpy, top, &a) || a.map_state != IsViewable) {
		top = find(DefaultRootWindow(dpy), 0);
		if (top && keep) adopt(top);
	}
	// Asked again every frame: a plugin's own window is embedded a moment after Reaper's opens,
	// and until it is, the biggest thing in Reaper's is Reaper's.
	target = top ? content(top) : 0;
	if (!target || !XGetWindowAttributes(dpy, target, &a)) {
		top = target = 0;
		header(0, 0, 0); fflush(stdout);
		return;
	}
	XImage *img = XGetImage(dpy, target, 0, 0, a.width, a.height, AllPlanes, ZPixmap);
	if (!img) {
		header(0, 0, 0); fflush(stdout);
		return;
	}
	uint32_t w = a.width, h = a.height;
	size_t size = (size_t)w * h * 4;
	unsigned char *px = malloc(size);
	int direct = img->bits_per_pixel == 32 && img->byte_order == LSBFirst && img->red_mask == 0xff0000
			&& img->green_mask == 0xff00 && img->blue_mask == 0xff;
	for (uint32_t y = 0; y < h; y++) {
		unsigned char *out = px + (size_t)y * w * 4;
		if (direct) {
			const unsigned char *in = (unsigned char *)img->data + (size_t)y * img->bytes_per_line;
			for (uint32_t x = 0; x < w; x++) {
				out[x * 4 + 0] = in[x * 4 + 2];
				out[x * 4 + 1] = in[x * 4 + 1];
				out[x * 4 + 2] = in[x * 4 + 0];
				out[x * 4 + 3] = 0xff;
			}
		} else {
			for (uint32_t x = 0; x < w; x++) {
				unsigned long p = XGetPixel(img, x, y);
				out[x * 4 + 0] = (p >> 16) & 0xff;
				out[x * 4 + 1] = (p >> 8) & 0xff;
				out[x * 4 + 2] = p & 0xff;
				out[x * 4 + 3] = 0xff;
			}
		}
	}
	XDestroyImage(img);
	// Open menus over it, where they were put.
	for (int i = 0; i < n_popups; i++) {
		Popup *p = &popups[i];
		XWindowAttributes m;
		if (!viewable(p->window, &m)) continue;
		XImage *mi = XGetImage(dpy, p->window, 0, 0, m.width, m.height, AllPlanes, ZPixmap);
		if (!mi) continue;
		for (int y = 0; y < m.height; y++) {
			int ty = p->y + y;
			if (ty < 0 || ty >= (int)h) continue;
			for (int x = 0; x < m.width; x++) {
				int tx = p->x + x;
				if (tx < 0 || tx >= (int)w) continue;
				unsigned long q = XGetPixel(mi, x, y);
				unsigned char *o = px + ((size_t)ty * w + tx) * 4;
				o[0] = (q >> 16) & 0xff; o[1] = (q >> 8) & 0xff; o[2] = q & 0xff; o[3] = 0xff;
			}
		}
		XDestroyImage(mi);
	}
	// A plugin at rest is the same picture frame after frame; saying so is sixteen bytes, not
	// three megabytes.
	if (last && last_size == size && memcmp(last, px, size) == 0) {
		free(px);
		header(w, h, 1);
	} else {
		header(w, h, 0);
		fwrite(px, 1, size, stdout);
		free(last);
		last = px;
		last_size = size;
	}
	fflush(stdout);
}

// The deepest window under (x, y) of the target -- or of an open menu there -- the point in its own
// coordinates, and on the screen: the plugin's real window is a Wine child embedded inside Reaper's,
// and it is the one listening.
static Window under(int x, int y, int *cx, int *cy, int *rx, int *ry) {
	Window base = target, child = 0;
	int bx = x, by = y;
	Popup *menu = open_popup_at(x, y);
	in_menu = menu != NULL;
	if (menu) {
		base = menu->window;
		bx = x - menu->x;
		by = y - menu->y;
	}
	Window w = base;
	int tx, ty;
	for (int i = 0; i < 8; i++) {
		if (!XTranslateCoordinates(dpy, base, w, bx, by, &tx, &ty, &child) || !child) break;
		w = child;
	}
	XTranslateCoordinates(dpy, base, w, bx, by, cx, cy, &child);
	XTranslateCoordinates(dpy, base, DefaultRootWindow(dpy), bx, by, rx, ry, &child);
	return w;
}

// The root an event into `w` names: the screen's, except in a menu, where it is the menu's own
// window. Wine places a point by the event's root position when its root is the screen's, and by
// the point in the window and where it believes the window is otherwise, which for a menu is
// where it put the menu, not where the window manager has since.
static Window event_root(Window w) {
	return in_menu ? w : DefaultRootWindow(dpy);
}

static unsigned int held = 0;

// GDK hands a click to the window it last saw the pointer go into, and drops it when there is
// none -- and nothing ever goes into a window kept in the holder, which no real pointer reaches.
// So the pointer is said to have gone in, once, before the first thing that needs it.
static void enter(Window w, int cx, int cy, int rx, int ry) {
	if (w == entered) return;
	XEvent e; memset(&e, 0, sizeof e);
	e.xcrossing.type = EnterNotify;
	e.xcrossing.display = dpy;
	e.xcrossing.window = w;
	e.xcrossing.root = event_root(w);
	e.xcrossing.x = cx; e.xcrossing.y = cy;
	e.xcrossing.x_root = rx; e.xcrossing.y_root = ry;
	e.xcrossing.mode = NotifyNormal;
	e.xcrossing.detail = NotifyNonlinear;
	e.xcrossing.same_screen = True;
	e.xcrossing.time = CurrentTime;
	XSendEvent(dpy, w, True, EnterWindowMask, &e);
	entered = w;
}

static void send_button(int x, int y, int button, int down) {
	unsigned int mask = button == 1 ? Button1Mask : button == 2 ? Button2Mask : button == 3 ? Button3Mask : 0;
	// A click outside an open menu closes it, as on a desktop, and does nothing else.
	if (swallowing) {
		if (!down) swallowing = 0;
		if (down) held |= mask; else held &= ~mask;
		return;
	}
	Popup *open = open_popup();
	if (down && open && !open_popup_at(x, y)) {
		for (int press = 1; press >= 0; press--) {
			XEvent k; memset(&k, 0, sizeof k);
			k.xkey.type = press ? KeyPress : KeyRelease;
			k.xkey.display = dpy;
			k.xkey.window = open->window;
			k.xkey.root = DefaultRootWindow(dpy);
			k.xkey.keycode = XKeysymToKeycode(dpy, XK_Escape);
			k.xkey.same_screen = True;
			k.xkey.time = CurrentTime;
			XSendEvent(dpy, open->window, True, press ? KeyPressMask : KeyReleaseMask, &k);
		}
		XFlush(dpy);
		swallowing = button <= 3;
		held |= mask;
		return;
	}
	if (keep) keep_menus_hidden();
	if (down && button <= 3) {
		if (menus_stay_put()) hold_active(MENU_WITHIN);
		last_press = seconds();
		press_x = x;
		press_y = y;
	}
	int cx, cy, rx, ry;
	if (keep && top) tell_where(top);
	Window w = under(x, y, &cx, &cy, &rx, &ry);
	enter(w, cx, cy, rx, ry);
	XEvent e; memset(&e, 0, sizeof e);
	e.xbutton.type = down ? ButtonPress : ButtonRelease;
	e.xbutton.display = dpy;
	e.xbutton.window = w;
	e.xbutton.root = event_root(w);
	e.xbutton.x = cx; e.xbutton.y = cy;
	e.xbutton.x_root = rx; e.xbutton.y_root = ry;
	e.xbutton.button = button;
	e.xbutton.state = held;
	e.xbutton.same_screen = True;
	e.xbutton.time = CurrentTime;
	XSendEvent(dpy, w, True, down ? ButtonPressMask : ButtonReleaseMask, &e);
	if (down) held |= mask; else held &= ~mask;
	XFlush(dpy);
}

static void send_motion(int x, int y) {
	int cx, cy, rx, ry;
	pointer_x = x;
	pointer_y = y;
	last_motion = seconds();
	if (keep) keep_menus_hidden();
	if (keep && top) tell_where(top);
	Window w = under(x, y, &cx, &cy, &rx, &ry);
	enter(w, cx, cy, rx, ry);
	XEvent e; memset(&e, 0, sizeof e);
	e.xmotion.type = MotionNotify;
	e.xmotion.display = dpy;
	e.xmotion.window = w;
	e.xmotion.root = event_root(w);
	e.xmotion.x = cx; e.xmotion.y = cy;
	e.xmotion.x_root = rx; e.xmotion.y_root = ry;
	e.xmotion.state = held;
	e.xmotion.same_screen = True;
	e.xmotion.time = CurrentTime;
	XSendEvent(dpy, w, True, PointerMotionMask | ButtonMotionMask, &e);
	XFlush(dpy);
}

// Between commands: take the window the moment it shows up, and again if the DAW puts it back
// on the desktop. Without this the window is on screen from when Reaper opens it until the
// first frame is asked for, and it is on screen for good if the user moves it before then.
static void watch(void) {
	root_events();
	if (!keep) return;
	XWindowAttributes a;
	if (!top || !XGetWindowAttributes(dpy, top, &a) || a.map_state != IsViewable)
		top = find(DefaultRootWindow(dpy), 0);
	if (top) adopt(top);
	tidy_popups();
	if (n_popups && open_popup()) hold_active(0.5);
	// Wine takes the pointer to be where the last event sent it put it for a tenth of a second after
	// it last moved, then asks X where the real one is -- on someone's desktop. A menu follows the
	// pointer by asking, and one opened by a press sees the button go up wherever the real pointer
	// is, and closes. So while a button is held, and while the pointer is over a menu, it is sent
	// again, a pixel to one side and back. (Reaper's own windows are answered from the events sent
	// for as long as they keep coming, by native/reaper_pointer.c.)
	if (target && pointer_x >= 0 && (held || open_popup_at(pointer_x, pointer_y)) && seconds() - last_motion > 0.04
			&& first_of_another(top, pid_of(top), 0)) {
		int x = pointer_x, y = pointer_y;
		send_motion(x + (nudged ? 0 : 1), y);
		pointer_x = x;
		nudged = !nudged;
	}
}

int main(int argc, char **argv) {
	if (argc < 2 || !argv[1][0]) { fprintf(stderr, "usage: plugin_view <title>\n"); return 2; }
	wanted = argv[1];
	if (argc > 2 && strcmp(argv[2], "--in-place") == 0) keep = 0;
	XInitThreads();
	dpy = XOpenDisplay(NULL);
	if (!dpy) { fprintf(stderr, "plugin_view: no X display\n"); return 1; }
	XSetErrorHandler(ignore_errors);
	// Every window that appears, to catch the plugin's menus as they open.
	XSelectInput(dpy, DefaultRootWindow(dpy), SubstructureNotifyMask);
	char line[256];
	setvbuf(stdin, NULL, _IONBF, 0);
	for (;;) {
		struct pollfd waiting = { 0, POLLIN, 0 };
		int ready = poll(&waiting, 1, 4);
		watch();
		if (ready == 0) continue;
		if (ready < 0 || !fgets(line, sizeof line, stdin)) break;
		int x = 0, y = 0, b = 1;
		switch (line[0]) {
		case 'f': frame(); break;
		case 'm': if (sscanf(line + 1, "%d %d", &x, &y) == 2 && target) send_motion(x, y); break;
		case 'd': if (sscanf(line + 1, "%d %d %d", &x, &y, &b) >= 2 && target) send_button(x, y, b, 1); break;
		case 'u': if (sscanf(line + 1, "%d %d %d", &x, &y, &b) >= 2 && target) send_button(x, y, b, 0); break;
		case 'w': if (sscanf(line + 1, "%d %d %d", &x, &y, &b) == 3 && target) {
			int button = b > 0 ? 4 : 5;
			for (int i = 0; i < abs(b); i++) { send_button(x, y, button, 1); send_button(x, y, button, 0); }
		} break;
		case 'q': release(top); return 0;
		}
	}
	return 0;
}
