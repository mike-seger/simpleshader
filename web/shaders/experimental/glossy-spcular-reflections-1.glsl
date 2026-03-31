precision highp float;

// Lipstick — Glossy Specular Reflections
// Raymarched 3×3 lipstick grid with mirror reflections

uniform vec2 u_resolution;
uniform float u_time;

// @lil-gui-start
const vec3 LIGHT_DIR = vec3(-3.6, 3.0, -1.9);
const vec3 LIGHT_COLOR = vec3(1.0, 0.98, 0.95);
const float LIGHT_INTENSITY = 0.9;    // @range(0.0, 5.0, 0.05)
const float LIGHT_DIFFUSION = 1.5;    // @range(0.0, 2.0, 0.05)
const float CAMERA_SPEED = 0.3;       // @range(0.0, 2.0, 0.05)
const float CAMERA_ANGLE = 180.0;      // @range(-180.0, 180.0, 1.0) @label Start Angle (degrees)
const float ZOOM = 3.4;               // @range(0.5, 4.0, 0.05)
const float BASE_HEIGHT = 1.275;      // @range(0.3, 3.0, 0.025)
const float COLLAR_HEIGHT = 0.45;     // @range(0.1, 1.5, 0.025)
const float WAX_HEIGHT = 0.5;        // @range(0.5, 3.0, 0.025) @label Wax Height (×radius)
const float WAX_ANGLE = 55.5;         // @range(0.0, 75.0, 0.5) @label Cut Angle (degrees)
const float WAX_CHAMFER = 0.115;       // @range(0.0, 0.2, 0.005) @label Edge Chamfer
// @lil-gui-end

const float CYL_RADIUS = 0.4;
const float GRID_SPACING = 2.0;
const float GROUND_Y = 0.0;
const float MAX_DIST = 40.0;
const float SURF_DIST = 0.0005;
const float F0_CHROME = 0.9;
const float SPEC_POWER = 200.0;

float hash(float n) { return fract(sin(n) * 43758.5453123); }

// Capped cylinder SDF — along Y axis, between y=yBase and y=yBase+h
float sdCylSection(vec3 p, float r, float yBase, float h) {
    float dR = length(p.xz) - r;
    float midY = yBase + h * 0.5;
    float dV = abs(p.y - midY) - h * 0.5;
    return min(max(dR, dV), 0.0) + length(max(vec2(dR, dV), 0.0));
}

// Capped cylinder with rounded top edge (bevel radius = bev)
float sdCylSectionRoundTop(vec3 p, float r, float yBase, float h, float bev) {
    vec3 q = p - vec3(0.0, yBase, 0.0);
    float dR = length(q.xz) - r;
    float dBot = -q.y;
    float dTop = q.y - h;
    // Below bevel zone: standard box
    float dBody = max(dR, max(dBot, dTop));
    // Top-outer edge rounding
    float dR2 = length(q.xz) - (r - bev);
    float dTop2 = q.y - (h - bev);
    if (dR2 > 0.0 && dTop2 > 0.0) {
        dBody = max(dBot, length(vec2(dR2, dTop2)) - bev);
    }
    return dBody;
}

// Hemisphere bottom cap (lower half of sphere at y=0)
float sdDomeBottom(vec3 p, float r) {
    return max(length(p) - r, p.y);
}

// Lipstick bullet: straight wax shaft + oblique-cut tip
// Clean max-intersection SDF for artifact-free raymarching.
// Chamfer is applied visually via normal blending only (calcBulletNormal).
float sdBullet(vec3 p, float r, float yBase) {
    float shaft = r * WAX_HEIGHT;
    float slope = tan(radians(WAX_ANGLE));
    float rise = slope * r;
    vec3 q = p - vec3(0.0, yBase, 0.0);

    float dRadial = length(q.xz) - r;
    float halfRise = rise * 0.5;
    float nLen = sqrt(halfRise * halfRise / (r * r) + 1.0);
    float dOblique = (q.y - shaft - halfRise - q.x * halfRise / r) / nLen;
    float dBottom = -q.y;

    return max(max(dRadial, dOblique), dBottom);
}

// Analytical normal for the bullet — visual chamfer via smooth normal blend
vec3 calcBulletNormal(vec3 p, float cylId) {
    float idx = cylId - 1.0;
    float fi = floor(idx / 3.0) - 1.0;
    float fj = mod(idx, 3.0) - 1.0;
    vec3 center = vec3(fi * GRID_SPACING, 0.0, fj * GRID_SPACING);

    float r = CYL_RADIUS * 0.85;
    float yBase = BASE_HEIGHT + COLLAR_HEIGHT + 0.02;
    float shaft = r * WAX_HEIGHT;
    float slope = tan(radians(WAX_ANGLE));
    float rise = slope * r;
    float halfRise = rise * 0.5;

    vec3 q = p - center - vec3(0.0, yBase, 0.0);

    float dRadial = length(q.xz) - r;
    float nLen = sqrt(halfRise * halfRise / (r * r) + 1.0);
    float dOblique = (q.y - shaft - halfRise - q.x * halfRise / r) / nLen;
    float dBottom = -q.y;

    // Bottom cap
    if (dBottom > max(dRadial, dOblique) + 0.001) return vec3(0.0, -1.0, 0.0);

    vec3 cylN = normalize(vec3(q.x, 0.0, q.z));
    vec3 obliqueN = vec3(-halfRise / r, 1.0, 0.0) / nLen;

    // Visual chamfer: smoothstep blend between normals near the edge
    float c = WAX_CHAMFER + 0.001; // avoid div-by-zero when chamfer=0
    float blend = smoothstep(-c, c, dOblique - dRadial);
    return normalize(mix(cylN, obliqueN, blend));
}

// Full lipstick: returns vec3(distance, materialID, cylinderID)
// Materials: 1=black base, 2=gold collar, 3=lipstick tip
vec3 sdFullLipstick(vec3 p, float r, float id) {
    float collarR = r * 0.95;
    float tipR = r * 0.85;
    // Black tube wider so exposed wall = collar wall = r - tipR
    float baseR = collarR + (r - tipR);
    float bev = 0.04;  // top-edge bevel radius
    float collarTop = BASE_HEIGHT + COLLAR_HEIGHT;

    // Black glossy base: dome bottom + cylinder with rounded top edge
    float dome = sdDomeBottom(p, baseR);
    float baseCyl = sdCylSectionRoundTop(p, baseR, 0.0, BASE_HEIGHT, bev);
    float base = min(dome, baseCyl);

    // Gold metallic collar with rounded top edge
    float collar = sdCylSectionRoundTop(p, collarR, BASE_HEIGHT, COLLAR_HEIGHT, bev);

    // Lipstick bullet tip — slightly inset to keep clear gap from collar
    float tip = sdBullet(p, tipR, collarTop + 0.02);

    // Find closest part
    vec3 res = vec3(base, 1.0, id);  // black base
    if (collar < res.x) res = vec3(collar, 2.0, id);
    if (tip < res.x) res = vec3(tip, 3.0, id);
    return res;
}

// 9 lipstick colors — reds, pinks, berries, nudes, corals
vec3 lipstickColor(float id) {
    float idx = id - 1.0;
    vec3 col;
    if (idx < 0.5)      col = vec3(0.72, 0.07, 0.10); // classic red
    else if (idx < 1.5) col = vec3(0.85, 0.15, 0.25); // cherry red
    else if (idx < 2.5) col = vec3(0.75, 0.20, 0.35); // raspberry
    else if (idx < 3.5) col = vec3(0.55, 0.05, 0.20); // deep berry
    else if (idx < 4.5) col = vec3(0.90, 0.35, 0.30); // coral
    else if (idx < 5.5) col = vec3(0.85, 0.45, 0.50); // rose pink
    else if (idx < 6.5) col = vec3(0.70, 0.30, 0.28); // brick red
    else if (idx < 7.5) col = vec3(0.82, 0.52, 0.45); // nude peach
    else                col = vec3(0.60, 0.10, 0.30); // plum
    return col;
}

// Scene SDF. Returns vec2(distance, encodedID).
// encodedID = material * 10 + cylinderID
// Materials: 0=ground, 1=black base, 2=gold collar, 3=lipstick tip
vec2 mapScene(vec3 p) {
    float dGround = p.y - GROUND_Y;
    vec2 res = vec2(dGround, 0.0);

    for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 3; j++) {
            float fi = float(i) - 1.0;
            float fj = float(j) - 1.0;
            vec3 cp = p - vec3(fi * GRID_SPACING, 0.0, fj * GRID_SPACING);
            float id = float(i * 3 + j) + 1.0;
            vec3 ls = sdFullLipstick(cp, CYL_RADIUS, id);
            if (ls.x < res.x) {
                // Encode: material * 10 + cylinderID
                res = vec2(ls.x, ls.y * 10.0 + ls.z);
            }
        }
    }
    return res;
}

// Raymarch the scene. Returns vec2(distance, materialID).
vec2 raymarch(vec3 ro, vec3 rd) {
    float t = 0.0;
    vec2 res = vec2(-1.0, -1.0);
    for (int i = 0; i < 80; i++) {
        vec3 p = ro + rd * t;
        vec2 h = mapScene(p);
        if (h.x < SURF_DIST) {
            res = vec2(t, h.y);
            break;
        }
        t += h.x;
        if (t > MAX_DIST) break;
    }
    return res;
}

// Compute normal via central differences
vec3 calcNormal(vec3 p, float eps) {
    vec2 e = vec2(eps, 0.0);
    return normalize(vec3(
        mapScene(p + e.xyy).x - mapScene(p - e.xyy).x,
        mapScene(p + e.yxy).x - mapScene(p - e.yxy).x,
        mapScene(p + e.yyx).x - mapScene(p - e.yyx).x
    ));
}

// Soft shadow — march from point toward light
float softShadow(vec3 ro, vec3 rd, float tMin, float tMax, float k) {
    float res = 1.0;
    float t = tMin;
    for (int i = 0; i < 48; i++) {
        float h = mapScene(ro + rd * t).x;
        res = min(res, k * h / t);
        t += clamp(h, 0.02, 0.5);
        if (h < 0.001 || t > tMax) break;
    }
    return clamp(res, 0.0, 1.0);
}

// Schlick Fresnel
float fresnel(float cosTheta, float f0) {
    return f0 + (1.0 - f0) * pow(1.0 - cosTheta, 5.0);
}

// Shade a surface hit — direct lighting only (used for reflection bounces too)
vec3 shadeDirect(vec3 p, vec3 rd, vec3 n, float encodedId) {
    vec3 lightDir = normalize(LIGHT_DIR);

    // Decode material and cylinder ID
    float mat = floor(encodedId / 10.0);
    float cylId = encodedId - mat * 10.0;

    vec3 baseCol;
    float specMult;
    float specPow = SPEC_POWER;

    if (encodedId < 0.5) {
        // Ground
        baseCol = vec3(0.06);
        specMult = 0.3;
    } else if (mat < 1.5) {
        // Black glossy plastic base — dielectric, white specular
        baseCol = vec3(0.02);
        specMult = 1.5;
        specPow = 400.0;
    } else if (mat < 2.5) {
        // Gold metallic collar
        baseCol = vec3(0.85, 0.70, 0.25);
        specMult = 1.2;
        specPow = 250.0;
    } else {
        // Lipstick tip — glossy colored
        baseCol = lipstickColor(cylId);
        specMult = 0.7;
        specPow = 80.0;
    }

    // Wrap lighting for wax (subsurface-like); standard Lambertian for others
    float wrap = mat > 2.5 ? 0.35 : 0.0;
    float NdotL = max((dot(n, lightDir) + wrap) / (1.0 + wrap), 0.0);
    // Wax: skip shadow march (convex surface, self-shadow is always an artifact)
    float shadow = 1.0;
    if (mat < 2.5) {
        shadow = softShadow(p + n * 0.01, lightDir, 0.1, 20.0, 12.0);
    }

    vec3 viewDir = -rd;
    vec3 halfVec = normalize(lightDir + viewDir);
    float NdotH = max(dot(n, halfVec), 0.0);
    float spec = pow(NdotH, specPow) * specMult;

    vec3 lCol = LIGHT_COLOR * LIGHT_INTENSITY;
    vec3 ambient = baseCol * 0.08;
    vec3 diffuse = baseCol * lCol * NdotL * shadow * LIGHT_DIFFUSION;
    // Gold tints its specular; black plastic and lipstick get white highlights
    vec3 specTint = (mat > 1.5 && mat < 2.5) ? baseCol : vec3(1.0);
    vec3 specular = specTint * lCol * spec * shadow * 2.0;
    return ambient + diffuse + specular;
}

// Full shade with one-bounce mirror reflection
vec3 shade(vec3 p, vec3 rd, vec3 n, float encodedId) {
    vec3 directColor = shadeDirect(p, rd, n, encodedId);

    float mat = floor(encodedId / 10.0);

    // Lipstick wax: no mirror reflection (matte/satin finish, avoids self-intersection)
    if (mat > 2.5) return directColor;

    float reflectivity;
    if (encodedId < 0.5) reflectivity = 0.2;      // ground
    else if (mat < 1.5) reflectivity = 0.7;        // black plastic — strong but dielectric
    else reflectivity = 0.85;                       // gold collar — high mirror

    // One-bounce mirror reflection
    vec3 reflDir = reflect(rd, n);
    float bias = 0.02;
    vec2 reflHit = raymarch(p + n * bias, reflDir);
    vec3 reflColor;
    if (reflHit.x > 0.0) {
        vec3 rp = p + n * bias + reflDir * reflHit.x;
        float rMat = floor(reflHit.y / 10.0);
        float rCylId = reflHit.y - rMat * 10.0;
        vec3 rn = rMat > 2.5 ? calcBulletNormal(rp, rCylId) : calcNormal(rp, 0.001);
        reflColor = shadeDirect(rp, reflDir, rn, reflHit.y);
        // Fade grazing-angle hits to sky (they cause aliased dashed lines)
        float graze = abs(dot(rn, reflDir));
        float grazeFade = smoothstep(0.0, 0.08, graze);
        vec3 skyFall = mix(vec3(0.15, 0.15, 0.18), vec3(0.4, 0.45, 0.55), 0.5 + 0.5 * reflDir.y);
        reflColor = mix(skyFall, reflColor, grazeFade);
        // Distance fade — far reflections blur to sky (reduces aliased edges)
        float distFade = 1.0 - smoothstep(2.0, 8.0, reflHit.x);
        reflColor = mix(skyFall, reflColor, distFade);
    } else {
        float skyT = 0.5 + 0.5 * reflDir.y;
        reflColor = mix(vec3(0.15, 0.15, 0.18), vec3(0.4, 0.45, 0.55), skyT);
    }

    // Fresnel blend — dielectric F0 for plastic, metallic for gold
    float NdotV = max(dot(n, -rd), 0.0);
    float f0 = (mat < 1.5 && encodedId > 0.5) ? 0.04 : F0_CHROME;
    float fres = fresnel(NdotV, f0);
    float reflAmount;
    if (encodedId < 0.5) {
        reflAmount = reflectivity * fres * 0.3;
    } else if (mat < 1.5) {
        // Black plastic — subtle gloss (keeps sheen without aliased reflected edges)
        reflAmount = mix(0.02, 0.35, fres);
    } else {
        // Gold collar — strong metallic mirror
        reflAmount = mix(reflectivity * 0.5, 1.0, fres);
    }

    return mix(directColor, reflColor, reflAmount);
}

void main() {
    vec2 uv = (2.0 * gl_FragCoord.xy - u_resolution) / min(u_resolution.x, u_resolution.y);

    // Orbiting camera
    float angle = radians(CAMERA_ANGLE) + u_time * CAMERA_SPEED;
    float camDist = 8.0;
    float camHeight = 4.5;
    vec3 ro = vec3(camDist * cos(angle), camHeight, camDist * sin(angle));
    vec3 target = vec3(0.0, 0.6, 0.0);

    // Look-at camera matrix
    vec3 forward = normalize(target - ro);
    vec3 right = normalize(cross(forward, vec3(0.0, 1.0, 0.0)));
    vec3 up = cross(right, forward);

    // 2×2 supersampling for anti-aliasing
    vec3 total = vec3(0.0);
    for (int si = 0; si < 2; si++) {
        for (int sj = 0; sj < 2; sj++) {
            vec2 off = (vec2(float(si), float(sj)) - 0.5) * 0.5;
            vec2 suv = (2.0 * (gl_FragCoord.xy + off) - u_resolution) / min(u_resolution.x, u_resolution.y);
            vec3 rd = normalize(forward * ZOOM + right * suv.x + up * suv.y);

            vec2 hit = raymarch(ro, rd);

            vec3 col;
            if (hit.x > 0.0) {
                vec3 p = ro + rd * hit.x;
                float hitMat = floor(hit.y / 10.0);
                float hitCylId = hit.y - hitMat * 10.0;
                vec3 n = hitMat > 2.5 ? calcBulletNormal(p, hitCylId) : calcNormal(p, 0.0005);
                col = shade(p, rd, n, hit.y);
            } else {
                float skyT = 0.5 + 0.5 * rd.y;
                col = mix(vec3(0.12, 0.12, 0.15), vec3(0.3, 0.35, 0.45), skyT);
            }
            total += col;
        }
    }
    vec3 col = total * 0.25;

    // Vignette
    vec2 q = gl_FragCoord.xy / u_resolution;
    float vig = 1.0 - 0.3 * dot((q - 0.5) * 1.5, (q - 0.5) * 1.5);
    col *= vig;

    // Gamma correction
    col = pow(col, vec3(1.0 / 2.2));

    gl_FragColor = vec4(col, 1.0);
}
