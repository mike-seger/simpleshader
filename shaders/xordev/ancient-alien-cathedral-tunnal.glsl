// ==========================================================
// NAME : ANCIENT ALIEN CATHEDRAL TUNNEL
// ==========================================================
// DESCRIPTION : A high-fidelity cinematic raymarched tunnel. 
// It features procedural alien glyphs, volumetric light shafts, 
// a dynamic firefly particle system, and an advanced
// post-processing stack including ACES tonemapping and 
// chromatic aberration.
// ==========================================================
// Credits : Patrick JAILLET
// https://shaderstudio.xo.je
// https://renderforge.ct.ws

precision highp float;

uniform vec2 u_resolution;
uniform float u_time;

#define iTime u_time
#define iResolution u_resolution

#define MAX_STEPS 100 
#define MAX_DIST 120.0
#define SURF_DIST 0.001

// --- UTILITY FUNCTIONS ---

mat2 rot(float a) {
    float s = sin(a);
    float c = cos(a);
    return mat2(c, -s, s, c);
}

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// --- AUDIO SIMULATION (no iChannel0 in glsl-canvas) ---
float getAudioLow() { return 0.3 + 0.2 * sin(iTime * 2.0); }
float getAudioMid() { return 0.25 + 0.15 * sin(iTime * 3.5 + 1.0); }

// --- PROCEDURAL GLYPH GENERATION ---
float glyphs(vec3 p) {
    vec2 uv = p.xz * 2.0;
    vec2 id = floor(uv);
    vec2 gv = fract(uv) - 0.5;
    
    float n = hash21(id);
    
    if(n < 0.5) gv.x *= -1.0;
    float d = abs(abs(gv.x + gv.y) - 0.5);
    vec2 cUv = gv - vec2(0.5, -0.5);
    float dots = length(cUv) - 0.1;
    
    // Combine line segments and dots to form a "symbol."
    float symbol = smoothstep(0.1, 0.04, d) + smoothstep(0.1, 0.04, dots);
    
    // Apply a random mask so symbols don't appear in every cell.
    return symbol * step(0.35, n); 
}

// --- SIGNED DISTANCE FUNCTION (SDF) ---
float map(vec3 p) {
    vec3 p2 = p;
    // Movement: The "camera" flows through the tunnel along Z.
    p2.z += iTime * 2.5;
    
    // Apply a twist to the space based on depth and time.
    p2.xy *= rot(p2.z * 0.08 + sin(iTime*0.5)*0.5);
    
    // Tunnel Shape: Created by inverting the interior of a rounded box.
    // The formula $-length(p^4) + radius$ creates a square-ish profile.
    float tunnel = -length(pow(abs(p2.xy), vec2(4.0))) + 3.5;
    
    // Surface Detail: Add the glyphs as a displacement (bump map).
    float g = glyphs(p2);
    float disp = g * 0.15;
    
    // Audio deformation: The walls pulse based on low frequencies.
    disp += sin(p2.z * 8.0 - iTime * 6.0) * 0.08 * getAudioLow();
    
    return tunnel + disp;
}

// --- LIGHTING HELPERS ---

// Calculates the surface normal using finite difference.
vec3 getNormal(vec3 p) {
    float d = map(p);
    vec2 e = vec2(0.005, 0); 
    vec3 n = d - vec3(
        map(p - e.xyy),
        map(p - e.yxy),
        map(p - e.yyx));
    return normalize(n);
}

// ACES Filmic Tonemapping curve for high dynamic range (HDR) results.
vec3 aces(vec3 x) {
    float a = 2.51; float b = 0.03; float c = 2.43; float d = 0.59; float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

// --- MAIN RENDERING ---

void main()
{
    vec2 fragCoord = gl_FragCoord.xy;
    // UV Setup
    vec2 uv = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
    vec2 uvn = fragCoord / iResolution.xy;
    
    float fftLow = getAudioLow();
    float fftMid = getAudioMid();
    
    // --- CAMERA LOGIC ---
    vec3 ro = vec3(0.0, 0.0, -3.0); 
    ro.z += iTime * 3.0; // Forward travel
    ro.x += sin(iTime * 0.4) * 1.0; // Horizontal swaying
    ro.y += cos(iTime * 0.3) * 1.0; // Vertical swaying
    
    // Audio Camera Shake
    float shakeAmount = (fftLow * 0.15) + 0.005;
    ro += (vec3(hash21(uv + iTime), hash21(uv + iTime + 1.3), 0.0) - 0.5) * shakeAmount;

    vec3 rd = normalize(vec3(uv, 1.2)); 
    
    // Cinematic camera tilt
    rd.xy *= rot(sin(iTime * 0.2) * 0.15);
    rd.xz *= rot(sin(iTime * 0.15) * 0.15);

    // --- RAYMARCHING & VOLUMETRICS ---
    float d = 0.0, t = 0.0;
    vec3 p = vec3(0.0);
    float volumetrics = 0.0, lightShafts = 0.0, fireflyGlow = 0.0;
    
    for(int i = 0; i < MAX_STEPS; i++) {
        p = ro + rd * t;
        d = map(p);
        
        // 1. Density Volumetrics: Glow focused towards the center.
        float density = max(0.0, 2.5 - length(p.xy)); 
        
        // 2. Light Shafts (God Rays): Sample shadows at an offset.
        float sha = max(0.0, map(p + vec3(0.2, 0.5, 0.2))); 
        lightShafts += (1.0 - smoothstep(0.0, 0.2, sha)) * 0.03 * density * (0.8 + fftMid);
        
        // 3. Ambient Glow: Accumulate light based on surface proximity.
        volumetrics += 0.0025 / (0.015 + abs(d)); 
        
        // 4. Fireflies: Grid-based particle system.
        vec3 ffPos = p * 0.4; 
        ffPos.z += iTime * 0.5; // Fireflies move slower than the camera.
        vec3 ffId = floor(ffPos);
        vec3 ffLocal = fract(ffPos) - 0.5;
        
        // Chaotic orbital movement for each particle.
        vec3 ffOffset = sin(ffId * vec3(13.0, 47.0, 71.0) + iTime * vec3(0.8, 1.1, 0.6)) * 0.35;
        float ffDist = length(ffLocal - ffOffset);
        
        // Lifecycle: Organic blinking using sin and hash.
        float ffLife = smoothstep(0.1, 0.9, sin(iTime * 1.5 + hash21(ffId.xy)*6.28)*0.5+0.5);
        
        // Particles glow using an Inverse Square Law fallback: $Glow = Intensity / Distance^2$.
        float distFade = 1.0 - smoothstep(MAX_DIST*0.5, MAX_DIST, t);
        fireflyGlow += (0.0008 / (ffDist*ffDist + 0.015)) * ffLife * distFade;

        if(d < SURF_DIST || t > MAX_DIST) break;
        t += max(d * 0.5, 0.02); 
    }
    
    // --- SHADING ---
    vec3 col = vec3(0.0);
    vec3 bgCol = vec3(0.01, 0.02, 0.05); 
    
    if(t < MAX_DIST) {
        vec3 n = getNormal(p);
        vec3 l = normalize(vec3(0.0, 0.5, 1.0)); 
        
        float diff = max(0.0, dot(n, l));
        // Tight specular for a wet/metallic sheen.
        float spec = pow(max(0.0, dot(reflect(-l, n), -rd)), 40.0);
        float ao = clamp(map(p + n * 0.3) / 0.3, 0.0, 1.0);
        
        vec3 baseColor = vec3(0.05, 0.08, 0.12);
        vec3 glowColor = vec3(0.0);
        
        // Material Switch: Emissive light for Glyphs.
        vec3 glyphP = p;
        glyphP.z += iTime * 2.5;
        glyphP.xy *= rot(glyphP.z * 0.08 + sin(iTime*0.5)*0.5);
        if(glyphs(glyphP) > 0.05) {
             baseColor = vec3(0.02);
             glowColor = vec3(1.0, 0.5, 0.1) * (2.0 + fftLow * 6.0); // Gold/Orange
             spec *= 0.1;
        }

        col = baseColor * diff * ao + spec * 0.8;
        col += vec3(0.3, 0.2, 0.1) * max(0.0, n.y) * ao * 0.3; // Bounce light
        col += glowColor * volumetrics * 0.1;
    } else {
        col = bgCol;
    }
    
    // --- COMPOSITION ---
    col += vec3(0.1, 0.3, 0.8) * volumetrics * 1.5; // Blue Haze
    col += vec3(1.0, 0.9, 0.7) * lightShafts * (0.5 + fftMid * 1.5); // Gold Shafts
    col += vec3(0.8, 1.0, 0.2) * fireflyGlow * 2.0; // Greenish Fireflies

    // Background Fog: Exponential decay over distance.
    float fogAmount = 1.0 - exp(-t * 0.025);
    col = mix(col, vec3(0.02, 0.05, 0.15), fogAmount);


    // --- POST-PROCESSING STACK ---

    // 1. Chromatic Aberration: Color splitting at screen edges.
    vec3 aberration;
    aberration.r = col.r; 
    aberration.g = mix(col.g, col.r, length(uv) * 0.01);
    aberration.b = mix(col.b, col.g, length(uv) * 0.02);
    col = aberration;

    // 2. Simple Bloom: Glowing highlights.
    float bloomThresh = 0.6;
    vec3 bloom = max(vec3(0.0), col - bloomThresh);
    col += bloom * 0.8;

    // 3. Tonemapping: Converting HDR values to displayable LDR.
    col = aces(col * 1.2); 

    // 4. Film Grain & CRT Scanlines: Cinematic texture.
    float grain = (hash21(uv + mod(iTime, 10.0)) * 2.0 - 1.0) * 0.06;
    col += grain;
    col -= sin(uvn.y * 900.0) * 0.03;

    // 5. Vignette & Gamma.
    col *= smoothstep(1.4, 0.6, length(uv));
    col = pow(col, vec3(1.0 / 2.2));

    gl_FragColor = vec4(col, 1.0);
}
