precision highp float;

uniform vec2  u_resolution;
uniform float u_time;

#define PI 3.14159265

// @lil-gui-start
const float ANIM_DURATION    = 7.0;    // seconds per cycle // @range(0.0, 10.0, 0.5)
const float HEAD_DIAMETER    = 0.1;   // head size (fraction of height) // @range(0.05, 1.0, 0.01)
const float HEAD_POINTS      = 5.0;    // number of star points // @range(3.0, 15.0, 1.0)
const float HEAD_INNER_R     = 0.47;    // inner radius ratio // @range(0.0, 1.0, 0.01)
const float HEAD_GLOW        = 0.33;    // head glow brightness // @range(0.0, 4.0, 0.01)
const float HEAD_SPIN        = 0.2;    // star rotation speed // @range(0.0, 3.0, 0.01)
const float TAIL_LENGTH      = 1.65;   // tail length (fraction of height) // @range(0.0, 4.5, 0.05)
const float TAIL_WIDTH_HEAD  = 0.03;  // tail width at the head end // @range(0.01, 1.0, 0.005)
const float TAIL_WIDTH_END   = 0.378;   // tail width at the tail tip // @range(0.0, 0.6, 0.001)
const float GLOW_FREQ        = 0.11;    // glow pulsation frequency // @range(0.0, 1.0, 0.01)
const float GLOW_AMP         = 0.36;    // glow pulsation amplitude // @range(0.0, 1.0, 0.01)
const float GLOW_INTENSITY   = 1.6;    // overall brightness // @range(0.3, 5.0, 0.1)
const vec4  HEAD_COLOR       = vec4(0.6588, 0.8, 1.0, 1.0);  // head glow color
const vec4  TAIL_START_COLOR = vec4(0.1294, 0.3216, 0.7098, 1.0);   // tail color near head
const vec4  TAIL_END_COLOR   = vec4(0.0118, 0.1451, 0.549, 0.0);  // tail color at tip
const float STAR_COUNT       = 8.0;    // number of stars // @range(1.0, 10.0, 1.0)
const float STAR_CONCURRENCY = 8.0;    // stars visible at once // @range(1.0, 10.0, 1.0)
const float STAR_VARIANCE    = 0.84;    // size/path randomness // @range(0.0, 1.0, 0.01)
// @lil-gui-end

// ── N-pointed star sparkle shape ──────────────────────────
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

// ── Pseudo-random ─────────────────────────────────────────
float hash1(float n) {
    return fract(sin(n) * 43758.5453123);
}

// ── Curve with precomputed rotation ─────────────────
vec2 curveBase(float t, float aspect) {
    float ct = clamp(t, -0.5, 2.0);
    return vec2(ct * aspect, 0.5 * inversesqrt(max(ct + 0.3, 0.001)));
}

vec2 curvePoint(float t, float aspect, vec2 origin, float ca, float sa) {
    vec2 rel = curveBase(t, aspect) - origin;
    return origin + vec2(rel.x * ca - rel.y * sa, rel.x * sa + rel.y * ca);
}

// Z-depth follows same curve; perspective scale normalized to 1.0 at t=0.5
float perspScale(float t) {
    float ct = clamp(t, -0.5, 2.0);
    return (ct + 0.3) * 1.25;  // linear approx, 1.0 at t=0.5
}

void main() {
    float aspect = u_resolution.x / u_resolution.y;
    vec2 uv = gl_FragCoord.xy / u_resolution.y;  // height-normalized

    vec3 col = vec3(0.01, 0.01, 0.04);  // dark background

    // Glow pulsation (shared)
    float glowPulse = 1.0 + GLOW_AMP * sin(u_time * GLOW_FREQ * PI * 2.0);

    // Shared curve origin (entry point at t=-0.15)
    vec2 cOrigin = curveBase(-0.15, aspect);

    // ── Per-star loop ─────────────────────────────────────
    for (int si = 0; si < 10; si++) {
        if (float(si) >= STAR_COUNT) break;
        float fi = float(si);

        // Per-star variance: size, tail, timing, angle spread
        float vSize   = 1.0 + (hash1(fi * 7.13) - 0.5) * STAR_VARIANCE;
        float vTail   = 1.0 + (hash1(fi * 11.37) - 0.5) * STAR_VARIANCE;
        float vWidth  = 1.0 + (hash1(fi * 3.77) - 0.5) * STAR_VARIANCE;
        float vTime   = hash1(fi * 5.91) * STAR_VARIANCE;
        float vAngle  = (hash1(fi * 9.23) - 0.5) * STAR_VARIANCE * 0.5;
        float vSpin   = 1.0 + (hash1(fi * 13.7) - 0.5) * STAR_VARIANCE;

        // Precompute rotation for this star
        float cca = cos(vAngle), csa = sin(vAngle);

        float sTailLen = TAIL_LENGTH * vTail;
        float sHeadDia = HEAD_DIAMETER * vSize;

        // ── Animation ─────────────────────────────────────
        float tailParamLen = sTailLen / sqrt(aspect * aspect + 0.25);
        float exitParam = 1.15 + tailParamLen;
        float entryParam = -0.15;
        float totalRange = exitParam - entryParam;
        // Stagger stars evenly: STAR_CONCURRENCY controls overlap
        float stagger = fi / max(STAR_CONCURRENCY, 1.0);
        float cycle = mod(u_time / ANIM_DURATION + stagger + vTime, 1.0);
        float headParam = entryParam + cycle * totalRange;
        vec2 headPos = curvePoint(headParam, aspect, cOrigin, cca, csa);

        // Early skip: if head is far from pixel, skip trail computation
        float headDist = length(uv - headPos);
        float maxReach = max(sTailLen, TAIL_WIDTH_HEAD * vWidth) * 1.5;
        if (headDist > maxReach) {
            // Still render head glow if close enough
            float headPScale = perspScale(headParam);
            float headR = sHeadDia * 0.5 * headPScale;
            if (headDist < headR * 6.0) {
                float halo = exp(-headDist * headDist / (headR * headR * 3.0));
                col += HEAD_COLOR.rgb * halo * 0.4 * HEAD_GLOW * glowPulse;
                float hg = exp(-headDist * headDist / (headR * headR * 0.25));
                col += HEAD_COLOR.rgb * hg * HEAD_GLOW * GLOW_INTENSITY * glowPulse;
            }
            continue;
        }

        // ── Trail glow: closest distance to curve segments
        float minDist = 1e9;
        float closestFade = 0.0;
        vec2 prevPt = curvePoint(headParam, aspect, cOrigin, cca, csa);
        for (int i = 0; i < 20; i++) {
            float f1 = float(i + 1) / 20.0;
            vec2 nextPt = curvePoint(headParam - f1 * tailParamLen, aspect, cOrigin, cca, csa);
            vec2 seg = nextPt - prevPt;
            float proj = clamp(dot(uv - prevPt, seg) / dot(seg, seg), 0.0, 1.0);
            float d = length(uv - (prevPt + seg * proj));
            if (d < minDist) {
                minDist = d;
                float f0 = float(i) / 20.0;
                closestFade = 1.0 - mix(f0, f1, proj);
            }
            prevPt = nextPt;
        }

        // Perspective scale at closest trail point
        float closestT = headParam - (1.0 - closestFade) * tailParamLen;
        float pScale = perspScale(closestT);

        // Trail glow (narrows from head to tail end)
        float sWidthHead = TAIL_WIDTH_HEAD * vWidth;
        float sWidthEnd  = TAIL_WIDTH_END * vWidth;
        float trailW = mix(sWidthEnd, sWidthHead, closestFade) * pScale;
        float gd = minDist / max(trailW, 0.001);
        float trailGlow = exp(-gd * gd * 3.0) * closestFade;
        vec3 trailTint = mix(TAIL_END_COLOR.rgb, TAIL_START_COLOR.rgb, closestFade);
        float trailAlpha = mix(TAIL_END_COLOR.a, TAIL_START_COLOR.a, closestFade);
        col += trailTint * trailGlow * GLOW_INTENSITY * glowPulse * 0.5 * trailAlpha;

        // Inner bright core of trail
        float coreW = trailW * 0.3;
        float coreGd = minDist / max(coreW, 0.001);
        float coreGlow = exp(-coreGd * coreGd * 2.0) * closestFade;
        col += vec3(1.0) * coreGlow * GLOW_INTENSITY * glowPulse * 0.3 * trailAlpha;

        // ── Bright head ───────────────────────────────────
        float headPScale = perspScale(headParam);
        float headR = sHeadDia * 0.5 * headPScale;
        float headD = length(uv - headPos);

        // Soft outer halo
        float halo = exp(-headD * headD / (headR * headR * 3.0));
        col += HEAD_COLOR.rgb * halo * 0.4 * HEAD_GLOW * glowPulse;

        // Core glow
        float headGlow = exp(-headD * headD / (headR * headR * 0.25));
        col += HEAD_COLOR.rgb * headGlow * HEAD_GLOW * GLOW_INTENSITY * glowPulse;

        // Sparkle: use cached tangent from trail direction
        vec2 hp = uv - headPos;
        vec2 tang = curveBase(headParam + 0.02, aspect) - curveBase(headParam - 0.02, aspect);
        vec2 rtang = vec2(tang.x * cca - tang.y * csa, tang.x * csa + tang.y * cca);
        float pathAngle = atan(rtang.y, rtang.x);
        float spinAngle = pathAngle + u_time * HEAD_SPIN * vSpin * PI * 2.0;
        float cs = cos(spinAngle), sn = sin(spinAngle);
        vec2 rhp = vec2(hp.x * cs + hp.y * sn, -hp.x * sn + hp.y * cs);
        float headSpark = sparkleStar(rhp, headR * 0.6, HEAD_POINTS, HEAD_INNER_R);
        col += vec3(1.0) * headSpark * 0.12 * GLOW_INTENSITY;
    }

    // ── Tone mapping ──────────────────────────────────────
    col = col / (1.0 + col);

    gl_FragColor = vec4(col, 1.0);
}
