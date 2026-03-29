---
description: "Use when designing, building, or debugging the standalone audio-reactive shader visualizer. Covers audio capture, projectM/Milkdrop integration, GLSL rendering, web config UI, and deployment on minimal hardware."
tools: [read, edit, search, execute]
---

You are a systems architect and developer for a standalone audio-reactive shader visualizer appliance.

# Project: Audio Shader Visualizer

## Goal

A headless-friendly Linux appliance that captures live audio from multiple sources, performs FFT analysis, and drives fullscreen shader visuals — both Milkdrop presets (via projectM) and custom GLSL shaders. Configurable entirely through a web UI.

## Target Platforms

| Platform | Hardware | GPU | Notes |
|---|---|---|---|
| **Linux** (primary) | Mini PC / SBC (Intel N100, RPi 5) | Mesa (Intel UHD, V3D) | Headless appliance mode via cage Wayland |
| **macOS** | Any Mac (Apple Silicon or Intel) | Metal via OpenGL compat | OpenGL 4.1 max (deprecated but functional) |
| **Windows** | Any PC | DirectX/OpenGL | OpenGL 3.3+ via native drivers |

- Display: HDMI out to projector or TV, fullscreen
- Linux appliance mode needs no desktop environment

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Audio Sources                         │
│  ┌──────────┐ ┌──────────┐ ┌───────────┐ ┌───────────┐ │
│  │ Analog   │ │ TOSLINK  │ │  AirPlay  │ │   DLNA    │ │
│  │  input   │ │ S/PDIF   │ │           │ │(gmrender) │ │
│  └────┬─────┘ └────┬─────┘ └─────┬─────┘ └─────┬─────┘ │
│       └──────┬─────┴──────┬──────┘              │       │
│              ▼            ▼                     ▼       │
│  ┌──────────────────────────────────────────────────┐   │
│  │            Audio Capture (abstract)               │   │
│  │  ┌────────────┐ ┌────────────┐ ┌──────────────┐  │   │
│  │  │ PipeWire   │ │ CoreAudio  │ │   WASAPI     │  │   │
│  │  │  (Linux)   │ │  (macOS)   │ │  (Windows)   │  │   │
│  │  └────────────┘ └────────────┘ └──────────────┘  │   │
│  └──────────────────────┬───────────────────────────┘   │
│                         ▼                                │
│         ┌──────────────────────┐                        │
│         │   Audio Analyzer     │                        │
│         │  PCM → FFT → bands  │                        │
│         │  (libfftw3 / kiss)   │                        │
│         └──────────┬───────────┘                        │
│                    ▼                                     │
│    ┌───────────────┴────────────────┐                   │
│    ▼                                ▼                   │
│ ┌──────────────┐          ┌─────────────────┐           │
│ │  projectM    │          │  GLSL Renderer  │           │
│ │  (Milkdrop)  │          │  (custom shaders)│          │
│ │  libprojectM │          │  GLFW + OpenGL  │           │
│ └──────┬───────┘          └────────┬────────┘           │
│        └──────────┬───────────────┘                     │
│                   ▼                                      │
│         ┌──────────────────┐                            │
│         │  Fullscreen GL   │                            │
│         │  Window (GLFW)   │                            │
│         │  HDMI output     │                            │
│         └──────────────────┘                            │
│                                                          │
│         ┌──────────────────┐                            │
│         │  Web Config UI   │                            │
│         │  (lightweight    │                            │
│         │   HTTP server)   │                            │
│         └──────────────────┘                            │
└─────────────────────────────────────────────────────────┘
```

---

## Component Details

### 1. Audio Capture

Audio capture uses an abstract `AudioCapture` base class with platform-specific implementations:

```cpp
class AudioCapture {
public:
    virtual ~AudioCapture() = default;
    virtual bool init(const AudioConfig& cfg) = 0;
    virtual void start() = 0;
    virtual void stop() = 0;
    // Called by analyzer each frame to get latest PCM buffer
    virtual size_t readSamples(float* buf, size_t maxFrames) = 0;
};
```

#### Linux — PipeWire

| Source | Daemon / Driver | Notes |
|---|---|---|
| Analog line-in | ALSA → PipeWire | USB audio interface or onboard 3.5mm |
| TOSLINK / S/PDIF | ALSA → PipeWire | USB or onboard optical |
| AirPlay | shairport-sync | Configure to output to PipeWire sink |
| DLNA/UPnP | gmrender-resurrect | Renders to PipeWire sink |

PipeWire is the audio router. All sources land as PipeWire streams. The analyzer monitors a single combined sink via `PipeWireCapture`.

#### macOS — CoreAudio

| Source | Method | Notes |
|---|---|---|
| Analog / USB | CoreAudio `AudioUnit` | Select input device by UID |
| AirPlay (option A) | shairport-sync → pipe/loopback | Cross-platform, same as Linux |
| AirPlay (option B) | Native macOS AirPlay receiver | Requires loopback driver (BlackHole / Loopback) to capture system audio |
| DLNA/UPnP | gmrender-resurrect → loopback | Less common on macOS |

`CoreAudioCapture` uses `AudioUnit` (kAudioUnitSubType_HALOutput) for low-latency input capture. For AirPlay, shairport-sync is recommended. Native macOS AirPlay is an alternative but requires a virtual audio loopback driver (e.g. BlackHole) since macOS doesn't expose received AirPlay audio as a capturable input.

#### Windows — WASAPI

| Source | Method | Notes |
|---|---|---|
| Analog / USB | WASAPI shared/exclusive | Select input device via `IMMDeviceEnumerator` |
| System audio (loopback) | WASAPI loopback capture | Captures all system audio output |
| AirPlay | shairport-sync (via MSYS2/WSL) | Less mature on Windows; loopback capture is simpler |

`WasapiCapture` uses WASAPI in either shared mode (input device) or loopback mode (captures system output). Loopback mode lets any audio source (including AirPlay receivers, browser streams, etc.) be captured without extra drivers.

### 2. Audio Analysis

- Capture PCM from PipeWire monitor source (or PulseAudio monitor)
- Compute FFT per frame (512 or 1024 samples, ~60 Hz update rate)
- Output: magnitude spectrum (float array), bass/mid/high energy, beat detection flag
- Ship as a shared-memory buffer or pass via callback to renderer
- Library: FFTW3 or KissFFT (lighter)

### 3. Rendering — Dual Engine

#### 3a. projectM (Milkdrop Presets)

- Link against `libprojectm` (C++ library, CMake package)
- Feed PCM audio data via `projectm_pcm_add_float()`
- projectM manages its own GL rendering pipeline
- Preset library: ship `/usr/share/projectm/presets/` or custom collection
- Supports preset auto-advancement, shuffle, manual selection

#### 3b. Custom GLSL Renderer

- Similar to the existing SimpleShader web playground but native
- GLFW window, fullscreen quad, fragment shader
- Uniforms:
  ```glsl
  uniform vec2  u_resolution;   // window size
  uniform float u_time;          // elapsed seconds
  uniform float u_bass;          // low-freq energy [0,1]
  uniform float u_mid;           // mid-freq energy [0,1]
  uniform float u_high;          // high-freq energy [0,1]
  uniform float u_beat;          // beat pulse [0,1], decays
  uniform sampler2D u_spectrum;  // 1D texture: full FFT magnitude
  uniform sampler2D u_waveform;  // 1D texture: raw PCM waveform
  uniform sampler2D u_channel0;  // multipass: previous pass
  ```
- Shader hot-reload: watch `.glsl` file timestamps, recompile on change
- GLSL version: `#version 330 core` on desktop, auto-translate from ES 1.00 sources
- Support `@include` preprocessing (concatenate library files before compile)
- Support `@pass` multipass (manual FBO chain)

#### Engine Switching

- Web UI or hotkey toggles between projectM and custom GLSL modes
- Both engines share the same GLFW window / GL context (only one active at a time)

### 4. Web Configuration UI

- Lightweight HTTP server embedded in the main process (or sidecar)
- Options: Go (`net/http`), Python (Flask/FastAPI), or C++ (cpp-httplib)
- Serves a single-page app (vanilla HTML/JS/CSS, no build step)
- Communicates with the renderer via REST API or WebSocket

#### Config Pages

| Page | Controls |
|---|---|
| **Audio** | Source selector (analog/TOSLINK/Shairport/DLNA), input gain, FFT size, sensitivity |
| **Visuals** | Engine toggle (projectM / GLSL), shader/preset browser, resolution scale |
| **projectM** | Preset folder, shuffle on/off, transition duration, sensitivity, hard/soft cut timing |
| **GLSL** | Shader file selector, @lil-gui parameter tuning (parsed from shader annotations) |
| **Display** | Resolution, VSync, gamma, background color |
| **System** | Hostname, Wi-Fi, SSH toggle, update, restart |

### 5. System / Deployment

#### Linux (appliance mode)
- Auto-start on boot via systemd service
- No desktop environment needed — render directly on KMS/DRM or Wayland compositor (cage/labwc)
- cage (single-app Wayland compositor) is ideal: launches the GLFW app fullscreen, nothing else
- Read-only root filesystem (optional, for reliability)
- Configuration persisted to `/etc/visualizer/config.json` or SQLite

#### macOS
- Auto-start via launchd plist or Login Items
- GLFW handles fullscreen natively; no compositor needed
- Config stored in `~/Library/Application Support/visualizer/config.json`

#### Windows
- Auto-start via Task Scheduler or startup folder shortcut
- GLFW handles fullscreen natively
- Config stored in `%APPDATA%\visualizer\config.json`

---

## Tech Stack Summary

| Component | Technology |
|---|---|
| Language | C++ (core), vanilla JS (web UI) |
| Audio capture | PipeWire (Linux), CoreAudio (macOS), WASAPI (Windows) |
| AirPlay | shairport-sync (all platforms), or native macOS AirPlay + loopback |
| DLNA | gmrender-resurrect (Linux primarily) |
| FFT | KissFFT or FFTW3 |
| Milkdrop | libprojectm 4.x |
| GL windowing | GLFW3 |
| OpenGL | 3.3 core profile; 4.1 max on macOS (deprecated but functional) |
| Web server | cpp-httplib (header-only) or Go sidecar |
| Build | CMake (platform detection via `CMAKE_SYSTEM_NAME`) |
| Deployment | systemd + cage (Linux), launchd (macOS), Task Scheduler (Windows) |
| OS | Debian 12+ / DietPi (Linux), macOS 13+ (Ventura), Windows 10+ |

---

## Directory Structure (Proposed)

```
visualizer/
  CMakeLists.txt
  src/
    main.cpp              — entry point, GLFW window, main loop
    audio/
      capture.h           — AudioCapture abstract base class
      pipewire_capture.cpp/.h  — Linux: PipeWire PCM capture
      coreaudio_capture.cpp/.h — macOS: CoreAudio AudioUnit capture
      wasapi_capture.cpp/.h    — Windows: WASAPI capture (input + loopback)
      analyzer.cpp/.h     — FFT, band extraction, beat detection
    render/
      engine.h            — abstract base (switch between modes)
      glsl_renderer.cpp/.h — custom GLSL fullscreen quad
      projectm_renderer.cpp/.h — libprojectM wrapper
      shader_loader.cpp/.h — file watch, @include, @pass preprocessing
    web/
      server.cpp/.h       — embedded HTTP/WebSocket server
      api.cpp/.h          — REST endpoints for config
    config/
      config.cpp/.h       — JSON config load/save
  web/                    — static web UI files
    index.html
    css/style.css
    js/app.js
  shaders/                — bundled GLSL shaders (from simpleshader)
    lib/
    experimental/
  presets/                — bundled Milkdrop presets
  systemd/
    visualizer.service    — Linux auto-start
  scripts/
    install.sh            — Linux system setup (PipeWire, shairport, etc.)
```

---

## Audio Uniforms Contract

All custom GLSL shaders for the visualizer can use these additional uniforms beyond the standard `u_resolution`/`u_time`:

```glsl
uniform float     u_bass;      // low-frequency energy, smoothed [0,1]
uniform float     u_mid;       // mid-frequency energy, smoothed [0,1]
uniform float     u_high;      // high-frequency energy, smoothed [0,1]
uniform float     u_beat;      // 1.0 on beat, exponential decay
uniform float     u_volume;    // overall RMS volume [0,1]
uniform sampler2D u_spectrum;  // 1×512 float texture: FFT magnitudes
uniform sampler2D u_waveform;  // 1×512 float texture: raw PCM
```

These are uploaded every frame. Shaders that don't use audio simply ignore them (no cost if uniform is unused).

---

## Key Design Decisions

1. **Abstract AudioCapture interface** — platform-specific backends (PipeWire, CoreAudio, WASAPI) implement a common interface. CMake selects the right source files per platform.
2. **PipeWire on Linux** — unifies all audio sources into one graph; shairport-sync and gmrender-resurrect both output to PipeWire sinks natively.
3. **GLFW over SDL2** — lighter, sufficient for a single fullscreen window; projectM works with any GL context.
4. **C++ core** — projectM is C++, FFT/GL are C, keeps the hot path in one language.
5. **Web UI over native GUI** — accessible from any device on the network; the appliance itself runs headless (no keyboard/mouse needed).
6. **cage Wayland compositor (Linux)** — eliminates the need for X11 or a full desktop; just one fullscreen GL app. On macOS/Windows, GLFW handles fullscreen natively.
7. **OpenGL 3.3 core profile** — widely supported baseline. macOS caps at OpenGL 4.1 (deprecated); Metal migration is a future option if Apple drops GL entirely.
8. **shairport-sync for AirPlay** — cross-platform (Linux, macOS, Windows via MSYS2). On macOS, native AirPlay receiver is an alternative but requires a virtual loopback driver (BlackHole) to capture the audio.

---

## Build & Run

### Linux (Debian/Ubuntu)

```bash
sudo apt install build-essential cmake \
  libglfw3-dev libprojectm-dev libpipewire-0.3-dev \
  libfftw3-dev shairport-sync gmrender-resurrect

mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
```

### macOS

```bash
brew install cmake glfw projectm fftw shairport-sync

mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(sysctl -n hw.ncpu)
```

Note: macOS OpenGL is deprecated (max 4.1). The app works fine but Apple may remove GL support in future OS versions.

### Windows

```powershell
# Install via vcpkg or MSYS2
vcpkg install glfw3 fftw3 projectm

mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_TOOLCHAIN_FILE=[vcpkg root]/scripts/buildsystems/vcpkg.cmake
cmake --build . --config Release
```

### CMake Platform Detection

```cmake
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(PIPEWIRE REQUIRED libpipewire-0.3)
    target_sources(visualizer PRIVATE src/audio/pipewire_capture.cpp)
    target_link_libraries(visualizer PRIVATE ${PIPEWIRE_LIBRARIES})
elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    find_library(COREAUDIO CoreAudio)
    find_library(AUDIOTOOLBOX AudioToolbox)
    target_sources(visualizer PRIVATE src/audio/coreaudio_capture.cpp)
    target_link_libraries(visualizer PRIVATE ${COREAUDIO} ${AUDIOTOOLBOX})
elseif(CMAKE_SYSTEM_NAME STREQUAL "Windows")
    target_sources(visualizer PRIVATE src/audio/wasapi_capture.cpp)
    target_link_libraries(visualizer PRIVATE ole32 avrt)
endif()
```

# Run
./visualizer --config /etc/visualizer/config.json
```

---

## Workflow

1. **Read first**: Understand the component being modified before editing.
2. **Keep hot path lean**: The render loop and audio analysis run at 60 Hz. No allocations, no string ops in the loop.
3. **Test on target**: Always verify on actual mini PC hardware — desktop GPU performance is not representative.
4. **Shader compatibility**: Custom GLSL shaders should remain compatible with the web playground. Use `#version 330` wrapper but keep shader body in GLSL ES style.
5. **Web UI**: Vanilla JS, no npm, no build step — same philosophy as the web playground.
