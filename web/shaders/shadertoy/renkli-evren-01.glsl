/*
    Source: https://www.shadertoy.com/view/sfB3zd
    The license if not specified by the author is assumed to be:
    This work is licensed under a Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License.
    
    Please see the original shader for comments and description. 

    This is a slightly modified copy of the shader code, with only minor edits to make it compatible with SimpleShader 
    (e.g. renaming mainImage to main, stubbing iChannel0, etc.). If you intend to reuse this shader, please add credits to 'msttezcan'.
*/
precision highp float;
uniform vec2 u_resolution;
uniform float u_time;

vec2 tanhv(vec2 x) {
    vec2 e = exp(2.0 * clamp(x, -10.0, 10.0));
    return (e - 1.0) / (e + 1.0);
}

void main() {
    vec2 v = u_resolution, 
         w,
         u = gl_FragCoord.xy,
         k = u = 0.2 * (u + u - v) / v.y;

    vec4 o = vec4(1, 2, 3, 0);

    float a = 0.5;
    float t = u_time;
    for (float i = 1.0; i < 19.0; i += 1.0) {
        t += 1.0;
        a += 0.03;
        v = cos(t - 7.0 * u * pow(a, i)) - 5.0 * u;
        u *= mat2(cos(i + t * 0.02 - vec4(0, 11, 33, 0)));
        u += 0.005 * tanhv(40.0 * dot(u, u) * cos(1e2 * u.yx + t))
           + 0.2 * a * u
           + 0.003 * cos(t + 4.0 * exp(-0.01 * dot(o, o)));
        w = u / (1.0 - 2.0 * dot(u, u));
        o += (1.0 + cos(vec4(0, 1, 3, 0) + t))
           / length((1.0 + i * dot(v, v)) * sin(w * 3.0 - 9.0 * u.yx + t));
    }

    o = pow(o = 1.0 - sqrt(exp(-o * o * o / 2e2)), 0.3 * o / o)
      - dot(k -= u, k) / 250.0;

    gl_FragColor = vec4(o.rgb, 1.0);
}
