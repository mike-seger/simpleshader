// ── palette.glsl ─────────────────────────────────────────────────────────────
// Reusable IQ cosine-palette library.
// No dependencies — pure math, no uniforms required.
//
// Usage:
//   vec3 col = getPaletteColor(t, PALETTE);   // t ∈ [0,1], palette ∈ [0,5]

// IQ cosine palette: color = a + b * cos(2π*(c*t + d))
vec3 cospalette(float t, vec3 a, vec3 b, vec3 c, vec3 d) {
    return clamp(a + b * cos(6.28318 * (c * t + d)), 0.0, 1.0);
}

// palette: 0=Rainbow  1=Neon  2=Pastel  3=Ocean  4=Sunset  5=Mono
vec3 getPaletteColor(float t, int palette) {
    if (palette == 0) // Rainbow
        return cospalette(t, vec3(0.5, 0.5, 0.5), vec3(0.5, 0.5, 0.5),
                             vec3(1.0, 1.0, 1.0), vec3(0.00, 0.33, 0.67));
    if (palette == 1) // Neon
        return cospalette(t, vec3(0.5, 0.5, 0.5), vec3(0.5, 0.5, 0.5),
                             vec3(2.0, 1.0, 0.0), vec3(0.50, 0.20, 0.25));
    if (palette == 2) // Pastel
        return cospalette(t, vec3(0.8, 0.5, 0.4), vec3(0.2, 0.4, 0.2),
                             vec3(2.0, 1.0, 1.0), vec3(0.00, 0.25, 0.25));
    if (palette == 3) // Ocean
        return cospalette(t, vec3(0.1, 0.3, 0.5), vec3(0.1, 0.3, 0.3),
                             vec3(1.0, 1.0, 1.0), vec3(0.30, 0.50, 0.70));
    if (palette == 4) // Sunset
        return cospalette(t, vec3(0.5, 0.2, 0.1), vec3(0.5, 0.3, 0.2),
                             vec3(1.0, 1.0, 2.0), vec3(0.00, 0.15, 0.20));
    // 5 = Mono
    return cospalette(t, vec3(0.5), vec3(0.5), vec3(1.0), vec3(0.0));
}
