//
//  C ABI implemented by ios_bridge.m and consumed by ac-ios-pal (Rust).
//  See rust/ac-ios-pal/src/lib.rs :: ios_bindings.
//
#ifndef AC_IOS_BRIDGE_H
#define AC_IOS_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Real AC lap timer state, mirrored from Rust `AcIosLapState` (fixed-width only). */
typedef struct {
    uint32_t current_ms;
    uint32_t last_ms;
    uint32_t best_ms;
    uint32_t laps;
    uint32_t on_track;
    uint32_t valid;
    uint32_t last_valid;
    int32_t  cuts;
    float    position;
} ACIosLapState;

typedef struct {
    float steer;          /* -1..1 */
    float throttle;       /*  0..1 */
    float brake;          /*  0..1 */
    uint8_t handbrake;
    int8_t camera_request;
    uint8_t gear_up;      /* one-shot */
    uint8_t gear_down;    /* one-shot */
}ACIosInputState;

int  ac_ios_content_root(char *buf, size_t cap);
int  ac_ios_input_state(ACIosInputState *out);
int  ac_ios_audio_set(float rpm, float load);
void ac_ios_audio_suspend(void);
void ac_ios_audio_resume(void);

/* Diagnostic gameplay audio. This is a SYNTHESIZED engine/road sound driven by
 * real GameSim telemetry — NOT playback of original AC FMOD banks (no FMOD iOS
 * SDK is available). Kept strictly separate from any original asset playback. */
int  ac_ios_audio_init(char *err, size_t cap);
void ac_ios_audio_shutdown(void);
void ac_ios_audio_set_state(float rpm, float throttle, float brake, float speed, float gear);
void ac_ios_audio_set_volumes(float master, float engine, float effects);
void ac_ios_audio_set_mute(int muted);
int  ac_ios_audio_status(char *buf, size_t cap);
void ac_ios_texture_stats(uint64_t *loaded, uint64_t *failed, uint64_t *cpu_decoded_bc);

/* Phase 11: real AC lap timer, tested UI helpers, memory footprint. */
int  ac_ios_lap_state(ACIosLapState *out);
int  ac_ios_format_lap_ms(uint32_t ms, char *buf, size_t cap);
int64_t ac_ios_lap_delta_ms(uint32_t lap_ms, uint32_t best_ms);
int  ac_ios_should_accept_pb(uint32_t candidate_ms, uint32_t valid, int32_t cuts, uint32_t best_ms);
uint32_t ac_ios_fps_cap_for_index(int index);
int  ac_ios_fps_index_for_cap(uint32_t cap);
uint32_t ac_ios_thermal_cap(uint32_t user_cap, int thermal_state);
uint64_t ac_ios_memory_footprint(void);
void *ac_ios_metal_layer(void);
void ac_ios_set_metal_layer(void *layer);   /* pass NULL on view teardown */
#ifdef __OBJC__
@class NSString;
void ac_ios_set_content_root(NSString *path);
#endif
void ac_ios_set_input(ACIosInputState state);

/* Exported by ac-ios-runtime (Rust staticlib). */
int  ac_ios_boot(void *out_vtable);

/* Boots the Rust runtime and installs the resulting vtable into the native
 * PAL bridge. Implemented here so no C function-pointer casts are needed in
 * the Objective-C view controller. */
int  ac_ios_install_core_vtable(void);
/* Set BEFORE creating a session: 1 = automatic gearbox, 0 = manual paddles. */
void ac_ios_set_auto_shifter(int enabled);

/* Real wgpu/Metal chain implemented in ac-ios-runtime/src/metal.rs.
   These are plain C symbols exported by the Rust staticlib. */
int      ac_ios_metal_init(void *layer, uint32_t width, uint32_t height,
                           char *err, size_t cap);
int      ac_ios_metal_resize(uint32_t width, uint32_t height);
void     ac_ios_metal_destroy(void);
int      ac_ios_metal_is_ready(void);
int      ac_ios_metal_device_info(uint64_t *features_out4);

/* Real AC renderer (AcRenderer) driven by the live GameSim. */
int      ac_ios_render_init(void *session, uint32_t width, uint32_t height,
                            char *err, size_t cap);
int      ac_ios_render_frame(void *session);
int      ac_ios_render_resize(uint32_t width, uint32_t height);
float    ac_ios_render_last_draw_ms(void);
void     ac_ios_render_stats(uint64_t *frames, float *mean_ms);
void     ac_ios_render_destroy(void);

#ifdef __cplusplus
}
#endif
#endif
