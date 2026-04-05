// ── grid.glsl ─────────────────────────────────────────────────────────────────
// Reusable cartesian grid library.
//
// Requires in the host shader:
//   uniform vec2 u_resolution;   // canvas size in pixels
//   built-in gl_FragCoord
//
// Usage:
//   vec4 rect = framedRect(0.0, 0.0, res.x, res.y, frameWidth, numX, numY);
//   GridParams p;
//   p.rect = rect;  p.dxy = rect.zw/vec2(numX, numY);
//   p.lineWidth = ...; p.lineHColor = ...; ...
//   vec4 g = drawGrid(p);   // rgb=line colour, a=mask
//   col = mix(background, g.rgb, g.a);

struct GridParams {
    vec4  rect;       // vec4(x, y, w, h) in pixel coords (origin bottom-left)
    vec2  dxy;        // cell size in pixels (width, height)
    float lineWidth;  // line half-width as fraction of screen height
    vec3  lineHColor;
    vec3  lineVColor;
    float lineHAlpha;
    float lineVAlpha;
};

// Returns vec4(x, y, w, h) of the largest inner rectangle that:
//   • sits inside [rx, ry, rw, rh] with at least frameWidth*resolution.y px margin,
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

// Draw a cartesian grid inside GridParams.rect.
// Returns vec4(rgb = line colour, a = line mask) for compositing.
// Returns vec4(0) outside the rectangle or when lineWidth is 0.
vec4 drawGrid(GridParams p) {
    vec2 fc = gl_FragCoord.xy;

    if (fc.x < p.rect.x || fc.x > p.rect.x + p.rect.z ||
        fc.y < p.rect.y || fc.y > p.rect.y + p.rect.w) return vec4(0.0);

    vec2 pos = fc - p.rect.xy;
    vec2 frac_ = fract(pos / p.dxy);
    vec2 dist = min(frac_, 1.0 - frac_) * p.dxy;

    float halfPx = p.lineWidth * u_resolution.y * 0.5;
    float lineOn = step(0.5, halfPx);   // zero mask when lineWidth is 0

    float maskV = lineOn * (1.0 - smoothstep(halfPx - 1.0, halfPx + 1.0, dist.x));
    float maskH = lineOn * (1.0 - smoothstep(halfPx - 1.0, halfPx + 1.0, dist.y));

    vec3 colH = maskH * p.lineHColor * p.lineHAlpha;
    vec3 colV = maskV * p.lineVColor * p.lineVAlpha;

    float mask = max(maskH * p.lineHAlpha, maskV * p.lineVAlpha);
    return vec4(max(colH, colV), mask);
}
