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
    float s = 0.0;

    for (int ii = 1; ii <= 70; ii++) {
        float i = float(ii);
        vec3 p = z * normalize(gl_FragCoord.xyz * 2.0 - vec3(u_resolution.x, u_resolution.y, u_resolution.y));
        p.z += 9.0;

        vec3 a = vec3(0.0);
        a -= 0.57;
        s -= u_time;
        a = mix(dot(a, p) * a, p, cos(s)) - sin(s) * cross(a, p);
        s = sqrt(max(length(a.xz - a.y), 0.0));

        for (int jj = 2; jj <= 9; jj++) {
            float dj = float(jj);
            a += sin(a * dj - u_time).yzx / dj;
        }

        d = length(sin(a) + (a.x + a.y + a.z) * 0.2) * s / 20.0;
        d = max(d, 0.0001);
        z += d;
        float sg = max(s, 0.0001);
        o += vec4(z, 2.0, s, 1.0) / sg / d;
    }

    o = tanh_safe(o / 2000.0);

    gl_FragColor = vec4(o.rgb, 1.0);
}