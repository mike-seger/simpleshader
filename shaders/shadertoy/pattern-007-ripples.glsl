/*
    Source: https://www.shadertoy.com/view/fc23Wc
    The license if not specified by the author is assumed to be:
    This work is licensed under a Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License.
    
    Please see the original shader for comments and description. 

    This is a slightly modified copy of the shader code, with only minor edits to make it compatible with SimpleShader 
    (e.g. renaming mainImage to main, stubbing iChannel0, etc.). If you intend to reuse this shader, please add credits to 'PAEz'.
*/
precision highp float;

uniform vec2  u_resolution;
uniform float u_time;

// tanh() is not available in GLSL ES 1.00
vec4 tanh4(vec4 x) {
    vec4 e2x = exp(2.0 * x);
    return (e2x - 1.0) / (e2x + 1.0);
}

void main() {
    vec3 rayPosition;
    vec3 rayDirection = normalize(vec3(gl_FragCoord.xy + gl_FragCoord.xy - u_resolution, -u_resolution.y));
    vec3 rotationAxis = normalize(tan(u_time * 0.06 + vec3(0.5, -1.5, 2.5)));

    float totalDistance = 23.0;
    float volumeValue = 0.0;

    gl_FragColor = vec4(0.0);

    for (int i = 1; i <= 55; i++) {
        // Raymarching: depth-scaled movement with temporal jittering
        rayPosition = rayDirection * totalDistance;
        rayPosition.z += 26.0;
        rayPosition = reflect(rayPosition, rotationAxis);

        // Fractal domain warping: log-spherical displacement mapping
        // Inner loop runs only once (1.0 -> 31.2 > 17.0), so inlined at innerIteration = 1.0
        float t = u_time * 1.4;
        rayPosition.zy += cos(rayPosition.xz + t);
        rayPosition.x  += sin(rayPosition.y * 1.2 + t) * 0.3;

        // Volume evaluation: oscillating shell density mimicking biological pulses
        volumeValue = pow(abs(sin(length(rayPosition) * 4.0 - u_time)), 6.0) * 2.4 + 0.05;

        gl_FragColor += (0.2 + 1.3 * sin(vec4(0.0, 4.0, 2.5, 0.0) + length(rayPosition))) / (volumeValue * 16.0)
           + vec4(0.7, 1.0, 0.8, 0.0) * (0.005 / (volumeValue * volumeValue));

        totalDistance += volumeValue * 0.07;
    }

    gl_FragColor = tanh4(gl_FragColor / 100.0);
    gl_FragColor.a = 1.0;
}
