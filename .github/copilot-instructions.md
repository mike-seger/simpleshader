# Simple Shader — Project Instructions

## Project Overview

A browser-based GLSL shader playground with a Monaco code editor, WebGL 1 renderer, live-tuning sidebar (lil-gui), and a growing shader collection.

Served locally with `python3 -m http.server 8080` from the repo root.

## Architecture

```
web/
  js/
    app.js           — entry point, wires sidebar + renderer + editor
    renderer.js      — WebGL context, shader compilation, render loop
    editor.js        — Monaco editor wrapper
    sidebar.js       — shader tree navigation (reads web/shaders/index.js)
    shader-tuner.js  — @lil-gui annotation parser → lil-gui panel
    splitter.js      — draggable pane divider
    store.js         — localStorage persistence for custom shaders
  shaders/
    default.glsl     — fallback shader
    index.js         — static shader listing for sidebar
    lib/             — reusable @include libraries (palette, grid, plasma)
    experimental/    — original shaders in development
    shadertoy/       — ported Shadertoy remixes
    xordev/          — ported xordev tweetcarts
  css/style.css
  font/              — Material Symbols icon font
cpp/                 — offline C++ renderer (PPM frame output)
```

## GLSL Constraints

- **WebGL 1 / GLSL ES 1.00 only** — no `in`/`out`, no `texelFetch`, no `layout()`, no unsigned types
- Every shader must start with `precision highp float;`
- Standard uniforms: `uniform vec2 u_resolution;` and `uniform float u_time;`
- Multipass shaders additionally receive `uniform sampler2D u_channel0;` (previous pass output), `u_channel1`, etc.

## Shader Annotations

### Tunable constants (`@lil-gui`)

Constants between `// @lil-gui-start` and `// @lil-gui-end` are auto-exposed in the sidebar tuner panel:

```glsl
// @lil-gui-start
const float OPACITY = 0.8;
const vec4  STAR_COLOR = vec4(0.5, 0.9, 1.0, 0.95);
const vec3  LIGHT_DIR  = vec3(1.5, 2.0, -2.0);
const bool  GRID       = true;
// @lil-gui-end
```

Naming conventions control widget types:
- `*_COLOR` (vec4) → color picker + alpha slider
- `*_DIR` (vec3) → three sliders
- `const bool PREFIX` + `PREFIX_*` siblings → gate checkbox pattern

Range heuristics from name: `*OPACITY*`/`*ALPHA*`/`*RATIO*` → [0,1]; `*SIZE*` → [0.1,5]; `*INTENSITY*` → [0,20]; `*ANGLE*`/`*SPEED*` → [-360,360]; `*FREQ*` → [0,20]. Override with `// @range(min, max[, step])`.

### Include system

```glsl
// @include ../lib/palette.glsl
```

Resolved relative to the shader file's URL. Available libraries in `web/shaders/lib/`:
- `palette.glsl` — `cospalette()`, `getPaletteColor(t, palette)` (6 presets)
- `grid.glsl` — `framedRect()`, grid drawing utilities
- `plasma.glsl` — `plasma(uv, t)` four-wave sine plasma

### Multipass

```glsl
// @pass cell size=NUM_X,NUM_Y
void main() { ... }

// @pass composite
void main() { vec4 prev = texture2D(u_channel0, uv); ... }
```

Last pass renders to screen; intermediate passes render to FBOs. Size values can reference `const` names from the shader preamble.

## Code Style

- Vanilla JS (ES modules, no build step, no npm)
- No frameworks — plain DOM manipulation
- External deps loaded from CDN: Monaco editor, lil-gui
