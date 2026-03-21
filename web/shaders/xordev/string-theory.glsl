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

    vec3 p = vec3(0.0);
    float z = 0.0;
    float d = 0.0;

    for (int ii = 0; ii < 100; ii++) {
        // Body
        p = z * normalize(gl_FragCoord.xyz * 2.0 - vec3(r.x, r.y, r.y));
        p.z -= t;
        float a = z * 0.2 + t * 0.1;
        p.xy *= mat2(cos(a), cos(a + 33.0), cos(a + 11.0), cos(a));
        d = length(cos(p + cos(p.yzx + p.z - t * 0.2)).xy) / 6.0;
        z += d;

        // Update
        o += (sin(p.x + t + vec4(0.0, 2.0, 3.0, 0.0)) + 1.0) / d;
    }

    o = tanh_safe(o / 5000.0);

    gl_FragColor = vec4(o.rgb, 1.0);
}