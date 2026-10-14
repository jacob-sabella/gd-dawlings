// reaper_pointer: lets Reaper's own windows be worked by the clicks plugin_view sends them.
//
//   LD_PRELOAD=/path/to/reaper_pointer.so reaper ...
//
// plugin_view drives a plugin's window by sending it pointer events, never by moving the real
// pointer: the window sits where no pointer can reach, and the person at the desk is still using
// theirs. Plugins in a window of their own toolkit (Wine, through yabridge) take those events as
// they come. Reaper's own plugins -- ReaEQ, ReaComp and the rest -- are drawn by SWELL on GDK, and
// that is not enough for them, for three reasons this library takes away:
//
//   * GDK on X reads the pointer through XInput2 and ignores the core events a client can send.
//     GDK_CORE_DEVICE_EVENTS=1 puts it back on core events; it is set here, before GDK starts, so
//     whoever starts Reaper only has to name this library.
//   * A drag asks where the pointer IS (GetCursorPos, GetAsyncKeyState) rather than reading the
//     event it was given -- and is told where the real pointer is, on the person's own screen, with
//     no button down. While sent events are arriving, those questions are answered from them.
//   * A knob hides the cursor while it is turned and warps it back afterwards: that would move the
//     person's real pointer to wherever the tablet's last was. While sent events are arriving, a
//     warp only moves the answer above, and the events after it, the way a real warp would.
//
// The moment a real pointer event arrives -- someone using Reaper on the desktop -- every answer is
// the real one again. Nothing here does anything to a window that is not being sent events.
//
// Built by tools/reaper_rig.sh: cc -O2 -shared -fPIC -o reaper_pointer.so reaper_pointer.c -ldl
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>

// GDK 3's own layouts, which are frozen: declared here so this builds without GTK's headers.
typedef void GdkWindow;
typedef void GdkDisplay;
typedef void GdkScreen;
typedef void GdkDevice;
typedef union _GdkEvent GdkEvent;
typedef void (*GdkEventFunc)(GdkEvent *event, void *data);
typedef void (*GDestroyNotify)(void *data);

enum { MOTION = 3, PRESS = 4, PRESS2 = 5, PRESS3 = 6, RELEASE = 7, ENTER = 10, LEAVE = 11, SCROLL = 31 };

struct any { int type; GdkWindow *window; signed char send_event; };
struct motion { int type; GdkWindow *window; signed char send_event; unsigned time; double x, y; double *axes;
	unsigned state; short is_hint; GdkDevice *device; double x_root, y_root; };
struct button { int type; GdkWindow *window; signed char send_event; unsigned time; double x, y; double *axes;
	unsigned state; unsigned button; GdkDevice *device; double x_root, y_root; };
struct crossing { int type; GdkWindow *window; signed char send_event; GdkWindow *subwindow; unsigned time;
	double x, y, x_root, y_root; int mode, detail, focus; unsigned state; };
struct scroll { int type; GdkWindow *window; signed char send_event; unsigned time; double x, y;
	unsigned state; int direction; GdkDevice *device; double x_root, y_root; };
union _GdkEvent { int type; struct any any; struct motion motion; struct button button;
	struct crossing crossing; struct scroll scroll; char pad[256]; };

// Whether the pointer Reaper hears about is the sent one, where it is, and which buttons are down.
static int sent;
static int at_x, at_y;
static unsigned state;
// How far warps have moved the sent pointer from where the sender puts it.
static double off_x, off_y;

static GdkEventFunc handler;

static void *real(const char *name) { return dlsym(RTLD_NEXT, name); }

static unsigned button_mask(unsigned b) { return b >= 1 && b <= 5 ? 1u << (7 + b) : 0; }

// What a pointer event tells: whether the pointer is the sent one now, and where, and which buttons.
static void note(GdkEvent *e) {
	struct any *a = &e->any;
	double *x = NULL, *y = NULL, *rx = NULL, *ry = NULL;
	unsigned *st = NULL;
	switch (a->type) {
	case MOTION: x = &e->motion.x; y = &e->motion.y; rx = &e->motion.x_root; ry = &e->motion.y_root; st = &e->motion.state; break;
	case PRESS: case PRESS2: case PRESS3: case RELEASE:
		x = &e->button.x; y = &e->button.y; rx = &e->button.x_root; ry = &e->button.y_root; st = &e->button.state; break;
	case ENTER: case LEAVE:
		x = &e->crossing.x; y = &e->crossing.y; rx = &e->crossing.x_root; ry = &e->crossing.y_root; st = &e->crossing.state; break;
	case SCROLL: x = &e->scroll.x; y = &e->scroll.y; rx = &e->scroll.x_root; ry = &e->scroll.y_root; st = &e->scroll.state; break;
	}
	if (rx) {
		if (!a->send_event) {
			sent = 0;
		} else {
			// A press is where the sender says it is: whatever a warp did ends with the drag it was part of.
			if (a->type == PRESS) off_x = off_y = 0;
			*x += off_x; *y += off_y; *rx += off_x; *ry += off_y;
			sent = 1;
			at_x = (int)*rx; at_y = (int)*ry;
			state = *st;
			if (a->type == PRESS) state |= button_mask(e->button.button);
			if (a->type == RELEASE) state &= ~button_mask(e->button.button);
		}
	}
}

// SWELL hears events both ways GDK has of giving them: handed to it, and asked for.
static void heard(GdkEvent *e, void *data) {
	note(e);
	if (handler) handler(e, data);
}

GdkEvent *gdk_event_get(void) {
	GdkEvent *(*get)(void) = real("gdk_event_get");
	GdkEvent *e = get();
	if (e) note(e);
	return e;
}

void gdk_event_handler_set(GdkEventFunc func, void *data, GDestroyNotify notify) {
	void (*set)(GdkEventFunc, void *, GDestroyNotify) = real("gdk_event_handler_set");
	handler = func;
	set(func ? heard : NULL, data, notify);
}

// SWELL asks GDK for every kind of event, motion hints included: one motion, and then none until
// the program asks where the pointer went. GDK keeps the hints' books per device, and a sent
// motion it was not expecting is dropped -- so a drag would be a press and a release and nothing
// in between. Its windows get every motion instead.
struct window_attr { char *title; int event_mask; };
enum { MOTION_HINT_MASK = 1 << 3 };

GdkWindow *gdk_window_new(GdkWindow *parent, struct window_attr *attr, int mask) {
	GdkWindow *(*make)(GdkWindow *, struct window_attr *, int) = real("gdk_window_new");
	if (attr) attr->event_mask &= ~MOTION_HINT_MASK;
	return make(parent, attr, mask);
}

void gdk_display_get_pointer(GdkDisplay *d, GdkScreen **screen, int *x, int *y, unsigned *mask) {
	void (*get)(GdkDisplay *, GdkScreen **, int *, int *, unsigned *) = real("gdk_display_get_pointer");
	get(d, screen, x, y, mask);
	if (!sent) return;
	if (x) *x = at_x;
	if (y) *y = at_y;
	if (mask) *mask = state;
}

void gdk_device_get_position(GdkDevice *dev, GdkScreen **screen, int *x, int *y) {
	void (*get)(GdkDevice *, GdkScreen **, int *, int *) = real("gdk_device_get_position");
	get(dev, screen, x, y);
	if (!sent) return;
	if (x) *x = at_x;
	if (y) *y = at_y;
}

GdkWindow *gdk_window_get_pointer(GdkWindow *w, int *x, int *y, unsigned *mask) {
	GdkWindow *(*get)(GdkWindow *, int *, int *, unsigned *) = real("gdk_window_get_pointer");
	GdkWindow *under = get(w, x, y, mask);
	if (!sent) return under;
	int ox = 0, oy = 0;
	int (*origin)(GdkWindow *, int *, int *) = real("gdk_window_get_origin");
	if (w && origin) origin(w, &ox, &oy);
	if (x) *x = at_x - ox;
	if (y) *y = at_y - oy;
	if (mask) *mask = state;
	return under;
}

void gdk_device_warp(GdkDevice *dev, GdkScreen *screen, int x, int y) {
	if (sent) {
		off_x += x - at_x; off_y += y - at_y;
		at_x = x; at_y = y;
		return;
	}
	void (*warp)(GdkDevice *, GdkScreen *, int, int) = real("gdk_device_warp");
	warp(dev, screen, x, y);
}

// In Reaper itself only: the shell script that may start it has to pass LD_PRELOAD on, and the
// plugin hosts Reaper starts (yabridge's Wine among them) have no use for this.
__attribute__((constructor)) static void start(void) {
	if (strcmp(program_invocation_short_name, "reaper") != 0) return;
	setenv("GDK_CORE_DEVICE_EVENTS", "1", 1);
	const char *pre = getenv("LD_PRELOAD");
	if (!pre) return;
	char *kept = malloc(strlen(pre) + 1), *out = kept;
	const char *at = pre;
	while (*at) {
		size_t n = strcspn(at, ": ");
		if (n && !(n >= 17 && memcmp(at + n - 17, "reaper_pointer.so", 17) == 0)) {
			if (out != kept) *out++ = ':';
			memcpy(out, at, n);
			out += n;
		}
		at += n;
		if (*at) at++;
	}
	*out = 0;
	if (*kept) setenv("LD_PRELOAD", kept, 1); else unsetenv("LD_PRELOAD");
	free(kept);
}
