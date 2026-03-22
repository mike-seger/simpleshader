precision highp float;
uniform vec2 u_resolution;
uniform float u_time;

#define iTime u_time
#define iResolution vec3(u_resolution, 1.0)

// Shadertoy-compatible Flowing Ribbons shader for Kodi screensaver
// Lines with drop shadows, opaque color fills, and configurable background gradients
//
// Most parameters are configurable to create your own customized version.
// I like using this site to be able to pick my colors: https://rgbcolorpicker.com/0-1
//
// by Elmangomez, ChatGPT and Grok AI.

#define NUM_LINES 10           // Number of seismograph lines
#define LINE_SPACING 0.18      // Vertical spacing between lines
#define AMPLITUDE 0.15         // Base amplitude
#define TIME_SCALE 0.8         // Time multiplier for motion
#define WAVE_DETAIL 16.0       // Higher = more complex wave
#define LINE_THICKNESS 0.001   // Thickness of the waveform line

// ADJUSTABLE: Bottom shadow settings
// BOTTOM_SHADOW_ENABLED: Set to 1 to enable the drop shadow below the lines, 0 to disable
#define BOTTOM_SHADOW_ENABLED 1
// BOTTOM_SHADOW_ALPHA: Maximum darkness/lightness of the drop shadow below the lines
#define BOTTOM_SHADOW_ALPHA 0.45
// BOTTOM_SHADOW_SIZE: Vertical size of the shadow fade region below the lines
#define BOTTOM_SHADOW_SIZE 0.1
// BOTTOM_SHADOW_LIGHTEN: Set to 1 to lighten the area below the lines, 0 to darken
#define BOTTOM_SHADOW_LIGHTEN 0

// ADJUSTABLE: Top shadow settings
// TOP_SHADOW_ENABLED: Set to 1 to enable the drop shadow above the lines, 0 to disable
#define TOP_SHADOW_ENABLED 1
// TOP_SHADOW_ALPHA: Maximum darkness/lightness of the drop shadow above the lines
#define TOP_SHADOW_ALPHA 0.15
// TOP_SHADOW_SIZE: Vertical size of the shadow fade region above the lines
#define TOP_SHADOW_SIZE 0.02
// TOP_SHADOW_LIGHTEN: Set to 1 to lighten the area above the lines, 0 to darken
#define TOP_SHADOW_LIGHTEN 1

// ADJUSTABLE: Gradient type for the background
// 0: Flat color (uses BACKGROUND_COLOR_1)
// 1: Two-color linear gradient (uses BACKGROUND_COLOR_1 and BACKGROUND_COLOR_2)
// 2: Three-color linear gradient (uses all three colors)
// 3: Two-color radial gradient (uses BACKGROUND_COLOR_1 and BACKGROUND_COLOR_2)
// 4: Three-color radial gradient (uses all three colors)
#define GRADIENT_TYPE 4

// ADJUSTABLE: Colors for the background gradient
// BACKGROUND_COLOR_1: Used as the flat color, top color in linear gradients, or center color in radial gradients
// Default: Matches the base fill color (vec3(0.0, 0.4, 0.2))
const vec3 BACKGROUND_COLOR_1 = vec3(0.0, 0.4, 0.2);

// BACKGROUND_COLOR_2: Bottom color in two-color linear gradients, middle color in three-color linear gradients, or outer color in two-color radial gradients
// Default: Darker green (vec3(0.0, 0.2, 0.15))
const vec3 BACKGROUND_COLOR_2 = vec3(0.0, 0.2, 0.15); // Set to a distinct color for testing

// BACKGROUND_COLOR_3: Bottom color in three-color linear gradients, or outer color in three-color radial gradients
// Default: Dark gray (vec3(0.0, 0.1, 0.075)) as an example
const vec3 BACKGROUND_COLOR_3 = vec3(0.0, 0.1, 0.075);

// ADJUSTABLE: Angle for linear gradients (in degrees)
// 0 degrees = rightward, 90 degrees = top-to-bottom, 180 degrees = leftward, 270 degrees = bottom-to-top
// Default: -45 degrees for diagonal gradient
#define GRADIENT_ANGLE -45.0

// ADJUSTABLE: Center position for radial gradients (in UV space, 0.0 to 1.0)
// Default: Center of the screen (vec2(0.5, 0.5))
#define RADIAL_CENTER vec2(0.5, 0.5)

float rand(float x) {
    return fract(sin(x * 12.9898) * 43758.5453);
}

// Seismograph waveform generator
float seismoWave(float x, float time, float lineOffset) {
    float freq = 3.0 + sin(time * 0.5 + lineOffset) * 2.0;
    float t = x * freq + time + lineOffset * 2.0;
    float wave = sin(t * 3.1415) * sin(t * 0.5) + sin(t * 2.5);
    wave += 0.3 * sin(t * 7.0 + sin(time + lineOffset * 3.0)); // higher freq jitter
    wave *= (0.3 + 0.7 * sin(time * 0.25 + lineOffset * 1.3)); // magnitude variation
    return wave * AMPLITUDE;
}

// Function to compute the background color based on UV coordinates
vec3 getBackgroundColor(vec2 uv) {
    #if GRADIENT_TYPE == 0
        // Flat color
        return BACKGROUND_COLOR_1;
    
    #elif GRADIENT_TYPE == 1
        // Two-color linear gradient (top to bottom when GRADIENT_ANGLE = 90.0)
        float angleRad = radians(GRADIENT_ANGLE);
        vec2 dir = vec2(cos(angleRad), sin(angleRad));
        float t = dot(uv - vec2(0.5), dir);
        t = (t + 0.707) / 1.414; // Normalize to [0, 1]
        t = clamp(t, 0.0, 1.0);
        // Invert t for top-to-bottom mapping when angle is around 90 degrees
        if (abs(GRADIENT_ANGLE - 90.0) < 0.1 || abs(GRADIENT_ANGLE - 270.0) < 0.1) {
            t = 1.0 - uv.y; // Directly use uv.y for top-to-bottom
        }
        return mix(BACKGROUND_COLOR_1, BACKGROUND_COLOR_2, t);
    
    #elif GRADIENT_TYPE == 2
        // Three-color linear gradient (top to bottom when GRADIENT_ANGLE = 90.0)
        float angleRad = radians(GRADIENT_ANGLE);
        vec2 dir = vec2(cos(angleRad), sin(angleRad));
        float t = dot(uv - vec2(0.5), dir);
        t = (t + 0.707) / 1.414;
        t = clamp(t, 0.0, 1.0);
        // Invert t for top-to-bottom mapping
        if (abs(GRADIENT_ANGLE - 90.0) < 0.1 || abs(GRADIENT_ANGLE - 270.0) < 0.1) {
            t = 1.0 - uv.y;
        }
        if (t < 0.5) {
            return mix(BACKGROUND_COLOR_1, BACKGROUND_COLOR_2, t * 2.0);
        } else {
            return mix(BACKGROUND_COLOR_2, BACKGROUND_COLOR_3, (t - 0.5) * 2.0);
        }
    
    #elif GRADIENT_TYPE == 3
        // Two-color radial gradient
        float r = length(uv - RADIAL_CENTER);
        float t = r / 0.707; // Normalize based on max distance (sqrt(2)/2)
        t = clamp(t, 0.0, 1.0);
        return mix(BACKGROUND_COLOR_1, BACKGROUND_COLOR_2, t);
    
    #elif GRADIENT_TYPE == 4
        // Three-color radial gradient
        float r = length(uv - RADIAL_CENTER);
        float t = r / 0.707;
        t = clamp(t, 0.0, 1.0);
        if (t < 0.5) {
            return mix(BACKGROUND_COLOR_1, BACKGROUND_COLOR_2, t * 2.0);
        } else {
            return mix(BACKGROUND_COLOR_2, BACKGROUND_COLOR_3, (t - 0.5) * 2.0);
        }
    
    #else
        // Default to flat color if GRADIENT_TYPE is invalid
        return BACKGROUND_COLOR_1;
    #endif
}

// Function to get the line and fill colors based on the line index
void getColors(int index, out vec3 lineColor, out float fillIntensity) {
    float t = float(index) / float(NUM_LINES);
    
    // ADJUSTABLE: Color for all lines (matches the top line from previous gradient)
    // This defines the uniform color of all seismograph lines.
    // Default: Dark green (vec3(0.0, 0.8, 0.4))
    // Examples:
    // - Red: vec3(1.0, 0.0, 0.0)
    // - Blue: vec3(0.0, 0.0, 1.0)
    // - White: vec3(1.0, 1.0, 1.0)
    vec3 lineColorUniform = vec3(0.0, 0.8, 0.4);
    
    // ADJUSTABLE: Base intensity for the fills (region below the topmost line)
    // This defines the fill intensity below the topmost line, extending to the top of the screen.
    // Default: 0.8 (fairly dark)
    float baseFillIntensity = 0.8;
    
    // ADJUSTABLE: End intensity for the fill gradient (region below the bottommost line)
    // This defines the fill intensity below the bottommost line, extending to the bottom of the screen.
    // The fill intensities transition smoothly from baseFillIntensity (top) to endFillIntensity (bottom).
    // Default: 0.4 (lighter)
    float endFillIntensity = 0.4;
    
    // Set the line color to be uniform for all lines
    lineColor = lineColorUniform;
    
    // Compute the gradient for the fill intensities
    fillIntensity = mix(baseFillIntensity, endFillIntensity, t);
}

void main() {
    vec4 fragColor;
    vec2 fragCoord = gl_FragCoord.xy;
    vec2 uv = fragCoord.xy / iResolution.xy;
    float aspect = iResolution.x / iResolution.y;
    vec2 centeredUV = uv * 2.0 - 1.0;
    centeredUV.x *= aspect;

    float time = iTime * TIME_SCALE;

    // Start with the background gradient
    vec3 color = getBackgroundColor(uv);

    // First Pass: Compute the fill intensity for all lines
    float fillIntensity = 1.0; // Default to 1.0 (no darkening) if no fill is applied
    bool filled = false;
    for (int i = 0; i < NUM_LINES; i++) {
        float yOffset = 1.0 - float(i) * LINE_SPACING - 0.2;
        float wave = seismoWave(centeredUV.x, time, float(i));
        float lineY = yOffset + wave;
        
        vec3 lineColor;
        float lineFillIntensity;
        getColors(i, lineColor, lineFillIntensity);

        // Apply fill intensity under the waveform
        if (!filled && centeredUV.y < lineY) {
            fillIntensity = lineFillIntensity; // Use the intensity to darken the background
            filled = true;                     // Prevent lower lines from filling this pixel
        }
    }

    // If no fill was applied (pixel is above the top line), use the top line's fill intensity
    if (!filled) {
        vec3 lineColor;
        float lineFillIntensity;
        getColors(0, lineColor, lineFillIntensity);
        fillIntensity = lineFillIntensity;
    }

    // Apply the fill intensity to the background gradient
    color *= fillIntensity;

    // Second Pass: Compute the combined drop shadow effects (top and bottom)
    float topShadowIntensity = 0.0;
    float bottomShadowIntensity = 0.0;
    for (int i = 0; i < NUM_LINES; i++) {
        float yOffset = 1.0 - float(i) * LINE_SPACING - 0.2;
        float wave = seismoWave(centeredUV.x, time, float(i));
        float lineY = yOffset + wave;

        // Compute the top shadow (above the line)
        #if TOP_SHADOW_ENABLED == 1
        float topShadowDist = centeredUV.y - lineY; // Positive when above the line
        if (topShadowDist > 0.0 && topShadowDist < TOP_SHADOW_SIZE) {
            float shadowFade = smoothstep(TOP_SHADOW_SIZE, 0.0, topShadowDist);
            topShadowIntensity = max(topShadowIntensity, TOP_SHADOW_ALPHA * shadowFade);
        }
        #endif

        // Compute the bottom shadow (below the line)
        #if BOTTOM_SHADOW_ENABLED == 1
        float bottomShadowDist = lineY - centeredUV.y; // Positive when below the line
        if (bottomShadowDist > 0.0 && bottomShadowDist < BOTTOM_SHADOW_SIZE) {
            float shadowFade = smoothstep(BOTTOM_SHADOW_SIZE, 0.0, bottomShadowDist);
            bottomShadowIntensity = max(bottomShadowIntensity, BOTTOM_SHADOW_ALPHA * shadowFade);
        }
        #endif
    }

    // Apply the top shadow effect
    #if TOP_SHADOW_ENABLED == 1
    #if TOP_SHADOW_LIGHTEN == 1
    color = mix(color, vec3(1.0), topShadowIntensity); // Lighten towards white
    #else
    color *= (1.0 - topShadowIntensity); // Darken
    #endif
    #endif

    // Apply the bottom shadow effect
    #if BOTTOM_SHADOW_ENABLED == 1
    #if BOTTOM_SHADOW_LIGHTEN == 1
    color = mix(color, vec3(1.0), bottomShadowIntensity); // Lighten towards white
    #else
    color *= (1.0 - bottomShadowIntensity); // Darken
    #endif
    #endif

    // Third Pass: Draw the lines on top (opaque, topmost line takes precedence)
    float closestDist = 9999.0; // Large initial distance
    vec3 closestLineColor = vec3(0.0);
    float closestBrightness = 0.0;

    // First loop: Find the closest line to this pixel
    for (int i = 0; i < NUM_LINES; i++) {
        float yOffset = 1.0 - float(i) * LINE_SPACING - 0.2;
        float wave = seismoWave(centeredUV.x, time, float(i));
        float lineY = yOffset + wave;
        
        vec3 lineColor;
        float fillIntensity;
        getColors(i, lineColor, fillIntensity);

        float dist = abs(centeredUV.y - lineY);
        if (dist < closestDist) {
            closestDist = dist;
            closestLineColor = lineColor;
            closestBrightness = smoothstep(3./iResolution.y, 0., dist);
        }
    }

    // Second loop: Draw only the closest line (opaque)
    if (closestBrightness > 0.0) {
        // Blend the line color with the background based on brightness (for anti-aliasing)
        // Since brightness is 0.0 to 1.0, this ensures the line is opaque at its center
        color = mix(color, closestLineColor, closestBrightness);
    }

    fragColor = vec4(color, 1.0);
    gl_FragColor = fragColor;
}