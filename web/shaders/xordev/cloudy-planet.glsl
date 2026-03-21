#extension GL_OES_standard_derivatives : enable
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

    vec3 dir = (gl_FragCoord.xyz * 2.0 - vec3(r.x, r.y, r.y)) / r.y;
    float z = 0.0;
    for (int ii = 1; ii <= 100; ii++) {
        float i = float(ii);
        vec3 p = z * dir;
        vec3 c = p;
        p.z += 8.0;
        c.z *= 3.0;
        float f = 1.0;
        for (int fi = 2; fi <= 9; fi++) {
            f = float(fi);
            c += sin(c.yzx * f + z + t * 0.5) / f;
        }
        float cloud = 0.1 + abs(0.2 * c.y + abs(p.y + 0.8));
        float d = max(length(p) - 3.0, 0.9 - length(p - vec3(-1.0, 1.0, 3.0)));
        z += min(cloud, d) / 7.0;
        o += vec4(4.0, 6.0, 8.0 + z, 0.0) / max(cloud, 0.001) - min(dFdx(z) * r.y + z, 0.0) / exp(d * d / 0.1);
    }

    o = tanh_safe(o / 2e3);

    gl_FragColor = vec4(o.rgb, 1.0);
}