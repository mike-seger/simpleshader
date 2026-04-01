---
description: "Use when writing, editing, porting, or debugging GLSL fragment shaders. Covers WebGL 1 constraints, uniform conventions, annotation syntax, and common patterns."
applyTo: "**/*.glsl"
---

# GLSL Shader Guidelines

## Hard Constraints (WebGL 1 / GLSL ES 1.00)

- First line must be `precision highp float;`
- Use `attribute`/`varying`, never `in`/`out`
- No `texelFetch()` — use `texture2D()` only
- No `layout()` qualifiers
- No unsigned types (`uint`, `uvec2`, etc.)
- No bitwise operators (`<<`, `>>`, `&`, `|`, `^`)
- `for` loops must have constant bounds — no `for (int i = 0; i < N; i++)` where N is a variable
- `for` loops must have all three expressions — `for(x; y; )` is invalid; use a separate variable if the increment is computed in the body
- `for` loop index cannot be modified inside the loop body — use a separate variable (e.g. `float st = 0.; for(int i=0; i<N; i++) { ... st += h; }`)
- `round()` is not available — use `floor(x + 0.5)` instead
- Array indexing must use constants or loop variables — no `arr[dynamicIndex]`
- `switch`/`case` not available — use `if`/`else if` chains

## Uniforms

These uniforms are available and **must be explicitly declared** in the shader (they are not auto-injected):
```glsl
uniform vec2  u_resolution;   // canvas size in pixels
uniform float u_time;          // elapsed seconds
```

`u_channel*` sampler uniforms are injected automatically when `@iChannel` or `@pass` annotations are present — do not declare them manually:
```glsl
uniform sampler2D u_channel0;  // multipass: previous pass / @iChannel media
uniform sampler2D u_channel1;  // multipass: pass before that / @iChannel media
```

When porting from Shadertoy, replace:
- `iResolution` → `u_resolution` (vec2, not vec3)
- `iTime` / `iGlobalTime` → `u_time`
- `fragCoord` → `gl_FragCoord.xy`
- `fragColor` → `gl_FragColor`
- `iChannel0` → `u_channel0`
- `texture()` → `texture2D()`
- `iDate` → remove or approximate (e.g. `iDate.z` → `floor(u_time)` for a varying seed)
- `iMouse` → remove (no mouse uniform); inline the no-mouse fallback values
- `mainImage(out vec4 O, in vec2 F)` → `void main()` using `gl_FragCoord.xy` and `gl_FragColor`

## @lil-gui Tunable Constants

Wrap tweakable constants to auto-generate UI controls:
```glsl
// @lil-gui-start
const float SIZE = 1.0;           // slider, heuristic range from name
const float CUSTOM = 5.0;         // @range(0, 20, 0.5) — explicit range
const vec4  BASE_COLOR = vec4(1.0, 0.5, 0.2, 1.0);  // color picker
const vec3  LIGHT_DIR = vec3(1.0, 2.0, -1.0);        // 3 sliders
const bool  GRID = true;          // checkbox
// @lil-gui-end
```

Name suffixes that trigger special widgets: `*_COLOR` (vec4) → color picker + alpha; `*_DIR` (vec3) → direction sliders.

Always name RGBA color constants ending with `_COLOR` (e.g. `HEAD_COLOR`, `TAIL_START_COLOR`, `TAIL_END_COLOR`) so the tuner auto-generates color pickers.

Gate pattern: a `const bool NAME` followed by `NAME_*` siblings → the bool becomes a toggle that shows/hides the group.

## @include Libraries

```glsl
// @include ../lib/palette.glsl   — cospalette(), getPaletteColor(t, palette)
// @include ../lib/grid.glsl      — framedRect(), grid utilities
// @include ../lib/plasma.glsl    — plasma(uv, t)
```

Paths are relative to the shader file's location.

## @iChannel Media Inputs

Load external images or audio as sampler inputs:
```glsl
// @iChannel0 media/audio.mp3  audio   — audio FFT texture (256×2 LUMINANCE)
// @iChannel1 media/image.jpg          — static image texture
```

Paths resolve relative to the shader file URL. The `uniform sampler2D u_channel*` declarations are injected automatically.

Audio channels produce a 256×2 texture: row 0 = frequency data, row 1 = waveform (like Shadertoy).

## Common Patterns

**Normalized coordinates:**
```glsl
float s = min(u_resolution.x, u_resolution.y);
vec2 uv = (2.0 * gl_FragCoord.xy - u_resolution) / s;  // centered, aspect-correct
```

**Rotation matrix:**
```glsl
mat2 rot(float a) { float c = cos(a), s = sin(a); return mat2(c, -s, s, c); }
```

**Output:** Always write `gl_FragColor = vec4(col, 1.0);` — alpha must be 1.0 for the final output.
