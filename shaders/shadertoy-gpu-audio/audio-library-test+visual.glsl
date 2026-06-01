precision highp float;

// Audio Library Test + Visual
// https://www.shadertoy.com/view/7clGD7

// @iChannel0 "audio-library-test+visual-sound.glsl" gpu-audio 60

uniform vec2 u_resolution;
uniform float u_time;

// @include audio-library-test+visual-common.glsl

// IMAGE

vec3 hsv(float h, float s, float v) {
    vec3 k = clamp(abs(fract(h + vec3(0,2,1)/3.0)*6.0 - 3.0) - 1.0, 0.0, 1.0);
    return v * mix(vec3(1), k, s);
}

void main() {
    vec2 uv = (gl_FragCoord.xy - 0.5*u_resolution.xy) / u_resolution.y;
    SongState s = getSongState(u_time);

    // root note → base hue (chord = colour)
    float hue = 0.58 + float(s.root - 36) * 0.035;

    // ─── BACKGROUND — pad-coloured, breathes with LFO ───────
    vec3 col = hsv(hue, 0.5, 0.06) * (1.0 - length(uv)*0.25);
    col += hsv(hue+0.03, 0.3, 0.02) * (0.5 + 0.5*lfo(u_time, 0.05, 0));

    // ─── 16-STEP RING ────────────────────────────────────────
    // each dot shows what lives on that step; arp dots sit at
    // a radius proportional to pitch → melody becomes shape
    const float R = 0.33;
    for (int i = 0; i < 16; i++) {
        float ang = PI*0.5 - float(i)/16.0 * TAU;   // 12 o'clock, clockwise

        bool eArp  = euclidean(i, 11, 16, 0);
        bool eHat  = euclidean(i,  5, 16, 3);
        bool eOpen = imod(i, 8) == 6;
        bool cur   = (i == imod(s.s16i, 16));

        // pitch of the note *that would play* on this step
        float noteRnd = hashNoise(float(i) + s.arpSeed);
        float radius  = R + (eArp ? (noteRnd - 0.5) * 0.11 : 0.0);
        vec2  pos     = vec2(cos(ang), sin(ang)) * radius;

        float size   = 0.010 + (eHat ? 0.004 : 0.0) + (eOpen ? 0.006 : 0.0);
        float bright = 0.12;
        vec3  dc     = vec3(0.35);

        if (eArp) {                                  // pitch → warm hue offset
            dc = hsv(hue + 0.35 + noteRnd*0.18, 0.85, 1.0);
            bright = 0.25 * (0.4 + s.sweep);         // filter sweep = arp glow
        }
        if (eOpen) dc = mix(dc, vec3(0.95,0.85,0.6), 0.7);

        if (cur) {                                   // playhead hit
            float e = envPerc(s.tStep, 18.0);
            size   += e * 0.018;
            bright += e * (1.2 + (s.arpOn ? 1.6 : 0.0));
        }

        float d = length(uv - pos) - size;
        col += dc * exp(-max(d,0.0) * 90.0) * bright;
    }

    // ─── SMOOTH PLAYHEAD — ghost dot orbits continuously ────
    float pa = PI*0.5 - fract(s.b*0.25) * TAU;
    vec2  pp = vec2(cos(pa), sin(pa)) * R;
    col += vec3(0.5,0.6,0.7) * exp(-length(uv-pp)*60.0) * 0.15;

    // ─── KICK — centre pulse driven by the sidechain env ────
    float punch = 1.0 - s.duck;                      // 0.75 → 0 over beat
    float kr = 0.09 + punch*0.13;
    float kd = length(uv) - kr;
    col += hsv(hue-0.02, 0.55, 1.0) * exp(-abs(kd)*28.0) * (0.25 + punch*1.8);
    col += hsv(hue,      0.30, 0.5) * smoothstep(0.008, -0.008, kd) * 0.4;

    // ─── SNARE — side flashes ───────────────────────────────
    float se = (s.snareMain  ? envPerc(s.tBeat, 16.0)       : 0.0)
             + (s.snareGhost ? envPerc(s.tStep, 35.0) * 0.3 : 0.0);
    float bar = min(abs(uv.x-0.55), abs(uv.x+0.55));
    col += vec3(0.95,0.9,0.85) * exp(-bar*22.0) * se * 0.55;

    // ─── SIDECHAIN PUMP — whole frame ducks with the bass ──
    col *= 0.68 + 0.32 * s.duck;

    // tone & out
    col = 1.0 - exp(-col * 1.6);
    col = pow(col, vec3(0.45));
    gl_FragColor = vec4(col, 1.0);
}
