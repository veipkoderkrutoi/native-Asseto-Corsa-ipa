/*
 * ac_pal_bridge.c - see ac_pal_bridge.h.
 *
 * This is deliberately free of any Assetto Corsa game logic. It is the native
 * ARM64 adapter that an iOS build links against the Rust simulation core.
 */
#include "ac_pal_bridge.h"

/* Zig's aarch64-ios target ships neither math.h nor string.h and the iOS SDK
 * cannot be assumed on a cross-compilation host. Builtins and a tiny zeroing
 * loop keep this translation unit self-contained for genuine ARM64 codegen. */
static float ac_fabsf(float v) { return __builtin_fabsf(v); }
static float ac_copysignf(float v, float s) { return __builtin_copysignf(v, s); }
static void ac_zero(void *p, size_t n) {
    unsigned char *b = (unsigned char *)p;
    while (n--) { *b++ = 0; }
}

static AcCoreVTable g_vt;
static AcSession   *g_session;
static AcFixedStep  g_clock;
static float        g_steer;
static float        g_throttle;
static float        g_brake;
static float        g_handbrake;
static int          g_gear_up_pending;
static int          g_gear_dn_pending;
static int          g_camera_pending;
static int          g_initialized;

void ac_fixed_step_init(AcFixedStep *fs, double hz, int max_steps) {
    if (!fs || hz <= 0.0) {
        return;
    }
    fs->dt = 1.0 / hz;
    fs->accumulator = 0.0;
    fs->max_steps = max_steps > 0 ? max_steps : 5;
}

int ac_fixed_step_advance(AcFixedStep *fs,
                          double frame_delta,
                          void *ctx,
                          void (*step)(void *ctx, double dt)) {
    if (!fs || !step || frame_delta <= 0.0) {
        return 0;
    }

    /* Clamp pathological deltas (app resume, breakpoint, backgrounding). */
    if (frame_delta > 0.25) {
        frame_delta = 0.25;
    }

    fs->accumulator += frame_delta;
    int steps = 0;
    while (fs->accumulator >= fs->dt && steps < fs->max_steps) {
        step(ctx, fs->dt);
        fs->accumulator -= fs->dt;
        ++steps;
    }

    /* If we hit the guard, drop the backlog rather than accumulating debt. */
    if (steps == fs->max_steps && fs->accumulator >= fs->dt) {
        fs->accumulator = 0.0;
    }
    return steps;
}

float ac_apply_deadzone(float v, float dz) {
    if (v > 1.0f) v = 1.0f;
    if (v < -1.0f) v = -1.0f;
    if (dz < 0.0f) dz = 0.0f;
    if (dz >= 1.0f) return 0.0f;
    float a = ac_fabsf(v);
    if (a <= dz) return 0.0f;
    return (v - ac_copysignf(dz, v)) / (1.0f - dz);
}

float ac_apply_expo(float v, float expo) {
    if (v > 1.0f) v = 1.0f;
    if (v < -1.0f) v = -1.0f;
    if (expo <= 0.0f) return v;
    if (expo > 1.0f) expo = 1.0f;
    float linear = 1.0f - expo;
    return v * (linear + expo * v * v);
}

float ac_input_curve(float raw, float dz, float expo) {
    return ac_apply_expo(ac_apply_deadzone(raw, dz), expo);
}

void ac_map_gamepad(float axis_x, float trigger_r, float trigger_l,
                    float *steer, float *throttle, float *brake) {
    if (steer)    *steer    = ac_input_curve(axis_x,   0.08f, 0.35f);
    if (throttle) {
        *throttle = ac_input_curve(trigger_r, 0.05f, 0.20f);
        if (*throttle < 0.0f) *throttle = 0.0f;   /* triggers are unipolar */
    }
    if (brake) {
        *brake = ac_input_curve(trigger_l, 0.05f, 0.20f);
        if (*brake < 0.0f) *brake = 0.0f;
    }
}

void ac_map_touch(float steer_touch, float throttle_touch, float brake_touch,
                  float *steer, float *throttle, float *brake) {
    /* Touch values arrive normalised to [0,1] by the UIKit gesture handlers;
     * the steering pad is [-1,1]. */
    if (steer)    *steer    = ac_input_curve(steer_touch,    0.02f, 0.25f);
    if (throttle) {
        *throttle = ac_input_curve(throttle_touch, 0.02f, 0.10f);
        if (*throttle < 0.0f) *throttle = 0.0f;
    }
    if (brake) {
        *brake = ac_input_curve(brake_touch, 0.02f, 0.10f);
        if (*brake < 0.0f) *brake = 0.0f;
    }
}

int ac_pal_bridge_init(const AcCoreVTable *vt) {
    if (!vt || !vt->session_create || !vt->session_step ||
        !vt->session_set_input || !vt->session_set_ext_input ||
        !vt->session_snapshot) {
        return -1;
    }
    g_vt = *vt;
    g_session = NULL;
    g_steer = g_throttle = g_brake = g_handbrake = 0.0f;
    g_gear_up_pending = g_gear_dn_pending = g_camera_pending = 0;
    /* rustyac_game::sim::DT is 0.003 s (333.33 Hz). 12 steps cover a 60 Hz
     * frame (16.7 ms) plus realistic jitter without a spiral of death. */
    ac_fixed_step_init(&g_clock, 1000.0 / 3.0, 12);
    g_initialized = 1;
    return 0;
}

void ac_pal_bridge_shutdown(void) {
    if (g_initialized && g_session && g_vt.session_destroy) {
        g_vt.session_destroy(g_session);
    }
    g_session = NULL;
    g_gear_up_pending = g_gear_dn_pending = g_camera_pending = 0;
    ac_zero(&g_vt, sizeof(g_vt));
    g_initialized = 0;
}

int ac_pal_bridge_open_session(const char *ac_root,
                               const char *car_id,
                               const char *track_id) {
    if (!g_initialized || !ac_root || !car_id || !track_id) {
        return -1;
    }
    if (g_session && g_vt.session_destroy) {
        g_vt.session_destroy(g_session);
        g_session = NULL;
    }
    g_session = g_vt.session_create(ac_root, car_id, track_id);
    return g_session ? 0 : -2;
}

void ac_pal_bridge_set_input(float steer, float throttle, float brake) {
    g_steer = steer;
    g_throttle = throttle;
    g_brake = brake;
}

void ac_pal_bridge_set_controls(float steer, float throttle, float brake,
                                float handbrake, int gear_up, int gear_down,
                                int camera_next) {
    g_steer = steer;
    g_throttle = throttle;
    g_brake = brake;
    g_handbrake = handbrake < 0.0f ? 0.0f : (handbrake > 1.0f ? 1.0f : handbrake);
    /* One-shot requests: OR so a press between physics steps is not lost. */
    g_gear_up_pending   |= gear_up   ? 1 : 0;
    g_gear_dn_pending   |= gear_down ? 1 : 0;
    g_camera_pending    |= camera_next ? 1 : 0;
}

/* Called by the Rust core's step callback through the vtable. */
static void ac_bridge_step(void *ctx, double dt) {
    (void)ctx;
    if (g_session) {
        g_vt.session_set_input(g_session, g_steer, g_throttle, g_brake);
        if (g_vt.session_set_ext_input) {
            g_vt.session_set_ext_input(g_session, g_handbrake,
                                       g_gear_up_pending, g_gear_dn_pending,
                                       g_camera_pending);
        }
        /* Consume one-shot requests exactly once, regardless of step count. */
        g_gear_up_pending = g_gear_dn_pending = g_camera_pending = 0;
        g_vt.session_step(g_session, dt);
    }
}

int ac_pal_bridge_run_frame(double frame_delta) {
    if (!g_initialized || !g_session) {
        return 0;
    }
    return ac_fixed_step_advance(&g_clock, frame_delta, NULL, ac_bridge_step);
}

void *ac_pal_bridge_session(void) {
    return g_session;
}

void ac_pal_bridge_snapshot(float out[16]) {
    if (out) {
        ac_zero(out, 16 * sizeof(float));
        if (g_initialized && g_session) {
            g_vt.session_snapshot(g_session, out);
        }
    }
}
