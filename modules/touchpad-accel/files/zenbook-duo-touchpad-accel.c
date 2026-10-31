// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * Apple's trackpad pointer acceleration for the ASUS Zenbook Duo 2026
 * keyboard touchpad, inside KWin (loaded with LD_PRELOAD).
 *
 * KWin 6.8 offers only libinput's flat and adaptive profiles. For the keyboard
 * touchpad (0b05:1cd7 docked, 0b05:1cd8 on Bluetooth) this library replaces
 * the accelerated motion libinput hands to KWin, libinput_event_pointer_get_dx()
 * and _get_dy(), with Apple's parametric acceleration computed from libinput's
 * unaccelerated motion. Every other device, and every other libinput call,
 * passes through untouched.
 *
 * The curve is IOHIDFamily's IOHIDParametricAcceleration with the Magic
 * Trackpad 2 HIDAccelCurves table: a finger speed of v inches/s moves the
 * pointer 96 * f(v) points/s. KDE's pointer speed slider picks the tracking
 * speed like macOS's slider does (-1..0..1 -> 0..1..3). A macOS point is
 * taken as 0.2 mm, its size on a MacBook at the default scaling.
 *
 * Speed is measured per event, as macOS does: an event that arrives within
 * 1.5 scan periods of the last one carries one scan (7.1 ms) of motion, even
 * when Bluetooth delivers two scans 0.5 ms apart; slower events use the time
 * since the last one. The first event after a pause counts as slow, so a
 * finger landing does not throw the pointer.
 *
 * Settings: /etc/zenbook-duo/touchpad-accel.conf, re-read within a second.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <libinput.h>
#include <locale.h>
#include <math.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#define EXPORT __attribute__((visibility("default")))

#define CONFIG_PATH "/etc/zenbook-duo/touchpad-accel.conf"
#define LIB_NAME "libzenbook-duo-touchpad-accel.so"

/* 3911 x 2382 units over 124.2 x 75.6 mm (HID descriptor); libinput's
 * unaccelerated touchpad motion is in x-axis units */
#define UNITS_PER_MM (3911.0 / 124.2)
#define SCAN_US 7100.0
#define PAUSE_US 100000.0
#define POINT_MM 0.2
#define CURSOR_SCALE (96.0 / 67.0) /* kCursorScale */
#define FRAME_RATE 67.0            /* IOHIDFamily FRAME_RATE */

struct accel_curve {
	double index, linear, parabolic, cubic, quartic, tangent_linear, tangent_root;
};

/* Magic Trackpad 2 HIDAccelCurves */
static const struct accel_curve apple_curves[] = {
	{ 0.0, 1.00, 0.00, 0.00, 0, 7.4, 21 },
	{ 0.125, 0.99, 0.50, 0.08, 0, 7.3, 20 },
	{ 0.5, 0.98, 0.66, 0.10, 0, 7.2, 19 },
	{ 0.6875, 0.96, 0.83, 0.12, 0, 7.1, 18 },
	{ 0.875, 0.94, 1.00, 0.15, 0, 7.0, 17 },
	{ 1.0, 0.92, 1.15, 0.18, 0, 7.0, 16 },
	{ 1.5, 0.89, 1.30, 0.21, 0, 7.0, 15 },
	{ 2.0, 0.86, 1.45, 0.24, 0, 7.0, 14 },
	{ 2.5, 0.83, 1.66, 0.28, 0, 7.0, 13 },
	{ 3.0, 1.00, 1.88, 0.36, 0, 7.0, 12 },
};

/* IOHIDParametricAcceleration after CreateWithParameters() */
struct parametric {
	struct accel_curve c;
	double tangent[2], m[2], b[2];
};

static void parametric_init(struct parametric *p, double index)
{
	const size_t n = sizeof(apple_curves) / sizeof(apple_curves[0]);
	size_t cur = 0;

	for (size_t i = 0; i < n; i++)
		if (index >= apple_curves[i].index)
			cur = i;

	const struct accel_curve *lo = &apple_curves[cur];
	if (lo->index < index && cur + 1 < n) {
		const struct accel_curve *hi = &apple_curves[cur + 1];
		double r = (index - lo->index) / (hi->index - lo->index);
#define LERP(f) (lo->f + r * (hi->f - lo->f))
		p->c = (struct accel_curve){ LERP(index), LERP(linear), LERP(parabolic),
					     LERP(cubic), LERP(quartic), LERP(tangent_linear),
					     LERP(tangent_root) };
#undef LERP
	} else {
		p->c = *lo;
	}

	const struct accel_curve *c = &p->c;
	p->tangent[0] = p->tangent[1] = INFINITY;
	p->m[0] = p->m[1] = p->b[0] = p->b[1] = 0;
	if (c->tangent_linear != 0) {
		double x = c->tangent_linear;
		double y0 = c->linear * x + pow(c->parabolic * x, 2) + pow(c->cubic * x, 3) +
			    pow(c->quartic * x, 4);
		p->m[0] = c->linear + 2 * x * pow(c->parabolic, 2) + 3 * pow(x, 2) * pow(c->cubic, 3) +
			  4 * pow(x, 3) * pow(c->quartic, 4);
		p->b[0] = y0 - p->m[0] * x;
		p->tangent[0] = x;
		if (c->tangent_root != 0) {
			double y1 = p->m[0] * c->tangent_root + p->b[0];
			p->m[1] = 2 * y1 * p->m[0];
			p->b[1] = pow(y1, 2) - p->m[1] * c->tangent_root;
			p->tangent[1] = c->tangent_root;
		}
	} else if (c->tangent_root != 0) {
		double x = c->tangent_root;
		double y0 = c->linear * x + pow(c->parabolic * x, 2) + pow(c->cubic * x, 3) +
			    pow(c->quartic * x, 4);
		p->m[1] = c->linear + 2 * x * pow(c->parabolic, 2) + 3 * pow(x, 2) * pow(c->cubic, 3) +
			  4 * pow(x, 3) * pow(c->quartic, 4);
		p->b[1] = pow(y0, 2) - p->m[1] * x;
		p->tangent[0] = x;
	}
}

/* IOHIDParametricAcceleration::multiplier() without kCursorScale, for a
 * standardized speed in inches/s */
static double parametric_f(const struct parametric *p, double v)
{
	const struct accel_curve *c = &p->c;

	if (v <= p->tangent[0])
		return c->linear * v + pow(c->parabolic * v, 2) + pow(c->cubic * v, 3) +
		       pow(c->quartic * v, 4);
	if (v <= p->tangent[1] && p->tangent[0] == c->tangent_linear)
		return p->m[0] * v + p->b[0];
	return sqrt(fmax(p->m[1] * v + p->b[1], 0));
}

/* Screen millimetres per millimetre of finger travel at a finger speed */
static double apple_gain(const struct parametric *p, double mm_per_s)
{
	const double points_per_s_per_f = CURSOR_SCALE * FRAME_RATE; /* 96 */

	if (mm_per_s <= 1e-9)
		return points_per_s_per_f * p->c.linear * POINT_MM / 25.4;
	return points_per_s_per_f * parametric_f(p, mm_per_s / 25.4) * POINT_MM / mm_per_s;
}

/* ---------------------------------------------------------------- state */

enum curve_kind { CURVE_APPLE, CURVE_LIBINPUT };

static struct {
	pthread_mutex_t lock;
	bool resolved, broken;
	/* KWin runs in the user's locale (decimal comma in Turkish); settings
	 * and log lines use C numbers */
	locale_t c_locale;

	double (*get_dx)(struct libinput_event_pointer *);
	double (*get_dy)(struct libinput_event_pointer *);
	double (*get_dx_unaccel)(struct libinput_event_pointer *);
	double (*get_dy_unaccel)(struct libinput_event_pointer *);
	uint64_t (*get_time_usec)(struct libinput_event_pointer *);
	struct libinput_event *(*get_base_event)(struct libinput_event_pointer *);
	enum libinput_event_type (*get_type)(struct libinput_event *);
	struct libinput_device *(*get_device)(struct libinput_event *);
	unsigned int (*id_vendor)(struct libinput_device *);
	unsigned int (*id_product)(struct libinput_device *);
	int (*tap_finger_count)(struct libinput_device *);
	double (*accel_get_speed)(struct libinput_device *);
	enum libinput_config_accel_profile (*accel_get_profile)(struct libinput_device *);
	const char *(*device_name)(struct libinput_device *);

	/* settings */
	enum curve_kind curve;
	double px_mm;
	struct timespec conf_mtime;
	uint64_t conf_checked_us;

	/* the touchpad */
	struct libinput_device *dev;
	double speed;
	struct parametric curve_params;
	uint64_t last_us;

	/* the event KWin is reading: get_dx and get_dy come in either order */
	struct libinput_event_pointer *ev;
	uint64_t ev_us;
	double ev_dx, ev_dy;
} s = {
	.lock = PTHREAD_MUTEX_INITIALIZER,
	.curve = CURVE_APPLE,
	.px_mm = 301.6 / 1600, /* top panel at 1.8x */
	.speed = NAN,
};

__attribute__((format(printf, 1, 2))) static void say(const char *fmt, ...)
{
	locale_t old = uselocale(s.c_locale);
	va_list ap;

	va_start(ap, fmt);
	fputs(LIB_NAME ": ", stderr);
	vfprintf(stderr, fmt, ap);
	va_end(ap);
	uselocale(old);
}

static void *sym(const char *name)
{
	void *p = dlsym(RTLD_NEXT, name);
	if (!p) {
		say("%s not found, passing motion through\n", name);
		s.broken = true;
	}
	return p;
}

static void resolve(void)
{
	s.c_locale = newlocale(LC_ALL_MASK, "C", (locale_t)0);
	s.get_dx = sym("libinput_event_pointer_get_dx");
	s.get_dy = sym("libinput_event_pointer_get_dy");
	s.get_dx_unaccel = sym("libinput_event_pointer_get_dx_unaccelerated");
	s.get_dy_unaccel = sym("libinput_event_pointer_get_dy_unaccelerated");
	s.get_time_usec = sym("libinput_event_pointer_get_time_usec");
	s.get_base_event = sym("libinput_event_pointer_get_base_event");
	s.get_type = sym("libinput_event_get_type");
	s.get_device = sym("libinput_event_get_device");
	s.id_vendor = sym("libinput_device_get_id_vendor");
	s.id_product = sym("libinput_device_get_id_product");
	s.tap_finger_count = sym("libinput_device_config_tap_get_finger_count");
	s.accel_get_speed = sym("libinput_device_config_accel_get_speed");
	s.accel_get_profile = sym("libinput_device_config_accel_get_profile");
	s.device_name = sym("libinput_device_get_name");
	s.resolved = true;
}

static void load_config(uint64_t now_us)
{
	struct stat st;
	FILE *f;
	char line[256];
	locale_t old;

	if (s.conf_checked_us && now_us - s.conf_checked_us < 1000000)
		return;
	s.conf_checked_us = now_us;
	if (stat(CONFIG_PATH, &st) < 0) {
		if (s.conf_mtime.tv_sec || s.conf_mtime.tv_nsec) {
			s.curve = CURVE_APPLE;
			s.conf_mtime = (struct timespec){ 0, 0 };
		}
		return;
	}
	if (st.st_mtim.tv_sec == s.conf_mtime.tv_sec && st.st_mtim.tv_nsec == s.conf_mtime.tv_nsec)
		return;
	s.conf_mtime = st.st_mtim;

	f = fopen(CONFIG_PATH, "re");
	if (!f)
		return;
	s.curve = CURVE_APPLE;
	old = uselocale(s.c_locale);
	while (fgets(line, sizeof(line), f)) {
		char key[64], value[128];

		if (sscanf(line, " %63[a-z_] = %127s", key, value) != 2)
			continue;
		if (strcmp(key, "curve") == 0) {
			s.curve = strcmp(value, "libinput") == 0 ? CURVE_LIBINPUT : CURVE_APPLE;
		} else if (strcmp(key, "px_mm") == 0) {
			double v = strtod(value, NULL);
			if (v > 0.01 && v < 2)
				s.px_mm = v;
		}
	}
	uselocale(old);
	fclose(f);
	say("curve %s, %.4f mm per pixel\n", s.curve == CURVE_APPLE ? "apple" : "libinput", s.px_mm);
}

static bool is_touchpad(struct libinput_device *dev)
{
	unsigned int product;

	if (!dev || s.id_vendor(dev) != 0x0b05)
		return false;
	product = s.id_product(dev);
	if (product != 0x1cd7 && product != 0x1cd8)
		return false;
	return s.tap_finger_count(dev) > 0;
}

/* Fills s.ev_dx/ev_dy for this event. Returns false to pass it through. */
static bool accelerate(struct libinput_event_pointer *ev)
{
	struct libinput_event *base = s.get_base_event(ev);
	struct libinput_device *dev;
	uint64_t now;
	double ux, uy, mm, dt, v, gain, speed;

	if (!base || s.get_type(base) != LIBINPUT_EVENT_POINTER_MOTION)
		return false;
	dev = s.get_device(base);
	if (!is_touchpad(dev))
		return false;
	now = s.get_time_usec(ev);
	load_config(now);
	if (s.curve != CURVE_APPLE || s.accel_get_profile(dev) != LIBINPUT_CONFIG_ACCEL_PROFILE_ADAPTIVE)
		return false;

	speed = s.accel_get_speed(dev);
	if (dev != s.dev || speed != s.speed) {
		double index = speed <= 0 ? 1 + speed : 1 + 2 * speed;

		/* KDE may set the speed after the first motion; log every change */
		parametric_init(&s.curve_params, fmin(fmax(index, 0), 3));
		say("Apple acceleration for %s, tracking speed %.3f\n", s.device_name(dev),
		    s.curve_params.c.index);
		s.dev = dev;
		s.speed = speed;
		s.last_us = 0;
	}

	ux = s.get_dx_unaccel(ev);
	uy = s.get_dy_unaccel(ev);
	mm = hypot(ux, uy) / UNITS_PER_MM;
	dt = (double)(now - s.last_us);
	if (s.last_us == 0 || now < s.last_us || dt > PAUSE_US)
		v = 0;
	else
		v = mm / ((dt < 1.5 * SCAN_US ? SCAN_US : dt) * 1e-6);
	s.last_us = now;

	gain = apple_gain(&s.curve_params, v) / (UNITS_PER_MM * s.px_mm);
	if (!isfinite(gain))
		return false;
	s.ev_dx = ux * gain;
	s.ev_dy = uy * gain;
	return true;
}

static double motion(struct libinput_event_pointer *ev, bool want_x)
{
	double r;

	pthread_mutex_lock(&s.lock);
	if (!s.resolved)
		resolve();
	if (s.broken) {
		double (*real)(struct libinput_event_pointer *) = want_x ? s.get_dx : s.get_dy;
		pthread_mutex_unlock(&s.lock);
		return real ? real(ev) : 0.0;
	}
	if (ev != s.ev || s.get_time_usec(ev) != s.ev_us) {
		s.ev = ev;
		s.ev_us = s.get_time_usec(ev);
		if (!accelerate(ev)) {
			s.ev_dx = NAN;
			s.ev_dy = NAN;
		}
	}
	r = want_x ? s.ev_dx : s.ev_dy;
	if (isnan(r))
		r = want_x ? s.get_dx(ev) : s.get_dy(ev);
	pthread_mutex_unlock(&s.lock);
	return r;
}

EXPORT double libinput_event_pointer_get_dx(struct libinput_event_pointer *event)
{
	return motion(event, true);
}

EXPORT double libinput_event_pointer_get_dy(struct libinput_event_pointer *event)
{
	return motion(event, false);
}

/* Keep Xwayland and everything else KWin starts free of this library; the
 * wrapper keeps it so a restarted KWin loads it again. */
__attribute__((constructor)) static void drop_from_children(void)
{
	const char *preload = getenv("LD_PRELOAD");
	char kept[4096] = "", *copy, *tok, *save = NULL;

	if (!preload || strcmp(program_invocation_short_name, "kwin_wayland") != 0)
		return;
	copy = strdup(preload);
	if (!copy)
		return;
	for (tok = strtok_r(copy, ": ", &save); tok; tok = strtok_r(NULL, ": ", &save)) {
		if (strstr(tok, LIB_NAME))
			continue;
		if (strlen(kept) + strlen(tok) + 2 > sizeof(kept))
			break;
		if (kept[0])
			strcat(kept, ":");
		strcat(kept, tok);
	}
	free(copy);
	if (kept[0])
		setenv("LD_PRELOAD", kept, 1);
	else
		unsetenv("LD_PRELOAD");
}
