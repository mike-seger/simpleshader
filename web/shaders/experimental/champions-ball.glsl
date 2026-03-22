// Fragment shader (GLSL 1.00 compatible)
#ifdef GL_ES
precision highp float;
#endif

uniform vec3 u_lightDir;
uniform sampler2D u_logoTexture;

varying vec3 v_position;
varying vec3 v_normal;

// Golden ratio
const float phi = 1.618033988749895;

// Star centers as individual constants (no array initialization)
// Using separate vec3 constants since const arrays with initializers aren't supported
const vec3 sc0  = vec3( phi,  1.,  0.); const vec3 sc1  = vec3( phi, -1.,  0.);
const vec3 sc2  = vec3(-phi,  1.,  0.); const vec3 sc3  = vec3(-phi, -1.,  0.);
const vec3 sc4  = vec3( 1.,  0.,  phi); const vec3 sc5  = vec3( 1.,  0., -phi);
const vec3 sc6  = vec3(-1.,  0.,  phi); const vec3 sc7  = vec3(-1.,  0., -phi);
const vec3 sc8  = vec3( 0.,  phi,  1.); const vec3 sc9  = vec3( 0.,  phi, -1.);
const vec3 sc10 = vec3( 0., -phi,  1.); const vec3 sc11 = vec3( 0., -phi, -1.);

// Helper to get center by index (GLSL 1.00 doesn't support array indexing in const arrays)
vec3 getStarCenter(int idx) {
    if (idx == 0) return sc0;
    if (idx == 1) return sc1;
    if (idx == 2) return sc2;
    if (idx == 3) return sc3;
    if (idx == 4) return sc4;
    if (idx == 5) return sc5;
    if (idx == 6) return sc6;
    if (idx == 7) return sc7;
    if (idx == 8) return sc8;
    if (idx == 9) return sc9;
    if (idx == 10) return sc10;
    return sc11;
}

void main() {
    // Normalize position on sphere
    vec3 p = normalize(v_position);
    vec3 norm = normalize(v_normal);
    
    // Find closest star center (unrolled loop for GLSL 1.00 compatibility)
    int closestIdx = 0;
    float maxDot = -1.0;
    
    float d0 = dot(p, normalize(sc0));  if (d0 > maxDot) { maxDot = d0; closestIdx = 0; }
    float d1 = dot(p, normalize(sc1));  if (d1 > maxDot) { maxDot = d1; closestIdx = 1; }
    float d2 = dot(p, normalize(sc2));  if (d2 > maxDot) { maxDot = d2; closestIdx = 2; }
    float d3 = dot(p, normalize(sc3));  if (d3 > maxDot) { maxDot = d3; closestIdx = 3; }
    float d4 = dot(p, normalize(sc4));  if (d4 > maxDot) { maxDot = d4; closestIdx = 4; }
    float d5 = dot(p, normalize(sc5));  if (d5 > maxDot) { maxDot = d5; closestIdx = 5; }
    float d6 = dot(p, normalize(sc6));  if (d6 > maxDot) { maxDot = d6; closestIdx = 6; }
    float d7 = dot(p, normalize(sc7));  if (d7 > maxDot) { maxDot = d7; closestIdx = 7; }
    float d8 = dot(p, normalize(sc8));  if (d8 > maxDot) { maxDot = d8; closestIdx = 8; }
    float d9 = dot(p, normalize(sc9));  if (d9 > maxDot) { maxDot = d9; closestIdx = 9; }
    float d10 = dot(p, normalize(sc10)); if (d10 > maxDot) { maxDot = d10; closestIdx = 10; }
    float d11 = dot(p, normalize(sc11)); if (d11 > maxDot) { maxDot = d11; closestIdx = 11; }
    
    // Angular distance from star center (in degrees)
    float angle = degrees(acos(maxDot));
    
    // Star radius (degrees)
    float starRadius = 40.0;
    float falloff = smoothstep(starRadius, starRadius - 15.0, angle);
    
    // Get the center direction for this star
    vec3 centerDir = normalize(getStarCenter(closestIdx));
    
    // Build local coordinate system within the panel
    // Find an arbitrary perpendicular vector
    vec3 upRef = abs(centerDir.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 up = normalize(cross(centerDir, upRef));
    vec3 right = normalize(cross(up, centerDir));
    
    // Local 2D coordinates in panel space
    vec2 local = vec2(dot(p, right), dot(p, up));
    float radial = length(local);
    float azimuth = atan(local.y, local.x);
    
    // 5-point star mask
    float starPoints = 0.0;
    if (radial < 0.3) {
        starPoints = 1.0;
    } else {
        float anglePerPoint = 6.28318 / 5.0;
        float angleOffset = mod(azimuth + 1.256637, anglePerPoint) - anglePerPoint / 2.0;
        float pointFactor = 1.0 - abs(angleOffset) * 2.5;
        starPoints = clamp(pointFactor * (1.0 - (radial - 0.3) / 0.7), 0.0, 1.0);
    }
    
    // Combine panel and star
    float starMask = falloff * starPoints;
    
    // Colors
    vec3 starColor = vec3(1.0, 0.8, 0.2);
    vec3 panelColor = vec3(1.0);
    
    vec3 color = mix(panelColor, starColor, starMask);
    
    // Simple lighting
    float diffuse = max(0.3, dot(norm, normalize(u_lightDir)));
    color *= diffuse;
    
    gl_FragColor = vec4(color, 1.0);
}
