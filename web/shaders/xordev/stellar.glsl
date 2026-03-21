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
    vec3 v = vec3(0.0);
    float z = 0.0;
    float d = 0.0;
    float l = 0.0;

    for (int ii = 0; ii < 100; ii++) {
        // Body
        p = z * (gl_FragCoord.xyz * 2.0 - vec3(r.x, r.y, r.y)) / r.y;
        p.z += 2.0;
        l = length(p);
        v = vec3(atan(p.x, p.z), atan(p.y, length(p.xz)), log(l)) * 8.0 + t;
        d = length(cos(v) + sin(v.yzx + v + t - l)) * l * 0.03;
        z += d;

        // Update
        o += (cos(v.z + l * vec4(3.0, 2.0, 1.0, 0.0)) + 1.0) / d;
    }

    o = tanh_safe(o / 8000.0);

    gl_FragColor = vec4(o.rgb, 1.0);
}