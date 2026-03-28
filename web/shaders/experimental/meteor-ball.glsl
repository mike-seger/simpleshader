precision highp float;

uniform vec2 u_resolution;
uniform float u_time;

#define PI  3.14159265

// ── Tweakable constants ────────────────────────────────────
// @lil-gui-start
// ── Ball ──
const float STAR_SIZE           = 1.6;   // @range(0.5, 4.0, 0.1)
const float STAR_INNER_RATIO    = 0.39;  // @range(0.1, 1.0, 0.01)
const vec4  STAR_COLOR          = vec4(0.8706, 0.8745, 0.9098, 0.95);
const float STAR_INTENSITY      = 1.5;   // @range(0.0, 5.0, 0.1)
const float STAR_EDGE_WIDTH     = 0.1;   // @range(0.01, 2.0, 0.01)
const vec4  STAR_EDGE_COLOR     = vec4(0.8392, 0.9216, 1.0, 1.0);
const vec4  STAR_EDGE_COLOR2    = vec4(0.2431, 0.6118, 0.8, 1.0);
const float STAR_EDGE_INTENSITY = 2.0;   // @range(0.0, 5.0, 0.1)
const vec4  SPHERE_COLOR        = vec4(0.1137, 0.1294, 0.6863, 0.95);
const float SPHERE_INTENSITY    = 1.0;   // @range(0.0, 3.0, 0.1)
const float SPHERE_GLOSS        = 500.0; // @range(1.0, 2000.0, 1.0)
const float SPHERE_REFLECT      = 0.0;   // @range(0.0, 1.0, 0.01)
const float SPHERE_SIZE         = 1.3;   // @range(0.5, 2.5, 0.05)
const vec3  LIGHT_DIR           = vec3(1.5, 2.0, -2.0);
const float SPIN_SPEED          = 4.5;   // @range(0.0, 20.0, 0.1)
const float SPIN_RATIO          = 0.61;  // @range(0.0, 2.0, 0.01)
const float SPIN_ANGLE1         = 83.0;  // @range(0.0, 360.0, 1.0)
const float SPIN_ANGLE2         = 150.0; // @range(0.0, 360.0, 1.0)
const float PULSE_FREQ          = 2.0;   // @range(0.0, 10.0, 0.1)
const float CLOUD_SPEED         = 0.3;   // @range(0.0, 2.0, 0.01)
const float CLOUD_DENSITY       = 0.2;   // @range(0.0, 1.0, 0.01)
const float CLOUD_FLOOR         = 0.1;   // @range(0.0, 1.0, 0.01)
const float CLOUD_Y_OFFSET      = 0.8;   // @range(-2.0, 2.0, 0.1)
const float CLOUD_BRIGHTNESS    = 2400.0; // @range(100.0, 10000.0, 100.0)
const vec3  CLOUD_TINT          = vec3(1.7725, 0.7216, 2.6353);
const float CLOUD_GLOW          = 0.4;   // @range(0.0, 2.0, 0.01)
// ── Meteors ──
const float ANIM_DURATION       = 7.0;   // seconds per cycle // @range(0.0, 10.0, 0.5)
const float HEAD_DIAMETER       = 0.1;   // head size // @range(0.05, 1.0, 0.01)
const vec4  HEAD_COLOR          = vec4(1.0, 1.0, 1.0, 1.0);
const float HEAD_POINTS         = 5.0;   // star points // @range(3.0, 15.0, 1.0)
const float HEAD_INNER_R        = 0.47;  // inner radius ratio // @range(0.0, 1.0, 0.01)
const float HEAD_GLOW           = 0.33;  // head glow brightness // @range(0.0, 4.0, 0.01)
const float HEAD_SPIN           = 0.2;   // star rotation speed // @range(0.0, 3.0, 0.01)
const float TAIL_LENGTH         = 1.65;  // tail length // @range(0.0, 4.5, 0.05)
const vec4  TAIL_START_COLOR    = vec4(0.1294, 0.3216, 0.7098, 1.0);
const vec4  TAIL_END_COLOR      = vec4(0.0118, 0.1451, 0.549, 0.0);
const float TAIL_WIDTH_HEAD     = 0.03;  // tail width at head // @range(0.01, 1.0, 0.005)
const float TAIL_WIDTH_END      = 0.378; // tail width at tip // @range(0.0, 0.6, 0.001)
const float GLOW_FREQ           = 0.11;  // glow pulsation frequency // @range(0.0, 60.0, 0.01)
const float GLOW_AMP            = 0.36;  // glow pulsation amplitude // @range(0.0, 1.0, 0.01)
const float GLOW_INTENSITY      = 1.6;   // meteor brightness // @range(0.3, 5.0, 0.1)
const float METEOR_COUNT        = 8.0;   // number of meteors // @range(1.0, 10.0, 1.0)
const float METEOR_CONCURRENCY  = 8.0;   // meteors visible at once // @range(1.0, 10.0, 1.0)
const float METEOR_VARIANCE     = 0.84;  // size/path randomness // @range(0.0, 5.0, 0.01)
// @lil-gui-end


// ── Shared utilities ───────────────────────────────────────
mat2 rot(float a) {
    float c = cos(a), s = sin(a);
    return mat2(c, -s, s, c);
}

// ── Ball: five-pointed star SDF ────────────────────────────
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

// ── Ball: sphere ray intersection ──────────────────────────
vec2 iSphere(vec3 ro, vec3 rd, float r) {
    float b = dot(ro, rd);
    float c = dot(ro, ro) - r * r;
    float h = b * b - c;
    if (h < 0.0) return vec2(-1.0);
    h = sqrt(h);
    return vec2(-b - h, -b + h);
}

// ── Ball: dodecahedron geometry ────────────────────────────
const float phi = 1.618033988749895;

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

float starsPattern(vec3 n) {
    float t = u_time * SPIN_SPEED * (PI / 180.0);
    n.xz *= rot(t + SPIN_ANGLE1 * (PI / 180.0));
    n.xy *= rot(t * SPIN_RATIO + SPIN_ANGLE2 * (PI / 180.0));

    float d = 1e9;

    for (int i = 0; i < 12; i++) {
        vec3 cDir = getStarCenter(i);

        float cosA = dot(n, cDir);
        if (cosA > 0.3) {
            vec3 upRef = abs(cDir.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
            vec3 tU = normalize(cross(upRef, cDir));
            vec3 tV = normalize(cross(cDir, tU));
            vec2 lp = vec2(dot(n, tU), dot(n, tV)) / cosA;
            lp *= 2.6 / STAR_SIZE;
            lp *= rot(getStarRotation(i));
            float sd = sdStar5(lp, 1.0, STAR_INNER_RATIO);
            d = min(d, sd);
            if (d < -0.05) break;
        }
    }

    return d;
}

// ── Ball: shading ──────────────────────────────────────────
vec3 lightDir = normalize(LIGHT_DIR);

vec4 shadeSphere(vec3 n, vec3 rd) {
    float colorBlend = smoothstep(-0.3, 0.8, dot(n, normalize(vec3(1.0, -0.5, 0.0))));
    vec3 edgeRGB = mix(STAR_EDGE_COLOR.rgb, STAR_EDGE_COLOR2.rgb, colorBlend);
    float edgeI = STAR_EDGE_INTENSITY;

    float d = starsPattern(n);
    float insideStar = smoothstep(0.02, -0.02, d);

    float edgeDist = abs(d);
    float edgeLine = smoothstep(0.06 * STAR_EDGE_WIDTH, 0.0, edgeDist);
    float edgeGlow = exp(-edgeDist * 6.0 / STAR_EDGE_WIDTH);

    vec3 L = lightDir;
    float diff = max(dot(n, L), 0.0);
    vec3 H = normalize(L - rd);
    float spec = pow(max(dot(n, H), 0.0), SPHERE_GLOSS) * SPHERE_REFLECT;
    float rimFactor = 1.0 - max(dot(n, -rd), 0.0);
    float fresnel = pow(rimFactor, 3.0);
    float silhouette = fresnel * fresnel;

    vec3 baseCol = SPHERE_COLOR.rgb * SPHERE_INTENSITY;
    baseCol *= (0.15 + diff * 0.5);

    vec3 starCol = STAR_COLOR.rgb * STAR_INTENSITY * (0.3 + diff * 0.7);
    starCol += STAR_COLOR.rgb * spec * STAR_INTENSITY * 0.4;

    vec3 surfCol = mix(baseCol, starCol, insideStar);

    surfCol += edgeRGB * edgeLine * edgeI;
    surfCol += edgeRGB * edgeGlow * edgeI * 0.35;
    surfCol += edgeRGB * spec * 0.5;
    surfCol += edgeRGB * fresnel * 0.5;
    surfCol += edgeRGB * silhouette * edgeI * 0.3;

    surfCol *= 1.0 + 0.05 * sin(u_time * PULSE_FREQ);

    float surfAlpha = mix(SPHERE_COLOR.a, STAR_COLOR.a, insideStar);
    return vec4(surfCol, surfAlpha);
}

// ── Meteor: N-pointed star sparkle ─────────────────────────
float sparkleStar(vec2 p, float size, float points, float innerR) {
    float r = length(p);
    float a = atan(p.y, p.x);
    float sector = PI / points;
    float sa = mod(a + sector, 2.0 * sector) - sector;
    float f = abs(sa) / sector;
    float starR = mix(size, size * innerR, f);
    float d = r / max(starR, 0.001);
    return 1.0 / (d * d + 0.5);
}

// ── Meteor: pseudo-random ──────────────────────────────────
float hash1(float n) {
    return fract(sin(n) * 43758.5453123);
}

// ── Meteor: parametric curve ───────────────────────────────
vec2 curveBase(float t, float aspect) {
    float ct = clamp(t, -0.5, 2.0);
    return vec2(ct * aspect, 0.5 * inversesqrt(max(ct + 0.3, 0.001)));
}

vec2 curvePoint(float t, float aspect, vec2 origin, float ca, float sa) {
    vec2 rel = curveBase(t, aspect) - origin;
    return origin + vec2(rel.x * ca - rel.y * sa, rel.x * sa + rel.y * ca);
}

float perspScale(float t) {
    float ct = clamp(t, -0.5, 2.0);
    return max((ct + 0.3) * 1.25, 0.01);
}

// ── Main ───────────────────────────────────────────────────
void main() {
    float s = min(u_resolution.x, u_resolution.y);
    vec2 uv = (2.0 * gl_FragCoord.xy - u_resolution) / s;

    float aspect = u_resolution.x / u_resolution.y;
    vec2 muv = gl_FragCoord.xy / u_resolution.y;  // height-normalized for meteors

    // ── Ball: ray setup ────────────────────────────────────
    vec3 ro = vec3(0.0, 0.0, -2.8);
    vec3 rd = normalize(vec3(uv, 1.6));
    float ballR = SPHERE_SIZE;
    vec2 hit = iSphere(ro, rd, ballR);
    bool hitsphere = hit.x > 0.0;

    // ── Analytical fog / atmosphere ───────────────────────────
    // Replaces ray march with a single evaluation — no loop
    float cloudTime = u_time * CLOUD_SPEED;

    // Fog density increases downward and toward the horizon
    float horizon = 1.0 - abs(rd.y);
    float fogDepth = horizon * horizon * horizon;
    float yBand = exp(-(rd.y + CLOUD_Y_OFFSET) * (rd.y + CLOUD_Y_OFFSET) * 2.0);

    // Animated wisps using ray direction as coordinate
    vec3 fogPos = rd * 3.0;
    float wisps = sin(fogPos.x * 2.0 + cloudTime) * 0.5
               + sin(fogPos.z * 3.0 - cloudTime * 0.7) * 0.3
               + sin((fogPos.x + fogPos.z) * 4.0 + cloudTime * 1.3) * 0.2;
    wisps = wisps * 0.5 + 0.5;  // normalize to 0..1

    float fogAmount = (CLOUD_DENSITY * 3.0 + CLOUD_FLOOR) * mix(fogDepth, yBand, 0.6) * wisps;

    // Color the fog
    vec3 fogCol = CLOUD_TINT / CLOUD_BRIGHTNESS * fogAmount * 800.0;

    // Sphere proximity glow bleeding into fog
    if (hitsphere) {
        float edgeDist = length(uv) - ballR * 0.55;
        float glow = exp(-edgeDist * edgeDist * 3.0) * CLOUD_GLOW;
        float lr = smoothstep(-0.3, 0.3, uv.x);
        vec3 glowCol = mix(STAR_EDGE_COLOR.rgb, STAR_EDGE_COLOR2.rgb, lr);
        fogCol += glowCol * glow * 0.3;
    }

    // ── Ball: composite ────────────────────────────────────
    vec3 col = fogCol;

    if (hitsphere) {
        vec3 nFront = normalize(ro + rd * hit.x);
        vec4 front = shadeSphere(nFront, rd);
        col = mix(col, front.rgb, front.a);
    }

    // ── Meteors (rendered in front of ball) ────────────────
    float glowPulse = 1.0 + GLOW_AMP * sin(u_time * GLOW_FREQ * PI * 2.0);
    vec2 cOrigin = curveBase(-0.15, aspect);

    for (int si = 0; si < 10; si++) {
        if (float(si) >= METEOR_COUNT) break;
        float fi = float(si);

        float vSize   = 1.0 + (hash1(fi * 7.13) - 0.5) * METEOR_VARIANCE;
        float vTail   = 1.0 + (hash1(fi * 11.37) - 0.5) * METEOR_VARIANCE;
        float vWidth  = 1.0 + (hash1(fi * 3.77) - 0.5) * METEOR_VARIANCE;
        float vTime   = hash1(fi * 5.91) * METEOR_VARIANCE;
        float vSpin   = 1.0 + (hash1(fi * 13.7) - 0.5) * METEOR_VARIANCE;

        float sTailLen = TAIL_LENGTH * vTail;
        float sHeadDia = HEAD_DIAMETER * vSize;

        float tailParamLen = sTailLen / sqrt(aspect * aspect + 0.25);
        float exitParam = 1.15 + tailParamLen;
        float entryParam = -0.15;
        float totalRange = exitParam - entryParam;
        float stagger = fi / max(METEOR_CONCURRENCY, 1.0);
        float rawCycle = u_time / ANIM_DURATION + stagger + vTime;
        float cycle = mod(rawCycle, 1.0);
        float iter = floor(rawCycle);
        float vAngle  = (hash1(fi * 9.23 + iter * 17.31) - 0.5) * METEOR_VARIANCE * 0.5;
        float cca = cos(vAngle), csa = sin(vAngle);
        float headParam = entryParam + cycle * totalRange;
        vec2 headPos = curvePoint(headParam, aspect, cOrigin, cca, csa);

        // Clamp tail to avoid curve asymptote (inversesqrt blows up near t=-0.3)
        float effTailParamLen = min(tailParamLen, max(headParam + 0.1, 0.0));

        float headPScale = perspScale(headParam);
        float headR = sHeadDia * 0.5 * headPScale;

        // Head glow (cheap, always rendered)
        float headDist = length(muv - headPos);
        if (headDist < headR * 6.0) {
            float halo = exp(-headDist * headDist / (headR * headR * 3.0));
            col += HEAD_COLOR.rgb * halo * 0.4 * HEAD_GLOW * glowPulse;
            float hg = exp(-headDist * headDist / (headR * headR * 0.25));
            col += HEAD_COLOR.rgb * hg * HEAD_GLOW * GLOW_INTENSITY * glowPulse;
        }

        // Trail (skip if no effective tail, or pixel outside bounding box)
        if (effTailParamLen >= 0.01) {
            vec2 tailEnd = curvePoint(headParam - effTailParamLen, aspect, cOrigin, cca, csa);
            float pad = max(TAIL_WIDTH_END, TAIL_WIDTH_HEAD) * vWidth * 2.0 + 0.15;
            vec2 bMin = min(headPos, tailEnd) - vec2(pad);
            vec2 bMax = max(headPos, tailEnd) + vec2(pad);

            if (muv.x >= bMin.x && muv.x <= bMax.x && muv.y >= bMin.y && muv.y <= bMax.y) {
                float minDist = 1e9;
                float closestFade = 0.0;
                vec2 prevPt = headPos;
                for (int i = 0; i < 4; i++) {
                    float f1 = float(i + 1) / 4.0;
                    vec2 nextPt = curvePoint(headParam - f1 * effTailParamLen, aspect, cOrigin, cca, csa);
                    vec2 seg = nextPt - prevPt;
                    float segLenSq = dot(seg, seg);
                    if (segLenSq > 0.0000000001) {
                        float proj = clamp(dot(muv - prevPt, seg) / segLenSq, 0.0, 1.0);
                        float d = length(muv - (prevPt + seg * proj));
                        if (d < minDist) {
                            minDist = d;
                            float f0 = float(i) / 4.0;
                            closestFade = 1.0 - mix(f0, f1, proj);
                        }
                    }
                    prevPt = nextPt;
                }

                float closestT = headParam - (1.0 - closestFade) * effTailParamLen;
                float pScale = perspScale(closestT);

                float sWidthHead = TAIL_WIDTH_HEAD * vWidth;
                float sWidthEnd  = TAIL_WIDTH_END * vWidth;
                float trailW = mix(sWidthEnd, sWidthHead, closestFade) * pScale;
                float gd = minDist / max(trailW, 0.001);
                float trailGlow = exp(-gd * gd * 3.0) * closestFade;
                vec3 trailTint = mix(TAIL_END_COLOR.rgb, TAIL_START_COLOR.rgb, closestFade);
                float trailAlpha = mix(TAIL_END_COLOR.a, TAIL_START_COLOR.a, closestFade);
                col += trailTint * trailGlow * GLOW_INTENSITY * glowPulse * 0.5 * trailAlpha;

                // Sparkle star
                vec2 hp = muv - headPos;
                float spinAngle = u_time * HEAD_SPIN * vSpin * PI * 2.0;
                float cs = cos(spinAngle), sn = sin(spinAngle);
                vec2 rhp = vec2(hp.x * cs + hp.y * sn, -hp.x * sn + hp.y * cs);
                float headSpark = sparkleStar(rhp, headR * 0.6, HEAD_POINTS, HEAD_INNER_R);
                col += vec3(1.0) * headSpark * 0.12 * GLOW_INTENSITY;
            }
        }
    }

    // ── Tone mapping ──────────────────────────────────────
    col = col / (1.0 + col * 0.5);

    gl_FragColor = vec4(col, 1.0);
}
