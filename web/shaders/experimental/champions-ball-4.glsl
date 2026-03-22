precision highp float;

uniform vec2 u_resolution;
uniform float u_time;

#define PI  3.14159265
#define TAU 6.28318530

mat2 rot(float a) {
    float c = cos(a), s = sin(a);
    return mat2(c, -s, s, c);
}

// ── Five-pointed star SDF (exact) ──────────────────────────
float sdStar5(vec2 p, float r, float rf) {
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

// ── Golden ratio for dodecahedron geometry ─────────────────
const float phi = 1.618033988749895;

// 12 face centers of a dodecahedron (star centers)
vec3 getStarCenter(int idx) {
    // (±φ, ±1, 0) cyclically - these give the 12 face centers
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

// ── Champions League star arrangement with proper 12-star distribution ──
float starsPattern(vec3 n) {
    // Slow tumble - rotates the entire star pattern
    float t = u_time * 0.12;
    vec3 rotatedN = n;
    rotatedN.xz *= rot(t);
    rotatedN.xy *= rot(t * 0.7);
    
    float minDist = 1e9;
    
    // Loop through all 12 star centers
    for (int i = 0; i < 12; i++) {
        vec3 centerDir = getStarCenter(i);
        
        // Build tangent frame at star centre
        vec3 upRef = abs(centerDir.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
        vec3 tU = normalize(cross(upRef, centerDir));
        vec3 tV = normalize(cross(centerDir, tU));
        
        // Gnomonic projection - projects sphere point onto tangent plane
        float cosAngle = dot(rotatedN, centerDir);
        
        // Only consider points in front of the star center
        if (cosAngle > 0.15) {
            // Project onto tangent plane
            vec2 localPos = vec2(dot(rotatedN, tU), dot(rotatedN, tV)) / cosAngle;
            
            // Scale factor - controls star size (larger = bigger stars)
            // Stars should nearly touch each other at the edges
            float starScale = 2.2;
            localPos *= starScale;
            
            // Rotate stars slightly for visual interest
            float rotAngle = float(i) * PI / 6.0;
            localPos *= rot(rotAngle);
            
            // Calculate star SDF (negative inside star)
            float starDist = sdStar5(localPos, 1.0, 0.38);
            
            minDist = min(minDist, starDist);
        }
    }
    
    return minDist;
}

// ── Background stars ─────────────────────────────────────────────
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 background(vec2 uv) {
    vec3 col = mix(vec3(0.01, 0.005, 0.04), vec3(0.03, 0.01, 0.08), uv.y * 0.5 + 0.5);
    float t = u_time * 0.25;
    for (int i = 0; i < 24; i++) {
        float fi = float(i);
        vec2 p = vec2(hash(vec2(fi, 1.0)) * 2.4 - 1.2, hash(vec2(fi, 2.0)) * 0.8 + 0.1);
        p.x += sin(t + fi * 1.3) * 0.06;
        float r = hash(vec2(fi, 3.0)) * 0.02 + 0.006;
        float b = smoothstep(r, 0.0, length(uv - p));
        col += mix(vec3(0.1, 0.15, 0.9), vec3(0.0, 0.5, 1.0), hash(vec2(fi, 4.0))) * b * 0.4;
    }
    return col;
}

// ── Neon colours ───────────────────────────────────────────
vec3 neonBlue = vec3(0.08, 0.40, 1.0);
vec3 neonCyan = vec3(0.05, 0.65, 1.0);
vec3 starFill = vec3(0.12, 0.35, 0.85);  // Brighter star interior

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

        // Star pattern - returns SDF value (negative inside star)
        float d = starsPattern(n);

        // Inside star = negative d
        float insideStar = smoothstep(0.03, -0.03, d);
        
        // Star edge glow (neon outline) - wider for better visibility
        float edgeDist = abs(d);
        float edgeLine = smoothstep(0.09, 0.0, edgeDist);
        float edgeGlow = exp(-edgeDist * 5.0);

        // Lighting
        vec3 L = normalize(vec3(1.5, 2.0, -2.0));
        float diff = max(dot(n, L), 0.0);
        vec3 H = normalize(L - rd);
        float spec = pow(max(dot(n, H), 0.0), 80.0);
        float fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 2.5);

        // Base sphere: dark blue metallic
        vec3 baseCol = vec3(0.008, 0.015, 0.045);
        baseCol *= (0.2 + diff * 0.6);

        // Stars: brighter with subtle gradient
        vec3 starCol = starFill * (0.4 + diff * 0.7);
        
        // Add subtle blue gradient across star
        starCol += neonCyan * 0.2;

        vec3 surfCol = mix(baseCol, starCol, insideStar);

        // Neon edge lines (brighter for visibility)
        surfCol += neonBlue * edgeLine * 3.0;
        surfCol += neonCyan * edgeGlow * 1.2;

        // Add inner star glow for stars that are fully visible
        float innerGlow = (1.0 - insideStar) * (1.0 - smoothstep(0.0, 0.08, edgeDist));
        surfCol += neonCyan * innerGlow * 0.8;

        // Specular highlight
        surfCol += neonBlue * spec * 0.6;
        
        // Fresnel rim light
        surfCol += neonBlue * fresnel * 0.7;

        // Sphere silhouette edge glow
        float rim = 1.0 - max(dot(n, -rd), 0.0);
        float silhouette = pow(rim, 5.0);
        surfCol += neonCyan * silhouette * 0.6;

        // Subtle pulse animation
        surfCol *= 1.0 + 0.04 * sin(u_time * 2.2);

        col = surfCol;

        // Ground reflection (simple fake)
        float groundY = -0.85;
        if (uv.y < -0.42) {
            float reflDist = abs(uv.y + 0.42);
            float reflStr = exp(-reflDist * 4.0) * 0.35;
            col = mix(col, col * 0.4 + neonBlue * 0.2, reflStr);
        }
    }

    // Ground glow beneath sphere
    float gd = length(vec2(uv.x, max(uv.y + 0.55, 0.0)));
    col += neonBlue * exp(-gd * 3.0) * 0.12;

    // Vignette
    vec2 vuv = gl_FragCoord.xy / u_resolution;
    float vig = 1.0 - 0.35 * length(vuv - 0.5);
    col *= vig;

    // Tone map
    col = col / (1.0 + col);
    col = pow(col, vec3(0.9));

    gl_FragColor = vec4(col, 1.0);
}
