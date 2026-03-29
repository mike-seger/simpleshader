/*
    Source: https://www.shadertoy.com/view/wtt3RX
    The license if not specified by the author is assumed to be:
    This work is licensed under a Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License.
    
    Please see the original shader for comments and description. 

    This is a slightly modified copy of the shader code, with only minor edits to make it compatible with SimpleShader 
    (e.g. renaming mainImage to main, stubbing iChannel0, etc.). If you intend to reuse this shader, please add credits to 'dtsmio'.
*/
precision highp float;
uniform vec2 u_resolution;
uniform float u_time;

#define iTime u_time
#define iResolution vec3(u_resolution, 1.0)

vec3 paletteColor(int idx) {
    if (idx == 0) return vec3(53.0, 80.0, 112.0);
    if (idx == 1) return vec3(109.0, 89.0, 122.0);
    if (idx == 2) return vec3(181.0, 101.0, 118.0);
    if (idx == 3) return vec3(229.0, 107.0, 111.0);
    return vec3(234.0, 172.0, 139.0);
}

void main()
{
    vec4 fragColor;
    vec2 fragCoord = gl_FragCoord.xy;
    vec2 uv = fragCoord/iResolution.xy;
    float aspect = iResolution.x / iResolution.y;
    uv.x *= aspect;
    
    float t = iTime * 0.25;

    float background_value = 40.0 / 255.0;
    vec3 color = vec3(background_value);

    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        // The wave's equation
        float line = 0.5 + 0.3 * sin(3.0 * t + 2.0 * uv.x + 0.3 * fi) * sin(2.0 * t + uv.x);
        // The width of the ribbon
        float width = 1.4 * (0.14 + (0.12 * sin(1.5 * t + sin(0.5 * t) * 1.5 * uv.x + fi) * sin(0.5 * t + 0.5 * uv.x)));
        float lineRatio = (5.0 - fi) / 5.0;
        float space = 0.3 * sin(1.0 * t + 2.0 * uv.x) * lineRatio;
        // The distance to the wave
        float dist = abs(uv.y - line + space) - width * lineRatio * 0.5;
        float shadow_drop = 20.0 / (abs(space) + 0.1);
        if (dist > 0.0) {
            color *= vec3(mix(0.75, 1.0, 1.0 - exp(-shadow_drop * dist)));
        } else {
            color = paletteColor(i) / 255.0;
        }
    }
    
    fragColor = vec4(color, 1.0);
    gl_FragColor = fragColor;
}
