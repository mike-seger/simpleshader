// Audio Library Test — common definitions (shared by visual and sound tabs)
// https://www.shadertoy.com/view/7clGD7

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

// tanh is not available in GLSL ES 1.00
float tanh(float x) { float e = exp(2.0 * x); return (e - 1.0) / (e + 1.0); }

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
