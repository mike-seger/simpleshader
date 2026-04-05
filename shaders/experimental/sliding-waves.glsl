precision highp float;
uniform vec2 u_resolution;
uniform float u_time;

// @lil-gui-start
const float LINE_SPACING  = 0.13;   // distance between parallel lines @range(0.004, 1.0)
const float LINE_DIAMETER = 0.014;  // line half-thickness @range(0.001, 0.2)
const int   LINE_COUNT    = 11;     // number of lines @range(1, 50, 1)
const float LINE_LENGTH   = 50.00;  // snake length in canvas-widths @range(0.1, 1000.0)
const float WAVE_AMP      = 0.20;   // main wave amplitude @range(0.0, 0.5)
const float WAVE_FREQ     = 1.50;   // wave cycles across canvas @range(0.5, 6.0)
const float MOD_FREQ      = 0.40;   // amplitude-modulation frequency (Hz) @range(0.0, 4.0)
const float MOD_AMP       = 0.30;   // modulation depth @range(0.0, 1.0)
const float ROLL_FREQ     = 0.045;  // roll oscillation frequency (Hz) @range(0.0, 3.0)
const float ROLL_AMP      = 1.20;   // roll amplitude (radians) @range(0.0, 3.14)
// @lil-gui-end

void main() {
    const float PI = 3.14159265;
    float aspect   = u_resolution.x / u_resolution.y;
    vec2  uv       = (gl_FragCoord.xy - u_resolution * 0.5) / u_resolution.y;

    float speed    = 0.20;
    float snakeLen = LINE_LENGTH * aspect;
    float lineHalf = LINE_SPACING * float(LINE_COUNT - 1) * 0.5;

    float waveK = 2.0 * PI * WAVE_FREQ / aspect;
    float waveW = waveK * speed;

    // Amplitude-modulated wave path
    float effAmp = WAVE_AMP * (1.0 + MOD_AMP * sin(2.0 * PI * MOD_FREQ * u_time));

    float headX = -0.5 * aspect + mod(u_time * speed, aspect + snakeLen);
    float s = headX - uv.x;
    if (s < 0.0 || s > snakeLen) {
        gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    // Local tangent / normal at this pixel's x
    float pathY = effAmp * sin(waveK * uv.x - waveW * u_time);
    float dydx  = effAmp * waveK * cos(waveK * uv.x - waveW * u_time);
    vec2  tang  = normalize(vec2(1.0, dydx));
    vec2  nrm   = vec2(-tang.y, tang.x);

    float across = dot(uv - vec2(uv.x, pathY), nrm);

    // Roll oscillates (not continuous spin) → propagates from head toward tail
    float propSpeed = 0.4;
    float rollTime  = max(0.0, u_time - s / propSpeed);
    float roll      = ROLL_AMP * sin(2.0 * PI * ROLL_FREQ * rollTime);
    float cosR      = cos(roll);

    // Band narrows when edge-on
    float cosRabs  = max(abs(cosR), 0.10);
    float visCore  = lineHalf * cosRabs;                       // projected outermost line center
    float visHalf  = visCore + LINE_SPACING * 0.5 * cosRabs;  // ribbon edge: half a gap beyond
    float edgeFade = smoothstep(visHalf, visCore, abs(across));
    if (edgeFade <= 0.0) { gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0); return; }

    float endFade = smoothstep(0.0, 0.06, s) * smoothstep(snakeLen, snakeLen - 0.10, s);

    // LINE_COUNT stripes projected under roll.
    // Fade by abs(cosR) so the band dims when edge-on → no knotting artefact.
    float rollFade = abs(cosR);
    float brightness = 0.0;
    for (int i = 0; i < LINE_COUNT; i++) {
        float yi   = (float(i) - float(LINE_COUNT - 1) * 0.5) * LINE_SPACING;
        float proj = yi * cosR;
        brightness = max(brightness, smoothstep(LINE_DIAMETER, 0.0, abs(across - proj)));
    }

    gl_FragColor = vec4(vec3(brightness * rollFade * edgeFade * endFade), 1.0);
}



