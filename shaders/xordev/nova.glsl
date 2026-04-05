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

    float s = 0.8*min(r.x, r.y);
    vec2 p = (gl_FragCoord.xy * 2.0 - r) / s;
    float l = 1.0 - length(p);
    o += tanh_safe((1.1 + sin(p.x + t + vec4(0.0, 2.0, 4.0, 0.0))) / 200.0 / max(l, -l * 0.1));

    gl_FragColor = vec4(o.rgb, 1.0);
}