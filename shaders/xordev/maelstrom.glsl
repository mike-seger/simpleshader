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

    float z = 0.001;
    float d = 0.0;

    for (int ii = 0; ii < 90; ii++) {
        float i = float(ii) + 1.0;
        vec3 p = z * normalize(gl_FragCoord.xyz * 2.0 - vec3(r.x, r.y, r.x));
        p = vec3(atan(p.y, p.x), p.z / 8.0 - t, length(p.xy) - 9.0);

        for (int jj = 1; jj <= 7; jj++) {
            d = float(jj);
            p += sin(p.yzx * d + t + i * 0.2) / d;
        }

        d = 0.2 * length(vec4(0.2 * cos(6.0 * p) - 0.2, p.z));
        d = max(d, 0.001);
        z += d;
        o += (cos(p.x + vec4(0.0, 0.5, 1.0, 0.0)) + 1.0) / d / max(z, 0.001);
    }

    o = tanh_safe(o * o / 300.0);

    gl_FragColor = vec4(o.rgb, 1.0);
}