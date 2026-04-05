/*
    Built by @XorDev
    https://fragcoord.xyz/
*/

precision highp float;

uniform vec2 u_resolution;
uniform float u_time;

// Simplex 2D noise (Ashima Arts / Ian McEwan)
vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec2 mod289(vec2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec3 permute(vec3 x) { return mod289(((x * 34.0) + 1.0) * x); }

float snoise2D(vec2 v) {
    const vec4 C = vec4(0.211324865405187, 0.366025403784439,
                       -0.577350269189626, 0.024390243902439);
    vec2 i  = floor(v + dot(v, C.yy));
    vec2 x0 = v - i + dot(i, C.xx);
    vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
    vec4 x12 = x0.xyxy + C.xxzz;
    x12.xy -= i1;
    i = mod289(i);
    vec3 p = permute(permute(i.y + vec3(0.0, i1.y, 1.0)) + i.x + vec3(0.0, i1.x, 1.0));
    vec3 m = max(0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);
    m = m * m;
    m = m * m;
    vec3 x = 2.0 * fract(p * C.www) - 1.0;
    vec3 h = abs(x) - 0.5;
    vec3 ox = floor(x + 0.5);
    vec3 a0 = x - ox;
    m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
    vec3 g;
    g.x = a0.x * x0.x + h.x * x0.y;
    g.yz = a0.yz * x12.xz + h.yz * x12.yw;
    return 130.0 * dot(m, g);
}

void main() {
    vec4 o = vec4(0.0);
    vec2 r = u_resolution;
    float t = u_time;

    vec2 p = (gl_FragCoord.xy - r * 0.5) / r.y * mat2(8.0, -6.0, 6.0, 8.0), v;
    float f = 3.0 + snoise2D(p + vec2(t * 7.0, 0.0));

    for (int ii = 1; ii <= 50; ii++) {
        float i = float(ii);
        v = p + cos(i * i + (t + p.x * 0.1) * 0.03 + i * vec2(11.0, 9.0)) * 5.0;
        o += (cos(sin(i) * vec4(1, 2, 3, 1)) + 1.0) * exp(sin(i * i + t)) / length(max(v, vec2(v.x * f * 0.02, v.y)));
    }

    vec4 val = pow(o / 1e2, vec4(1.5));
    vec4 e2 = exp(2.0 * val);
    o = (e2 - 1.0) / (e2 + 1.0);

    gl_FragColor = o;
}