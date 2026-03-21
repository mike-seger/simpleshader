precision highp float;

uniform vec2 u_resolution;
uniform float u_time;

void main() {
    vec4 o = vec4(0.0);
    vec2 r = u_resolution;
    float t = u_time;

    float a = min(u_resolution.x, u_resolution.y);
    vec2 p = (gl_FragCoord.xy * 2.0 - r) / (a * 0.70),
         l,
         v = p * (1.0 - (l += abs(0.7 - dot(p, p)))) / 0.2;

    for (float i = 1.0; i <= 8.0; i += 1.0) {
        o += (sin(v.xyyx) + 1.0) * abs(v.x - v.y) * 0.2;
        v += cos(v.yx * i + vec2(0.0, i) + t) / i + 0.7;
    }

    vec4 e = exp(p.y * vec4(1, -1, -2, 0)) * exp(-4.0 * l.x) / o;
    vec4 e2 = exp(2.0 * e);
    o = (e2 - 1.0) / (e2 + 1.0);

    gl_FragColor = o;
}
