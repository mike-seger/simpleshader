/*
    Built by @XorDev
    https://fragcoord.xyz/
*/

precision highp float;

uniform vec2  u_resolution;
uniform float u_time;

vec4 tanh4(vec4 x) {
    vec4 e2x = exp(2.0 * x);
    return (e2x - 1.0) / (e2x + 1.0);
}

void main()
{
    gl_FragColor = vec4(0.0);
    float z = 0.0;
    for(int i = 0; i < 100; i++)
    {
        vec3 p = z * normalize(gl_FragCoord.rgb * 2.0 - vec3(u_resolution, 1.0).xyy);
        p.z -= 5.0 * u_time;
        p.xy *= mat2(cos(z * 0.1 + u_time * 0.1 + vec4(0, 33, 11, 0)));
        float d = 1.0;
        for(int j = 0; j < 8; j++) {
            p += cos(p.yzx * d + u_time) / d;
            d /= 0.7;
            if (d >= 9.0) break;
        }
        d = 0.02 + abs(2.0 - dot(cos(p), sin(p.yzx * 0.6))) / 8.0;
        z += d;
        gl_FragColor += vec4(z / 7.0, 2.0, 3.0, 1.0) / d;
    }
    gl_FragColor = tanh4(gl_FragColor * gl_FragColor / 1e7);
    gl_FragColor.a = 1.0;
}