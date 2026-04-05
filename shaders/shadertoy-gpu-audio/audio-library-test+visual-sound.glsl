// # SOUND https://www.shadertoy.com/view/7clGD7


#define SCALE_MINOR  0x5AD

float phaseSamp(int samp, float freq, float sr) {
    int period = int(sr);
    int sampMod = samp % period;
    return fract(float(sampMod) * freq / sr);
}
float mtof(float note) {
    return 440.0 * pow(2.0, (note - 69.0) / 12.0);
}

float sinOsc(float p) { return sin(p * TAU); }

float sawOsc(float p) { return 2.0 * p - 1.0; }

float polyblep(float t, float dt) {
    if (t < dt)        { t /= dt; return t+t - t*t - 1.0; }
    else if (t > 1.0-dt) { t = (t-1.0)/dt; return t*t + t+t + 1.0; }
    return 0.0;
}

float sawBL(float p, float freq, float sr) {
    float dt = freq / sr;
    return sawOsc(p) - polyblep(p, dt);
}

float noiseSmooth(float time, float rate) {
    float t = time * rate;
    float i = floor(t);
    float f = fract(t);
    return mix(hashNoise(i), hashNoise(i+1.0), smoothstep(0.0,1.0,f))*2.0-1.0;
}

float kickSynth(float t, float hit, float f0, float f1, float decay) {
    float elapsed = t - hit;
    if (elapsed < 0.0) return 0.0;
    float freq  = f1 + (f0 - f1) * exp(-elapsed * 30.0);
    float phase = f1*elapsed + (f0-f1)*(1.0 - exp(-elapsed*30.0))/30.0;
    return sin(TAU * phase) * exp(-elapsed * decay);
}

float hihatSynth(float t, float hit, float decay) {
    float elapsed = t - hit;
    if (elapsed < 0.0) return 0.0;
    return (hashNoise(elapsed*SAMPLE_RATE + hit)*2.0-1.0) * exp(-elapsed*decay);
}

float snareSynth(float t, float hit, float toneDecay, float noiseDecay) {
    float elapsed = t - hit;
    if (elapsed < 0.0) return 0.0;
    float tone  = sin(TAU*180.0*elapsed) * exp(-elapsed*toneDecay);
    float noise = (hashNoise(elapsed*SAMPLE_RATE+hit)*2.0-1.0)*exp(-elapsed*noiseDecay);
    return tone*0.5 + noise*0.5;
}

vec2 panEqualPower(float p) {
    return vec2(cos(p*PI*0.5), sin(p*PI*0.5));
}

float softClip(float x) { return tanh(x); }
float quantize(float note, int scale) {
    float octave = floor(note / 12.0);
    int degree = int(mod(note, 12.0));
    for (int i = 0; i < 12; i++) {
        if (((scale >> ((degree + i) % 12)) & 1) == 1)
            return octave * 12.0 + float((degree + i) % 12);
    }
    return note;
}


float envAD(float t, float attack, float decay) {
    if (t < 0.0) return 0.0;
    if (t < attack) return t / attack;
    return exp(-(t - attack) / decay);
}

vec2 mainSound(int samp, float time) {
    float sr = iSampleRate;
    SongState s = getSongState(time);

    // ─── DRUMS ───────────────────────────────────────────────
    float kick = kickSynth(time, time - s.tBeat, 130.0, 48.0, 5.5);

    float snare = 0.0;
    if (s.snareMain)  snare  = snareSynth(time, time - s.tBeat, 14.0, 22.0);
    if (s.snareGhost) snare += snareSynth(time, time - s.tStep, 25.0, 45.0) * 0.12;

    float hatDecay = s.hatOpen ? 10.0 : (s.hatAccent ? 35.0 : 90.0);
    float hatAmp   = s.hatOpen ? 0.22 : (s.hatAccent ? 0.28 : 0.12);
    float hat      = hihatSynth(time, time - s.tStep, hatDecay) * hatAmp;

    // ─── BASS ────────────────────────────────────────────────
    int bassSteps[8] = int[8](0, 12, 0, 7, 0, 12, 7, 0);
    float bassFreq   = mtof(float(s.root + bassSteps[s.s16i % 8]));
    float bassOsc    = sawBL (phaseSamp(samp, bassFreq,     sr), bassFreq, sr) * 0.35
                     + sinOsc(phaseSamp(samp, bassFreq*0.5, sr))               * 0.65;
    float bass = bassOsc * envAD(s.tStep, 0.004, s.s16Len * 0.55) * s.duck;

    // ─── ARP ─────────────────────────────────────────────────
    float arpMidi = quantize(float(s.root) + 24.0 + s.arpRnd * 19.0, SCALE_MINOR);
    float arpFreq = mtof(arpMidi);
    float arpEnv  = s.arpOn ? envPerc(s.tStep, 20.0) : 0.0;

    float pL = phaseSamp(samp, arpFreq * 0.996, sr);
    float pR = phaseSamp(samp, arpFreq * 1.004, sr);
    float pC = phaseSamp(samp, arpFreq,         sr);
    float aL = mix(sinOsc(pC), sawBL(pL, arpFreq, sr), s.sweep) * arpEnv;
    float aR = mix(sinOsc(pC), sawBL(pR, arpFreq, sr), s.sweep) * arpEnv;

    // ─── PAD ─────────────────────────────────────────────────
    float drift = 1.0 + noiseSmooth(time, 0.25) * 0.004;
    float pad = ( sinOsc(phaseSamp(samp, mtof(float(s.root)+12.0)*drift, sr))
                + sinOsc(phaseSamp(samp, mtof(float(s.root)+15.0),       sr)) * 0.6
                + sinOsc(phaseSamp(samp, mtof(float(s.root)+19.0),       sr)) * 0.7 )
              * 0.07 * (0.6 + 0.4 * lfo(time, 0.05, 0));

    // ─── MIX ─────────────────────────────────────────────────
    vec2 hatPan = panEqualPower(0.5 + lfo(time, 0.31, 1) * 0.18);
    vec2 m = kick*0.95 + snare*0.55 + hat*hatPan + bass*0.50
           + vec2(aL,aR)*0.22 + pad*vec2(1.0,0.93);
    return vec2(softClip(m.x*0.8), softClip(m.y*0.8));
}
