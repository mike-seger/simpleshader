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
const int   PALETTE      = 0;    // @range(0, 5, 1)  0=Rainbow 1=Neon 2=Pastel 3=Ocean 4=Sunset 5=Mono
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

struct GridParams {
    vec4  rect;
    float dx;
    float dy;
    float lineWidth;
    vec3  lineHColor;
    vec3  lineVColor;
    float lineHAlpha;
    float lineVAlpha;
};

// Draw a cartesian grid inside rect = vec4(x, y, w, h) (pixel coords, origin bottom-left).
// dx/dy are cell dimensions in pixels; lineWidth is a fraction of screen height.
// Returns vec4(rgb = line colour, a = line mask) so the caller can composite over a background.
// Returns vec4(0) when outside the rectangle.
vec4 drawGrid(GridParams p) {
    vec2 fc = gl_FragCoord.xy;

    // Clip to rectangle
    if (fc.x < p.rect.x || fc.x > p.rect.x + p.rect.z ||
        fc.y < p.rect.y || fc.y > p.rect.y + p.rect.w) return vec4(0.0);

    // Position relative to rectangle origin, in pixels
    float px = fc.x - p.rect.x;
    float py = fc.y - p.rect.y;

    // Fractional position within current cell
    float fracX = fract(px / p.dx);
    float fracY = fract(py / p.dy);

    // Pixel distance to nearest vertical / horizontal grid line
    float distV = min(fracX, 1.0 - fracX) * p.dx;
    float distH = min(fracY, 1.0 - fracY) * p.dy;

    // Half-width in pixels
    float halfPx = p.lineWidth * u_resolution.y * 0.5;

    float maskV = 1.0 - smoothstep(halfPx - 1.0, halfPx + 1.0, distV);
    float maskH = 1.0 - smoothstep(halfPx - 1.0, halfPx + 1.0, distH);

    vec3 colH = maskH * p.lineHColor * p.lineHAlpha;
    vec3 colV = maskV * p.lineVColor * p.lineVAlpha;

    // Composite mask: maximum opacity across both line axes
    float mask = max(maskH * p.lineHAlpha, maskV * p.lineVAlpha);
    return vec4(max(colH, colV), mask);
}

// IQ cosine palette: color = a + b * cos(2π*(c*t + d))
vec3 cospalette(float t, vec3 a, vec3 b, vec3 c, vec3 d) {
    return clamp(a + b * cos(6.28318 * (c * t + d)), 0.0, 1.0);
}

// Returns a colour from the active palette for a normalised value t ∈ [0,1]
vec3 getPaletteColor(float t) {
    if (PALETTE == 0) // Rainbow
        return cospalette(t, vec3(0.5, 0.5, 0.5), vec3(0.5, 0.5, 0.5),
                             vec3(1.0, 1.0, 1.0), vec3(0.00, 0.33, 0.67));
    if (PALETTE == 1) // Neon
        return cospalette(t, vec3(0.5, 0.5, 0.5), vec3(0.5, 0.5, 0.5),
                             vec3(2.0, 1.0, 0.0), vec3(0.50, 0.20, 0.25));
    if (PALETTE == 2) // Pastel
        return cospalette(t, vec3(0.8, 0.5, 0.4), vec3(0.2, 0.4, 0.2),
                             vec3(2.0, 1.0, 1.0), vec3(0.00, 0.25, 0.25));
    if (PALETTE == 3) // Ocean
        return cospalette(t, vec3(0.1, 0.3, 0.5), vec3(0.1, 0.3, 0.3),
                             vec3(1.0, 1.0, 1.0), vec3(0.30, 0.50, 0.70));
    if (PALETTE == 4) // Sunset
        return cospalette(t, vec3(0.5, 0.2, 0.1), vec3(0.5, 0.3, 0.2),
                             vec3(1.0, 1.0, 2.0), vec3(0.00, 0.15, 0.20));
    // 5 = Mono
    return cospalette(t, vec3(0.5), vec3(0.5), vec3(1.0), vec3(0.0));
}

vec4 paintCellsRandomly(GridParams p) {
    vec2 fc = gl_FragCoord.xy;

    // Clip to rectangle
    if (fc.x < p.rect.x || fc.x > p.rect.x + p.rect.z ||
        fc.y < p.rect.y || fc.y > p.rect.y + p.rect.w) return vec4(0.0);

    // Position relative to rectangle origin, in pixels
    float px = fc.x - p.rect.x;
    float py = fc.y - p.rect.y;

    // Cell indices
    float cellX = floor(px / p.dx);
    float cellY = floor(py / p.dy);

    // Random value per cell + time, mapped through the selected palette
    float r = fract(sin(dot(vec3(cellX, cellY, u_time), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
    return vec4(getPaletteColor(r), 1.0);
}

void main() {
    vec2 res = u_resolution;

    vec4 rect = framedRect(0.0, 0.0, res.x, res.y, FRAME_WIDTH, NUM_X, NUM_Y);

    GridParams p;
    p.rect      = rect;
    p.dx        = rect.z / NUM_X;
    p.dy        = rect.w / NUM_Y;
    p.lineWidth = LINE_W;
    p.lineHColor = LINE_H_COLOR.rgb;
    p.lineVColor = LINE_V_COLOR.rgb;
    p.lineHAlpha = LINE_H_COLOR.a;
    p.lineVAlpha = LINE_V_COLOR.a;

    // Cell colours as background, grid lines composited on top
    vec3 cells = paintCellsRandomly(p).rgb;
    vec4 grid  = drawGrid(p);
    vec3 col   = mix(cells, grid.rgb, grid.a);

    gl_FragColor = vec4(col, 1.0);
}
