precision highp float;

// Lipstick — Glossy Specular Reflections
// Raymarched 3×3 lipstick grid with mirror reflections

uniform vec2 u_resolution;
uniform float u_time;

// @lil-gui-start
const vec3 LIGHT_DIR = vec3(2.0, 4.0, -3.0);
const vec3 LIGHT_COLOR = vec3(1.0, 0.98, 0.95);
const float LIGHT_INTENSITY = 1.0;    // @range(0.0, 5.0, 0.05)
const float LIGHT_DIFFUSION = 0.6;    // @range(0.0, 2.0, 0.05)
const float CAMERA_SPEED = 0.3;       // @range(0.0, 2.0, 0.05)
const float ZOOM = 1.5;               // @range(0.5, 4.0, 0.05)
// @lil-gui-end

const float CYL_RADIUS = 0.4;
const float BASE_HEIGHT = 1.275;   // black glossy base (+50%)
const float COLLAR_HEIGHT = 0.45;  // gold metallic collar
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

// Hemisphere bottom cap (lower half of sphere at y=0)
float sdDomeBottom(vec3 p, float r) {
    return max(length(p) - r, p.y);
}

// Lipstick bullet: straight wax shaft + oblique-cut tip, with chamfered edge
// shaft = straight cylinder of height h, then oblique cut adds another h on top
float sdBullet(vec3 p, float r, float yBase) {
    float h = r * 1.35;           // height of the oblique cut portion
    float shaft = h;              // straight shaft below the cut (100% of cut height)
    vec3 q = p - vec3(0.0, yBase, 0.0);
    float chamfer = 0.12;

    // Infinite cylinder (radial distance only)
    float dRadial = length(q.xz) - r;

    // Oblique cutting plane, shifted up by shaft height
    // At x=-r: y = shaft, at x=+r: y = shaft + h
    float halfH = h * 0.5;
    float nx = -halfH / r;
    float ny = 1.0;
    float nLen = sqrt(nx * nx + ny * ny);
    float dOblique = (q.y - shaft - halfH - q.x * halfH / r) / nLen;

    // Bottom cap at y = 0
    float dBottom = -q.y;

    // Chamfered intersection of cylinder wall and oblique plane
    float a = dRadial + chamfer;
    float b = dOblique + chamfer;
    float d = length(max(vec2(a, b), 0.0)) - chamfer;

    return max(d, dBottom);
}

// Full lipstick: returns vec3(distance, materialID, cylinderID)
// Materials: 1=black base, 2=gold collar, 3=lipstick tip
vec3 sdFullLipstick(vec3 p, float r, float id) {
    float collarTop = BASE_HEIGHT + COLLAR_HEIGHT;

    // Black glossy base: dome bottom + cylinder
    float dome = sdDomeBottom(p, r);
    float baseCyl = sdCylSection(p, r, 0.0, BASE_HEIGHT);
    float base = min(dome, baseCyl);

    // Gold metallic collar
    float collar = sdCylSection(p, r * 0.95, BASE_HEIGHT, COLLAR_HEIGHT);

    // Lipstick bullet tip — slightly inset to keep clear gap from collar
    float tip = sdBullet(p, r * 0.85, collarTop + 0.02);

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
        baseCol = vec3(0.83, 0.65, 0.22);
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
    // Lipstick tip: offset along light direction to skip own oblique geometry
    vec3 sOrigin = mat > 2.5 ? p + lightDir * 1.5 : p + n * 0.01;
    float shadow = softShadow(sOrigin, lightDir, 0.1, 20.0, 12.0);

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
        vec3 rn = calcNormal(rp, rMat > 2.5 ? 0.002 : 0.0005);
        reflColor = shadeDirect(rp, reflDir, rn, reflHit.y);
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
        // Black plastic — Fresnel-driven gloss
        reflAmount = mix(0.04, 0.8, fres);
    } else {
        // Gold collar — strong metallic mirror
        reflAmount = mix(reflectivity * 0.5, 1.0, fres);
    }

    return mix(directColor, reflColor, reflAmount);
}

void main() {
    vec2 uv = (2.0 * gl_FragCoord.xy - u_resolution) / min(u_resolution.x, u_resolution.y);

    // Orbiting camera
    float angle = u_time * CAMERA_SPEED;
    float camDist = 8.0;
    float camHeight = 4.5;
    vec3 ro = vec3(camDist * cos(angle), camHeight, camDist * sin(angle));
    vec3 target = vec3(0.0, 0.6, 0.0);

    // Look-at camera matrix
    vec3 forward = normalize(target - ro);
    vec3 right = normalize(cross(forward, vec3(0.0, 1.0, 0.0)));
    vec3 up = cross(right, forward);

    vec3 rd = normalize(forward * ZOOM + right * uv.x + up * uv.y);

    // Raymarch primary ray
    vec2 hit = raymarch(ro, rd);

    vec3 col;
    if (hit.x > 0.0) {
        vec3 p = ro + rd * hit.x;
        float hitMat = floor(hit.y / 10.0);
        // Wax: larger epsilon smooths normals at the acute chamfer edge
        vec3 n = calcNormal(p, hitMat > 2.5 ? 0.002 : 0.0005);
        col = shade(p, rd, n, hit.y);
    } else {
        // Background sky gradient
        float skyT = 0.5 + 0.5 * rd.y;
        col = mix(vec3(0.12, 0.12, 0.15), vec3(0.3, 0.35, 0.45), skyT);
    }

    // Vignette
    vec2 q = gl_FragCoord.xy / u_resolution;
    float vig = 1.0 - 0.3 * dot((q - 0.5) * 1.5, (q - 0.5) * 1.5);
    col *= vig;

    // Gamma correction
    col = pow(col, vec3(1.0 / 2.2));

    gl_FragColor = vec4(col, 1.0);
}
