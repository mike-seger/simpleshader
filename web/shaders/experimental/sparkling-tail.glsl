precision highp float;

uniform vec2  u_resolution;
uniform float u_time;

#define PI 3.14159265

// @lil-gui-start
const float ANIM_DURATION    = 4.0;    // seconds per cycle // @range(0.0, 10.0, 0.5)
const float HEAD_DIAMETER    = 0.28;   // head size (fraction of height) // @range(0.05, 0.5, 0.01)
const float TAIL_LENGTH      = 2.45;   // tail length (fraction of height) // @range(0.0, 4.5, 0.05)
const float TAIL_WIDTH_HEAD  = 0.285;   // tail width at the head end // @range(0.01, 0.3, 0.005)
const float TAIL_WIDTH_END   = 0.04;  // tail width at the tail tip // @range(0.0, 0.1, 0.001)
const float SPARKLE_COUNT    = 0.0;   // sparkles (trail + head) // @range(0.0, 100.0, 1.0)
const float GLOW_INTENSITY   = 1.7;    // overall brightness // @range(0.3, 5.0, 0.1)
const vec4  HEAD_COLOR       = vec4(0.88, 0.93, 1.0, 1.0);  // head glow color
const vec4  TAIL_START_COLOR = vec4(0.85, 0.9, 1.0, 1.0);   // tail color near head
const vec4  TAIL_END_COLOR   = vec4(0.55, 0.65, 0.95, 0.0);  // tail color at tip
const float BG_STARS         = 60.0;   // background star count // @range(0.0, 200.0, 1.0)
// @lil-gui-end

// ── Pseudo-random ─────────────────────────────────────────
float hash1(float n) {
    return fract(sin(n) * 43758.5453123);
}

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
// t in [0,1] maps head position along curve
// Returns position in height-normalized coords (x: 0→aspect, y: 0→1)
vec2 curvePoint(float t, float aspect) {
    float ct = clamp(t, -0.5, 2.0);
    return vec2(ct * aspect, 0.5 / sqrt(max(ct + 0.3, 0.001)));
}

void main() {
    float aspect = u_resolution.x / u_resolution.y;
    vec2 uv = gl_FragCoord.xy / u_resolution.y;  // height-normalized

    vec3 col = vec3(0.01, 0.01, 0.04);  // dark background

    // ── Background stars ──────────────────────────────────
    for (int i = 0; i < 80; i++) {
        if (float(i) >= BG_STARS) break;
        float fi = float(i);
        vec2 sp = vec2(hash1(fi * 7.13) * aspect, hash1(fi * 11.37));
        float bright = hash1(fi * 3.77);
        float twinkle = 0.4 + 0.6 * sin(u_time * (1.0 + bright * 3.0) + fi);
        float d = length(uv - sp);
        col += vec3(0.6, 0.7, 1.0) * exp(-d * d * 20000.0) * bright * twinkle * 0.5;
    }

    // ── Animation ─────────────────────────────────────────
    float cycle = mod(u_time, ANIM_DURATION) / ANIM_DURATION;  // 0→1
    float headParam = cycle * 1.3 - 0.15;  // margin for entry/exit
    vec2 headPos = curvePoint(headParam, aspect);

    // Tail parameter extent (approximate arc-length → parameter mapping)
    float tailParamLen = TAIL_LENGTH / sqrt(aspect * aspect + 0.25);

    // ── Trail glow: find closest curve point ──────────────
    float minDist = 1e9;
    float closestFade = 0.0;
    for (int i = 0; i <= 40; i++) {
        float frac = float(i) / 40.0;
        float t = headParam - frac * tailParamLen;
        vec2 pt = curvePoint(t, aspect);
        float d = length(uv - pt);
        if (d < minDist) {
            minDist = d;
            closestFade = 1.0 - frac;
        }
    }

    // Trail glow (narrows from head to tail end)
    float trailW = mix(TAIL_WIDTH_END, TAIL_WIDTH_HEAD, closestFade);
    float gd = minDist / max(trailW, 0.001);
    float trailGlow = exp(-gd * gd * 3.0) * closestFade;
    vec3 trailTint = mix(TAIL_END_COLOR.rgb, TAIL_START_COLOR.rgb, closestFade);
    float trailAlpha = mix(TAIL_END_COLOR.a, TAIL_START_COLOR.a, closestFade);
    col += trailTint * trailGlow * GLOW_INTENSITY * 0.5 * trailAlpha;

    // Inner bright core of trail
    float coreW = trailW * 0.3;
    float coreGd = minDist / max(coreW, 0.001);
    float coreGlow = exp(-coreGd * coreGd * 2.0) * closestFade;
    col += vec3(1.0) * coreGlow * GLOW_INTENSITY * 0.3 * trailAlpha;

    // ── Sparkles along the trail ──────────────────────────
    for (int i = 0; i < 80; i++) {
        if (float(i) >= SPARKLE_COUNT) break;
        float fi = float(i);

        // Position along trail (0 = head, 1 = tail end)
        float alongFrac = hash1(fi * 1.731);
        float paramT = headParam - alongFrac * tailParamLen;
        vec2 center = curvePoint(paramT, aspect);

        // Scatter perpendicular to curve
        vec2 tang = curvePoint(paramT + 0.01, aspect) - curvePoint(paramT - 0.01, aspect);
        vec2 perp = normalize(vec2(-tang.y, tang.x));
        float scatterW = mix(TAIL_WIDTH_END, TAIL_WIDTH_HEAD, 1.0 - alongFrac);
        float scatter = (hash1(fi * 2.937) - 0.5) * scatterW * 2.0;
        center += perp * scatter;

        // Blink
        float phase = u_time * (2.0 + hash1(fi * 5.13) * 3.0) + fi * 1.2;
        float blink = pow(max(sin(phase), 0.0), 3.0);

        float fade = 1.0 - alongFrac;

        // Sparkle shape (randomly rotated)
        vec2 lp = uv - center;
        float angle = hash1(fi * 4.29) * PI;
        float ca = cos(angle), sa = sin(angle);
        lp = vec2(lp.x * ca - lp.y * sa, lp.x * sa + lp.y * ca);

        float size = 0.007 * (0.4 + hash1(fi * 6.17) * 0.8);
        float spark = sparkleStar(lp, size) * blink * fade;

        // Color interpolated along tail position
        vec3 sparkBase = mix(TAIL_END_COLOR.rgb, TAIL_START_COLOR.rgb, fade);
        float hueShift = hash1(fi * 8.31);
        vec3 sparkCol = mix(sparkBase, vec3(0.9, 0.95, 1.0), hueShift * 0.3);

        col += sparkCol * spark * GLOW_INTENSITY * 0.05;
    }

    // ── Bright head ───────────────────────────────────────
    float headR = HEAD_DIAMETER * 0.5;
    float headD = length(uv - headPos);

    // Soft outer halo
    float halo = exp(-headD * headD / (headR * headR * 3.0));
    col += HEAD_COLOR.rgb * halo * 0.4;

    // Core glow
    float headGlow = exp(-headD * headD / (headR * headR * 0.25));
    col += HEAD_COLOR.rgb * headGlow * 2.0 * GLOW_INTENSITY;

    // Central sparkle cross
    vec2 hp = uv - headPos;
    float headSpark = sparkleStar(hp, headR * 0.6);
    col += vec3(1.0) * headSpark * 0.12 * GLOW_INTENSITY;

    // ── Starry sparkles inside the head ───────────────────
    for (int i = 0; i < 20; i++) {
        if (float(i) >= SPARKLE_COUNT * 0.2) break;
        float fi = float(i);

        // Orbit around head center
        float orbitR = headR * (0.15 + hash1(fi * 13.7) * 0.7);
        float a = fi * PI * 2.0 / 7.0 + u_time * (0.8 + hash1(fi * 9.3) * 0.6);
        vec2 sp = headPos + vec2(cos(a), sin(a)) * orbitR;

        // Blink
        float phase = u_time * (3.0 + fi * 0.7) + fi * 2.0;
        float blink = pow(max(sin(phase), 0.0), 2.0);

        // Sparkle shape
        vec2 lp = uv - sp;
        float angle = u_time * 0.4 + fi * 1.5;
        float ca = cos(angle), sa = sin(angle);
        lp = vec2(lp.x * ca - lp.y * sa, lp.x * sa + lp.y * ca);

        float spark = sparkleStar(lp, 0.006 + hash1(fi * 7.1) * 0.004) * blink;

        // Slightly varied color
        vec3 sCol = mix(HEAD_COLOR.rgb, vec3(0.7, 0.85, 1.0), hash1(fi * 4.4));
        col += sCol * spark * GLOW_INTENSITY * 0.08;
    }

    // ── Tone mapping ──────────────────────────────────────
    col = col / (1.0 + col);

    gl_FragColor = vec4(col, 1.0);
}
