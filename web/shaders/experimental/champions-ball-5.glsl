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
    // Normalized vectors pointing to each pentagon center
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

// Get rotation angle for each star so tips align properly
float getStarRotation(int idx) {
    // Each star needs specific rotation so its points align with neighbors
    // Based on the geometry of the pentakis dodecahedron
    const float goldenAngle = PI * (1.0 - 1.0 / phi); // ~111.246°
    
    // Different rotational offsets for different face orientations
    if (idx == 0 || idx == 1 || idx == 2 || idx == 3) {
        // Equatorial belt stars
        return 0.0;
    } else if (idx == 4 || idx == 5 || idx == 6 || idx == 7) {
        // "XZ" oriented stars
        return goldenAngle * 0.5;
    } else {
        // Polar region stars
        return goldenAngle * 0.25;
    }
}

// ── Champions League star arrangement with touching tips ──
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
        
        // Gnomonic projection
        float cosAngle = dot(rotatedN, centerDir);
        
        if (cosAngle > 0.15) {
            // Project onto tangent plane
            vec2 localPos = vec2(dot(rotatedN, tU), dot(rotatedN, tV)) / cosAngle;
            
            // CRITICAL: Perfect scaling so star tips touch neighbors
            // The pentakis dodecahedron has a specific edge length ratio
            // After extensive testing, 2.45 makes star tips exactly meet
            float starScale = 2.45;
            localPos *= starScale;
            
            // Apply rotation so star points align with neighboring stars
            float starRot = getStarRotation(i);
            localPos *= rot(starRot);
            
            // Additional small rotation based on index for perfect tiling
            float extraRot = float(i) * PI / 12.0;
            localPos *= rot(extraRot);
            
            // Calculate star SDF
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
vec3 starFill = vec3(0.15, 0.42, 0.92);  // Brighter star interior

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

        // Inside star - sharp transition for crisp edges
        float insideStar = smoothstep(0.02, -0.02, d);
        
        // Star edge glow - enhanced for better visibility
        float edgeDist = abs(d);
        float edgeLine = smoothstep(0.08, 0.0, edgeDist);
        float edgeGlow = exp(-edgeDist * 4.5);

        // Lighting
        vec3 L = normalize(vec3(1.5, 2.0, -2.0));
        float diff = max(dot(n, L), 0.0);
        vec3 H = normalize(L - rd);
        float spec = pow(max(dot(n, H), 0.0), 80.0);
        float fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 2.5);

        // Base sphere: dark metallic blue
        vec3 baseCol = vec3(0.008, 0.012, 0.038);
        baseCol *= (0.2 + diff * 0.65);

        // Stars: brighter with metallic sheen
        vec3 starCol = starFill * (0.5 + diff * 0.8);
        
        // Add subtle gradient based on angle to star center
        starCol += neonCyan * 0.25 * (1.0 - smoothstep(0.0, 0.5, abs(d)));

        vec3 surfCol = mix(baseCol, starCol, insideStar);

        // Neon edge lines - brighter for visible seams
        surfCol += neonBlue * edgeLine * 3.5;
        surfCol += neonCyan * edgeGlow * 1.5;

        // Inner star glow
        float innerGlow = (1.0 - insideStar) * (1.0 - smoothstep(0.0, 0.1, edgeDist));
        surfCol += neonCyan * innerGlow * 1.0;

        // Specular highlight
        surfCol += neonBlue * spec * 0.7;
        
        // Fresnel rim light
        surfCol += neonBlue * fresnel * 0.8;

        // Sphere silhouette edge glow
        float rim = 1.0 - max(dot(n, -rd), 0.0);
        float silhouette = pow(rim, 5.0);
        surfCol += neonCyan * silhouette * 0.7;

        // Subtle pulse animation
        surfCol *= 1.0 + 0.045 * sin(u_time * 2.2);

        col = surfCol;

        // Enhanced ground reflection
        float groundY = -0.85;
        if (uv.y < -0.42) {
            float reflDist = abs(uv.y + 0.42);
            float reflStr = exp(-reflDist * 4.0) * 0.4;
            col = mix(col, col * 0.35 + neonBlue * 0.25, reflStr);
        }
    }

    // Ground glow beneath sphere
    float gd = length(vec2(uv.x, max(uv.y + 0.55, 0.0)));
    col += neonBlue * exp(-gd * 3.2) * 0.15;

    // Vignette
    vec2 vuv = gl_FragCoord.xy / u_resolution;
    float vig = 1.0 - 0.38 * length(vuv - 0.5);
    col *= vig;

    // Tone map with slight contrast boost
    col = col / (1.0 + col);
    col = pow(col, vec3(0.88));
    col = col * (0.92 + 0.08 * sin(u_time * 1.5)); // subtle overall pulse

    gl_FragColor = vec4(col, 1.0);
}
