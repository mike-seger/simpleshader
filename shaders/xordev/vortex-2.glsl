/*
    Built by @XorDev
    https://fragcoord.xyz/
*/

precision highp float;

uniform vec2 u_resolution;
uniform float u_time;

#define PI  3.14159265359
#define PI2 6.28318530718

vec4 tanh_safe(vec4 x) {
    vec4 cx = clamp(x, -10.0, 10.0);
    vec4 e2 = exp(2.0 * cx);
    return (e2 - 1.0) / (e2 + 1.0);
}

void main() {
    vec2 p = (gl_FragCoord.xy * 2.0 - u_resolution) / u_resolution.y;
    vec4 o = vec4(0.0);

    for (int ii = 0; ii < 16; ii++) {
        float i = 0.2 + float(ii) * 0.05;
        if (i >= 1.0) break;

        float lp = length(p);
        float angle = mod(atan(p.y, p.x) + i + i * u_time, PI2) - PI;

        vec2 v = vec2(angle, 1.0) * lp - i;

        // v.x += i then clamp(v.x, -i, i) then v.x -= that
        float vx_plus_i = v.x + i;
        v.x -= clamp(vx_plus_i, -i, i);

        float l = length(v) + 0.003;
        o += (cos(i * 5.0 + vec4(0.0, 1.0, 2.0, 3.0)) + 1.0) * (1.0 + v.y / l) / l / 100.0;
    }

    o = tanh_safe(o);

    gl_FragColor = vec4(o.rgb, 1.0);
}