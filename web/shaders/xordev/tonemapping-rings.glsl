precision highp float;

uniform vec2 u_resolution;
uniform float u_time;

float hash(float n) {
    return fract(sin(n) * 43758.5453);
}

vec3 neonColor(float id) {
    float h = hash(id * 17.3) * 6.28;
    return 0.5 + 0.5 * cos(h + vec3(0.0, 2.09, 4.18));
}

void main() {
    vec2 uv = (gl_FragCoord.xy - 0.5 * u_resolution.xy) / u_resolution.y;
    vec3 col = vec3(0.0);

    // Background gradient
    col += mix(vec3(0.02, 0.02, 0.06), vec3(0.06, 0.02, 0.08), uv.y + 0.5);

    for (int i = 0; i < 12; i++) {
        float id = float(i);

        // Random ring properties from id
        float size = 0.08 + hash(id * 7.1) * 0.35;
        float speed = 0.15 + hash(id * 3.7) * 0.25;
        float phase = hash(id * 13.3) * 6.28;

        // Orbit: each ring drifts on its own path
        vec2 center = vec2(
            sin(u_time * speed + phase) * (0.4 + hash(id * 5.9) * 0.5),
            cos(u_time * speed * 0.7 + phase * 1.3) * (0.3 + hash(id * 9.1) * 0.4)
        );

        float dist = length(uv - center);
        float ring = abs(dist - size);

        // Thickness varies per ring
        float thickness = 0.005 + hash(id * 23.7) * 0.008;

        // Sharp ring + soft glow
        float sharp = smoothstep(thickness, 0.0, ring);
        float glow = 0.003 / (ring * ring + 0.001);

        vec3 c = neonColor(id);
        col += c * sharp * 2.0;
        col += c * glow * 0.15;
    }

    // Vignette
    col *= 1.0 - 0.4 * dot(uv, uv);

    // Simple tonemap
    col = col / (col + 1.0);
    col = pow(col, vec3(1.0 / 2.2));

    gl_FragColor = vec4(col, 1.0);
}
