precision highp float;

uniform vec2 u_resolution;
uniform float u_time;

#define PI  3.14159265
#define TAU 6.28318530

// ── Tweakable constants ────────────────────────────────────
const float STAR_SIZE   = 1.6;  // 1.0 = default, larger = bigger stars
const float EDGE_WIDTH  = 0.1;  // 1.0 = default, larger = thicker neon edges
const bool  SHOW_LABELS = false; // show star index numbers

mat2 rot(float a) {
    float c = cos(a), s = sin(a);
    return mat2(c, -s, s, c);
}

// ── Five-pointed star SDF (exact) ──────────────────────────
// Returns negative inside the star, positive outside
float sdStar5(vec2 p, float r, float rf) {
    // r  = outer tip radius
    // rf = inner valley radius fraction (0..1)
    const float an = PI / 5.0;
    float bn = mod(atan(p.x, p.y), 2.0 * an) - an;
    vec2 q = length(p) * vec2(cos(bn), abs(sin(bn)));
    vec2 tip = r * vec2(cos(an), sin(an));
    vec2 val = r * rf * vec2(1.0, 0.0);
    vec2 e = val - tip;
    vec2 d = q - tip;
    d -= e * clamp(dot(d, e) / dot(e, e), 0.0, 1.0);
    return length(d) * sign(d.x);
}

// ── Dot-grid label (3 rows × 4 cols) ──────────────────────
// Draws n dots (0–12) in rows of up to 4, centered.
float drawDots(float n, vec2 p, float dotR, float spacing) {
    float row0 = min(n, 4.0);
    float row1 = min(max(n - 4.0, 0.0), 4.0);
    float row2 = max(n - 8.0, 0.0);
    float result = 0.0;
    for (int r = 0; r < 3; r++) {
        float count = r == 0 ? row0 : (r == 1 ? row1 : row2);
        if (count < 0.5) continue;
        float cy = (1.0 - float(r)) * spacing;
        float xStart = -(count - 1.0) * 0.5 * spacing;
        for (int c = 0; c < 4; c++) {
            if (float(c) >= count) break;
            float cx = xStart + float(c) * spacing;
            float d = length(p - vec2(cx, cy));
            result = max(result, 1.0 - smoothstep(dotR * 0.6, dotR, d));
        }
    }
    return result;
}

// ── Sphere ray intersection ────────────────────────────────
vec2 iSphere(vec3 ro, vec3 rd, float r) {
    float b = dot(ro, rd);
    float c = dot(ro, ro) - r * r;
    float h = b * b - c;
    if (h < 0.0) return vec2(-1.0);
    h = sqrt(h);
    return vec2(-b - h, -b + h);
}

// ── Golden ratio for dodecahedron geometry ─────────────────
const float phi = 1.618033988749895;

// 12 face centers of a dodecahedron (star centers)
vec3 getStarCenter(int idx) {
    if (idx == 0) return normalize(vec3( phi,  1.0,  0.0));
    if (idx == 1) return normalize(vec3( phi, -1.0,  0.0));
    if (idx == 2) return normalize(vec3(-phi,  1.0,  0.0));
    if (idx == 3) return normalize(vec3(-phi, -1.0,  0.0));
    if (idx == 4) return normalize(vec3( 1.0,  0.0,  phi));
    if (idx == 5) return normalize(vec3( 1.0,  0.0, -phi));
    if (idx == 6) return normalize(vec3(-1.0,  0.0,  phi));
    if (idx == 7) return normalize(vec3(-1.0,  0.0, -phi));
    if (idx == 8) return normalize(vec3( 0.0,  phi,  1.0));
    if (idx == 9) return normalize(vec3( 0.0,  phi, -1.0));
    if (idx == 10) return normalize(vec3( 0.0, -phi,  1.0));
    return normalize(vec3( 0.0, -phi, -1.0));
}

// Per-star rotation so each tip points at a neighbor
float getStarRotation(int idx) {
    if (idx ==  0) return  3.1415927;
    if (idx ==  1) return  0.0000000;
    if (idx ==  2) return  3.1415927;
    if (idx ==  3) return  0.0000000;
    if (idx ==  4) return -1.5707963;
    if (idx ==  5) return  1.5707963;
    if (idx ==  6) return  1.5707963;
    if (idx ==  7) return -1.5707963;
    if (idx ==  8) return  0.0000000;
    if (idx ==  9) return  0.0000000;
    if (idx == 10) return  3.1415927;
    return  3.1415927;
}

// ── Champions League star arrangement ──────────────────────
float starsPattern(vec3 n) {
    float t = u_time * 0.15;
    n.xz *= rot(t);
    n.xy *= rot(t * 0.6);

    float d = 1e9;

    for (int i = 0; i < 12; i++) {
        vec3 cDir = getStarCenter(i);

        // Build tangent frame at star centre
        vec3 upRef = abs(cDir.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
        vec3 tU = normalize(cross(upRef, cDir));
        vec3 tV = normalize(cross(cDir, tU));

        // Gnomonic projection
        float cosA = dot(n, cDir);
        if (cosA > 0.1) {
            vec2 lp = vec2(dot(n, tU), dot(n, tV)) / cosA;
            lp *= 2.6 / STAR_SIZE;
            lp *= rot(getStarRotation(i));
            float sd = sdStar5(lp, 1.0, 0.38);
            d = min(d, sd);
        }
    }

    return d;
}

// ── Star index labels ──────────────────────────────────────
float starLabels(vec3 n) {
    float t = u_time * 0.15;
    n.xz *= rot(t);
    n.xy *= rot(t * 0.6);

    float bestDot = -1.0;
    int bestIdx = 0;
    for (int i = 0; i < 12; i++) {
        vec3 cDir = getStarCenter(i);
        float d = dot(n, cDir);
        if (d > bestDot) { bestDot = d; bestIdx = i; }
    }

    vec3 cDir = getStarCenter(bestIdx);
    vec3 upRef = abs(cDir.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 tU = normalize(cross(upRef, cDir));
    vec3 tV = normalize(cross(cDir, tU));
    vec2 lp = vec2(dot(n, tU), dot(n, tV)) / bestDot;
    lp *= 2.6 / STAR_SIZE;

    return drawDots(float(bestIdx), lp, 0.035, 0.055);
}

// ── Background ─────────────────────────────────────────────
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 background(vec2 uv) {
    vec3 col = mix(vec3(0.01, 0.005, 0.04), vec3(0.03, 0.01, 0.08), uv.y * 0.5 + 0.5);
    float t = u_time * 0.25;
    for (int i = 0; i < 12; i++) {
        float fi = float(i);
        vec2 p = vec2(hash(vec2(fi, 1.0)) * 2.4 - 1.2, hash(vec2(fi, 2.0)) * 0.8 + 0.1);
        p.x += sin(t + fi * 1.3) * 0.06;
        float r = hash(vec2(fi, 3.0)) * 0.025 + 0.008;
        float b = smoothstep(r, 0.0, length(uv - p));
        col += mix(vec3(0.1, 0.15, 0.9), vec3(0.0, 0.5, 1.0), hash(vec2(fi, 4.0))) * b * 0.5;
    }
    return col;
}

// ── Neon colours ───────────────────────────────────────────
vec3 neonBlue = vec3(0.08, 0.40, 1.0);
vec3 neonCyan = vec3(0.05, 0.65, 1.0);

// ── Main ───────────────────────────────────────────────────
void main() {
    float s = min(u_resolution.x, u_resolution.y);
    vec2 uv = (2.0 * gl_FragCoord.xy - u_resolution) / s;

    // Camera
    vec3 ro = vec3(0.0, 0.0, -2.8);
    vec3 rd = normalize(vec3(uv, 1.6));

    float ballR = 0.85;
    vec3 col = background(uv);

    // Intersect sphere
    vec2 hit = iSphere(ro, rd, ballR);
    if (hit.x > 0.0) {
        vec3 p = ro + rd * hit.x;
        vec3 n = normalize(p);

        // Star pattern
        float d = starsPattern(n);

        // Inside star = negative d
        float insideStar = smoothstep(0.02, -0.02, d);

        // Star edge glow (neon outline)
        float edgeDist = abs(d);
        float edgeLine = smoothstep(0.06 * EDGE_WIDTH, 0.0, edgeDist);
        float edgeGlow = exp(-edgeDist * 6.0 / EDGE_WIDTH);

        // Lighting
        vec3 L = normalize(vec3(1.5, 2.0, -2.0));
        float diff = max(dot(n, L), 0.0);
        vec3 H = normalize(L - rd);
        float spec = pow(max(dot(n, H), 0.0), 80.0);
        float fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);

        // Base sphere: very dark blue
        vec3 baseCol = vec3(0.005, 0.012, 0.035);
        baseCol *= (0.15 + diff * 0.5);

        // Stars are filled with a slightly brighter shade
        vec3 starCol = vec3(0.01, 0.025, 0.06) * (0.2 + diff * 0.5);

        vec3 surfCol = mix(baseCol, starCol, insideStar);

        // Neon edge lines
        surfCol += neonBlue * edgeLine * 2.5;
        surfCol += neonCyan * edgeGlow * 0.8;

        // Specular
        surfCol += neonBlue * spec * 0.5;

        // Fresnel rim
        surfCol += neonBlue * fresnel * 0.5;

        // Sphere silhouette edge glow
        float rim = 1.0 - max(dot(n, -rd), 0.0);
        float silhouette = pow(rim, 6.0);
        surfCol += neonCyan * silhouette * 0.8;

        // Star index labels
        if (SHOW_LABELS) {
            float label = starLabels(n);
            surfCol = mix(surfCol, vec3(1.0), label);
        }

        // Pulse
        surfCol *= 1.0 + 0.05 * sin(u_time * 2.0);

        col = surfCol;

        // Ground reflection (simple fake)
        float groundY = -0.85;
        if (uv.y < -0.42) {
            float reflDist = abs(uv.y + 0.42);
            float reflStr = exp(-reflDist * 4.0) * 0.4;
            col = mix(col, col * 0.3 + neonBlue * 0.15, reflStr);
        }
    }

    // Ground glow beneath sphere
    float gd = length(vec2(uv.x, max(uv.y + 0.5, 0.0)));
    col += neonBlue * exp(-gd * 3.0) * 0.15;

    // Vignette
    vec2 vuv = gl_FragCoord.xy / u_resolution;
    float vig = 1.0 - 0.4 * length(vuv - 0.5);
    col *= vig;

    // Tone map
    col = col / (1.0 + col);
    col = pow(col, vec3(0.88));

    gl_FragColor = vec4(col, 1.0);
}
