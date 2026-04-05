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
    // Dither to reduce banding
    float z = fract(dot(gl_FragCoord.xy, sin(gl_FragCoord.xy)));
    float d = 0.0;

    for (int ii = 1; ii <= 100; ii++) {
        float i = float(ii);
        vec3 p = z * normalize(gl_FragCoord.xyz * 2.0 - vec3(u_resolution.x, u_resolution.y, u_resolution.y));
        p.z += 6.0;

        d = 1.0;
        for (int jj = 0; jj < 30; jj++) {
            if (d >= 9.0) break;
            p += cos(p.yzx * d - u_time) / d;
            d /= 0.8;
        }

        d = 0.002 + abs(length(p) - 0.5) / 40.0;
        z += d;
        o += (sin(z - u_time + vec4(6.0, 2.0, 4.0, 0.0)) + 1.5) / d;
    }

    o = tanh_safe(o / 7000.0);

    gl_FragColor = vec4(o.rgb, 1.0);
}