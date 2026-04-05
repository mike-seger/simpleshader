/*
    Source: https://www.shadertoy.com/view/t3BXWd
    The license if not specified by the author is assumed to be:
    This work is licensed under a Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License.
    
    Please see the original shader for comments and description. 

    This is a slightly modified copy of the shader code, with only minor edits to make it compatible with SimpleShader 
    (e.g. renaming mainImage to main, stubbing iChannel0, etc.). If you intend to reuse this shader, please add credits to 'microbe'.
*/
precision highp float;
uniform vec2 u_resolution;
uniform float u_time;

#define iTime u_time
#define iResolution vec3(u_resolution, 1.0)

#define NUM_LINES 12
#define AMPLITUDE 0.15
#define LINE_THICKNESS 0.012
#define USE_AUDIO 0  // Set to 1 to enable audio reactivity (requires iChannel0)


float getAudioLevel(float band) {
    return 0.0; // iChannel0 not available
}

float seismoWave(float x, float time, float lineOffset) {
    float freq = 3.0 + sin(time * 0.5 + lineOffset) * 2.0;
    float t = x * freq + time + lineOffset * 2.0;

    float baseWave = sin(t * 3.1415) * sin(t * 0.5) + sin(t * 2.5);
    baseWave += 0.3 * sin(t * 7.0 + sin(time + lineOffset * 3.0));

    float amp = AMPLITUDE;

#if USE_AUDIO
    float band = lineOffset / float(NUM_LINES);
    amp += 0.5 * getAudioLevel(band);
#endif

    baseWave *= (0.3 + 0.7 * sin(time * 0.25 + lineOffset * 1.3));
    return baseWave * amp;
}

vec3 getLineColor(int i, float time) {
    float baseHue = float(i) / float(NUM_LINES);
    float brightness = 0.8 + 0.2 * sin(time * 0.6 + float(i));

#if USE_AUDIO
    float band = float(i) / float(NUM_LINES);
    brightness += 0.4 * getAudioLevel(band);
#endif

    vec3 color = vec3(0.5 + 0.5 * sin(6.2831 * (baseHue + vec3(0.0, 0.33, 0.67))));
    return color * brightness;
}

void main() {
    vec4 fragColor;
    vec2 fragCoord = gl_FragCoord.xy;
    vec2 uv = fragCoord.xy / iResolution.xy;
    uv.y -= 0.5;
    uv.x = (uv.x - 0.5) * (iResolution.x / iResolution.y);
    
    vec3 col = vec3(0.0);
    float time = iTime;

    for (int i = 0; i < NUM_LINES; i++) {
        float lineOffset = float(i);
        float wave = seismoWave(uv.x, time, lineOffset);
        float y = -0.5 + float(i) / float(NUM_LINES);
        
        float dist = abs(uv.y - (y + wave));
        float alpha = smoothstep(LINE_THICKNESS, 0.0, dist);
        col += getLineColor(i, time) * alpha;
    }

    fragColor = vec4(col, 1.0);
    gl_FragColor = fragColor;
}
