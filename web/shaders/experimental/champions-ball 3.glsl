#ifdef GL_ES
precision highp float;
#endif

uniform vec2 u_resolution;
uniform float u_time;      // Optional: for animation
uniform vec3 u_lightDir;

// Golden ratio
const float phi = 1.618033988749895;

// Star centers (12 directions)
const vec3 sc0  = vec3( phi,  1.,  0.); const vec3 sc1  = vec3( phi, -1.,  0.);
const vec3 sc2  = vec3(-phi,  1.,  0.); const vec3 sc3  = vec3(-phi, -1.,  0.);
const vec3 sc4  = vec3( 1.,  0.,  phi); const vec3 sc5  = vec3( 1.,  0., -phi);
const vec3 sc6  = vec3(-1.,  0.,  phi); const vec3 sc7  = vec3(-1.,  0., -phi);
const vec3 sc8  = vec3( 0.,  phi,  1.); const vec3 sc9  = vec3( 0.,  phi, -1.);
const vec3 sc10 = vec3( 0., -phi,  1.); const vec3 sc11 = vec3( 0., -phi, -1.);

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

// Ray-sphere intersection
vec2 raySphere(vec3 ro, vec3 rd, vec3 center, float radius) {
    vec3 oc = ro - center;
    float b = dot(oc, rd);
    float c = dot(oc, oc) - radius * radius;
    float h = b * b - c;
    if (h < 0.0) return vec2(-1.0);
    float t = -b - sqrt(h);
    return vec2(t, t + 2.0 * sqrt(h));
}

// Get sphere normal at point
vec3 getNormal(vec3 p) {
    return normalize(p);
}

// Star pattern on sphere surface
float starPattern(vec3 p) {
    // Find closest star center
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
    
    float angle = degrees(acos(maxDot));
    float starRadius = 40.0;
    float falloff = smoothstep(starRadius, starRadius - 15.0, angle);
    
    // Get center direction for this star
    vec3 centerDir = normalize(getStarCenter(closestIdx));
    
    // Build local coordinate system
    vec3 upRef = abs(centerDir.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 up = normalize(cross(centerDir, upRef));
    vec3 right = normalize(cross(up, centerDir));
    
    vec2 local = vec2(dot(p, right), dot(p, up));
    float radial = length(local);
    float azimuth = atan(local.y, local.x);
    
    float starPoints = 0.0;
    if (radial < 0.3) {
        starPoints = 1.0;
    } else {
        float anglePerPoint = 6.28318 / 5.0;
        float angleOffset = mod(azimuth + 1.256637, anglePerPoint) - anglePerPoint / 2.0;
        float pointFactor = 1.0 - abs(angleOffset) * 2.5;
        starPoints = clamp(pointFactor * (1.0 - (radial - 0.3) / 0.7), 0.0, 1.0);
    }
    
    return falloff * starPoints;
}

void main() {
    // Normalized screen coordinates (-1 to 1)
    vec2 uv = (gl_FragCoord.xy - u_resolution.xy * 0.5) / min(u_resolution.x, u_resolution.y);
    
    // Camera setup
    vec3 ro = vec3(0.0, 0.0, 3.0);  // Ray origin
    vec3 lookat = vec3(0.0, 0.0, 0.0);
    vec3 forward = normalize(lookat - ro);
    vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), forward));
    vec3 up = normalize(cross(forward, right));
    
    vec3 rd = normalize(forward + uv.x * right + uv.y * up);
    
    // Ray sphere intersection
    vec3 sphereCenter = vec3(0.0, 0.0, 0.0);
    float sphereRadius = 1.0;
    vec2 intersection = raySphere(ro, rd, sphereCenter, sphereRadius);
    
    if (intersection.x > 0.0) {
        vec3 hitPoint = ro + rd * intersection.x;
        vec3 normal = getNormal(hitPoint);
        
        // Get star pattern
        float starIntensity = starPattern(normal);
        
        // Colors
        vec3 starColor = vec3(0.0353, 0.1412, 0.3686);
        vec3 panelColor = vec3(0.95, 0.95, 1.0);
        vec3 color = mix(panelColor, starColor, starIntensity);
        
        // Simple lighting
        vec3 lightDir = normalize(u_lightDir);
        float diffuse = max(0.3, dot(normal, lightDir));
        
        // Add rim lighting
        vec3 viewDir = normalize(ro - hitPoint);
        float rim = pow(1.0 - max(0.0, dot(normal, viewDir)), 2.0);
        rim *= 0.5;
        
        color *= (diffuse + rim);
        
        // Add subtle specular
        vec3 reflectDir = reflect(-lightDir, normal);
        float spec = pow(max(0.0, dot(viewDir, reflectDir)), 32.0);
        color += vec3(0.3, 0.2, 0.1) * spec;
        
        gl_FragColor = vec4(color, 1.0);
    } else {
        // Background (sky)
        vec3 bgColor = vec3(0.05, 0.05, 0.1);
        gl_FragColor = vec4(bgColor, 1.0);
    }
}
