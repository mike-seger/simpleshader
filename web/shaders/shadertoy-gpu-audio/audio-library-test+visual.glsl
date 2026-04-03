precision highp float;

// Audio Library Test + Visual
// https://www.shadertoy.com/view/7clGD7

// @gpu-audio audio-library-test+visual-sound.glsl 60

uniform vec2 u_resolution;
uniform float u_time;

#define TAU 6.283185307
#define PI  3.141592653
#define SAMPLE_RATE 44100.0
#define BPM 124.0

// ─── shared library fns (both tabs need these) ──────────────
float hashNoise(float n) { return fract(sin(n) * 43758.5453123); }

int imod(int a, int b) { return a - (a / b) * b; }

bool euclidean(int step, int pulses, int steps, int rotation) {
    step = imod(step + rotation, steps);
    return imod(step * pulses, steps) < pulses;
}

float beat     (float t, float bpm) { return t * bpm / 60.0; }
int   beatIndex(float t, float bpm) { return int(floor(t * bpm / 60.0)); }
float beatFract(float t, float bpm) { return fract(t * bpm / 60.0); }

float envPerc(float t, float r) { return (t < 0.0) ? 0.0 : exp(-t * r); }

float lfo(float t, float rate, int shape) {
    float p = fract(t * rate);
    if (shape == 0) return sin(p * TAU);
    if (shape == 1) return 4.0 * abs(p - 0.5) - 1.0;
    if (shape == 2) return 2.0 * p - 1.0;
    if (shape == 3) return step(0.5, p) * 2.0 - 1.0;
    return hashNoise(floor(t * rate)) * 2.0 - 1.0;
}

// ─── the synaesthetic glue ──────────────────────────────────
// One source of truth for song timing & event gates.
// Audio and visuals both call getSongState() → perfect sync.
struct SongState {
    float b, bf, beatLen, tBeat;   // beat clock
    int   bi, bar;
    int   s16i;                    // 16th-note step
    float s16f, s16Len, tStep;
    int   root;                    // current MIDI root
    bool  snareMain, snareGhost;   // event gates
    bool  hatAccent, hatOpen, arpOn;
    float duck, sweep;             // continuous mod
    float arpSeed, arpRnd;         // arp pitch seed (reshuffles /4 bars)
};

SongState getSongState(float t) {
    SongState s;
    s.b       = beat(t, BPM);
    s.bi      = beatIndex(t, BPM);
    s.bf      = beatFract(t, BPM);
    s.beatLen = 60.0 / BPM;
    s.tBeat   = s.bf * s.beatLen;

    float g   = s.b * 4.0;
    s.s16i    = int(floor(g));
    s.s16f    = fract(g);
    s.s16Len  = s.beatLen * 0.25;
    s.tStep   = s.s16f * s.s16Len;

    s.bar     = s.bi / 4;
    int idx = imod(s.bar / 2, 4);                  // C C Eb F
    if (idx == 0 || idx == 1) s.root = 36;
    else if (idx == 2) s.root = 39;
    else s.root = 41;

    s.snareMain  = (s.bi - (s.bi / 2) * 2) == 1;
    s.snareGhost = euclidean(imod(s.s16i, 16), 3, 16, 9) && !s.snareMain;
    s.hatAccent  = euclidean(imod(s.s16i, 16), 5, 16, 3);
    s.hatOpen    = imod(s.s16i, 8) == 6;
    s.arpOn      = euclidean(imod(s.s16i, 16), 11, 16, 0);

    s.duck    = 1.0 - envPerc(s.tBeat, 7.0) * 0.75;
    s.sweep   = lfo(t, 1.0 / (s.beatLen * 16.0), 0) * 0.35 + 0.45;
    s.arpSeed = floor(s.b / 16.0) * 17.31;
    s.arpRnd  = hashNoise(float(imod(s.s16i, 16)) + s.arpSeed);
    return s;
}
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
