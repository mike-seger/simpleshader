precision highp float;

// Melodic Trance 20260530
// Original by Shadertoy
// Converted to play on WebGL 1 / GLSL ES 1.00 playground

// @iChannel1 "20260530_melodic trance -sound.glsl" gpu-audio 180

uniform vec2  u_resolution;
uniform float u_time;

#define bpm 140.0
#define S2T (15.0 / bpm)
#define B2T (60.0 / bpm)
#define ZERO 0
#define saturate(x) clamp(x, 0., 1.)
#define linearstep(a,b,x) saturate(((x)-(a))/((b)-(a)))
#define clip(x) clamp(x, -1., 1.)
#define lofi(i,m) (floor((i)/(m))*(m))
#define u2b(u) ((u) * 2.0 - 1.0)
#define b2u(b) ((b) * 0.5 + 0.5)
#define tri(x) (1.0 - 4.0 * abs(fract((x) + 0.25) - 0.5))
#define repeat(i, n) for (int i = ZERO; i < n; i++)
#define p2f(i) (exp2(((i)-69.)/12.)*440.)
#define TRANSPOSE 0.0

const float SWING = 0.5;
const float PI = 3.141592653589793;
const float TAU = 6.283185307179586;
const float LN2 = 0.6931471805599453;
const float CHORD_CUTOFF = 1.0;

// High-precision float-only hash (Dave Hoskins' hash33)
vec3 hash33(vec3 p3) {
    p3 = fract(p3 * vec3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yxz+33.33);
    return fract((p3.xxy+p3.yzz)*p3.zyx);
}

vec3 hash3f(vec3 p) {
    return hash33(p);
}

// tanh is not available in GLSL ES 1.00 — define float and vec2 versions
float tanh(float x) { float e = exp(2.0 * x); return (e - 1.0) / (e + 1.0); }
vec2  tanh(vec2  x) { vec2  e = exp(2.0 * x); return (e - 1.0) / (e + 1.0); }

int imod(int x, int y) {
  return x - (x / y) * y;
}

float imodf(float x, float y) {
  return x - floor(x / y) * y;
}

vec2 cis(float t) {
  return vec2(cos(t), sin(t));
}

mat2 rotate2D(float t) {
  float c = cos(t);
  float s = sin(t);
  return mat2(c, s, -s, c);
}

vec2 boxMuller(vec2 xi) {
  float r = sqrt(-2.0 * log(xi.x));
  float t = xi.y;
  return r * cis(TAU * t);
}

float tmod(vec4 time, float d) {
  vec4 timeLength_val = (B2T * vec4(1.0, 4.0, 64.0, 65536.0));
  vec4 t = mod(time, timeLength_val);
  float offset = lofi(t.z - t.x + timeLength_val.x / 2.0, timeLength_val.x);
  offset -= lofi(t.z, d);
  return t.x + offset;
}

float t2sSwing(float t) {
  float st = 4.0 * t / B2T;
  return 2.0 * floor(st / 2.0) + step(SWING, fract(0.5 * st));
}

float s2tSwing(float st) {
  return 0.5 * B2T * (floor(st / 2.0) + SWING * mod(st, 2.0));
}

bool isStepActive(int step, int seq) {
  float power = pow(2.0, float(15 - step));
  float quotient = floor(float(seq) / power);
  return mod(quotient, 2.0) >= 1.0;
}

vec4 seq16(float t, int seq) {
  float t_mod = mod(t, 4.0 * B2T);
  int sti = int(clamp(t2sSwing(t_mod), 0.0, 15.0));
  
  float prevStep = -1.0;
  for (int i = 0; i < 17; i++) {
    int checkStep = imod(sti - i, 16);
    if (isStepActive(checkStep, seq)) {
      prevStep = float(sti - i);
      break;
    }
  }
  
  float prevTime = s2tSwing(prevStep);
  
  float nextStep = -1.0;
  for (int i = 1; i < 18; i++) {
    int checkStep = imod(sti + i, 16);
    if (isStepActive(checkStep, seq)) {
      nextStep = float(sti + i);
      break;
    }
  }
  
  float nextTime = s2tSwing(nextStep);
  
  return vec4(
    prevStep,
    t_mod - prevTime,
    nextStep,
    nextTime - t_mod
  );
}

mat3 orthBas(vec3 z) {
  z = normalize(z);
  vec3 x = normalize(cross(vec3(0.0, 1.0, 0.0), z));
  vec3 y = cross(z, x);
  return mat3(x, y, z);
}

float glidephase(float t, float t1, float pitch0, float pitch1) {
  if (pitch0 == pitch1) {
    return t * p2f(pitch1);
  }

  float m0 = (pitch0 - 69.0) / 12.0;
  float m1 = (pitch1 - 69.0) / 12.0;
  float b = (m1 - m0) / t1;

  return (
    + p2f(pitch0) * (pow(2.0, b * min(t, t1)) - 1.0) / b / LN2
    + max(0.0, t - t1) * p2f(pitch1)
  );
}

vec3 cyclic(vec3 p, float pers, float lacu) {
  vec4 sum = vec4(0.0);
  mat3 rot = orthBas(vec3(2.0, -3.0, 1.0));

  repeat(i, 5) {
    p *= rot;
    p += sin(p.zxy);
    sum += vec4(cross(cos(p), sin(p.yzx)), 1.0);
    sum /= pers;
    p *= lacu;
  }

  return sum.xyz / sum.w;
}

float cheapfiltersaw(float phase, float k) {
  float wave = fract(phase);
  float c = smoothstep(1.0, 0.0, wave / (1.0 - k));
  return (wave + c - 1.0) * 2.0 + k;
}

vec2 cheapfiltersaw(vec2 phase, float k) {
  vec2 wave = fract(phase);
  vec2 c = smoothstep(1.0, 0.0, wave / (1.0 - k));
  return (wave + c - 1.0) * 2.0 + k;
}

float cheapfiltersquare(float phase, float k) {
  float s = floor(2.0 * fract(phase));
  float c = smoothstep(1.0, 0.0, fract(2.0 * phase) / (1.0 - k));
  return 2.0 * mix(c, 1.0 - c, s) - 1.0;
}

vec2 cheapfiltersquare(vec2 phase, float k) {
  vec2 s = floor(2.0 * fract(phase));
  vec2 c = smoothstep(1.0, 0.0, fract(2.0 * phase) / (1.0 - k));
  return 2.0 * mix(c, 1.0 - c, s) - 1.0;
}

vec2 cheapnoise(float t) {
  float s = floor(t * 256.0);
  float p = fract(t * 256.0);

  vec3 dice;
  vec2 v = vec2(0.0);

  dice = hash33(vec3(s, s, 0.0)) - vec3(0.5, 0.5, 0.0);
  v += dice.xy * smoothstep(1.0, 0.0, abs(p + dice.z));
  dice = hash33(vec3(s + 1.0, s, 1.0)) - vec3(0.5, 0.5, 1.0);
  v += dice.xy * smoothstep(1.0, 0.0, abs(p + dice.z));
  dice = hash33(vec3(s + 2.0, s, 2.0)) - vec3(0.5, 0.5, 2.0);
  v += dice.xy * smoothstep(1.0, 0.0, abs(p + dice.z));

  return 2.0 * v;
}

vec2 shotgun(float t, float spread, float snap, float fm) {
  vec2 sum = vec2(0.0);

  repeat(i, 64) {
    vec3 dice = hash3f(vec3(float(i) + 1.0));

    vec2 partial = exp2(spread * dice.xy);
    partial = mix(partial, floor(partial + 0.5), snap);

    sum += sin(TAU * t * partial + fm * sin(TAU * t * partial));
  }

  return sum / 64.0;
}

int getChordValue(int prog, int noteIdx) {
  if (prog < 8) {
    if (prog < 4) {
      if (prog < 2) {
        if (prog == 0) {
          if (noteIdx == 0) return -7;
          if (noteIdx == 1) return 0;
          if (noteIdx == 2) return 4;
          if (noteIdx == 3) return 7;
          return 12;
        } else {
          if (noteIdx == 0) return -7;
          if (noteIdx == 1) return 0;
          if (noteIdx == 2) return 4;
          if (noteIdx == 3) return 7;
          return 11;
        }
      } else {
        if (prog == 2) {
          if (noteIdx == 0) return -8;
          if (noteIdx == 1) return 2;
          if (noteIdx == 2) return 4;
          if (noteIdx == 3) return 7;
          return 11;
        } else {
          if (noteIdx == 0) return -8;
          if (noteIdx == 1) return 2;
          if (noteIdx == 2) return 4;
          if (noteIdx == 3) return 7;
          return 12;
        }
      }
    } else {
      if (prog < 6) {
        if (prog == 4) {
          if (noteIdx == 0) return -10;
          if (noteIdx == 1) return 2;
          if (noteIdx == 2) return 4;
          if (noteIdx == 3) return 7;
          return 12;
        } else {
          if (noteIdx == 0) return -4;
          if (noteIdx == 1) return 2;
          if (noteIdx == 2) return 4;
          if (noteIdx == 3) return 7;
          return 11;
        }
      } else {
        if (prog == 6) {
          if (noteIdx == 0) return -3;
          if (noteIdx == 1) return 2;
          if (noteIdx == 2) return 4;
          if (noteIdx == 3) return 7;
          return 11;
        } else {
          if (noteIdx == 0) return -5;
          if (noteIdx == 1) return -2;
          if (noteIdx == 2) return 4;
          if (noteIdx == 3) return 7;
          return 12;
        }
      }
    }
  } else {
    if (prog < 12) {
      if (prog < 10) {
        if (prog == 8) {
          if (noteIdx == 0) return -7;
          if (noteIdx == 1) return 0;
          if (noteIdx == 2) return 4;
          if (noteIdx == 3) return 7;
          return 12;
        } else {
          if (noteIdx == 0) return -7;
          if (noteIdx == 1) return 0;
          if (noteIdx == 2) return 4;
          if (noteIdx == 3) return 7;
          return 11;
        }
      } else {
        if (prog == 10) {
          if (noteIdx == 0) return -8;
          if (noteIdx == 1) return 0;
          if (noteIdx == 2) return 2;
          if (noteIdx == 3) return 7;
          return 11;
        } else {
          if (noteIdx == 0) return -3;
          if (noteIdx == 1) return 2;
          if (noteIdx == 2) return 4;
          if (noteIdx == 3) return 7;
          return 11;
        }
      }
    } else {
      if (prog < 14) {
        if (prog == 12) {
          if (noteIdx == 0) return -10;
          if (noteIdx == 1) return -3;
          if (noteIdx == 2) return 5;
          if (noteIdx == 3) return 7;
          return 12;
        } else {
          if (noteIdx == 0) return -8;
          if (noteIdx == 1) return -1;
          if (noteIdx == 2) return 2;
          if (noteIdx == 3) return 7;
          return 12;
        }
      } else {
        if (prog == 14) {
          if (noteIdx == 0) return -7;
          if (noteIdx == 1) return 0;
          if (noteIdx == 2) return 4;
          if (noteIdx == 3) return 7;
          return 12;
        } else {
          if (noteIdx == 0) return -5;
          if (noteIdx == 1) return 0;
          if (noteIdx == 2) return 2;
          if (noteIdx == 3) return 7;
          return 12;
        }
      }
    }
  }
}

float getChordNote(int i, float t) {
  int iProg = imod(int(t / (4.0 * B2T)), 16);
  int noteIdx = imod(i, 5);
  return TRANSPOSE + float(getChordValue(iProg, noteIdx));
}

int getArpNoteValue(int index) {
  int idx = imod(index, 6);
  if (idx == 0) return 7;
  if (idx == 1) return 12;
  if (idx == 2) return 14;
  if (idx == 3) return 19;
  if (idx == 4) return 14;
  return 12;
}

int getArpFillNoteValue(int index) {
  int idx = imod(index, 8);
  if (idx == 0) return 7;
  if (idx == 1) return 12;
  if (idx == 2) return 14;
  if (idx == 3) return 19;
  if (idx == 4) return 23;
  if (idx == 5) return 24;
  if (idx == 6) return 26;
  return 31;
}

vec2 mainAudioDry(vec4 time) {
  vec2 dest = vec2(0.0);

  float duck = smoothstep(0.0, 0.4, time.x) * smoothstep(0.0, 0.001, B2T - time.x);

  { // kick
    vec4 seq = seq16(time.y, 34952);
    float t = seq.y;
    float q = seq.w;

    if (time.z > 60.0 * B2T) {
      t = time.y;
      q = 4.0 * B2T - t;
    }

    duck = min(
      duck,
      smoothstep(0.0, 0.4, t) * smoothstep(0.0, 0.001, q)
    );

    float env = smoothstep(0.0, 0.001, q);
    env *= smoothstep(0.3, 0.1, t);

    vec2 phase = vec2(
      40.0 * t
      - 10.0 * exp2(-t * 30.0)
      - 6.0 * exp2(-t * 100.0)
      - 6.0 * exp2(-t * 600.0)
    );

    vec2 wave = tanh(2.0 * sin(TAU * phase));

    dest += 0.6 * env * wave;
  }

  { // bass
    vec4 seq = seq16(time.y, 65535);
    float st = seq.x;
    float t = seq.y;
    float q = seq.w;

    float env = smoothstep(0.0, 0.01, t) * smoothstep(0.0, 0.01, q);

    float pitch = 36.0 + getChordNote(0, time.z);
    pitch += mod(st, 4.0) == 2.0 ? 12.0 : 0.0;
    float freq = p2f(pitch);
    vec2 phase = vec2(freq * t);

    vec2 wave = sin(TAU * phase);

    repeat(i, 8) {
      vec3 dice = hash3f(vec3(float(i), 30.0, 18.0));
      vec2 phaseu = phase * exp2(0.02 * (dice.x - 0.5)) + dice.yz;

      float k = exp2(-2.0 * t);
      wave += 0.5 * cheapfiltersquare(phaseu, k);
    }

    wave = mix(vec2(dot(wave, vec2(0.5))), wave, 0.2);

    dest += 0.3 * mix(0.0, 1.0, duck) * env * wave;
  }

  { // hihat
    vec4 seq = seq16(time.y, 65535);
    float t = seq.y;
    float q = seq.w;

    float env = smoothstep(0.0, 0.01, q);
    env *= exp2(-30.0 * t);

    vec2 wave = shotgun(2800.0 * t, 2.6, 0.4, 1.0);
    wave = tanh(6.0 * wave);

    dest += 0.3 * mix(0.1, 1.0, duck) * env * wave;
  }

  { // clap
    vec4 seq = seq16(time.y, 2056);
    float t = seq.y;
    float q = seq.w;

    float env = mix(
      exp2(-20.0 * t),
      exp2(-500.0 * mod(t, 0.012)),
      exp2(-100.0 * max(0.0, t - 0.02))
    );

    vec2 wave = cyclic(vec3(4.0 * cis(2100.0 * t), 2830.0 * t), 1.0, 2.0).xy;

    dest += 0.2 * mix(0.5, 1.0, duck) * tanh(20.0 * env * wave);
  }

  { // shaker
    float t = mod(time.x, S2T);
    float st = mod(floor(time.y / S2T), 16.0);

    float vel = fract(st * 0.42 + 0.23);
    float env = smoothstep(0.0, 0.02, t) * exp(-exp2(5.0 - 2.0 * vel) * t);

    float phase = 280.0 * t;
    phase += phase + 0.1 * sin(TAU * phase);
    vec2 wave = shotgun(phase, 2.0, 0.4, exp2(mix(1.0, 3.0, vel)));

    dest += 0.1 * mix(0.3, 1.0, duck) * tanh(8.0 * env * wave);
  }

  { // open hihat
    float t = mod(time.x - 0.5 * B2T, B2T);
    float q = B2T - t;

    float env = exp2(-7.0 * t) * smoothstep(0.0, 0.01, q);

    vec2 sum = vec2(0.0);
    repeat(i, 16) {
      float odd = float(imod(i, 2));
      float tt = (t + 0.3) * mix(1.0, 1.002, odd);
      vec3 dice = hash3f(vec3(float(i / 2)));
      vec3 dice2 = hash3f(dice);

      vec2 wave = vec2(0.0);
      wave = 4.5 * exp2(-5.0 * t) * sin(wave + exp2(13.30 + 0.1 * dice.x) * tt + dice2.xy);
      wave = 3.2 * exp2(-1.0 * t) * sin(wave + exp2(11.78 + 0.3 * dice.y) * tt + dice2.yz);
      wave = 1.0 * exp2(-5.0 * t) * sin(wave + exp2(14.92 + 0.2 * dice.z) * tt + dice2.zx);

      sum += wave * mix(1.0, 0.5, odd);
    }

    dest += 0.16 * env * duck * tanh(sum);
  }

  { // ride
    vec4 seq = seq16(time.y, 34952);
    float t = seq.y;
    float q = seq.w;

    float env = exp2(-3.0 * t) * smoothstep(0.0, 0.01, q);

    vec2 sum = vec2(0.0);

    repeat(i, 8) {
      vec3 dice = hash3f(vec3(float(i)));
      vec3 dice2 = hash3f(dice);

      vec2 wave = vec2(0.0);
      wave = 2.9 * env * sin(wave + exp2(13.50 + 0.1 * dice.x) * t + dice2.xy);
      wave = 2.8 * env * sin(wave + exp2(12.97 + 0.2 * dice.y) * t + dice2.yz);
      wave = 1.0 * env * sin(wave + exp2(14.09 + 0.1 * dice.z) * t + dice2.zx);

      sum += wave;
    }

    dest += 0.06 * env * mix(0.3, 1.0, duck) * tanh(sum);
  }

  { // crash
    float t = mod(time.z, 64.0 * B2T);

    float env = mix(exp(-t), exp(-10.0 * t), 0.7);
    vec2 wave = shotgun(4100.0 * t, 1.9, 0.0, 1.0);
    dest += 0.6 * env * mix(0.3, 1.0, duck) * tanh(8.0 * wave);
  }

  { // lead
    vec2 sum = vec2(0.0);
    repeat(i, 4) {
      vec4 tdelay = time - float(i) * B2T;
      float gs = t2sSwing(tmod(tdelay, B2T * 64.0));
      float tss = 0.0;
      float s = 0.0;
      float sp = 0.0;
      float pitch = 0.0;

      #define S(ds, sl, p) tss += float(ds); if (gs >= tss) { s = tss; sp = tss + float(sl); pitch = float(p); }
      S(0, 12, 7) S(12, 4, 0)
      S(4, 4, 12) S(4, 4, 11) S(4, 4, 9) S(4, 4, 11)
      S(4, 6, 9) S(6, 16, 7)
      S(18, 4, 4) S(4, 4, 5)

      S(4, 12, 7) S(12, 4, 0)
      S(4, 4, 5) S(4, 4, 4) S(4, 4, 2) S(4, 4, 4)
      S(4, 6, 2) S(6, 16, 0)
      S(18, 4, 4) S(4, 4, 5)

      S(4, 12, 7) S(12, 4, 0)
      S(4, 4, 12) S(4, 4, 11) S(4, 4, 9) S(4, 4, 11)
      S(4, 10, 7) S(12, 4, 0)
      S(4, 6, 11) S(6, 10, 12)

      S(66, 4, 4) S(4, 4, 5)
      #undef S

      float t = tmod(tdelay - s2tSwing(s), B2T * 64.0);
      float l = s2tSwing(sp) - s2tSwing(s);
      float q = l - t;

      t += 0.0004 * smoothstep(0.0, 0.5, t) * sin(TAU * 6.0 * t);

      vec3 dice = hash3f(vec3(s, 10.0, 30.0));

      float env = smoothstep(0.0, 0.001, t) * smoothstep(0.0, 0.001, q);

      pitch += 72.0 + TRANSPOSE;
      float freq = p2f(pitch);
      vec2 phase = freq * t + vec2(0.0, 0.3);

      vec2 osc = 2.0 * fract(phase) - 1.0;

      float delaydecay = exp2(-1.4 * float(i));
      sum += delaydecay * env * osc;
    }
    dest += 0.25 * mix(0.3, 1.0, duck) * sum;
  }

  { // chord
    vec2 sum = vec2(0.0);
    repeat(iDelay, 4) {
      vec4 tdelay = mod(time - B2T * float(iDelay), B2T * vec4(1.0, 4.0, 64.0, 65536.0));
      float delaydecay = exp2(-2.0 * float(iDelay));

      vec4 seq = seq16(tdelay.z, 37448);
      float t = seq.y;
      float q = seq.w;

      float env = smoothstep(0.0, 0.001, t) * smoothstep(0.0, 0.001, q);
      env *= mix(
        smoothstep(0.0, 0.001, 2.0 * S2T - t),
        exp2(-t),
        0.3
      );

      repeat(iUnison, 40) {
        vec3 dice = hash3f(vec3(float(iUnison), seq.x, 7.0));
        vec2 dicen = boxMuller(dice.xy);

        float pitch = 60.0 + getChordNote(iUnison, tdelay.z);
        float freq = p2f(pitch) * exp2(0.02 * dicen.x);

        vec2 phase = t * freq * exp2(0.01 * (dice.xy - 0.5)) + dice.yx;

        float cutdecay = exp2(mix(4.0, -2.0, CHORD_CUTOFF));
        float k = exp2(-cutdecay * t) * exp2(-0.1 * float(iDelay));
        vec2 wave = cheapfiltersaw(phase, k);
        wave += 0.3 * (2.0 * fract(2.0 * phase) - 1.0);

        sum += delaydecay * env * wave * rotate2D(2.4 * float(iUnison));
      }
    }

    dest += 0.04 * sum * mix(0.4, 1.0, duck);
  }

  { // arp
    vec2 sum = vec2(0.0);
    repeat(i, 4) {
      vec4 tdelay = mod(time - float(i) * B2T, B2T * vec4(1.0, 4.0, 64.0, 65536.0));
      float delaydecay = exp2(-1.0 * float(i));

      vec4 seq = seq16(tdelay.y, 65535);
      float st = seq.x + 16.0 * floor(tdelay.z / (16.0 * S2T));
      float t = seq.y;
      float q = seq.w;

      int i_st = int(st);
      float pitch1 = float(getArpNoteValue(imod(i_st, 6)));
      float pitch0 = float(getArpNoteValue(imod(i_st + 5, 6)));

      if (mod(tdelay.z / B2T, 32.0) > 31.0) {
        t = mod(tdelay.x, 0.5 * S2T);
        q = 0.5 * S2T - t;

        int iPitch = imod(int(8.0 * (tdelay.x / B2T)), 8);
        pitch1 = float(getArpFillNoteValue(iPitch));
        pitch0 = (iPitch == 0) ? pitch0 : float(getArpFillNoteValue(iPitch - 1));
      }

      float basepitch = 60.0 + TRANSPOSE;
      pitch0 += basepitch;
      pitch1 += basepitch;

      float env = smoothstep(0.0, 0.001, t) * smoothstep(0.0, 0.001, q);
      env *= exp2(-6.0 * t);

      vec2 phase = vec2(glidephase(t, 0.01, pitch0, pitch1));
      phase += vec2(0.0, 0.1);

      vec2 osc = 2.0 * step(0.5 + 0.25 * tri(time.z / (S2T * 16.0)), fract(phase)) - 1.0;

      sum += delaydecay * env * osc;
    }

    dest += 0.08 * mix(0.4, 1.0, duck) * sum;
  }

  return dest;
}

vec2 mainAudio(vec4 time) {
  vec2 dest = mainAudioDry(time);
  dest *= 0.8;
  return clip(1.2 * tanh(dest));
}

// @pass sound size=1024,1
void main() {
  vec2 fragCoord = gl_FragCoord.xy;
  if (fragCoord.y > 1.0) {
    gl_FragColor = vec4(0.0);
  } else {
    float iSampleRate = 44100.0;
    vec4 time = mod(vec4(u_time - fragCoord.x / iSampleRate), B2T * vec4(1.0, 4.0, 64.0, 65536.0));

    // vec2 s is in [-1.0, 1.0] range
    vec2 s = mainAudio(time);

    // Map audio [-1.0, 1.0] range to [0.0, 1.0] range
    gl_FragColor = vec4(0.5 + 0.5 * s, 0.0, 1.0);
  }
}

// @pass composite
const float SQRT2 = 1.4142135623730951;
const float INV_SQRT2 = 0.7071067811865475;

float plot(vec2 p) {
  float d = 2.0 / u_resolution.y;
  
  float sum = 0.0;
  for (int i = 0; i < 1024; i++) {
    // Look up sample from pass 0 (sound pass)
    float u_coord = (float(i) + 0.5) / 1024.0;
    // Decode from [0.0, 1.0] range back to [-1.0, 1.0] range
    vec2 raw_s = texture2D(u_channel0, vec2(u_coord, 0.5)).xy * 2.0 - 1.0;
    vec2 s = raw_s * mat2(-0.5, 0.5, 0.5, 0.5);
    float r = length(p - s);
    sum += smoothstep(d, 0.0, r - 0.003);
  }
  return sum;
}

float bgPattern(vec2 p) {
  float d = 2.0 / u_resolution.y;

  float rect = 0.0;
  rect += smoothstep(2.0 * d, 0.0, abs(p.x + p.y)) * smoothstep(2.0 * d, 0.0, abs(p.x - p.y) - 0.95);
  rect += smoothstep(2.0 * d, 0.0, abs(p.x - p.y)) * smoothstep(2.0 * d, 0.0, abs(p.x + p.y) - 0.95);
  rect += smoothstep(2.0 * d, 0.0, abs(abs(p.x + p.y) - 1.0)) * smoothstep( 2.0 * d, 0.0, abs(p.x - p.y) - 1.0);
  rect += smoothstep(2.0 * d, 0.0, abs(abs(p.x - p.y) - 1.0)) * smoothstep( 2.0 * d, 0.0, abs(p.x + p.y) - 1.0);
  rect += smoothstep(2.0 * d, 0.0, abs(p.x)) * smoothstep(d, 0.0, abs(p.y) - 0.95);
  return min(rect, 1.0);
}

void main() {
  vec2 fragCoord = gl_FragCoord.xy;
  vec2 uv = fragCoord / u_resolution.xy;
  vec2 p = 2.0 * uv - 1.0;
  p.x *= u_resolution.x / u_resolution.y;
  
  float shape = 0.0;
  
  shape += plot(p);
  shape += 0.1 * bgPattern(p);

  gl_FragColor = vec4(vec3(shape), 1.0);
}
