// ── polyhedron.glsl ───────────────────────────────────────────────────────────
// Reusable regular-polyhedron SDF library (Platonic solids).
//
// Usage:
//   float d = polyhedronSDF(p, N, size);   // N: 4,6,8,12,20
//   float e = polyhedronEdge(p, N, size);  // distance to nearest edge
//   float t = renderPolyhedron(ro, rd, rot, N, sz, mat, light, col);
//
// `size` is always the circumradius (center-to-vertex distance) for all shapes.
// Structs Material, Light, and rotAxis() come from sdf-utils.glsl.
//
// All parameters are dynamic (no compile-time constants needed).

// @include sdf-utils.glsl

// ── Internal: face-plane SDF ─────────────────────────────────────────────────
// A regular polyhedron = intersection of half-spaces: max(dot(p, n_i)) - r.
// We use abs(p) symmetry where safe (cube, octahedron) and explicit normals
// for tetrahedron, dodecahedron and icosahedron to avoid symmetry-plane seams.

// ---- Tetrahedron (4 faces) ----
float tetrahedronSDF(vec3 p, float sz) {
    // 4 face normals of a regular tetrahedron, normalized.
    // sz = circumradius; inscribed radius = sz/3 (R/r = 3 for tetrahedron).
    float k = sz / 3.0;
    float d = dot(p, vec3( 1, 1, 1));
    d = max(d, dot(p, vec3( 1,-1,-1)));
    d = max(d, dot(p, vec3(-1, 1,-1)));
    d = max(d, dot(p, vec3(-1,-1, 1)));
    return d * 0.57735026919 - k;
}

float tetrahedronEdge(vec3 p, float sz) {
    float inv = 0.57735026919;
    float k = sz / 3.0;
    float f0 = dot(p, vec3( 1, 1, 1)) * inv;
    float f1 = dot(p, vec3( 1,-1,-1)) * inv;
    float f2 = dot(p, vec3(-1, 1,-1)) * inv;
    float f3 = dot(p, vec3(-1,-1, 1)) * inv;
    // Second-largest face distance (branchless)
    float m1 = f0, m2 = -1e10;
    m2 = max(m2, min(m1, f1)); m1 = max(m1, f1);
    m2 = max(m2, min(m1, f2)); m1 = max(m1, f2);
    m2 = max(m2, min(m1, f3)); m1 = max(m1, f3);
    return m2 - k;
}

// ---- Cube / Hexahedron (6 faces) ----
// sz = circumradius; half-side = sz/√3 (R/r = √3 for cube).
float cubeSDF(vec3 p, float sz) {
    float h = sz * 0.57735026919;
    vec3 d = abs(p) - vec3(h);
    return min(max(d.x, max(d.y, d.z)), 0.0) + length(max(d, 0.0));
}

float cubeEdge(vec3 p, float sz) {
    float h = sz * 0.57735026919;
    vec3 q = abs(p) - vec3(h);
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

// ── Render one polyhedron ────────────────────────────────────────────────────
// Raymarches, lights, detects edges (front + back), and composites onto `col`.
// Returns hit distance (MAX_DIST on miss).
//   ro, rd   — ray origin and direction (world space)
//   rot      — rotation matrix applied to query points
//   N        — face count (4,6,8,12,20)
//   sz       — circumradius
//   m        — Material (edges, surface, body)
//   light    — Light (direction, color, intensity)
//   col      — accumulated color (inout)
float renderPolyhedron(
    vec3 ro, vec3 rd,
    mat3 rot, int N, float sz,
    Material m, Light light,
    inout vec3 col
) {
    // Raymarch
    float t = 0.0;
    float d = 0.0;
    for (int i = 0; i < MAX_STEPS; i++) {
        vec3 rp = rot * (ro + rd * t);
        d = polyhedronSDF(rp, N, sz);
        if (d < SURF_DIST || t > MAX_DIST) break;
        t += d;
    }

    if (t >= MAX_DIST) {
        col += m.edgeColor.rgb * exp(-d * 3.0) * 0.15;
        return MAX_DIST;
    }

    vec3 rp = rot * (ro + rd * t);

    // Normal via central differences
    vec2 e = vec2(0.001, 0.0);
    vec3 n = normalize(vec3(
        polyhedronSDF(rp + e.xyy, N, sz) - polyhedronSDF(rp - e.xyy, N, sz),
        polyhedronSDF(rp + e.yxy, N, sz) - polyhedronSDF(rp - e.yxy, N, sz),
        polyhedronSDF(rp + e.yyx, N, sz) - polyhedronSDF(rp - e.yyx, N, sz)
    ));
    // Un-rotate normal to world space (transpose = inverse for orthogonal mat)
    vec3 wn = vec3(
        dot(vec3(rot[0][0], rot[1][0], rot[2][0]), n),
        dot(vec3(rot[0][1], rot[1][1], rot[2][1]), n),
        dot(vec3(rot[0][2], rot[1][2], rot[2][2]), n)
    );

    // Lighting
    float diff = max(dot(wn, light.dir), 0.0);
    float spec = pow(max(dot(reflect(-light.dir, wn), -rd), 0.0), 32.0);
    vec3 lit = light.color * light.intensity;
    vec3 surfCol = m.surfaceColor.rgb * (0.15 + diff * 0.7 * lit) + spec * 0.4 * lit;
    surfCol *= 1.0 + m.surfaceGlow * 0.1;

    // Front edge detection (fwidth for screen-space AA)
    float edgeDist = abs(polyhedronEdge(rp, N, sz));
    float fw = fwidth(edgeDist);
    float edgeMask = 1.0 - smoothstep(m.edgeWidth - fw, m.edgeWidth + fw, edgeDist);
    float edgeGlow = exp(-edgeDist * m.edgeGlow * 20.0);

    // March through to back surface for back-face edges
    float t2 = t + 0.02;
    for (int i = 0; i < BACK_STEPS; i++) {
        vec3 rp2 = rot * (ro + rd * t2);
        float d2 = polyhedronSDF(rp2, N, sz);
        if (d2 > SURF_DIST) break;
        t2 += max(-d2, 0.005);
    }
    vec3 backRP = rot * (ro + rd * t2);
    float backEdgeDist = abs(polyhedronEdge(backRP, N, sz));
    float bfw = fwidth(backEdgeDist);
    float backMask = 1.0 - smoothstep(m.edgeWidth - bfw, m.edgeWidth + bfw, backEdgeDist);
    float backGlow = exp(-backEdgeDist * m.edgeGlow * 20.0);

    // Composite back-to-front: background → back edges → body → surface → front edges
    vec3 backEdge = m.edgeColor.rgb * (backMask + backGlow * 0.4) * m.edgeColor.a;
    col = col * (1.0 - backMask * m.edgeColor.a) + backEdge;
    col = mix(col, m.bodyColor.rgb, m.bodyColor.a);
    col = mix(col, surfCol, m.surfaceColor.a);
    vec3 frontEdge = m.edgeColor.rgb * (edgeMask + edgeGlow * 0.4) * m.edgeColor.a;
    col = col * (1.0 - edgeMask * m.edgeColor.a) + frontEdge;

    return t;
}
