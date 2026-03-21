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
    float t = u_time;
    float c = cos(t), s = sin(t);
    float a = min(u_resolution.x, u_resolution.y);
    float z = -a;
    vec2 f = (2.0 * gl_FragCoord.xy - u_resolution) / a;

    for (int ii = 1; ii <= 100; ii++) {
        float i = float(ii);
        vec3 p = vec3(f.x * c - z * s, f.y, z * c + f.x * s);
        a = length(p.xy) - 0.6;
        float d = 0.01 + 0.3 * abs(sqrt(a * a + p.z * p.z) - 0.3);
        z += d;
        o += (sin(p.x / 0.2 + z / 0.1 + vec4(0.0, 1.0, 2.0, 3.0)) + 1.0) / d;
    }

    o = tanh_safe(o * o / 7e6);

    gl_FragColor = vec4(o.rgb, 1.0);
}