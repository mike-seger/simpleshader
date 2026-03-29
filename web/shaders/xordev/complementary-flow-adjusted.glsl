/*
    Built by @XorDev
    https://fragcoord.xyz/
*/

precision highp float;

uniform vec2 u_resolution;
uniform float u_time;

#define COLOR_0 vec3(1.000, 0.525, 0.000)
#define COLOR_1 (1.0 - COLOR_0)

vec2 curve(float t, float k)
{
    return vec2(sin(t) - cos(t + k), cos(3.0 * t) + sin(4.0 * -k)) * 0.5;
}

#define desat(x) vec3(dot(x, vec3(0.2126, 0.7152, 0.0722)))

vec3 tonemap(vec3 c)
{
    vec3 g = desat(c);
    c = mix(g / (g + 1.0), c / (c + 1.0), exp2(-g * 0.2));
    return c;
}

void main()
{
    vec2 uv = (gl_FragCoord.xy * 2.0 - u_resolution.xy) / u_resolution.y;

    // Simulate temporal trail by sampling multiple past time steps
    vec3 color = vec3(0.0);
    float trail_length = 3.0;
    int steps = 120;

    for (int i = 0; i < 120; i++) {
        float age = float(i) / float(steps) * trail_length;
        float decay = exp(-age * 2.5);

        float t = max(0.0001, u_time - age) * 0.5;
        float k = max(0.0001, u_time - age) * 0.25;

        float p0 = 0.3 / distance(uv, curve(t, k));
        float p1 = 0.3 / distance(uv, curve(t + 0.5, k + 0.5));

        color += (COLOR_0 * p0 + COLOR_1 * p1) * decay / float(steps);
    }

    color *= trail_length * 1.5;

    // Image pass: tonemap + gamma
    vec3 c = tonemap(pow(color, vec3(3.0)));
    c = pow(c, vec3(1.0 / 2.2));

    gl_FragColor = vec4(c, 1.0);
}
