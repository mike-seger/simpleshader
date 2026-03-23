precision highp float;

uniform vec2  u_resolution;
uniform float u_time;

// @lil-gui-start
const float NUM_X        = 32.0;  // @range(1.0, 128.0, 1)
const float NUM_Y        = 18.0;  // @range(1.0, 128.0, 1)
const float FRAME_WIDTH  = 0.05;  // @range(0.0, 0.3, 0.005)
const float LINE_W       = 0.0; // @range(0.0, 0.02, 0.001)
const vec4  LINE_H_COLOR = vec4(0.4392, 0.4392, 0.4392, 1.0); // horizontal line color + opacity
const vec4  LINE_V_COLOR = vec4(0.4392, 0.4392, 0.4392, 1.0); // vertical line color + opacity
const int   PALETTE      = 0;   // @range(0, 5, 1)  0=Rainbow 1=Neon 2=Pastel 3=Ocean 4=Sunset 5=Mono
const float PLASMA_SPEED = 1.82; // @range(0.0, 8.0, 0.01)
// @lil-gui-end

// @include ../lib/palette.glsl
// @include ../lib/grid.glsl
// @include ../lib/plasma.glsl

// @pass cell size=NUM_X,NUM_Y
// Runs at NUM_X × NUM_Y resolution — one fragment per cell.
// u_resolution = vec2(NUM_X, NUM_Y); gl_FragCoord centres map to cell-centre UVs.
void main() {
    vec2 uv = gl_FragCoord.xy / u_resolution;   // cell-centre UV [0,1]²
    gl_FragColor = vec4(getPaletteColor(plasma(uv, u_time * PLASMA_SPEED), PALETTE), 1.0);
}

// @pass composite
// Full-resolution pass. Samples cell colours from u_channel0 (NUM_X × NUM_Y
// texture written by the cell pass) then composites the grid lines on top.
void main() {
    vec2 res = u_resolution;

    vec4 rect = framedRect(0.0, 0.0, res.x, res.y, FRAME_WIDTH, NUM_X, NUM_Y);

    GridParams p;
    p.rect       = rect;
    p.dx         = rect.z / NUM_X;
    p.dy         = rect.w / NUM_Y;
    p.lineWidth  = LINE_W;
    p.lineHColor = LINE_H_COLOR.rgb;
    p.lineVColor = LINE_V_COLOR.rgb;
    p.lineHAlpha = LINE_H_COLOR.a;
    p.lineVAlpha = LINE_V_COLOR.a;

    vec2 fc = gl_FragCoord.xy;

    // Look up the pre-computed cell colour from pass 0
    vec3 cells = vec3(0.0);
    if (fc.x >= rect.x && fc.x <= rect.x + rect.z &&
        fc.y >= rect.y && fc.y <= rect.y + rect.w) {
        float cellX = floor((fc.x - rect.x) / p.dx);
        float cellY = floor((fc.y - rect.y) / p.dy);
        vec2 cellUV = (vec2(cellX, cellY) + 0.5) / vec2(NUM_X, NUM_Y);
        cells = texture2D(u_channel0, cellUV).rgb;
    }

    vec4 grid = drawGrid(p);
    gl_FragColor = vec4(mix(cells, grid.rgb, grid.a), 1.0);
}
