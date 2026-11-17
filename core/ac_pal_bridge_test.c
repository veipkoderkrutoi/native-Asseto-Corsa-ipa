/*
 * Host-side unit tests for the native PAL bridge. These run on Windows today
 * (via zig cc to a host exe) and on macOS as part of `make test`. They do not
 * require any Apple SDK, so they are real, executable verification.
 */
#include "ac_pal_bridge.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

static int g_failures = 0;

#define CHECK(cond)                                                            \
    do {                                                                       \
        if (!(cond)) {                                                         \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);             \
            ++g_failures;                                                      \
        }                                                                      \
    } while (0)

static int approx(float a, float b) { return fabsf(a - b) < 1e-5f; }

/* --- mock Rust core ------------------------------------------------------ */
typedef struct {
    int created, destroyed, steps, input_calls, snapshots;
    int ext_calls, last_gear_up, last_gear_dn, last_camera;
    int gear_up_seen, gear_dn_seen, camera_seen;
    float last_steer, last_throttle, last_brake, last_handbrake;
    double last_dt;
} MockCore;

static MockCore g_mock;

static AcSession *mock_create(const char *root, const char *car, const char *track) {
    (void)root; (void)car; (void)track;
    ++g_mock.created;
    return (AcSession *)&g_mock;
}
static void mock_destroy(AcSession *s) { (void)s; ++g_mock.destroyed; }
static void mock_input(AcSession *s, float st, float th, float br) {
    (void)s;
    ++g_mock.input_calls;
    g_mock.last_steer = st;
    g_mock.last_throttle = th;
    g_mock.last_brake = br;
}
static void mock_ext_input(AcSession *s, float hb, int gu, int gd, int cam) {
    (void)s;
    ++g_mock.ext_calls;
    g_mock.last_handbrake = hb;
    g_mock.last_gear_up = gu;
    g_mock.last_gear_dn = gd;
    g_mock.last_camera = cam;
    g_mock.gear_up_seen |= gu;
    g_mock.gear_dn_seen |= gd;
    g_mock.camera_seen |= cam;
}
static void mock_step(AcSession *s, double dt) {
    (void)s; ++g_mock.steps; g_mock.last_dt = dt;
}
static void mock_snapshot(AcSession *s, float out[16]) {
    (void)s; if (out) { out[0] = 42.0f; } ++g_mock.snapshots;
}

static void test_deadzone(void) {
    CHECK(approx(ac_apply_deadzone(0.0f, 0.1f), 0.0f));
    CHECK(approx(ac_apply_deadzone(0.05f, 0.1f), 0.0f));
    CHECK(approx(ac_apply_deadzone(0.1f, 0.1f), 0.0f));
    CHECK(approx(ac_apply_deadzone(0.55f, 0.1f), 0.5f));
    CHECK(approx(ac_apply_deadzone(-0.55f, 0.1f), -0.5f));
    CHECK(approx(ac_apply_deadzone(1.0f, 0.1f), 1.0f));
}

static void test_expo(void) {
    CHECK(approx(ac_apply_expo(0.5f, 0.0f), 0.5f));
    CHECK(approx(ac_apply_expo(1.0f, 0.5f), 1.0f));
    CHECK(ac_apply_expo(0.5f, 0.5f) < 0.5f);
}

static void test_gamepad(void) {
    float s, t, b;
    ac_map_gamepad(0.0f, 0.0f, 0.0f, &s, &t, &b);
    CHECK(approx(s, 0.0f) && approx(t, 0.0f) && approx(b, 0.0f));

    ac_map_gamepad(1.0f, 1.0f, 1.0f, &s, &t, &b);
    CHECK(approx(s, 1.0f) && approx(t, 1.0f) && approx(b, 1.0f));

    ac_map_gamepad(-1.0f, 0.0f, 0.0f, &s, &t, &b);
    CHECK(approx(s, -1.0f));

    /* Out-of-range values are clamped, never passed through. */
    ac_map_gamepad(4.0f, -3.0f, 2.0f, &s, &t, &b);
    CHECK(s <= 1.0f && t >= 0.0f && b <= 1.0f);
}

static void test_touch(void) {
    float s, t, b;
    ac_map_touch(1.0f, 1.0f, 0.0f, &s, &t, &b);
    CHECK(approx(s, 1.0f) && approx(t, 1.0f) && approx(b, 0.0f));
}

static void count_step(void *ctx, double dt);

static void test_fixed_step(void) {
    AcFixedStep fs;
    int calls = 0;

    ac_fixed_step_init(&fs, 100.0, 5);
    CHECK(approx((float)fs.dt, 0.01f));

    /* A NULL callback must be a safe no-op. */
    CHECK(ac_fixed_step_advance(&fs, 0.025, &calls, NULL) == 0);
    CHECK(calls == 0);
    CHECK(ac_fixed_step_advance(&fs, -0.1, &calls, count_step) == 0);
}

/* Real callback used by the deterministic accumulator test. */
static void count_step(void *ctx, double dt) {
    int *c = (int *)ctx;
    (void)dt;
    ++(*c);
}

static void test_fixed_step_real(void) {
    AcFixedStep fs;
    int calls = 0;
    ac_fixed_step_init(&fs, 100.0, 5);

    CHECK(ac_fixed_step_advance(&fs, 0.025, &calls, count_step) == 2);
    CHECK(calls == 2);
    CHECK(fs.accumulator >= 0.0 && fs.accumulator < fs.dt);

    /* Spiral-of-death guard: a huge delta must never exceed max_steps. */
    calls = 0;
    ac_fixed_step_init(&fs, 1000.0, 5);
    CHECK(ac_fixed_step_advance(&fs, 10.0, &calls, count_step) == 5);
    CHECK(calls == 5);
    CHECK(approx((float)fs.accumulator, 0.0f));
}

static void test_bridge_lifecycle(void) {
    AcCoreVTable vt;
    memset(&vt, 0, sizeof(vt));
    vt.session_create = mock_create;
    vt.session_destroy = mock_destroy;
    vt.session_set_input = mock_input;
    vt.session_set_ext_input = mock_ext_input;
    vt.session_step = mock_step;
    vt.session_snapshot = mock_snapshot;

    memset(&g_mock, 0, sizeof(g_mock));
    CHECK(ac_pal_bridge_init(&vt) == 0);
    CHECK(ac_pal_bridge_open_session("/legal/AC", "bmw_m3_e30", "drift") == 0);
    CHECK(g_mock.created == 1);

    ac_pal_bridge_set_input(0.5f, 1.0f, 0.0f);
    int steps = ac_pal_bridge_run_frame(0.05);
    CHECK(steps > 0);
    CHECK(g_mock.steps == steps);
    CHECK(approx(g_mock.last_steer, 0.5f));
    CHECK(approx(g_mock.last_throttle, 1.0f));
    CHECK(approx((float)g_mock.last_dt, 0.003f));

    /* Extended controls reach the core, and one-shot requests fire once. */
    ac_pal_bridge_set_controls(0.25f, 0.8f, 0.1f, 0.6f, 1, 0, 1);
    memset(&g_mock.gear_up_seen, 0, sizeof(int) * 3);
    ac_pal_bridge_run_frame(0.006);
    CHECK(g_mock.ext_calls > 0);
    CHECK(approx(g_mock.last_handbrake, 0.6f));
    CHECK(g_mock.gear_up_seen == 1);
    CHECK(g_mock.gear_dn_seen == 0);
    CHECK(g_mock.camera_seen == 1);
    /* The request must NOT persist into the next frame. */
    memset(&g_mock.gear_up_seen, 0, sizeof(int) * 3);
    ac_pal_bridge_run_frame(0.006);
    CHECK(g_mock.gear_up_seen == 0);
    CHECK(g_mock.camera_seen == 0);

    float snap[16];
    ac_pal_bridge_snapshot(snap);
    CHECK(approx(snap[0], 42.0f));
    CHECK(g_mock.snapshots == 1);

    ac_pal_bridge_shutdown();
    CHECK(g_mock.destroyed == 1);

    /* Reject invalid vtables. */
    memset(&vt, 0, sizeof(vt));
    CHECK(ac_pal_bridge_init(&vt) == -1);
}

int main(void) {
    test_deadzone();
    test_expo();
    test_gamepad();
    test_touch();
    test_fixed_step();
    test_fixed_step_real();
    test_bridge_lifecycle();

    if (g_failures == 0) {
        printf("ac_pal_bridge_test: ALL TESTS PASSED\n");
        return 0;
    }
    printf("ac_pal_bridge_test: %d FAILURE(S)\n", g_failures);
    return 1;
}
