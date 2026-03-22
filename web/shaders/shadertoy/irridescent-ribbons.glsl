precision highp float;
uniform vec2 u_resolution;
uniform float u_time;

#define iTime u_time
#define iResolution vec3(u_resolution, 1.0)

float tanhF(float x) { float e = exp(2.0*x); return (e-1.0)/(e+1.0); }

//## Common

#define PI 3.14159265

float _sin(float x) {
    return sin(2.0 * PI * x);
}

float _cos(float x) {
    return cos(2.0 * PI * x);
}

vec3 rotateX(vec3 v, float a) {
    return vec3(
        v.x,
        v.y * _cos(a) - v.z * _sin(a),
        v.z * _cos(a) + v.y * _sin(a)
    );
}

vec3 rotateY(vec3 v, float a) {
    return vec3(
        v.x * _cos(a) - v.z * _sin(a),
        v.y,
        v.z * _cos(a) + v.x * _sin(a)
    );
}

vec3 rotateZ(vec3 v, float a) {
    return vec3(
        v.x * _cos(a) - v.y * _sin(a),
        v.y * _cos(a) + v.x * _sin(a),
        v.z
    );
}

vec2 outOfBounds = vec2(-1.0, -1.0);

vec2 project(vec3 p, float d) {
    return 
        p.z > 0.0 ?
            vec2(p.x * d / p.z, p.y * d / p.z) :
            outOfBounds;
}


//## Image

vec3 palette(float t) {
    vec3 a = vec3(0.5);
    vec3 b = vec3(0.5);
    vec3 c = vec3(1.0);
    vec3 d = vec3(0.1, 0.4, 0.5);
    return a + b * cos(2.0 * PI * (c * t + d));
}

vec4 wave(vec2 xy, vec4 color, float amp, float freq, float phase, vec3 hue, float strength) {
    strength = clamp(strength, 0.0, 1.0);
    float wave1a = _sin(phase + 0.4 * freq * xy.x);
    float wave1b = _sin(phase + 0.2 * freq * xy.x);
    float y = clamp(xy.y + amp * (wave1a + wave1b) / 2.0, -1.0, 1.0);
    float wave2a = _sin(phase + 0.2 * freq * xy.x);
    float wave2b = _sin(phase + 0.1 * freq * xy.x);
    float thicknessBalance = 0.5 * (wave2a + wave2b) / 2.0;
    thicknessBalance = 0.5 + _sin(0.25 * (iTime + xy.x)) * thicknessBalance;
    float topThickness = 0.5 * pow(1.0 - thicknessBalance, 3.0);
    float bottomThickness = 0.25 * pow(thicknessBalance, 3.0);
    topThickness = clamp(topThickness, 0.01, 1.0);
    bottomThickness = clamp(bottomThickness, 0.01, 1.0);
    float brightness = y > 0.0 ? 1.0 - y / topThickness : 1.0 + y / bottomThickness;
    brightness = clamp(brightness, 0.0, 1.0);
    brightness = pow(brightness, 5.0 - 4.0 * strength);
    return vec4(vec3(brightness) * hue, 1.0);
}

void main() {
    vec4 color;
    vec2 coord = gl_FragCoord.xy;
    vec2 uv = (2.0 * coord - iResolution.xy) / min(iResolution.x, iResolution.y);
    vec2 mouse = vec2(0.0, 0.0);
    color = vec4(0.0, 0.0, 0.0, 1.0);
    float level = 0.0; // audio stubbed
    for (int li = 0; li < 5; li++) {
        float layer = float(li);
        float z = 0.25 + layer * 0.05;
        vec3 xyz = vec3(uv, z);
        xyz = rotateX(xyz, 0.25 * mouse.y / 4.0);
        xyz = rotateY(xyz, 0.25 * mouse.x / 4.0);
        xyz = rotateZ(xyz, 0.025 * _sin(0.1 * iTime));
        vec2 xy = project(xyz, z);
        float percent = layer / 5.0;
        float amp = 0.1 + 0.1 * percent;
        float freq = 0.5 + 1.0 * percent;
        float phase = 0.1 * iTime - percent;
        vec3 hue = palette(0.4 * percent + 0.1 * xy.x - iTime / 5.0);
        vec4 layerColor = wave(xy, color, amp, freq, phase, hue, 0.0);
        float darken = tanhF(xyz.z / 0.25);
        color += darken * layerColor;
    }
    gl_FragColor = color;
}
