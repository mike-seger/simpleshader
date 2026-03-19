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

    vec3 ray = normalize(gl_FragCoord.xyz * 2.0 - vec3(r.x, r.y, r.x));
    float z = 0.001;
    for (int ii = 1; ii <= 20; ii++) {
        float i = float(ii);
        vec3 p = z * ray;
        p = vec3(atan(p.y, p.x * 0.2) * 2.0, p.z / 3.0, length(p.xy) - 5.0 - z * 0.2);
        for (int di = 1; di < 7; di++)
            p += sin(p.yzx * float(di) + t + 0.3 * i) / float(di);
        float d = length(vec4(0.4 * cos(p) - 0.4, p.z));
        d = max(d, 0.001);
        z += d;
        o += (cos(p.x + i * 0.4 + z + vec4(6.0, 1.0, 2.0, 0.0)) + 1.0) / d;
    }

    o = tanh_safe(o * o / 4e2);

    gl_FragColor = o;
}