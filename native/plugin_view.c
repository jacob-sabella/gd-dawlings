// plugin_view: show a plugin's own window somewhere else, and pass clicks back into it.
//
//   plugin_view "<the window's title, or part of it>"
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
// Built on demand by core/reaper/reaper_plugin_window.gd: cc -O2 -o plugin_view plugin_view.c -lX11
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <ctype.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

static void put_u32(uint32_t v) { fwrite(&v, 4, 1, stdout); }

static void header(uint32_t w, uint32_t h, uint32_t same) {
	fwrite("PV02", 4, 1, stdout); put_u32(w); put_u32(h); put_u32(same);
}

static void frame(void) {
	XWindowAttributes a;
	if (!top || !XGetWindowAttributes(dpy, top, &a) || a.map_state != IsViewable)
		top = find(DefaultRootWindow(dpy), 0);
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

// The deepest window under (x, y) of the target, and the point in its own coordinates: the
// plugin's real window is a Wine child embedded inside Reaper's, and it is the one listening.
static Window under(int x, int y, int *cx, int *cy) {
	Window w = target, child = 0;
	int bx, by;
	for (int i = 0; i < 8; i++) {
		if (!XTranslateCoordinates(dpy, target, w, x, y, &bx, &by, &child) || !child) break;
		w = child;
	}
	XTranslateCoordinates(dpy, target, w, x, y, cx, cy, &child);
	return w;
}

static unsigned int held = 0;

static void send_button(int x, int y, int button, int down) {
	int cx, cy, rx, ry;
	Window dummy;
	Window w = under(x, y, &cx, &cy);
	XTranslateCoordinates(dpy, target, DefaultRootWindow(dpy), x, y, &rx, &ry, &dummy);
	XEvent e; memset(&e, 0, sizeof e);
	e.xbutton.type = down ? ButtonPress : ButtonRelease;
	e.xbutton.display = dpy;
	e.xbutton.window = w;
	e.xbutton.root = DefaultRootWindow(dpy);
	e.xbutton.x = cx; e.xbutton.y = cy;
	e.xbutton.x_root = rx; e.xbutton.y_root = ry;
	e.xbutton.button = button;
	e.xbutton.state = held;
	e.xbutton.same_screen = True;
	e.xbutton.time = CurrentTime;
	XSendEvent(dpy, w, True, down ? ButtonPressMask : ButtonReleaseMask, &e);
	unsigned int mask = button == 1 ? Button1Mask : button == 2 ? Button2Mask : button == 3 ? Button3Mask : 0;
	if (down) held |= mask; else held &= ~mask;
	XFlush(dpy);
}

static void send_motion(int x, int y) {
	int cx, cy, rx, ry;
	Window dummy;
	Window w = under(x, y, &cx, &cy);
	XTranslateCoordinates(dpy, target, DefaultRootWindow(dpy), x, y, &rx, &ry, &dummy);
	XEvent e; memset(&e, 0, sizeof e);
	e.xmotion.type = MotionNotify;
	e.xmotion.display = dpy;
	e.xmotion.window = w;
	e.xmotion.root = DefaultRootWindow(dpy);
	e.xmotion.x = cx; e.xmotion.y = cy;
	e.xmotion.x_root = rx; e.xmotion.y_root = ry;
	e.xmotion.state = held;
	e.xmotion.same_screen = True;
	e.xmotion.time = CurrentTime;
	XSendEvent(dpy, w, True, PointerMotionMask | ButtonMotionMask, &e);
	XFlush(dpy);
}

int main(int argc, char **argv) {
	if (argc < 2 || !argv[1][0]) { fprintf(stderr, "usage: plugin_view <title>\n"); return 2; }
	wanted = argv[1];
	dpy = XOpenDisplay(NULL);
	if (!dpy) { fprintf(stderr, "plugin_view: no X display\n"); return 1; }
	XSetErrorHandler(ignore_errors);
	char line[256];
	while (fgets(line, sizeof line, stdin)) {
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
		case 'q': return 0;
		}
	}
	return 0;
}
