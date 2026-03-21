#extension GL_OES_standard_derivatives : enable
precision highp float;

uniform vec2 u_resolution;
uniform float u_time;

float tanh_safe(float x) {
    float cx = clamp(x, -10.0, 10.0);
    float e2 = exp(2.0 * cx);
    return (e2 - 1.0) / (e2 + 1.0);
}

void main() {
    vec2 p = gl_FragCoord.xy / u_resolution.y * 20.0 + u_time;

    for (int ii = 1; ii <= 8; ii++) {
        float i = float(ii);
        p += sin(p + u_time / 0.2 + i) * 0.4;
        // mat2(6,-8,8,6)/9 = rotation+scale matrix
        p = mat2(6.0, -8.0, 8.0, 6.0) / 9.0 * p;
    }

    vec2 s = sin(p * 0.3) / 0.1;
    float caustic = tanh_safe(length(fwidth(s)));

    // Original uses texture(b, ...) for background - use a blue water tint instead
    vec3 water = vec3(0.0, 0.15, 0.3);
    vec3 col = mix(water, vec3(0.6, 0.85, 1.0), caustic);

    gl_FragColor = vec4(col, 1.0);
}
