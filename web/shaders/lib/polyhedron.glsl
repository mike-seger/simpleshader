// ── polyhedron.glsl ───────────────────────────────────────────────────────────
// Reusable regular-polyhedron SDF library (Platonic solids).
// No dependencies — pure math, no uniforms required.
//
// Usage:
//   float d = polyhedronSDF(p, N, size);   // N: 4,6,8,12,20
//   float e = polyhedronEdge(p, N, size);  // distance to nearest edge
//
// Rotation helpers:
//   mat3 rotAxis(vec3 axis, float angle)   // rotation matrix around axis
//
// All parameters are dynamic (no compile-time constants needed).

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

// ── Internal: face-plane SDF ─────────────────────────────────────────────────
// A regular polyhedron = intersection of half-spaces: max(dot(p, n_i)) - r.
// We use abs(p) symmetry where safe (cube, octahedron) and explicit normals
// for tetrahedron, dodecahedron and icosahedron to avoid symmetry-plane seams.

// ---- Tetrahedron (4 faces) ----
float tetrahedronSDF(vec3 p, float sz) {
    // 4 face normals of a regular tetrahedron, normalized
    float k = sz * 0.57735026919; // sz / sqrt(3)
    float d = dot(p, vec3( 1, 1, 1));
    d = max(d, dot(p, vec3( 1,-1,-1)));
    d = max(d, dot(p, vec3(-1, 1,-1)));
    d = max(d, dot(p, vec3(-1,-1, 1)));
    return d * 0.57735026919 - k;
}

float tetrahedronEdge(vec3 p, float sz) {
    float k = sz * 0.57735026919;
    float inv = 0.57735026919;
    float d0 = dot(p, vec3( 1, 1, 1)) * inv - k;
    float d1 = dot(p, vec3( 1,-1,-1)) * inv - k;
    float d2 = dot(p, vec3(-1, 1,-1)) * inv - k;
    float d3 = dot(p, vec3(-1,-1, 1)) * inv - k;
    float e = 1e10;
    e = min(e, max(d0, d1)); e = min(e, max(d0, d2)); e = min(e, max(d0, d3));
    e = min(e, max(d1, d2)); e = min(e, max(d1, d3)); e = min(e, max(d2, d3));
    return e;
}

// ---- Cube / Hexahedron (6 faces) ----
float cubeSDF(vec3 p, float sz) {
    vec3 d = abs(p) - vec3(sz);
    return min(max(d.x, max(d.y, d.z)), 0.0) + length(max(d, 0.0));
}

float cubeEdge(vec3 p, float sz) {
    vec3 q = abs(p) - vec3(sz);
    float e = 1e10;
    e = min(e, max(q.x, q.y));
    e = min(e, max(q.x, q.z));
    e = min(e, max(q.y, q.z));
    return e;
}

// ---- Octahedron (8 faces) ----
float octahedronSDF(vec3 p, float sz) {
    vec3 ap = abs(p);
    return (ap.x + ap.y + ap.z - sz) * 0.57735026919;
}

float octahedronEdge(vec3 p, float sz) {
    // 4 face groups via abs(dot) — each covers an antipodal pair.
    // Edge = where the two largest face distances are both near the inscribed radius.
    float inv = 0.57735026919;
    float r = sz * inv;
    float f0 = abs( p.x + p.y + p.z) * inv;
    float f1 = abs(-p.x + p.y + p.z) * inv;
    float f2 = abs( p.x - p.y + p.z) * inv;
    float f3 = abs( p.x + p.y - p.z) * inv;
    // Find second-largest face distance (branchless)
    float m1 = f0, m2 = -1e10;
    m2 = max(m2, min(m1, f1)); m1 = max(m1, f1);
    m2 = max(m2, min(m1, f2)); m1 = max(m1, f2);
    m2 = max(m2, min(m1, f3)); m1 = max(m1, f3);
    return m2 - r;
}

// ---- Dodecahedron (12 faces) ----
// Face normals are (0, ±φ, ±1), (±1, 0, ±φ), (±φ, ±1, 0) normalized,
// where φ = golden ratio. That's 12 normals (6 antipodal pairs).
// Using abs(p), dot(|p|, n) = max over all sign-flips of dot(p, n),
// so 3 normals cover all 12 faces.
// Normalized components: a = φ/√(φ²+1), b = 1/√(φ²+1).
// Inscribed radius for circumradius sz: r = sz * (a+b)/√3.
float dodecahedronSDF(vec3 p, float sz) {
    vec3 ap = abs(p);
    float a = 0.85065080835; // φ/√(φ²+1)
    float b = 0.52573111212; // 1/√(φ²+1)
    float r = sz * 0.7946544722; // sz * (a+b)/√3
    float d = dot(ap, vec3(0.0, a, b));
    d = max(d, dot(ap, vec3(b, 0.0, a)));
    d = max(d, dot(ap, vec3(a, b, 0.0)));
    return d - r;
}

float dodecahedronEdge(vec3 p, float sz) {
    // 6 face groups via abs(dot) — each covers an antipodal pair.
    // Adjacent faces like (0,a,b) and (0,a,-b) are in DIFFERENT groups,
    // so all edges are detectable.
    float a = 0.85065080835;
    float b = 0.52573111212;
    float r = sz * 0.7946544722;
    float f0 = abs(a * p.y + b * p.z);
    float f1 = abs(a * p.y - b * p.z);
    float f2 = abs(b * p.x + a * p.z);
    float f3 = abs(a * p.z - b * p.x);
    float f4 = abs(a * p.x + b * p.y);
    float f5 = abs(a * p.x - b * p.y);
    // Find second-largest face distance (branchless)
    float m1 = f0, m2 = -1e10;
    m2 = max(m2, min(m1, f1)); m1 = max(m1, f1);
    m2 = max(m2, min(m1, f2)); m1 = max(m1, f2);
    m2 = max(m2, min(m1, f3)); m1 = max(m1, f3);
    m2 = max(m2, min(m1, f4)); m1 = max(m1, f4);
    m2 = max(m2, min(m1, f5)); m1 = max(m1, f5);
    return m2 - r;
}

// ---- Icosahedron (20 faces) ----
// Face normals point toward the 20 face centers of a regular icosahedron.
// Two families:
//   Group A (8 faces): (±1,±1,±1)/√3  — 4 antipodal pairs
//   Group B (12 faces): (0, ±φ, ±1/φ)/√3 and cyclic — 6 antipodal pairs
// Using abs(p): 1 dot covers all 8 in group A, 3 dots cover all 12 in group B.
// All faces are equidistant from origin; inscribed radius = sz * (1+φ)/(√3·√(1+φ²)).
float icosahedronSDF(vec3 p, float sz) {
    vec3 ap = abs(p);
    // Group B normal components: c = φ/√3, d = 1/(φ√3)
    float c = 0.93417235896; // φ/√3
    float d = 0.35682208977; // 1/(φ√3)
    float r = sz * 0.7946544722; // inscribed radius ratio = (1+φ)/(√3·√(1+φ²))
    // Group A: (1,1,1)/√3
    float m = (ap.x + ap.y + ap.z) * 0.57735026919;
    // Group B: (0,c,d), (d,0,c), (c,d,0)
    m = max(m, dot(ap, vec3(0.0, c, d)));
    m = max(m, dot(ap, vec3(d, 0.0, c)));
    m = max(m, dot(ap, vec3(c, d, 0.0)));
    return m - r;
}

float icosahedronEdge(vec3 p, float sz) {
    // 10 face groups via abs(dot) — each covers an antipodal pair.
    // Group A: 4 groups from (±1,±1,±1)/√3
    // Group B: 6 groups from (0,±φ,±1/φ)/√3 and cyclic
    float inv = 0.57735026919;
    float c = 0.93417235896; // φ/√3
    float d = 0.35682208977; // 1/(φ√3)
    float r = sz * 0.7946544722;
    float a0 = abs( p.x + p.y + p.z) * inv;
    float a1 = abs(-p.x + p.y + p.z) * inv;
    float a2 = abs( p.x - p.y + p.z) * inv;
    float a3 = abs( p.x + p.y - p.z) * inv;
    float b0 = abs(c * p.y + d * p.z);
    float b1 = abs(c * p.y - d * p.z);
    float b2 = abs(d * p.x + c * p.z);
    float b3 = abs(c * p.z - d * p.x);
    float b4 = abs(c * p.x + d * p.y);
    float b5 = abs(c * p.x - d * p.y);
    // Find second-largest face distance (branchless)
    float m1 = a0, m2 = -1e10;
    m2 = max(m2, min(m1, a1)); m1 = max(m1, a1);
    m2 = max(m2, min(m1, a2)); m1 = max(m1, a2);
    m2 = max(m2, min(m1, a3)); m1 = max(m1, a3);
    m2 = max(m2, min(m1, b0)); m1 = max(m1, b0);
    m2 = max(m2, min(m1, b1)); m1 = max(m1, b1);
    m2 = max(m2, min(m1, b2)); m1 = max(m1, b2);
    m2 = max(m2, min(m1, b3)); m1 = max(m1, b3);
    m2 = max(m2, min(m1, b4)); m1 = max(m1, b4);
    m2 = max(m2, min(m1, b5)); m1 = max(m1, b5);
    return m2 - r;
}

// ── Public API ───────────────────────────────────────────────────────────────

// SDF for a regular polyhedron with N faces.
// Supported: N = 4 (tetrahedron), 6 (cube), 8 (octahedron),
//            12 (dodecahedron), 20 (icosahedron).
// Returns large positive value for unsupported N.
float polyhedronSDF(vec3 p, int N, float size) {
    if (N <= 4)  return tetrahedronSDF(p, size);
    if (N <= 6)  return cubeSDF(p, size);
    if (N <= 8)  return octahedronSDF(p, size);
    if (N <= 12) return dodecahedronSDF(p, size);
    return icosahedronSDF(p, size);
}

// Distance to the nearest edge of a regular polyhedron.
// Same N values as polyhedronSDF.
float polyhedronEdge(vec3 p, int N, float size) {
    if (N <= 4)  return tetrahedronEdge(p, size);
    if (N <= 6)  return cubeEdge(p, size);
    if (N <= 8)  return octahedronEdge(p, size);
    if (N <= 12) return dodecahedronEdge(p, size);
    return icosahedronEdge(p, size);
}
