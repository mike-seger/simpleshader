/*
    Source: https://www.shadertoy.com/view/NsVGWh
    The license if not specified by the author is assumed to be:
    This work is licensed under a Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License.
    
    Please see the original shader for comments and description. 

    This is a slightly modified copy of the shader code, with only minor edits to make it compatible with SimpleShader 
    (e.g. renaming mainImage to main, stubbing iChannel0, etc.). If you intend to reuse this shader, please add credits to 'morisil'.
*/
precision highp float;
uniform vec2 u_resolution;
uniform float u_time;

#define iTime u_time
#define iResolution vec3(u_resolution, 1.0)

const int   RIBBON_COUNT = 13;
const float RIBBON_WIDTH = .005;
const float RIBBON_EDGE_WIDTH = .003;
const float RIBBON_EDGE_START = RIBBON_WIDTH - RIBBON_EDGE_WIDTH;
const float SCALE_CHANGE = .9;
const float SCALE_CHANGE_VARIATION = .02;
const float SCALE_CHANGE_SPEED = 1.7;
const float WAVE1_PERIOD = 10.;
const float WAVE1_SPEED  = 3.;
const float WAVE1_IMPACT = .05;
const float WAVE2_PERIOD = 8.;
const float WAVE2_SPEED  = 2.5;
const float WAVE2_IMPACT = .2;


void main() {
    vec4 fragColor;
    vec2 fragCoord = gl_FragCoord.xy;
    vec2 uv = fragCoord / iResolution.xy;
    vec2 st =
        (2.* fragCoord - iResolution.xy)
        / min(iResolution.x, iResolution.y);
    vec3 color = vec3(0);
    for (int i = 0; i < RIBBON_COUNT; i++) {
        st *= (
            SCALE_CHANGE
            + (
                sin(iTime * SCALE_CHANGE_SPEED)
                * SCALE_CHANGE_VARIATION
            )
        );
        float dist = length(st);
        float shapeSpace = abs(
            st.x
            + sin(st.y * WAVE1_PERIOD + iTime * WAVE1_SPEED) * WAVE1_IMPACT * (1.2 - uv.y)
            + sin(st.y * WAVE2_PERIOD + iTime * WAVE2_SPEED) * WAVE2_IMPACT * (1.4 - uv.y)
        );
        float ribbon = smoothstep(
            RIBBON_WIDTH,
            RIBBON_EDGE_START,
            shapeSpace
        );
        color += vec3(ribbon);
    }

    fragColor = vec4(color, 1);
    gl_FragColor = fragColor;
}
