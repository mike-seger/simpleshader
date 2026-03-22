precision highp float;

uniform vec2 u_resolution;
uniform float u_time;

// ── helpers ────────────────────────────────────────────────
#define PI  3.14159265
#define TAU 6.28318530
#define PHI 1.61803398  // golden ratio

mat2 rot(float a) {
    float c = cos(a), s = sin(a);
    return mat2(c, -s, s, c);
}

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// ── SDF primitives ─────────────────────────────────────────
float sdSphere(vec3 p, float r) { return length(p) - r; }
float sdPlane(vec3 p, float y)  { return p.y - y; }

// ── Five-pointed star SDF ──────────────────────────────────
float sdStar5(vec2 p, float r, float rf) {
    // r = outer radius, rf = inner radius fraction
    const float an = PI / 5.0;  // 36 deg
    float bn = mod(atan(p.x, p.y), 2.0 * an) - an;
    vec2 q = length(p) * vec2(cos(bn), abs(sin(bn)));
    // Outer tip & inner valley points in one sector
    vec2 tip = r * vec2(cos(an), sin(an));
    vec2 val = r * rf * vec2(1.0, 0.0);
    // Edge vector
    vec2 e = val - tip;
    vec2 d = q - tip;
    d -= e * clamp(dot(d, e) / dot(e, e), 0.0, 1.0);
    return length(d) * sign(d.x);
}

// ── Regular pentagon SDF ───────────────────────────────────
float sdPentagon(vec2 p, float r) {
    const float an = PI / 5.0;   // 36 deg
    const float hn = PI / 10.0;  // 18 deg  — half-sector
    float bn = mod(atan(p.x, p.y) + hn, 2.0 * an) - an;
    vec2 q = length(p) * vec2(cos(bn), abs(sin(bn)));
    // Side sits at y = r * cos(an), so signed distance to that edge:
    float side = q.y - r * cos(an);
    return side;
}

// ── Dodecahedral geometry ──────────────────────────────────
// 12 face centres of a regular dodecahedron (dual of icosahedron).
// Using exact coordinates: the 12 vertices of an icosahedron
// are the face centres of the dodecahedron.
//
// Icosahedron vertices (normalised):
//   (0, ±1, ±φ), (±1, ±φ, 0), (±φ, 0, ±1)   [even permutations]
// where φ = golden ratio ≈ 1.618

// Returns: vec3(starDist, pentDist, closestFaceIdx)
// We compute the closest dodecahedral face, then draw in its tangent space.
vec3 ballPattern(vec3 n) {
    // Slow rotation
    float t = u_time * 0.12;
    n.xz *= rot(t);
    n.xy *= rot(t * 0.6);

    // 12 icosahedron vertices = dodecahedron face normals
    // We unroll into 3 groups of 4 to stay WebGL 1 friendly (no large arrays).
    // Group A: (0, ±1, ±φ) normalised
    float a1 = 1.0, a2 = PHI;
    float invLen = 1.0 / sqrt(1.0 + PHI * PHI); // normalise
    // Group B: (±1, ±φ, 0) normalised
    // Group C: (±φ, 0, ±1) normalised

    float bestDot = -2.0;
    vec3  bestDir = vec3(0.0, 1.0, 0.0);

    // Macro to test one face normal
    #define TEST_FACE(vx, vy, vz) { \
        vec3 fn = vec3(vx, vy, vz) * invLen; \
        float dp = dot(n, fn); \
        if (dp > bestDot) { bestDot = dp; bestDir = fn; } \
    }

    // Group A: (0, ±1, ±φ)
    TEST_FACE(0.0,  1.0,  PHI)
    TEST_FACE(0.0,  1.0, -PHI)
    TEST_FACE(0.0, -1.0,  PHI)
    TEST_FACE(0.0, -1.0, -PHI)
    // Group B: (±1, ±φ, 0)
    TEST_FACE( 1.0,  PHI, 0.0)
    TEST_FACE( 1.0, -PHI, 0.0)
    TEST_FACE(-1.0,  PHI, 0.0)
    TEST_FACE(-1.0, -PHI, 0.0)
    // Group C: (±φ, 0, ±1)
    TEST_FACE( PHI, 0.0,  1.0)
    TEST_FACE( PHI, 0.0, -1.0)
    TEST_FACE(-PHI, 0.0,  1.0)
    TEST_FACE(-PHI, 0.0, -1.0)

    #undef TEST_FACE

    // Build tangent frame for the closest face
    vec3 c = bestDir;
    vec3 up = abs(c.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 tU = normalize(cross(up, c));
    vec3 tV = cross(c, tU);

    // Project onto tangent plane via gnomonic projection
    float cosA = dot(n, c);
    vec2 lp = vec2(dot(n, tU), dot(n, tV)) / max(cosA, 0.01);

    // Scale so the pentagon fills the Voronoi cell.
    // Angular radius of dodecahedral face ≈ 37.38°, tan ≈ 0.7265
    float sc = 1.0 / 0.7265;
    lp *= sc;

    // Star: fills most of the cell, with the tips touching the cell boundary
    float starR  = 0.90;                // outer radius (relative to cell)
    float innerF = 0.42;               // inner/outer ratio ≈ star thinness
    float dStar = sdStar5(lp, starR, innerF);

    // Pentagon: drawn slightly smaller, sitting inside the star
    float pentR = starR * innerF * 0.95;
    float dPent = sdPentagon(lp, pentR);

    return vec3(dStar, dPent, bestDot);
}

// ── Scene SDF ──────────────────────────────────────────────
float ballRadius = 0.8;
float groundY    = -0.85;

vec2 map(vec3 p) {
    float db = sdSphere(p, ballRadius);
    float dg = sdPlane(p, groundY);
    if (db < dg) return vec2(db, 1.0);
    return vec2(dg, 2.0);
}

vec3 calcNormal(vec3 p) {
    vec2 e = vec2(0.001, 0.0);
    return normalize(vec3(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x));
}

// ── Ray march ──────────────────────────────────────────────
vec2 march(vec3 ro, vec3 rd) {
    float t = 0.0;
    float id = 0.0;
    for (int i = 0; i < 100; i++) {
        vec3 p = ro + rd * t;
        vec2 h = map(p);
        if (h.x < 0.001) { id = h.y; break; }
        t += h.x;
        if (t > 30.0) break;
    }
    return vec2(t, id);
}

// ── Soft shadow ────────────────────────────────────────────
float softShadow(vec3 ro, vec3 rd, float mint, float maxt) {
    float res = 1.0;
    float t = mint;
    for (int i = 0; i < 40; i++) {
        float h = map(ro + rd * t).x;
        res = min(res, 8.0 * h / t);
        t += clamp(h, 0.02, 0.2);
        if (t > maxt) break;
    }
    return clamp(res, 0.0, 1.0);
}

// ── Background / atmosphere ────────────────────────────────
vec3 background(vec2 uv) {
    vec3 col = mix(vec3(0.01, 0.005, 0.04), vec3(0.03, 0.01, 0.08), uv.y * 0.5 + 0.5);

    // Bokeh lights
    float t = u_time * 0.25;
    for (int i = 0; i < 14; i++) {
        float fi = float(i);
        vec2 p = vec2(
            hash(vec2(fi, 1.0)) * 2.4 - 1.2,
            hash(vec2(fi, 2.0)) * 0.8 + 0.1
        );
        p.x += sin(t + fi * 1.3) * 0.06;
        float r = hash(vec2(fi, 3.0)) * 0.025 + 0.008;
        float b = smoothstep(r, 0.0, length(uv - p));
        vec3 bc = mix(vec3(0.1, 0.15, 0.9), vec3(0.0, 0.5, 1.0), hash(vec2(fi, 4.0)));
        col += bc * b * 0.6;
    }
    return col;
}

// ── Neon colours (matching the reference image) ────────────
vec3 neonBlue  = vec3(0.08, 0.40, 1.0);
vec3 neonCyan  = vec3(0.05, 0.65, 1.0);
vec3 neonDeep  = vec3(0.03, 0.20, 0.80);

// ── Main shading ───────────────────────────────────────────
vec3 shade(vec3 ro, vec3 rd, vec2 hit) {
    float t = hit.x;
    float id = hit.y;
    vec3 p = ro + rd * t;
    vec3 n = calcNormal(p);

    vec3 lightPos = vec3(2.0, 4.0, -2.0);
    vec3 L = normalize(lightPos - p);

    if (id < 1.5) {
        // ── Ball ──
        vec3 norm = normalize(p / ballRadius);
        vec3 pat = ballPattern(norm);
        float dStar = pat.x;
        float dPent = pat.y;

        // Star outline glow — neon edges
        float starEdge = abs(dStar);
        float starLine = smoothstep(0.05, 0.0, starEdge);    // sharp bright line
        float starGlow = exp(-starEdge * 8.0);                // wider glow bloom

        // Pentagon outline glow
        float pentEdge = abs(dPent);
        float pentLine = smoothstep(0.05, 0.0, pentEdge);
        float pentGlow = exp(-pentEdge * 10.0);

        // Inside star vs outside
        float insideStar = smoothstep(0.02, -0.02, dStar);
        float insidePent = smoothstep(0.02, -0.02, dPent);

        // Base: very dark navy
        vec3 baseCol = vec3(0.005, 0.01, 0.03);

        // Inside stars: slightly lighter dark blue
        baseCol = mix(baseCol, vec3(0.01, 0.025, 0.07), insideStar * 0.5);
        // Inside pentagons: another subtle shade
        baseCol = mix(baseCol, vec3(0.015, 0.03, 0.08), insidePent * 0.4);

        // Diffuse + specular
        float diff = max(dot(n, L), 0.0);
        vec3 H = normalize(L - rd);
        float spec = pow(max(dot(n, H), 0.0), 80.0);

        // Fresnel rim
        float fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.5);

        vec3 col = baseCol * (0.06 + diff * 0.25);
        col += spec * neonDeep * 0.4;

        // ── Neon lines ──
        // Star outlines
        col += neonBlue * starLine * 2.0;
        col += neonCyan * starGlow * 1.2;

        // Pentagon outlines
        col += neonBlue * pentLine * 1.8;
        col += neonCyan * pentGlow * 0.9;

        // Bright intersection where star & pentagon edges overlap
        float overlap = starGlow * pentGlow;
        col += vec3(0.3, 0.7, 1.0) * overlap * 2.0;

        // Fresnel rim — strong neon blue
        col += neonBlue * fresnel * 0.8;

        // Subtle pulse
        col *= 1.0 + 0.06 * sin(u_time * 2.0);

        return col;
    } else {
        // ── Ground plane ──
        vec3 baseCol = vec3(0.005, 0.005, 0.015);

        float diff = max(dot(n, L), 0.0);
        float sh = softShadow(p + n * 0.01, L, 0.02, 5.0);

        // Reflection glow
        vec3 rp = p;
        rp.y = -rp.y - 2.0 * groundY;
        float distToBall = length(rp);
        float groundGlow = exp(-distToBall * 1.4) * 1.3;

        vec3 col = baseCol + diff * sh * vec3(0.01, 0.02, 0.05);

        // Neon reflection
        col += neonBlue * groundGlow * 0.9;
        col += neonCyan * exp(-distToBall * 2.2) * 0.5;

        // Wet specular
        vec3 H = normalize(L - rd);
        float spec = pow(max(dot(n, H), 0.0), 128.0);
        col += spec * neonDeep * sh * 0.3;

        // Scattered wet highlights
        float wet = hash(floor(p.xz * 12.0)) * 0.12;
        col += wet * neonBlue * groundGlow;

        return col;
    }
}

// ── Entry ──────────────────────────────────────────────────
void main() {
    float s = min(u_resolution.x, u_resolution.y);
    vec2 uv = (2.0 * gl_FragCoord.xy - u_resolution) / s;

    // Camera
    vec3 ro = vec3(0.0, 0.3, -2.8);
    vec3 ta = vec3(0.0, -0.1, 0.0);
    vec3 ww = normalize(ta - ro);
    vec3 uu = normalize(cross(ww, vec3(0.0, 1.0, 0.0)));
    vec3 vv = cross(uu, ww);
    vec3 rd = normalize(uv.x * uu + uv.y * vv + 1.6 * ww);

    // March
    vec2 hit = march(ro, rd);

    vec3 col;
    if (hit.x < 30.0) {
        col = shade(ro, rd, hit);

        // Fog
        float fog = 1.0 - exp(-hit.x * 0.05);
        col = mix(col, vec3(0.01, 0.005, 0.04), fog);
    } else {
        col = background(uv);
    }

    // Atmospheric glow halo
    float bd = length(cross(rd, ro)) / length(rd);
    col += neonBlue * exp(-bd * 2.0) * 0.12;

    // Vignette
    vec2 vuv = gl_FragCoord.xy / u_resolution;
    float vig = 1.0 - 0.45 * length(vuv - 0.5);
    col *= vig;

    // Tone map (Reinhard)
    col = col / (1.0 + col);
    col = pow(col, vec3(0.88));

    gl_FragColor = vec4(col, 1.0);
}
