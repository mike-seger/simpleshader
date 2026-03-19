precision highp float;

uniform vec2 u_resolution;
uniform float u_time;

float tanh_safe(float x) {
    float cx = clamp(x, -10.0, 10.0);
    float e2 = exp(2.0 * cx);
    return (e2 - 1.0) / (e2 + 1.0);
}

vec4 tanh_safe(vec4 x) {
    vec4 cx = clamp(x, -10.0, 10.0);
    vec4 e2 = exp(2.0 * cx);
    return (e2 - 1.0) / (e2 + 1.0);
}

void main() {
    vec4 o = vec4(0.0);
    vec2 r = u_resolution;
    float t = u_time;

    vec3 x = vec3(0.0);
    vec3 c = vec3(0.0);
    vec3 p = vec3(0.0);
    x.x += 9.0;

    float z = 0.0;
    float f = 0.0;

    for (int ii = 0; ii < 50; ii++) {
        float i = float(ii) + 1.0;

        // Inner loop init
        c = z * normalize(gl_FragCoord.xyz * 2.0 - vec3(r.x, r.y, r.y));
        p = c;
        f = 0.3;
        p.y *= f;

        // Inner loop: 5 iterations with f = 1.3, 2.3, 3.3, 4.3, 5.3
        for (int jj = 0; jj < 5; jj++) {
            f += 1.0;
            p += cos(p.yzx * f + i + z + x * t) / f;
        }

        // Outer update
        p = mix(c, p, 0.3);
        f = 0.2 * (abs(p.z + p.x + 16.0 + tanh_safe(p.y) / 0.1) + sin(p.x - p.z + t + t) + 1.0);
        z += f;
        o += (cos(p.x * 0.2 + f + vec4(6.0, 1.0, 2.0, 0.0)) + 2.0) / f / z;
    }

    o = tanh_safe(o / 30.0);

    gl_FragColor = vec4(o.rgb, 1.0);
}