// ── plasma.glsl ───────────────────────────────────────────────────────────────
// Classic four-wave sine plasma.
// No dependencies — pure math, no uniforms required.
//
// Usage:
//   float v = plasma(uv, t);   // uv ∈ [0,1]², t = time in seconds
//   vec3 col = getPaletteColor(v, palette);

// Returns a value in [0,1] driven by four overlapping sine waves.
float plasma(vec2 uv, float t) {
    float v = 0.0;
    v += sin(uv.x * 6.0 + t);
    v += sin(uv.y * 6.0 + t * 1.3);
    v += sin((uv.x + uv.y) * 5.0 + t * 0.7);
    v += sin(sqrt(uv.x * uv.x + uv.y * uv.y) * 8.0 - t * 1.1);
    return v * 0.125 + 0.5;   // map [-4,4] → [0,1]
}
