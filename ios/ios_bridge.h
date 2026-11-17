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
