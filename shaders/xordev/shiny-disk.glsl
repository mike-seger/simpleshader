/*
    Built by @XorDev
    https://fragcoord.xyz/
*/

precision highp float;

uniform vec2 u_resolution;
uniform float u_time;

void main() {
    vec4 o = vec4(0.0);
    vec2 r = u_resolution;

    vec2 p = (gl_FragCoord.xy * 2.0 - r) / r.y;
    o += 0.1 / abs(length(p) - 0.5 + 0.01 / (p.x - p.y));

    gl_FragColor = vec4(o.rgb, 1.0);
}
