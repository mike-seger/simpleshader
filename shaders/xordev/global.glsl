/*
    Built by @XorDev
    https://fragcoord.xyz/
*/

precision highp float;

uniform vec2 u_resolution;
uniform float u_time;

vec4 tanh_safe(vec4 x) {
    vec4 cx = clamp(x, -10.0, 10.0);
    vec4 e2 = exp(2.0 * cx);
    return (e2 - 1.0) / (e2 + 1.0);
}

void main() {
    vec4 o = vec4(0.0);
    vec2 r = u_resolution;
    float t = u_time;

    float a = min(r.x, r.y);
    vec2 p = (gl_FragCoord.xy * 2.0 - r) / a;
    float N = 400.0;

    for (int ii = 0; ii < 400; ii++) {
        float i = -1.0 + float(ii) * 2.0 / N;
        vec3 v = vec3(
            cos(N * i * 2.4 + sin(i * N + t) + t + vec2(0.0, 11.0)) * sqrt(1.0 - i * i),
            i
        );
        o += (sin(i * 4.0 + vec4(6.0, 1.0, 2.0, 3.0)) + 1.0)
            * (v.y + 1.0) / N / length(p - v.xz / (1.6 - v.y));
    }

    o = tanh_safe(0.2 * o * o);

    gl_FragColor = vec4(o.rgb, 1.0);
}