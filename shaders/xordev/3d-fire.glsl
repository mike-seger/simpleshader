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
    float z = 0.001;
    float d = 0.0;

    for (int ii = 1; ii <= 50; ii++) {
        float i = float(ii);
        vec3 p = z * normalize(gl_FragCoord.xyz * 2.0 - vec3(u_resolution.x, u_resolution.y, u_resolution.y));
        p.z += 5.0 + cos(u_time);

        // Rotation matrix from cos(t + p.y*.5 + vec4(0,33,11,0))
        float angle = u_time + p.y * 0.5;
        float c0 = cos(angle);
        float c1 = cos(angle + 33.0);
        float c2 = cos(angle + 11.0);
        float c3 = cos(angle);  // vec4(0,33,11,0) → 4th is same as 1st
        float scale = max(p.y * 0.1 + 1.0, 0.1);
        p.xz = mat2(c0, c2, c1, c3) * p.xz / scale;

        // Fractal displacement: j starts at 2, multiplied by 1/0.6 each step
        float j = 2.0;
        for (int jj = 0; jj < 15; jj++) {
            if (j >= 15.0) break;
            p += cos((p.yzx - vec3(u_time, 0.0, 0.0) / 0.1) * j + u_time) / j;
            j /= 0.6;
        }

        d = 0.01 + abs(length(p.xz) + p.y * 0.3 - 0.5) / 7.0;
        z += d;
        o += (sin(z / 3.0 + vec4(7.0, 2.0, 3.0, 0.0)) + 1.1) / d;
    }

    o = tanh_safe(o / 1000.0);

    gl_FragColor = vec4(o.rgb, 1.0);
}