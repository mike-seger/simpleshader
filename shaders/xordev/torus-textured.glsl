/*
    Built by @XorDev
    https://fragcoord.xyz/
*/

precision highp float;

uniform vec2 u_resolution;
uniform float u_time;

void main() {
    vec4 o = vec4(0.0);
    float t = u_time;
    float c = cos(t), s = sin(t);
    float a = min(u_resolution.x, u_resolution.y);
    float z = a;
    vec2 f = (gl_FragCoord.xy * 2.0 - u_resolution) / a;

    for (int ii = 0; ii < 1000; ii++) {
        float ti = t + float(ii);
        if (ti >= 1e3) break;
        o = vec4(f.x * c - z * s, f.y, z * c + f.x * s, 1.0);
        a = length(o.xy) - 0.6;
        z -= sqrt(a * a + o.z * o.z) - 0.3;
    }

    o = o * sin(9.0 * (atan(o.x, o.y) + s)) * sin(5.0 * atan(o.z, a)) + 0.1 * z;

    gl_FragColor = vec4(o.rgb, 1.0);
}