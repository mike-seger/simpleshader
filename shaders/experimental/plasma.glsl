precision highp float;

uniform vec2  u_resolution;
uniform float u_time;

// @lil-gui-start
const int   PALETTE      = 0;   // @range(0, 5, 1)  0=Rainbow 1=Neon 2=Pastel 3=Ocean 4=Sunset 5=Mono
const float PLASMA_SPEED = 1.0; // @range(0.0, 8.0, 0.01)
// @lil-gui-end

// @include ../lib/palette.glsl
// @include ../lib/plasma.glsl

void main() {
    vec2 uv = gl_FragCoord.xy / u_resolution;
    gl_FragColor = vec4(getPaletteColor(plasma(uv, u_time * PLASMA_SPEED), PALETTE), 1.0);
}
