/*
 * ac_pal_bridge.h - Native iOS platform <-> simulation bridge for the
 * Assetto Corsa iOS port prototype.
 *
 * IMPORTANT: This file is a PLATFORM ADAPTER contract, not a replacement for
 * Assetto Corsa physics. The bit-exact simulation lives in rustyAC's
 * `rustyac-physics` / `rustyac-ode` crates. This bridge only contains the
 * platform-side utilities that must run as native ARM64 code on iOS:
 *   - a deterministic fixed-step frame accumulator,
 *   - control mapping (deadzone / exponential / gamepad / touch),
 *   - the C ABI through which UIKit/MetalKit calls the Rust core.
 *
 * No game assets, protected resources or proprietary code are included.
 */
#ifndef AC_PAL_BRIDGE_H
#define AC_PAL_BRIDGE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque handle owned by the Rust simulation session. */
typedef struct AcSession AcSession;

/* VTable implemented by the Rust side (`ac-ios-app`). Filled once at startup. */
typedef struct AcCoreVTable {
    AcSession *(*session_create)(const char *ac_root,
                                 const char *car_id,
                                 const char *track_id);
    void (*session_destroy)(AcSession *session);
    void (*session_set_input)(AcSession *session,
                              float steer, float throttle, float brake);
    /* Extended controls: handbrake 0..1, one-shot gear requests, camera cycle. */
    void (*session_set_ext_input)(AcSession *session,
                                  float handbrake, int gear_up, int gear_down,
                                  int camera_next);
    void (*session_step)(AcSession *session, double dt);
    void (*session_snapshot)(AcSession *session, float out[16]);
} AcCoreVTable;

/* Deterministic fixed-step accumulator used by the MetalKit render loop. */
typedef struct AcFixedStep {
    double dt;          /* fixed simulation step, seconds */
    double accumulator; /* leftover time, seconds */
    int    max_steps;   /* spiral-of-death guard */
} AcFixedStep;

void ac_fixed_step_init(AcFixedStep *fs, double hz, int max_steps);

/* Advances `fs` by `frame_delta` seconds and calls `step(ctx, fs->dt)` zero or
 * more times. Returns the number of simulation steps executed. */
int ac_fixed_step_advance(AcFixedStep *fs,
                          double frame_delta,
                          void *ctx,
                          void (*step)(void *ctx, double dt));

/* Input shaping. These are real, testable utilities, not simulated gameplay. */
float ac_apply_deadzone(float v, float dz);
float ac_apply_expo(float v, float expo);
float ac_input_curve(float raw, float dz, float expo);

void ac_map_gamepad(float axis_x, float trigger_r, float trigger_l,
                    float *steer, float *throttle, float *brake);

void ac_map_touch(float steer_touch, float throttle_touch, float brake_touch,
                  float *steer, float *throttle, float *brake);

/* Bridge lifecycle, called from AppDelegate / GameViewController. */
int  ac_pal_bridge_init(const AcCoreVTable *vt);
void ac_pal_bridge_shutdown(void);
int  ac_pal_bridge_open_session(const char *ac_root,
                                const char *car_id,
                                const char *track_id);
int  ac_pal_bridge_run_frame(double frame_delta);
void ac_pal_bridge_set_input(float steer, float throttle, float brake);

/* Sets the full control state for the next physics steps. gear_up/gear_down/
 * camera_next are ONE-SHOT requests: the bridge consumes them on the next
 * simulation step so a held button cannot repeat shifts every 3 ms. */
void ac_pal_bridge_set_controls(float steer, float throttle, float brake,
                                float handbrake, int gear_up, int gear_down,
                                int camera_next);
void ac_pal_bridge_snapshot(float out[16]);

/// Opaque live session handle for the native renderer (NULL when no session).
void *ac_pal_bridge_session(void);

#ifdef __cplusplus
}
#endif

#endif /* AC_PAL_BRIDGE_H */
