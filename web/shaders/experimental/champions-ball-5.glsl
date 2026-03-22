precision highp float;

uniform vec2 u_resolution;
uniform float u_time;

#define PI  3.14159265

// ── Tweakable constants ────────────────────────────────────
const float STAR_SIZE           = 1.6;   // 1.0 = default, larger = bigger stars
const float STAR_TIP_ANGLE      = 0.38;  // inner valley fraction (0 = needle, 1 = pentagon)
const vec4  STAR_COLOR          = vec4(0.3059, 0.4588, 1.0, 0.95); // star color (rgb + opacity)
const float STAR_INTENSITY      = 5.0;                              // star fill brightness multiplier
const float STAR_EDGE_WIDTH     = 0.1;   // 1.0 = default, larger = thicker neon edges
const vec4  STAR_EDGE_COLOR     = vec4(0.5059, 0.8196, 1.0, 1.0); // edge color (rgb + opacity)
const float STAR_EDGE_INTENSITY = 1.0;                              // edge glow brightness multiplier
const vec4  SPHERE_COLOR        = vec4(0.005, 0.012, 0.035, 0.8); // sphere color (rgb + opacity)
const float SPHERE_INTENSITY    = 1.0;                              // sphere brightness multiplier
const float SPHERE_GLOSS        = 200.0;  // specular exponent (higher = sharper highlight)
const float SPHERE_REFLECT      = 0.1;   // specular reflectiveness (0 = none, 1 = mirror-like)
const float SPHERE_SIZE         = 1.3;   // sphere size factor (1.0 = default)
const float PROJ_SCALE          = 2.6 / STAR_SIZE; // gnomonic projection scale
const vec3  LIGHT_DIR           = vec3(1.5, 2.0, -2.0); // point light direction (world space)
const vec4  LIGHT_DIFFUSE       = vec4(1.0, 1.0, 1.0, 0.5); // diffuse light color + intensity

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
            lp *= PROJ_SCALE;
            lp *= rot(getStarRotation(i));
            float sd = sdStar5(lp, 1.0, STAR_TIP_ANGLE);
            d = min(d, sd);
        }
    }

    return d;
}

// ── Neon colours ───────────────────────────────────────────
vec3 edgeRGB = STAR_EDGE_COLOR.rgb;
float edgeI  = STAR_EDGE_INTENSITY;
vec3 lightDir = normalize(LIGHT_DIR);

// ── Shade one sphere hit point ─────────────────────────────
// Returns vec4(rgb, alpha) for compositing
vec4 shadeSphere(vec3 n, vec3 rd) {
    // Star pattern
    float d = starsPattern(n);
    float insideStar = smoothstep(0.02, -0.02, d);

    // Star edge glow (neon outline)
    float edgeDist = abs(d);
    float edgeLine = smoothstep(0.06 * STAR_EDGE_WIDTH, 0.0, edgeDist);
    float edgeGlow = exp(-edgeDist * 6.0 / STAR_EDGE_WIDTH);

    // Lighting
    vec3 L = lightDir;
    float diff = max(dot(n, L), 0.0);
    vec3 diffLight = LIGHT_DIFFUSE.rgb * LIGHT_DIFFUSE.a * diff;
    vec3 H = normalize(L - rd);
    float spec = pow(max(dot(n, H), 0.0), SPHERE_GLOSS) * SPHERE_REFLECT;
    float rimFactor = 1.0 - max(dot(n, -rd), 0.0);
    float fresnel = pow(rimFactor, 3.0);
    float silhouette = fresnel * fresnel;

    // Base sphere
    vec3 baseCol = SPHERE_COLOR.rgb * SPHERE_INTENSITY;
    baseCol *= (0.15 + diffLight);

    // Star fill with intensity for bright whites
    vec3 starCol = STAR_COLOR.rgb * STAR_INTENSITY * (0.3 + diff * 0.7);
    starCol += STAR_COLOR.rgb * spec * STAR_INTENSITY * 0.4;

    vec3 surfCol = mix(baseCol, starCol, insideStar);

    // Neon edge lines
    surfCol += edgeRGB * edgeLine * edgeI;
    surfCol += edgeRGB * edgeGlow * edgeI * 0.35;

    // Specular
    surfCol += edgeRGB * spec * 0.5;

    // Fresnel rim
    surfCol += edgeRGB * fresnel * 0.5;

    // Sphere silhouette edge glow
    surfCol += edgeRGB * silhouette * edgeI * 0.3;

    // Pulse
    surfCol *= 1.0 + 0.05 * sin(u_time * 2.0);

    // Alpha
    float surfAlpha = mix(SPHERE_COLOR.a, STAR_COLOR.a, insideStar);
    return vec4(surfCol, surfAlpha);
}

// ── Main ───────────────────────────────────────────────────
void main() {
    float s = min(u_resolution.x, u_resolution.y);
    vec2 uv = (2.0 * gl_FragCoord.xy - u_resolution) / s;

    // Camera
    vec3 ro = vec3(0.0, 0.0, -2.8);
    vec3 rd = normalize(vec3(uv, 1.6));

    float ballR = SPHERE_SIZE;
    vec3 col = mix(vec3(0.01, 0.005, 0.04), vec3(0.03, 0.01, 0.08), uv.y * 0.5 + 0.5);

    // Intersect sphere
    vec2 hit = iSphere(ro, rd, ballR);
    if (hit.x > 0.0) {
        // Back face first (far side, seen through transparent sphere)
        vec3 pBack = ro + rd * hit.y;
        vec3 nBack = normalize(pBack);
        vec4 back = shadeSphere(nBack, rd);
        col = mix(col, back.rgb, back.a);

        // Front face on top
        vec3 pFront = ro + rd * hit.x;
        vec3 nFront = normalize(pFront);
        vec4 front = shadeSphere(nFront, rd);
        col = mix(col, front.rgb, front.a);
    }

    gl_FragColor = vec4(col, 1.0);
}
