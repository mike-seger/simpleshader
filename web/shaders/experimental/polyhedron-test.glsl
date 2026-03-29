precision highp float;
uniform vec2 u_resolution;
uniform float u_time;

// @include ../lib/polyhedron.glsl

// @lil-gui-start
const float FACES = 6.0;             // @range(4, 20, 1)
const float SIZE = 1.11;               // @range(0.1, 2.0, 0.01)
const float TIME_OFFSET = 27.69;       // @range(-100, 100, 1)

const vec4  EDGE_COLOR = vec4(1.0, 0.0, 0.0, 0.95);
const float EDGE_WIDTH = 0.036;        // @range(0.001, 0.1, 0.001)
const float EDGE_GLOW = 9.7;          // @range(0.0, 20.0, 0.1)

const vec4  SURFACE_COLOR = vec4(0.1882, 0.5961, 0.9098, 0.0);
const float SURFACE_GLOW = 7.4;       // @range(0.0, 10.0, 0.1)
const vec4  BODY_COLOR = vec4(0.1, 0.15, 0.25, 0.55);

const vec3  AXIS1_DIR = vec3(0.0, 1.0, 0.3);
const float AXIS1_SPEED = 30.0;       // @range(-360, 360, 1)

const vec3  AXIS2_DIR = vec3(1.0, 0.0, 0.5);
const float AXIS2_SPEED = 20.0;       // @range(-360, 360, 1)

const bool  ORTHO = false;

const vec3  LIGHT_DIR = vec3(1.0, 1.5, 2.0);
const vec4  LIGHT_COLOR = vec4(0.4627, 0.5961, 0.8588, 1.0);
const float LIGHT_INTENSITY = 4.3;    // @range(0, 5, 0.05)
// @lil-gui-end

// Convert FACES float to nearest supported int (4,6,8,12,20)
int faceCountToN(float f) {
    if (f < 5.0)  return 4;
    if (f < 7.0)  return 6;
    if (f < 10.0) return 8;
    if (f < 16.0) return 12;
    return 20;
}

// Raymarching constants
const int   MAX_STEPS = 80;
const int   BACK_STEPS = 40;
const float MAX_DIST  = 20.0;
const float SURF_DIST = 0.001;

float sceneSDF(vec3 p, int N) {
    return polyhedronSDF(p, N, SIZE);
}

float sceneEdge(vec3 p, int N) {
    return polyhedronEdge(p, N, SIZE);
}

vec3 calcNormal(vec3 p, int N) {
    vec2 e = vec2(0.001, 0.0);
    return normalize(vec3(
        sceneSDF(p + e.xyy, N) - sceneSDF(p - e.xyy, N),
        sceneSDF(p + e.yxy, N) - sceneSDF(p - e.yxy, N),
        sceneSDF(p + e.yyx, N) - sceneSDF(p - e.yyx, N)
    ));
}

void main() {
    float s = min(u_resolution.x, u_resolution.y);
    vec2 uv = (2.0 * gl_FragCoord.xy - u_resolution) / s;

    int N = faceCountToN(FACES);

    // Build rotation from two axes
    float time = u_time + TIME_OFFSET;
    float a1 = AXIS1_SPEED * time * 0.01745329252; // deg → rad
    float a2 = AXIS2_SPEED * time * 0.01745329252;
    mat3 rot1 = rotAxis(AXIS1_DIR, a1);
    mat3 rot2 = rotAxis(AXIS2_DIR, a2);
    mat3 totalRot = rot2 * rot1;

    // Camera
    vec3 ro = ORTHO ? vec3(uv * 2.5, 5.0) : vec3(0.0, 0.0, 3.5);
    vec3 rd = ORTHO ? vec3(0.0, 0.0, -1.0) : normalize(vec3(uv, -1.5));

    // Raymarch
    float t = 0.0;
    float d = 0.0;
    for (int i = 0; i < MAX_STEPS; i++) {
        vec3 p = ro + rd * t;
        vec3 rp = totalRot * p; // rotate query point (equivalent to rotating the object)
        d = sceneSDF(rp, N);
        if (d < SURF_DIST || t > MAX_DIST) break;
        t += d;
    }

    vec3 col = vec3(0.02, 0.02, 0.04); // background

    if (t < MAX_DIST) {
        vec3 p = ro + rd * t;
        vec3 rp = totalRot * p;
        vec3 n = calcNormal(rp, N);
        // Un-rotate normal back to world space for lighting
        vec3 wn = vec3(
            dot(vec3(totalRot[0][0], totalRot[1][0], totalRot[2][0]), n),
            dot(vec3(totalRot[0][1], totalRot[1][1], totalRot[2][1]), n),
            dot(vec3(totalRot[0][2], totalRot[1][2], totalRot[2][2]), n)
        );

        // Directional light
        vec3 lightDir = normalize(LIGHT_DIR);
        float diff = max(dot(wn, lightDir), 0.0);
        float spec = pow(max(dot(reflect(-lightDir, wn), -rd), 0.0), 32.0);
        float amb = 0.15;

        // Surface color with lighting
        vec3 lit = LIGHT_COLOR.rgb * LIGHT_INTENSITY;
        vec3 surfCol = SURFACE_COLOR.rgb * (amb + diff * 0.7 * lit) + spec * 0.4 * lit;
        surfCol *= (1.0 + SURFACE_GLOW * 0.1);

        // Front edge detection
        float edgeDist = abs(sceneEdge(rp, N));
        float edgeMask = 1.0 - smoothstep(0.0, EDGE_WIDTH, edgeDist);
        float edgeGlow = exp(-edgeDist * EDGE_GLOW * 20.0);

        // March through to back surface for back-face edges
        float t2 = t + 0.02;
        for (int i = 0; i < BACK_STEPS; i++) {
            vec3 p2 = ro + rd * t2;
            vec3 rp2 = totalRot * p2;
            float d2 = sceneSDF(rp2, N);
            if (d2 > SURF_DIST) break;
            t2 += max(-d2, 0.005);
        }
        vec3 backRP = totalRot * (ro + rd * t2);
        float backEdgeDist = abs(sceneEdge(backRP, N));
        float backMask = 1.0 - smoothstep(0.0, EDGE_WIDTH, backEdgeDist);
        float backGlow = exp(-backEdgeDist * EDGE_GLOW * 20.0);

        // Composite back-to-front: background → back edges → body fill → front surface → front edges
        // Back edges
        vec3 backEdge = EDGE_COLOR.rgb * (backMask + backGlow * 0.4) * EDGE_COLOR.a;
        col = col * (1.0 - backMask * EDGE_COLOR.a) + backEdge;
        // Body fill
        col = mix(col, BODY_COLOR.rgb, BODY_COLOR.a);
        // Front surface
        col = mix(col, surfCol, SURFACE_COLOR.a);
        // Front edges
        vec3 frontEdge = EDGE_COLOR.rgb * (edgeMask + edgeGlow * 0.4) * EDGE_COLOR.a;
        col = col * (1.0 - edgeMask * EDGE_COLOR.a) + frontEdge;
    } else {
        // Glow around the object for near-misses
        float glowDist = d;
        float outerGlow = exp(-glowDist * 3.0) * 0.15;
        col += EDGE_COLOR.rgb * outerGlow;
    }

    // Tone mapping
    col = col / (col + vec3(1.0));
    col = pow(col, vec3(0.9));

    gl_FragColor = vec4(col, 1.0);
}
