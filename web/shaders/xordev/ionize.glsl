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
    float z = 0.001;
    float d = 0.0;
    float s = 0.0;

    for (int ii = 1; ii <= 100; ii++) {
        float i = float(ii);
        vec3 p = z * normalize(gl_FragCoord.xyz * 2.0 - vec3(u_resolution.x, u_resolution.y, u_resolution.y));
        p.z += 9.0;
        vec3 v = p;

        // Inner loop: d doubles each step (1, 2, 4, 8)
        d = 1.0;
        for (int jj = 0; jj < 4; jj++) {
            p += 0.5 * sin(p.yzx * d + u_time) / d;
            d += d;
        }

        s = dot(cos(p), sin(p / 0.7).yzx);
        d = 6.0 - length(v);
        d = 0.2 * (0.01 + abs(s) - min(d, -d * 0.1));
        d = max(d, 0.0001);
        z += d;
        o += (cos(s / 0.1 + z + u_time + vec4(2.0, 4.0, 5.0, 0.0)) + 1.2) / d / max(z, 0.0001);
    }

    o = tanh_safe(o / 2000.0);

    gl_FragColor = vec4(o.rgb, 1.0);
}