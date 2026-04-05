/*
    Source: https://www.shadertoy.com/view/7fSGDt
    The license if not specified by the author is assumed to be:
    This work is licensed under a Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License.
    
    Please see the original shader for comments and description. 

    This is a slightly modified copy of the shader code, with only minor edits to make it compatible with SimpleShader 
    (e.g. renaming mainImage to main, stubbing iChannel0, etc.). If you intend to reuse this shader, please add credits to 'msttezcan'.
*/
precision highp float;
uniform vec2 u_resolution;
uniform float u_time;

#define TAU 6.28318530718

// @lil-gui-start
const float SCALE      = 4.0;        // @range(1, 12, 0.5)
const float SMOOTHNESS = 0.15;       // @range(0.01, 0.5, 0.01)
const int   PALETTE = 0;             // @options(0:Neon Arcade, 1:Ocean Depths, 2:Autumn Harvest, 3:Jewel Box, 4:Rainbow, 5:Greyscale)
const bool  GLOSSY    = true;
const bool  ANIMATED  = true;
const bool  SCROLLING = true;
// @lil-gui-end

// ---- Palette ------------------------------------------------

struct Palette {
    vec3 c1, c2, c3, c4, c5, c6;
};

Palette getPalette(int p) {
    if (p == 1) {
        // Ocean Depths
        return Palette(
            vec3(0.05, 0.20, 0.55),  // deep navy
            vec3(0.10, 0.50, 0.65),  // slate teal
            vec3(0.20, 0.75, 0.70),  // seafoam
            vec3(0.90, 0.55, 0.35),  // coral
            vec3(0.85, 0.80, 0.55),  // sand
            vec3(0.30, 0.85, 0.90)   // turquoise
        );
    }
    if (p == 2) {
        // Autumn Harvest
        return Palette(
            vec3(0.80, 0.30, 0.08),  // burnt orange
            vec3(0.90, 0.70, 0.10),  // gold
            vec3(0.55, 0.10, 0.15),  // burgundy
            vec3(0.45, 0.50, 0.12),  // olive
            vec3(0.70, 0.20, 0.05),  // rust
            vec3(0.95, 0.85, 0.60)   // wheat
        );
    }
    if (p == 3) {
        // Jewel Box
        return Palette(
            vec3(0.85, 0.05, 0.15),  // ruby
            vec3(0.05, 0.70, 0.30),  // emerald
            vec3(0.10, 0.15, 0.85),  // sapphire
            vec3(0.55, 0.10, 0.75),  // amethyst
            vec3(0.95, 0.70, 0.10),  // topaz
            vec3(0.12, 0.12, 0.14)   // onyx
        );
    }
    if (p == 4) {
        // Rainbow
        return Palette(
            vec3(1.00, 0.00, 0.00),  // red
            vec3(1.00, 0.65, 0.00),  // orange
            vec3(1.00, 1.00, 0.00),  // yellow
            vec3(0.00, 1.00, 0.00),  // green
            vec3(0.00, 0.40, 1.00),  // blue
            vec3(0.60, 0.00, 1.00)   // violet
        );
    }
    if (p == 5) {
        // Greyscale
        return Palette(
            vec3(0.92),              // near white
            vec3(0.68),              // light grey
            vec3(0.46),              // mid grey
            vec3(0.28),              // dark grey
            vec3(0.14),              // charcoal
            vec3(0.05)               // near black
        );
    }
    // 0: Neon Arcade (default)
    return Palette(
        vec3(0.50, 0.93, 0.07),  // lime
        vec3(1.00, 0.19, 0.31),  // red
        vec3(0.38, 0.16, 0.98),  // violet
        vec3(0.04, 0.89, 0.57),  // teal
        vec3(0.74, 0.76, 0.00),  // yellow
        vec3(0.91, 0.04, 0.55)   // magenta
    );
}

vec3 paletteColor(Palette pal, int idx) {
    if (idx == 0) return pal.c1;
    if (idx == 1) return pal.c2;
    if (idx == 2) return pal.c3;
    if (idx == 3) return pal.c4;
    if (idx == 4) return pal.c5;
    return pal.c6;
}

// ---- Helpers ------------------------------------------------

float hash12(vec2 p) {
    p = fract(p * vec2(443.897, 441.423));
    p += dot(p, p.yx + 19.19);
    return fract((p.x + p.y) * p.x);
}

float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

vec3 stoneColor(vec2 id) {
    Palette pal = getPalette(PALETTE);
    int idx = int(mod(hash12(id) * 6.0, 6.0));
    vec3 col = paletteColor(pal, idx);

    // Per-stone brightness variation
    float h3 = hash12(id + vec2(53.1, 97.4));
    col *= 0.60 + 0.40 * h3;
    return col;
}

// ---- Animated span ------------------------------------------

float randSpan(vec2 p) {
    if (ANIMATED) {
        return (sin(u_time * 1.6 + hash12(p) * TAU) * 0.5 + 0.5) * 0.6 + 0.2;
    }
    return hash12(p) * 0.6 + 0.2;
}

// ---- Main ---------------------------------------------------

void main() {
    vec2 uv = (2.0 * gl_FragCoord.xy - u_resolution) / u_resolution.y;
    uv *= SCALE;

    if (SCROLLING) {
        uv += vec2(0.7, 0.5) * u_time;
    }

    vec2 fl = floor(uv);
    vec2 fr = fract(uv);

    bool ch = mod(fl.x + fl.y, 2.0) > 0.5;

    float r1 = randSpan(fl);
    vec2  ax = ch ? fr.xy : fr.yx;

    float a1 = ax.x - r1;
    float si = sign(a1);
    vec2  o1 = ch ? vec2(si, 0) : vec2(0, si);

    float r2 = randSpan(fl + o1);
    float a2 = ax.y - r2;

    vec2 st = step(vec2(0), vec2(a1, a2));

    // Tile ID
    vec2 of = ch ? st.xy : st.yx;
    vec2 id = fl + of - 1.0;

    bool ch2 = mod(id.x + id.y, 2.0) > 0.5;

    float r00 = randSpan(id + vec2(0, 0));
    float r10 = randSpan(id + vec2(1, 0));
    float r01 = randSpan(id + vec2(0, 1));
    float r11 = randSpan(id + vec2(1, 1));

    vec2 s0 = ch2 ? vec2(r00, r10) : vec2(r01, r00);
    vec2 s1 = ch2 ? vec2(r11, r01) : vec2(r10, r11);
    vec2 s  = 1.0 - s0 + s1;

    vec2 puv = (uv - id - s0) / s;

    // Border distance
    vec2  b = (0.5 - abs(puv - 0.5)) * s;
    float d = smin(b.x, b.y, SMOOTHNESS);
    float l = smoothstep(0.02, 0.06, d);

    // Highlights
    vec2  hp = (1.0 - puv) * s;
    float h  = smoothstep(0.08, 0.0, max(smin(hp.x, hp.y, SMOOTHNESS), 0.0));

    // Shadows
    vec2  sp = puv * s;
    float sh = smoothstep(0.05, 0.12, max(smin(sp.x, sp.y, SMOOTHNESS), 0.0));

    // Color from palette
    vec3 baseCol = stoneColor(id);
    vec3 col;

    // Approximate surface normal from tile-local UV (slight dome)
    vec2 n2 = (puv - 0.5) * 2.0;
    vec3 N = normalize(vec3(-n2 * 0.4, 1.0));

    if (GLOSSY) {
        // Glossy polished stone look
        vec3 L = normalize(vec3(0.4, 0.6, 1.0));
        vec3 V = vec3(0.0, 0.0, 1.0);
        vec3 H = normalize(L + V);
        vec3 R = reflect(-V, N);

        // Diffuse — wrap-lit, not flat
        float diff = max(dot(N, L), 0.0) * 0.5 + 0.5;

        // Specular — tight Blinn-Phong
        float spec = pow(max(dot(N, H), 0.0), 128.0) * 1.2;

        // Fresnel rim — polished surface reflects more at grazing angles
        float fresnel = pow(1.0 - max(dot(N, V), 0.0), 3.0);

        // Fake environment reflection
        vec3 envCol = mix(vec3(0.15, 0.12, 0.18), vec3(0.6, 0.7, 0.9), R.y * 0.5 + 0.5);

        col = baseCol * diff * 0.65;              // tinted diffuse
        col += envCol * fresnel * 0.35;           // environment at edges
        col += spec * vec3(1.0, 0.97, 0.92) * l; // white specular
        col += baseCol * 0.12;                    // ambient

        col *= sh * 0.7 + 0.3;
        col += h * vec3(0.7, 0.65, 0.55) * 0.5;
    } else {
        // Matte surface
        col = baseCol;
        col *= puv.x * 0.4 + 0.6;
        col *= puv.y * 0.3 + 0.7;
        col *= sh * 0.8 + 0.2;
        col += h * vec3(0.9, 0.8, 0.7);
    }

    // Edge
    col *= l * 5.0;

    col = max(col, vec3(0));
    col = col / (1.0 + col);
    col = pow(col, vec3(1.0 / 2.2));

    gl_FragColor = vec4(col, 1.0);
}
