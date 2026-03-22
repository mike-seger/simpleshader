precision highp float;

uniform vec2 u_resolution;
uniform float u_time;

#define PI  3.14159265
#define TAU 6.28318530
#define PHI 1.61803399

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

// ── Sphere ray intersection ────────────────────────────────
vec2 iSphere(vec3 ro, vec3 rd, float r) {
    float b = dot(ro, rd);
    float c = dot(ro, ro) - r * r;
    float h = b * b - c;
    if (h < 0.0) return vec2(-1.0);
    h = sqrt(h);
    return vec2(-b - h, -b + h);
}

vec3 faceDir(int i) {
    float invLen = inversesqrt(1.0 + PHI * PHI);
    if (i == 0) return vec3(0.0, 1.0, PHI) * invLen;
    if (i == 1) return vec3(0.0, 1.0, -PHI) * invLen;
    if (i == 2) return vec3(0.0, -1.0, PHI) * invLen;
    if (i == 3) return vec3(0.0, -1.0, -PHI) * invLen;
    if (i == 4) return vec3(1.0, PHI, 0.0) * invLen;
    if (i == 5) return vec3(1.0, -PHI, 0.0) * invLen;
    if (i == 6) return vec3(-1.0, PHI, 0.0) * invLen;
    if (i == 7) return vec3(-1.0, -PHI, 0.0) * invLen;
    if (i == 8) return vec3(PHI, 0.0, 1.0) * invLen;
    if (i == 9) return vec3(PHI, 0.0, -1.0) * invLen;
    if (i == 10) return vec3(-PHI, 0.0, 1.0) * invLen;
    return vec3(-PHI, 0.0, -1.0) * invLen;
}

vec3 toFrontFrame(vec3 v) {
    vec3 front = normalize(vec3(0.0, 1.0, PHI));
    vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), front));
    vec3 up = cross(front, right);
    return vec3(dot(v, right), dot(v, up), dot(v, front));
}

float starFaceDistance(vec3 n, vec3 c) {
    vec3 upRef = vec3(0.0, 1.0, 0.0);
    if (abs(dot(c, upRef)) > 0.95) {
        upRef = vec3(1.0, 0.0, 0.0);
    }

    vec3 tangentU = normalize(cross(upRef, c));
    vec3 tangentV = cross(c, tangentU);

    float cosA = dot(n, c);
    vec2 local = vec2(dot(n, tangentU), dot(n, tangentV)) / max(cosA, 0.0001);

    // Exact-ish dodecahedral face circumradius in gnomonic coordinates.
    local /= 0.72654;

    // Rotate the star so its tips align with the regular face vertices.
    float orient = atan(tangentU.y, tangentU.x) + PI * 0.5;
    local *= rot(-orient);

    return sdStar5(local, 1.0, 0.381966);
}

float starsPattern(vec3 n) {
    n = toFrontFrame(n);

    float bestDot = -1.0;
    vec3 bestFace = vec3(0.0, 0.0, 1.0);
    for (int i = 0; i < 12; i++) {
        vec3 face = toFrontFrame(faceDir(i));
        float dp = dot(n, face);
        if (dp > bestDot) {
            bestDot = dp;
            bestFace = face;
        }
    }

    return starFaceDistance(n, bestFace);
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
        float edgeLine = smoothstep(0.06, 0.0, edgeDist);
        float edgeGlow = exp(-edgeDist * 6.0);

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
