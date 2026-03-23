precision highp float;

uniform vec2  u_resolution;
uniform float u_time;

// @lil-gui-start
const float NUM_X        = 40.0;  // @range(1.0, 40.0, 1)
const float NUM_Y        = 16.0;  // @range(1.0, 40.0, 1)
const float FRAME_WIDTH  = 0.05;  // @range(0.0, 0.3, 0.005)
const float LINE_W       = 0.003; // @range(0.001, 0.02, 0.001)
const vec4  LINE_H_COLOR = vec4(0.4392, 0.4392, 0.4392, 1.0); // horizontal line color + opacity
const vec4  LINE_V_COLOR = vec4(0.4392, 0.4392, 0.4392, 1.0); // vertical line color + opacity
// @lil-gui-end

// Returns vec4(x, y, w, h) of the largest inner rectangle that:
//   • sits inside [rx, ry, rw, rh] with at least frameWidth*resolution.y px of margin,
//   • preserves the numX : numY aspect ratio,
//   • is centred within the outer rectangle.
vec4 framedRect(float rx, float ry, float rw, float rh,
                float frameWidth, float numX, float numY) {
    float margin = frameWidth * u_resolution.y;
    float availW = rw - 2.0 * margin;
    float availH = rh - 2.0 * margin;
    float aspect = numX / numY;

    float iw, ih;
    if (availW / availH > aspect) {
        ih = availH;
        iw = ih * aspect;
    } else {
        iw = availW;
        ih = iw / aspect;
    }

    float ix = rx + (rw - iw) * 0.5;
    float iy = ry + (rh - ih) * 0.5;
    return vec4(ix, iy, iw, ih);
}

// Draw a cartesian grid inside rect = vec4(x, y, w, h) (pixel coords, origin bottom-left).
// dx/dy are cell dimensions in pixels; lineWidth is a fraction of screen height.
// Returns the composited grid colour, or vec3(0) when outside the rectangle.
vec3 drawGrid(vec4 rect, float dx, float dy, float lineWidth,
              vec3 lineHColor, vec3 lineVColor,
              float lineHAlpha, float lineVAlpha) {
    vec2 fc = gl_FragCoord.xy;

    // Clip to rectangle
    if (fc.x < rect.x || fc.x > rect.x + rect.z ||
        fc.y < rect.y || fc.y > rect.y + rect.w) return vec3(0.0);

    // Position relative to rectangle origin, in pixels
    float px = fc.x - rect.x;
    float py = fc.y - rect.y;

    // Fractional position within current cell
    float fracX = fract(px / dx);
    float fracY = fract(py / dy);

    // Pixel distance to nearest vertical / horizontal grid line
    float distV = min(fracX, 1.0 - fracX) * dx;
    float distH = min(fracY, 1.0 - fracY) * dy;

    // Half-width in pixels
    float halfPx = lineWidth * u_resolution.y * 0.5;

    float maskV = 1.0 - smoothstep(halfPx - 1.0, halfPx + 1.0, distV);
    float maskH = 1.0 - smoothstep(halfPx - 1.0, halfPx + 1.0, distH);

    vec3 colH = maskH * lineHColor * lineHAlpha;
    vec3 colV = maskV * lineVColor * lineVAlpha;
    return max(colH, colV);
}

void main() {
    vec2 res = u_resolution;

    vec4 rect = framedRect(0.0, 0.0, res.x, res.y, FRAME_WIDTH, NUM_X, NUM_Y);

    vec3 col = drawGrid(rect, rect.z / NUM_X, rect.w / NUM_Y, LINE_W,
                        LINE_H_COLOR.rgb, LINE_V_COLOR.rgb,
                        LINE_H_COLOR.a,   LINE_V_COLOR.a);

    gl_FragColor = vec4(col, 1.0);
}
