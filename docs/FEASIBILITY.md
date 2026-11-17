# iOS API / subsystem compatibility matrix

Legend: **Portable** = pure Rust/C, no OS dependency. **Adapter** = needs new iOS code.
**Blocker** = cannot work as-is without a major port or external dependency.

| Subsystem | Original / rustyAC tech | iOS target | Verdict | Notes |
|---|---|---|---|---|
| Graphics API | D3D11 (`rustyac-render`), plus `backend-wgpu` / `kgl_wgpu.rs` | Metal via wgpu 30 `metal` feature + `CAMetalLayer` | **Adapter (compiled for iOS ARM64, not run)** | `rust/ac-ios-runtime/src/metal.rs` builds `Instance(METAL) → Surface(CoreAnimationLayer) → Adapter → Device/Queue`, configures the surface and calls upstream `Kgl::give_device`/`Kgl::init`. `Kgl::open()`'s VULKAN fallback is never reached. Device execution of this chain is still unverified |
| Shaders | AC compiled shaders → DXBC → WGSL (`rustyac-dxbc`) | WGSL → Metal via wgpu | **Adapter** | WGSL translation path exists for the browser proof; MSAA levels 2/8 are drawn as 4 on wgpu (upstream limitation). |
| Physics | `rustyac-physics`, `rustyac-ode` (ODE 0.13.1 port), pure Rust | `aarch64-apple-ios` | **Portable** | No OS APIs. Compile-check patch adds the target. Needs a non-UI physics thread. |
| Content / KN5 / ACD | `rustyac-content` (INI, ACD, KN5) | same files from imported folder | **Portable** | openASC's `asc-kn5`/`asc-acd` are a clean fallback if needed. |
| Input — gamepad | XInput/DirectInput (`rustyac-game`, windows-only) | `GameController.framework` (GCController) | **Adapter** | Implemented in `GameViewController.m`; AC's FFB/wheel APIs have no iOS equivalent. |
| Input — touch | n/a | UITouch → C bridge curves, 1 kHz step | **Adapter** | Implemented and host-tested (`core/ac_pal_bridge_test.c`). |
| Audio | FMOD Studio 1.08.12 banks + DLLs (`rustyac-audio`) | FMOD for iOS **or** CoreAudio | **Blocker** | `rustyac-audio` gates FMOD raw loading to `cfg(windows)`; browser uses FMOD HTML5/JS. iOS needs either an FMOD iOS SDK integration (license + binary) or a new CoreAudio sink fed by the portable DSP. Not solved. |
| Filesystem | absolute Windows paths, Steam library detection | app sandbox + security-scoped bookmark | **Adapter** | `ContentLocator` trait + `AppDelegate` bookmark implemented; no asset bundling. |
| App lifecycle | Win32 message loop | UIKit `UIApplicationDelegate`, MTKView delegate | **Adapter** | Implemented in shell; background/resume correctness untested. |
| Windowing / surface | Win32 + D3D11 swapchain | UIKit + CAMetalLayer + wgpu surface | **Blocker (verification)** | Needs macOS/Xcode to write and test the wgpu surface glue. Highest-risk integration item. |
| Shared memory / telemetry | Win32 named shared memory | iOS has no cross-process SHM equivalent | **Not applicable** | Telemetry consumers (SimHub etc.) are desktop-only; drop on iOS. |
| Python apps | `python33.dll` (`rustyac-python`) | no embedded Python on iOS (possible via PyO3 but heavy) | **Not planned** | Out of scope for the prototype. |
| Multiplayer | acServer client + rustls gateway | same Rust net crate | **Portable (later)** | rustyac-net is platform-agnostic; defer behind the core. |
| Launcher | .NET launcher + CEF (`rustyac-launcher`) | native iOS menu | **Adapter** | Native menu implemented; AC's CEF launcher cannot run on iOS. |
| VR / TrackIR / triple screen | OpenVR/Oculus/TrackIR | none | **Not applicable** | No iOS support; drop. |
| Code signing / distribution | none | Apple Developer identity, provisioning, notarization | **Blocker (environment)** | No signing identity or macOS in this sandbox. |

## Risks ranked

1. **wgpu surface lifetime on iOS** — Metal device + `CAMetalLayer` resizing, app
   background/foreground, and wgpu 30's iOS raw-window-handle path. Must be prototyped
   first on a Mac.
2. **Audio** — no iOS FMOD backend in rustyAC. `rustyac-audio`'s DSP is portable, but
   driving CoreAudio correctly (engine RPM/load, 3D positional audio, sample-accurate
   scheduling) is real work.
3. **Memory/storage** — a full AC install is ~42.7 GB; iPhones have 128 GB–1 TB and the
   Files-app import flow plus security-scoped bookmarks need device testing.
4. **Thermal/performance** — 1 kHz physics + AC's full post-processing on an iPhone is
   likely too heavy; expect needing reduced settings (upstream browser build already
   drops YEBIS post-processing). No FPS numbers are claimed.
5. **Licensing** — rustyAC game/physics is GPL-3.0-or-later; distributing an iOS app
   requires complying with GPL (source offer, license notices). AC content rights remain
   with Kunos/505; never bundle it.
