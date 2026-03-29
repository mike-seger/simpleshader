/*
    Built by @XorDev
    https://fragcoord.xyz/
*/

precision highp float;
uniform vec2 u_resolution;
uniform float u_time;

vec4 tanhv4(vec4 x) {
    vec4 e = exp(2.0 * clamp(x, -10.0, 10.0));
    return (e - 1.0) / (e + 1.0);
}

void main() {
    vec4 o = vec4(0.0);
    for (float i = 0.0; i < 1.0; i += 0.01) {
        vec2 p = (gl_FragCoord.xy * 2.0 - u_resolution) / u_resolution.y * i;
        float z = max(1.0 - dot(p, p), 0.0);
        p /= 0.2 + sqrt(z) * 0.3;
        p.y += fract(ceil(p.x = p.x / 0.9 + u_time) * 0.5) + u_time * 0.2;
        vec2 v = abs(fract(p) - 0.5);
        o += vec4(2, 3, 5, 1) / 2e3 * z / (abs(max(v.x * 1.5 + v, v + v).y - 1.0) + 0.1 - i * 0.09);
    }
    gl_FragColor = tanhv4(o * o);
}
