// ── sdf-utils.glsl ───────────────────────────────────────────────────────────
// Generic SDF rendering utilities: structs, constants, and helpers.
// No dependencies — pure math, no uniforms required.
//
// Provides:
//   struct Material   — edge, surface, and body appearance
//   struct Light      — directional light
//   mat3 rotAxis()    — rotation matrix around an arbitrary axis
//   vec3 sdfNormal()  — normal estimation stub (shape-specific, see below)
//
// Raymarching constants: MAX_STEPS, BACK_STEPS, MAX_DIST, SURF_DIST

// ── Raymarching constants ────────────────────────────────────────────────────
const int   MAX_STEPS  = 80;
const int   BACK_STEPS = 40;
const float MAX_DIST   = 20.0;
const float SURF_DIST  = 0.001;

// ── Appearance structs ───────────────────────────────────────────────────────
struct Material {
    vec4  edgeColor;
    float edgeWidth;
    float edgeGlow;
    vec4  surfaceColor;
    float surfaceGlow;
    vec4  bodyColor;
};

struct Light {
    vec3  dir;
    vec3  color;
    float intensity;
};

// ── Rotation around an arbitrary axis ────────────────────────────────────────
mat3 rotAxis(vec3 axis, float angle) {
    vec3 a = normalize(axis);
    float s = sin(angle), c = cos(angle), oc = 1.0 - c;
    return mat3(
        oc * a.x * a.x + c,       oc * a.x * a.y - a.z * s, oc * a.x * a.z + a.y * s,
        oc * a.x * a.y + a.z * s, oc * a.y * a.y + c,       oc * a.y * a.z - a.x * s,
        oc * a.x * a.z - a.y * s, oc * a.y * a.z + a.x * s, oc * a.z * a.z + c
    );
}
