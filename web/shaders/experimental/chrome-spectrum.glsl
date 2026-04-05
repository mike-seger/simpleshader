// Chrome Spectrum
//
// Audio-reactive chrome cylinder field. A mirrored grid of rounded metallic
// cylinders whose heights are driven by FFT frequency data, with optional
// ripple propagation through the rows. DDA grid traversal with per-cell
// analytic SDF marching; single-bounce chrome reflections.
//
// Inspired by Inigo Quilez' "Cubescape" (https://www.shadertoy.com/view/Msl3Rr).
// Huge thanks to iq and Shadertoy for the endless well of inspiration and
// techniques that made this possible.
//
// License: This shader may be freely used, modified, and redistributed for
// any purpose, including commercial use, without restriction or attribution
// requirement.

precision highp float;
uniform vec2  u_resolution;
uniform float u_time;

// @iChannel0 "../../media/audio/06 - 3 Body Problem.mp3" audio

// @lil-gui-start
const float SPECTRUM_COLS = 512.0; // @range(4, 512, 1)
const float RIPPLE_DECAY = 0.0;   // @range(0, 2, 0.05)
const float RIPPLE_SPEED = 4.5;   // @range(0, 10, 0.5)
// @lil-gui-end

float hash(float n) { return fract(sin(n) * 91.7328); }

// camera xz, set in main(), used by cellInfo() to lower cylinders near camera
vec2 g_camXZ;

// rounded cylinder SDF — inner radius 0.28, rounding 0.12 → visual radius 0.40
float sdf(vec3 p, float halfH) {
    vec2 d = vec2(length(p.xz) - 0.28, abs(p.y) - halfH);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)) - 0.12;
}

// cylinder height + metadata for grid cell
// returns vec3(height, id, intensity)
vec3 cellInfo(vec2 cell) {
    float id  = hash(cell.x + cell.y * 113.0);
    float row = abs(cell.y), ax = abs(cell.x);
    float hc  = SPECTRUM_COLS * 0.5;
    float f;
    if (ax < hc && row < hc) {
        float raw = texture2D(u_channel0, vec2((ax + 0.5) / hc, 0.25)).x;
        if (row < 0.5) {
            f = raw;
        } else {
            f = raw * exp(-RIPPLE_DECAY * row)
                    * (0.5 + 0.5 * sin(row * 1.5 - u_time * RIPPLE_SPEED));
        }
    } else {
        f = 0.15 + 0.2 * id;
    }
    f = clamp(f, 0.0, 1.0); f *= f;
    f = max(f, 0.05);
    // Lower cylinders near the camera to prevent clipping
    float camDist = distance(cell + 0.5, g_camXZ);
    f *= smoothstep(0.5, 3.0, camDist);
    return vec3(3.0 * f, id, f);
}

// SDF gradient → surface normal (tetrahedron method, 4 evaluations)
vec3 sdfNormal(vec3 p, float halfH) {
    vec2 e = vec2(0.001, -0.001);
    return normalize(
        e.xyy * sdf(p + e.xyy, halfH) +
        e.yyx * sdf(p + e.yyx, halfH) +
        e.yxy * sdf(p + e.yxy, halfH) +
        e.xxx * sdf(p + e.xxx, halfH));
}

float mx3(vec3 v) { return max(max(v.x, v.y), v.z); }

// DDA grid traversal + per-cell AABB → SDF march
// returns vec4(t, id, intensity, hitFlag)
vec4 traceGrid(vec3 ro, vec3 rd, float tmin, float tmax, out vec3 nor) {
    ro += tmin * rd;
    vec2  cell = floor(ro.xz);
    vec3  rdi  = 1.0 / rd;
    vec3  rda  = abs(rdi);
    vec2  rs   = sign(rd.xz);
    vec2  dist = (cell - ro.xz + 0.5 + rs * 0.5) * rdi.xz;

    for (int i = 0; i < 40; i++) {
        vec3 info = cellInfo(cell);
        float h = info.x;

        // early exit: cell entry beyond tmax
        vec2  pr = cell + 0.5 - ro.xz;
        float tCell = max((pr.x - 0.5 * rs.x) * rdi.x,
                          (pr.y - 0.5 * rs.y) * rdi.z);
        if (tmin + tCell > tmax) break;

        if (h > 0.01) {
            float hh = h * 0.5;
            vec3 ce = vec3(cell.x + 0.5, hh, cell.y + 0.5);
            vec3 rc = ro - ce;
            // AABB of rounded cylinder
            vec3 box = vec3(0.42, hh + 0.14, 0.42);
            float tN = mx3(-rdi * rc - rda * box);
            float tF = mx3(-rdi * rc + rda * box);

            if (tN < tF) {
                float s = max(tN, 0.0);
                for (int j = 0; j < 20; j++) {
                    float d = sdf(rc + s * rd, hh);
                    if (d < 0.002 * s) {
                        nor = sdfNormal(rc + s * rd, hh);
                        return vec4(tmin + s, info.y, info.z, 1.0);
                    }
                    s += d;
                    if (s > tF) break;
                }
            }
        }

        vec2 mm = step(dist.xy, dist.yx);
        dist += mm * rda.xz;
        cell += mm * rs;
    }
    return vec4(0.0, 0.0, 0.0, -1.0);
}

// y bounding planes — cylinders live in [0, ~3.2]
vec2 boundY(vec3 ro, vec3 rd) {
    vec2 tm = vec2(0.0, 45.0);
    float tp = (3.2 - ro.y) / rd.y;
    if (tp > 0.0) {
        if (ro.y > 3.2) tm.x = max(tm.x, tp);
        else            tm.y = min(tm.y, tp);
    }
    tp = -ro.y / rd.y;
    if (tp > 0.0 && ro.y > 0.0) tm.y = min(tm.y, tp);
    return tm;
}

const vec3 LIGHT_DIR = normalize(vec3(0.7, 0.8, -0.5));

vec3 shade(vec3 pos, vec3 nor, vec3 rd, vec3 baseCol) {
    float diff = clamp(dot(nor, LIGHT_DIR), 0.0, 1.0);
    float back = clamp(0.3 + 0.7 * dot(nor, vec3(-LIGHT_DIR.x, 0.0, -LIGHT_DIR.z)), 0.0, 1.0);
    float ao   = 0.3 + 0.7 * clamp(pos.y / 3.5, 0.0, 1.0);

    vec3 lin = vec3(1.0, 0.97, 0.92) * diff * 2.5
             + vec3(0.25, 0.27, 0.3) * back
             + vec3(0.06);
    lin *= ao;
    vec3 col = baseCol * lin;

    // Blinn-Phong specular
    vec3  hal  = normalize(LIGHT_DIR - rd);
    float spec = pow(clamp(dot(nor, hal), 0.0, 1.0), 200.0);
    float fres = 0.95 + 0.05 * pow(clamp(1.0 - dot(hal, LIGHT_DIR), 0.0, 1.0), 5.0);
    col += vec3(2.0) * spec * fres * diff * ao;

    return col;
}

vec3 render(vec3 ro, vec3 rd) {
    vec2 tm = boundY(ro, rd);

    vec3 nor;
    vec4 hit = traceGrid(ro, rd, tm.x, tm.y, nor);
    if (hit.w < 0.0) return vec3(0.0);

    float t  = hit.x;
    vec3 pos = ro + t * rd;

    // metal gray from cell id
    float gray = fract(hit.y * 5.17);
    gray = gray * gray * 0.9;
    vec3 col = shade(pos, nor, rd, vec3(gray));

    // chrome reflection (single bounce)
    vec3 ref = reflect(rd, nor);
    vec3 rNor;
    vec4 rHit = traceGrid(pos, ref, 0.05, 20.0, rNor);
    vec3 refCol;
    if (rHit.w > 0.0) {
        vec3 rp = pos + rHit.x * ref;
        float rg = fract(rHit.y * 5.17);
        rg = rg * rg * 0.9;
        refCol = shade(rp, rNor, ref, vec3(rg));
    } else {
        float sky = clamp(0.5 + 0.5 * ref.y, 0.0, 1.0);
        refCol = mix(vec3(0.04), vec3(0.4, 0.45, 0.5), sky * sky);
    }
    float fres = 0.95 + 0.05 * pow(clamp(1.0 + dot(rd, nor), 0.0, 1.0), 5.0);
    col = mix(col, refCol, fres);

    // tone map + distance fade
    col = 1.4 * col / (1.0 + col);
    col *= 1.0 - smoothstep(22.0, 45.0, t);

    return col;
}

void main() {
    float time = 3.0 + 0.15 * u_time;

    // figure-8 orbit tilted to sweep across the spectrum field
    float s8 = sin(0.27 * time), c8 = cos(0.27 * time);
    vec3 ro = vec3(7.0 * s8 * c8,
                   4.5 + 1.8 * sin(0.19 * time),
                   7.0 * c8);
    g_camXZ = ro.xz;
    vec3 ta = vec3(1.5 * sin(0.31 * time),
                   0.6,
                   1.5 * cos(0.23 * time + 1.0));
    float roll = 0.15 * sin(0.13 * time);

    vec3 cw = normalize(ta - ro);
    vec3 cu = normalize(cross(cw, vec3(sin(roll), cos(roll), 0.0)));
    vec3 cv = cross(cu, cw);

    vec3 tot = vec3(0.0);
    for (int j = 0; j < 2; j++)
        for (int i = 0; i < 2; i++) {
            vec2 off = vec2(float(i), float(j)) * 0.5;
            vec2 uv = (2.0 * (gl_FragCoord.xy + off) - u_resolution) / u_resolution.y;
            vec3 rd = normalize(cu * uv.x + cv * uv.y + cw * 1.6);
            vec3 col = render(ro, rd);
            col = pow(col, vec3(0.4545));
            tot += col;
        }
    tot *= 0.25;

    vec2 q = gl_FragCoord.xy / u_resolution;
    tot *= 0.25 + 0.75 * pow(16.0 * q.x * q.y * (1.0 - q.x) * (1.0 - q.y), 0.12);

    gl_FragColor = vec4(tot, 1.0);
}
