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
- Array indexing must use constants or loop variables — no `arr[dynamicIndex]`
- `switch`/`case` not available — use `if`/`else if` chains

## Uniforms

Only these uniforms are available (do not declare others):
```glsl
uniform vec2  u_resolution;   // canvas size in pixels
uniform float u_time;          // elapsed seconds
uniform sampler2D u_channel0;  // multipass only: previous pass output
uniform sampler2D u_channel1;  // multipass only: pass before that
```

When porting from Shadertoy, replace:
- `iResolution` → `u_resolution` (vec2, not vec3)
- `iTime` / `iGlobalTime` → `u_time`
- `fragCoord` → `gl_FragCoord.xy`
- `fragColor` → `gl_FragColor`
- `iChannel0` → `u_channel0`

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

Gate pattern: a `const bool NAME` followed by `NAME_*` siblings → the bool becomes a toggle that shows/hides the group.

## @include Libraries

```glsl
// @include ../lib/palette.glsl   — cospalette(), getPaletteColor(t, palette)
// @include ../lib/grid.glsl      — framedRect(), grid utilities
// @include ../lib/plasma.glsl    — plasma(uv, t)
```

Paths are relative to the shader file's location.

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
