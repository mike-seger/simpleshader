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

    vec3 c = vec3(0.0);
    vec3 p = vec3(0.0);
    float z = 0.0;
    float f = 0.0;
    float l = 0.001;

    for (int ii = 0; ii < 60; ii++) {
        // Inner loop init
        c = z * normalize(gl_FragCoord.xyz * 2.0 - vec3(r.x, r.y, r.y));
        p = c;
        p.z -= t / 0.2;
        c.z += 9.0;
        f = 0.0;

        // Inner loop: 7 iterations with f = 1..7
        for (int jj = 0; jj < 7; jj++) {
            f += 1.0;
            p += sin(p * f + z * 0.2 + 1.0 / l).yzx / f;
        }

        // Outer update
        f = 8.0 - length((c + p).xy);
        float maxVal = max(f, -f * 0.2);
        l = length(c + 4.0 * sin(t + vec3(0.0, 8.0, 4.0)));
        f = 0.01 + min(maxVal, l) / 7.0;
        z += f;
        o += vec4(5.0, 1.0, l, 1.0) / l / l / f / z;
    }

    o = tanh_safe(o / 300.0);

    gl_FragColor = vec4(o.rgb, 1.0);
}