precision highp float;

uniform vec2  u_resolution;
uniform float u_time;

#define PI 3.14159265

// @lil-gui-start
const float ANIM_DURATION    = 7.0;    // seconds per cycle // @range(0.0, 10.0, 0.5)
const float HEAD_DIAMETER    = 0.09;   // head size (fraction of height) // @range(0.05, 0.5, 0.01)
const float HEAD_GLOW        = 1.4;    // head glow brightness // @range(0.0, 4.0, 0.01)
const float HEAD_SPIN        = 0.2;    // star rotation speed // @range(0.0, 3.0, 0.01)
const float TAIL_LENGTH      = 1.65;   // tail length (fraction of height) // @range(0.0, 4.5, 0.05)
const float TAIL_WIDTH_HEAD  = 0.33;  // tail width at the head end // @range(0.01, 1.0, 0.005)
const float TAIL_WIDTH_END   = 0.378;   // tail width at the tail tip // @range(0.0, 0.6, 0.001)
const float GLOW_FREQ        = 0.34;    // glow pulsation frequency // @range(0.0, 1.0, 0.01)
const float GLOW_AMP         = 0.45;    // glow pulsation amplitude // @range(0.0, 1.0, 0.01)
const float GLOW_INTENSITY   = 1.7;    // overall brightness // @range(0.3, 5.0, 0.1)
const vec4  HEAD_COLOR       = vec4(0.2863, 0.5569, 0.9333, 1.0);  // head glow color
const vec4  TAIL_START_COLOR = vec4(0.1294, 0.3216, 0.7098, 1.0);   // tail color near head
const vec4  TAIL_END_COLOR   = vec4(0.0118, 0.1451, 0.549, 0.0);  // tail color at tip
// @lil-gui-end

// ── 4-pointed star sparkle shape ──────────────────────────
float sparkleStar(vec2 p, float size) {
    vec2 ap = abs(p);
    float c1 = max(ap.x * 10.0, ap.y) / size;
    float c2 = max(ap.x, ap.y * 10.0) / size;
    float d = min(c1, c2);
    vec2 rp = vec2(p.x + p.y, p.x - p.y) * 0.7071;
    vec2 arp = abs(rp);
    float c3 = max(arp.x * 7.0, arp.y) / size;
    float c4 = max(arp.x, arp.y * 7.0) / size;
    d = min(d, min(c3, c4));
    return 1.0 / (d * d + 0.5);
}

// ── Curve: y = 1 / (2 * sqrt(x + 0.3)) ───────────────────
vec2 curvePoint(float t, float aspect) {
    float ct = clamp(t, -0.5, 2.0);
    return vec2(ct * aspect, 0.5 / sqrt(max(ct + 0.3, 0.001)));
}

// Z-depth follows same curve; perspective scale normalized to 1.0 at t=0.5
float perspScale(float t) {
    float ct = clamp(t, -0.5, 2.0);
    return sqrt((ct + 0.3) / 0.8);
}

void main() {
    float aspect = u_resolution.x / u_resolution.y;
    vec2 uv = gl_FragCoord.xy / u_resolution.y;  // height-normalized

    vec3 col = vec3(0.01, 0.01, 0.04);  // dark background

    // ── Animation ─────────────────────────────────────────
    // Cycle ends when the tail tip exits the viewport
    // Tail tip param = headParam - tailParamLen; exits when curvePoint > viewport
    float tailParamLen = TAIL_LENGTH / sqrt(aspect * aspect + 0.25);
    float exitParam = 1.15 + tailParamLen;  // head param when tail tip clears viewport
    float entryParam = -0.15;
    float totalRange = exitParam - entryParam;
    float cycle = mod(u_time, ANIM_DURATION) / ANIM_DURATION;
    float headParam = entryParam + cycle * totalRange;
    vec2 headPos = curvePoint(headParam, aspect);

    // ── Trail glow: closest distance to curve segments ───
    float minDist = 1e9;
    float closestFade = 0.0;
    for (int i = 0; i < 60; i++) {
        float f0 = float(i) / 60.0;
        float f1 = float(i + 1) / 60.0;
        vec2 p0 = curvePoint(headParam - f0 * tailParamLen, aspect);
        vec2 p1 = curvePoint(headParam - f1 * tailParamLen, aspect);
        vec2 seg = p1 - p0;
        float proj = clamp(dot(uv - p0, seg) / dot(seg, seg), 0.0, 1.0);
        float d = length(uv - (p0 + seg * proj));
        if (d < minDist) {
            minDist = d;
            closestFade = 1.0 - mix(f0, f1, proj);
        }
    }

    // Glow pulsation
    float glowPulse = 1.0 + GLOW_AMP * sin(u_time * GLOW_FREQ * PI * 2.0);

    // Perspective scale at closest trail point
    float closestT = headParam - (1.0 - closestFade) * tailParamLen;
    float pScale = perspScale(closestT);

    // Trail glow (narrows from head to tail end, scaled by perspective)
    float trailW = mix(TAIL_WIDTH_END, TAIL_WIDTH_HEAD, closestFade) * pScale;
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

    // ── Bright head ───────────────────────────────────────
    float headPScale = perspScale(headParam);
    float headR = HEAD_DIAMETER * 0.5 * headPScale;
    float headD = length(uv - headPos);

    // Soft outer halo
    float halo = exp(-headD * headD / (headR * headR * 3.0));
    col += HEAD_COLOR.rgb * halo * 0.4 * HEAD_GLOW * glowPulse;

    // Core glow
    float headGlow = exp(-headD * headD / (headR * headR * 0.25));
    col += HEAD_COLOR.rgb * headGlow * HEAD_GLOW * GLOW_INTENSITY * glowPulse;

    // Sparkle cross: rotated normal to path + spin
    vec2 hp = uv - headPos;
    vec2 tang = curvePoint(headParam + 0.01, aspect) - curvePoint(headParam - 0.01, aspect);
    float pathAngle = atan(tang.y, tang.x);
    float spinAngle = pathAngle + u_time * HEAD_SPIN * PI * 2.0;
    float cs = cos(spinAngle), sn = sin(spinAngle);
    vec2 rhp = vec2(hp.x * cs + hp.y * sn, -hp.x * sn + hp.y * cs);
    float headSpark = sparkleStar(rhp, headR * 0.6);
    col += vec3(1.0) * headSpark * 0.12 * GLOW_INTENSITY;

    // ── Tone mapping ──────────────────────────────────────
    col = col / (1.0 + col);

    gl_FragColor = vec4(col, 1.0);
}
