/*
    Source: https://www.shadertoy.com/view/7fj3DK
    The license if not specified by the author is assumed to be:
    This work is licensed under a Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License.
    
    Please see the original shader for comments and description. 

    This is a slightly modified copy of the shader code, with only minor edits to make it compatible with SimpleShader 
    (e.g. renaming mainImage to main, stubbing iChannel0, etc.). If you intend to reuse this shader, please add credits to 'msttezcan'.
*/
precision highp float;

uniform vec2  u_resolution;
uniform float u_time;

float tanh1(float x) {
    float e2x = exp(2.0 * x);
    return (e2x - 1.0) / (e2x + 1.0);
}

vec4 tanh4(vec4 x) {
    vec4 e2x = exp(2.0 * x);
    return (e2x - 1.0) / (e2x + 1.0);
}

void main() {
    float s, d;
    float T = u_time * 0.5;

    vec2 uv = (gl_FragCoord.xy - u_resolution * 0.5) / u_resolution.y
              + vec2(sin(T * 0.2) * 0.3, sin(T * 0.5) * 0.1);
    gl_FragColor = vec4(0.0);

    float tanhT  = tanh1(T);
    float px_off = 1e2 - cos(T) * 1e1 + sin(T) * 1e1;
    float sinT   = sin(T);

    for (int i = 0; i < 64; i++) {
        vec3 p = vec3(uv * d, d + T * 1e2);
        p.z += 1.41421356 * sin(p.z * 0.7 + 0.78539816) + tanhT;
        p.x += px_off;
        p += cos(p.yzx / 16.0) * 16.0 + sin(p.yzx / 32.0) * 8.0;
        s = 0.005 + 0.8 * abs(32.0 * dot(sin(p / 132.0), cos(p.yzx / 94.0) + sin(p.yzx / 43.0)));
        d += s;
        gl_FragColor += (1.0 + cos(0.03 * p.y + vec4(3.0, 1.0, 0.0, 0.0))) / s + sinT;
    }
    gl_FragColor = tanh4(gl_FragColor / 3e3);
    gl_FragColor.a = 1.0;
}
