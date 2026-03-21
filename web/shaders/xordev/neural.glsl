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
        // Body (executed before the increment expression)
        p = z * (gl_FragCoord.xyz * 2.0 - vec3(r.x, r.y, r.y)) / r.y;
        p.z += 1.0;
        l = length(p);
        float lsafe = max(l, 0.0001);
        v = p / lsafe / lsafe * 5.0 + t * 3.0;
        d = (dot(cos(v), sin(v.yzx + 0.7)) + 1.8) / 40.0;
        d = max(d, 0.0001);
        z += d;

        // Increment expression (uses l and d from current iteration)
        o += (cos(9.0 / lsafe + vec4(6.0, 1.0, 2.0, 3.0)) + 1.0) / d;
    }

    o = tanh_safe(o / 10000.0);

    gl_FragColor = vec4(o.rgb, 1.0);
}