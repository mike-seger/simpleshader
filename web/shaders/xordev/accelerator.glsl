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

    for (int ii = 1; ii <= 80; ii++) {
        float i = float(ii);
        vec3 p = z * normalize(gl_FragCoord.xyz * 2.0 - vec3(u_resolution.x, u_resolution.y, u_resolution.y));
        p.z += 9.0;

        vec3 a = vec3(0.57);
        a = dot(a, p) * a * cross(a, p);
        s = sqrt(length(a.xz - a.y - 0.8));

        // Inner loop: d++ < 9 means body runs with d = 3..9
        for (int jj = 3; jj <= 9; jj++) {
            float dj = float(jj);
            a += sin(floor(a * dj + 0.5) - u_time).yzx / dj;
        }

        d = length(sin(a / 0.1)) * s / 20.0;
        d = max(d, 0.0001);
        z += d;
        float sg = max(s, 0.0001);
        o += vec4(s, 2.0, z, 1.0) / sg / d;
    }

    o = tanh_safe(o / 4000.0);

    gl_FragColor = vec4(o.rgb, 1.0);
}
