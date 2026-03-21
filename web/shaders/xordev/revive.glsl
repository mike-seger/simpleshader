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

    for (int ii = 1; ii <= 100; ii++) {
        float i = float(ii);
        vec3 p = z * normalize(gl_FragCoord.xyz * 2.0 - vec3(u_resolution.x, u_resolution.y, u_resolution.x));
        p.y -= 7.0;
        vec3 P = vec3(atan(p.y, p.x) * 3.0, p.z * 0.3, length(p.xy) - 11.0);

        for (int jj = 1; jj <= 8; jj++) {
            float dj = float(jj);
            P += sin(P.yzx * dj + 0.1 * z - u_time) / dj;
        }

        d = length(vec4(P.z * 5.0, cos(P) - 1.0)) / 20.0;
        d = max(d, 0.0001);
        z += d;
        o += (1.2 - sin(u_time + z / vec4(8.0, 7.0, 6.0, 0.0))) / d;
    }

    o = tanh_safe(o / 1000.0);

    gl_FragColor = vec4(o.rgb, 1.0);
}