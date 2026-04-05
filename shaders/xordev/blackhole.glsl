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
    float t = u_time;

    vec2 p = (gl_FragCoord.xy * 2.0 - r) / r.y / 0.7;
    vec2 d = vec2(-1.0, 1.0);
    vec2 grav = d / (0.1 + 5.0 / dot(5.0 * p - d, 5.0 * p - d));
    vec2 c = p * mat2(1.0, 1.0, grav.x, grav.y);
    vec2 v = c;

    float angle = log(length(v)) + t * 0.2;
    v *= mat2(cos(angle), cos(angle + 33.0), cos(angle + 11.0), cos(angle)) * 5.0;

    for (int ii = 1; ii <= 9; ii++) {
        float i = float(ii);
        o += sin(vec4(v.x, v.y, v.y, v.x)) + 1.0;
        v += 0.7 * sin(vec2(v.y, v.x) * i + t) / i + 0.5;
    }

    vec2 sv = sin(v / 0.3) * 0.2 + c * vec2(1.0, 2.0);
    float ring = pow(length(sv) - 1.0, 2.0);
    float rim = 0.03 + abs(length(p) - 0.7);
    float glow = 1.0 + 7.0 * exp(0.3 * c.y - dot(c, c));

    o = 1.0 - exp(-exp(c.x * vec4(0.6, -0.4, -1.0, 0.0)) / o / (0.1 + 0.1 * ring) / glow / rim * 0.2);

    gl_FragColor = vec4(o.rgb, 1.0);
}