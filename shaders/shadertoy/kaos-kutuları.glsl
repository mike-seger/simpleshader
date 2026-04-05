/*
    Source: https://www.shadertoy.com/view/scBGWd
    The license if not specified by the author is assumed to be:
    This work is licensed under a Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License.
    
    Please see the original shader for comments and description. 

    This is a slightly modified copy of the shader code, with only minor edits to make it compatible with SimpleShader 
    (e.g. renaming mainImage to main, stubbing iChannel0, etc.). If you intend to reuse this shader, please add credits to 'mcetinkaya'.
*/
precision highp float;
uniform vec2 u_resolution;
uniform float u_time;

const int maxIterations = 6;
float circleSize = 1.0 / (3.0 * pow(2.0, float(maxIterations)));

vec2 rot(vec2 uv, float a) {
    return vec2(uv.x*cos(a)-uv.y*sin(a), uv.y*cos(a)+uv.x*sin(a));
}

float hash11(float p) {
    return fract(sin(p * 127.1 + 311.7) * 43758.5453);
}
float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float hash22x(vec2 p) {
    return fract(sin(dot(p, vec2(269.5, 183.3))) * 43758.5453);
}

vec3 hsvToRgb(float h, float s, float v) {
    vec3 rgb = clamp(abs(mod(h*6.0+vec3(0,4,2),6.0)-3.0)-1.0, 0.0, 1.0);
    return v * mix(vec3(1.0), rgb, s);
}

// ---- Çokgen SDF: n kenarlı düzgün çokgen -------------------
// n=0 → daire (smooth), n=3,4,5,6,8 → çokgen
float polygonSDF(vec2 p, float n, float r) {
    if(n < 2.5) {
        // Daire
        return length(p) - r;
    }
    float an = 3.14159265 / n;
    float he = r * cos(an);
    // Açıyı n'e snap et
    float bn = mod(atan(p.x, p.y), 2.0*an) - an;
    vec2  q  = vec2(sin(bn), cos(bn)) * length(p);
    return length(vec2(q.x - clamp(q.x, -r*sin(an), r*sin(an)),
                       q.y - he));
}

// ---- Şekil sekansı: 0→daire, 1→üçgen, 2→kare,
//                     3→beşgen, 4→altıgen, 5→sekizgen, 6→daire
// sides[i]: her fazın kenar sayısı (0 = daire)
float getSides(int shapeIdx) {
    if(shapeIdx == 0) return 0.0;  // daire
    if(shapeIdx == 1) return 3.0;  // üçgen
    if(shapeIdx == 2) return 4.0;  // kare
    if(shapeIdx == 3) return 5.0;  // beşgen
    if(shapeIdx == 4) return 6.0;  // altıgen
    if(shapeIdx == 5) return 8.0;  // sekizgen
    return 0.0;                    // daire (döngü)
}

// Şekiller arası smooth geçiş
// t: global zaman, döngü süresi ayarlanabilir
float shapeBlend(float t, out float sidesA, out float sidesB) {
    float cycleDur = 2.0;          // her şekil kaç saniye sürsün
    float total    = 6.0;          // toplam şekil sayısı (daire dahil)
    float phase    = mod(t / cycleDur, total);
    int   idxA     = int(floor(phase));
    int   idxB     = int(mod(float(idxA) + 1.0, total));
    float blend    = smoothstep(0.0, 1.0, fract(phase));

    sidesA = getSides(idxA);
    sidesB = getSides(idxB);
    return blend;
}

// ---- Morph SDF: iki şekil arasında interpolasyon -----------
float morphSDF(vec2 p, float t, float r) {
    float sidesA, sidesB;
    float blend = shapeBlend(t, sidesA, sidesB);

    // Her şeklin dönüş açısını normalize et
    // Daire için döndürme anlamsız, çokgen için simetri açısı önemli
    float rotA = (sidesA > 2.5) ? 3.14159/(2.0*sidesA) : 0.0;
    float rotB = (sidesB > 2.5) ? 3.14159/(2.0*sidesB) : 0.0;
    float rotAngle = mix(rotA, rotB, blend);

    vec2 pRot = rot(p, rotAngle);

    float dA = polygonSDF(pRot, sidesA, r);
    float dB = polygonSDF(pRot, sidesB, r);

    // SDF'leri blend et — smooth geçiş
    return mix(dA, dB, blend);
}

// ---- Kaos ölçer --------------------------------------------
float measureChaos(vec2 uvIn, float t) {
    vec2  uv = uvIn;
    float s  = 0.3;
    float prevQ = 0.0;
    float chaos = 0.0;
    for(int i = 0; i < maxIterations; i++) {
        float qx = step(0.0, uv.x);
        float qy = step(0.0, uv.y);
        float q  = qx + qy * 2.0;
        chaos += abs(q - prevQ) / 3.0;
        prevQ = q;
        uv = abs(uv) - s;
        uv = rot(uv, t);
        s  = s / 2.1;
    }
    return clamp(chaos / float(maxIterations), 0.0, 1.0);
}

// ---- Fraktal zemin -----------------------------------------
float noise21(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f*f*(3.0-2.0*f);
    float a = hash22x(i);
    float b = hash22x(i+vec2(1,0));
    float c2= hash22x(i+vec2(0,1));
    float d = hash22x(i+vec2(1,1));
    return mix(mix(a,b,f.x), mix(c2,d,f.x), f.y);
}

float fbm(vec2 p, int oct) {
    float val=0.0, amp=0.5, freq=1.0;
    for(int i=0; i<8; i++) {
        if(i>=oct) break;
        val += amp * noise21(p*freq);
        amp *= 0.5; freq *= 2.1;
    }
    return val;
}

float warpedFbm(vec2 p, int oct, float warpStr) {
    vec2 q = vec2(fbm(p+vec2(0.0,0.0),oct), fbm(p+vec2(5.2,1.3),oct));
    vec2 r = vec2(fbm(p+4.0*q+vec2(1.7,9.2),oct), fbm(p+4.0*q+vec2(8.3,2.8),oct));
    return fbm(p + warpStr*r, oct);
}

float calmPattern(vec2 p, float t) {
    float w1 = sin(p.x*3.0+t*0.3)*sin(p.y*2.5+t*0.2);
    float w2 = sin((p.x+p.y)*2.0+t*0.15)*0.5;
    float w3 = fbm(p*1.5,3);
    return w1*0.3 + w2*0.3 + w3*0.4;
}

float chaoticPattern(vec2 p, float t) {
    p += vec2(sin(t*0.7)*0.3, cos(t*0.5)*0.3);
    return warpedFbm(p*2.5, 6, 3.5);
}

vec3 groundColor(vec2 p, float chaos, float t) {
    float calm    = calmPattern(p,t);
    float chao    = chaoticPattern(p,t);
    float pattern = mix(calm, chao, chaos);

    float angCalm = pattern*6.28318 + t*0.05;
    vec3 calmCol = vec3(
        0.2+0.2*sin(angCalm+0.0),
        0.3+0.3*sin(angCalm+2.094),
        0.4+0.3*sin(angCalm+4.189)
    );
    float angChao = pattern*6.28318*3.0 + t*0.2;
    vec3 chaosCol = vec3(
        0.5+0.5*sin(angChao+0.0),
        0.2+0.3*sin(angChao+1.5),
        0.4+0.4*sin(angChao+3.5)
    );
    vec3 col = mix(calmCol, chaosCol, chaos);

    float edge = abs(fract(pattern*4.0+chaos)-0.5)*2.0;
    edge = pow(edge, mix(8.0,2.0,chaos));
    col += edge * mix(vec3(0.1,0.2,0.3), vec3(0.4,0.1,0.05), chaos);

    float flicker = mix(0.0, sin(t*7.3+p.x*11.0+p.y*7.7)*0.15, chaos*chaos);
    col += flicker;
    return clamp(col*0.55, 0.0, 1.0);
}

void main() {
    vec2 uvRaw = u_resolution.xy;
    uvRaw = -.5*(uvRaw - 2.0*gl_FragCoord.xy) / uvRaw.x;

    vec2 uv = rot(uvRaw, u_time);
    uv *= sin(u_time)*0.5 + 1.5;

    // Kaos ölçümü
    vec2 uvC = rot(uvRaw, u_time) * (sin(u_time)*0.5+1.5);
    float chaos = measureChaos(uvC, u_time);

    // ---- Kutu rengi + hücre ID ------------------------------
    float s = 0.3;
    float cellId=0.0, levelId=0.0;
    vec3  finalColor = vec3(0.0);

    for(int i=0; i<maxIterations; i++) {
        float qx = step(0.0, uv.x);
        float qy = step(0.0, uv.y);
        float q  = qx + qy*2.0;
        cellId   = cellId*4.0 + q;
        levelId  = q;

        uv = abs(uv) - s;
        uv = rot(uv, u_time);
        s  = s / 2.1;

        float uid        = hash21(vec2(cellId, float(i)*17.3));
        float parentHue  = hash11(floor(cellId/4.0) + float(i)*3.7);
        float childOffset= (uid-0.5)*0.15;
        float hue        = fract(parentHue + childOffset);
        float sat        = 0.55 + 0.40*float(i)/float(maxIterations);
        float val        = 0.55 + 0.35*hash11(uid + levelId*0.1);

        vec3 col = hsvToRgb(hue, sat, val);
        float w  = pow(1.8, float(i));
        finalColor = mix(finalColor, col, w/(w+1.0));
    }

    // ---- Morph şekil maskesi --------------------------------
    // Her hücrenin kendi zaman offseti var → eş zamanlı dönüşmüyor
    float cellTimeOffset = hash21(vec2(cellId, 99.1)) * 3.0;
    float shapeTime = u_time + cellTimeOffset;

    // uv artık iterasyon sonrası lokal koordinat — şekil buraya çizilir
    float r       = circleSize * 1.1;
    float shapeDist = morphSDF(uv, shapeTime, r);

    // AA ile keskin kenar
    float inside = 1.0 - smoothstep(-0.0005, 0.0005, shapeDist);

    // Kenar parlaması — şekle göre
    float glow = exp(-max(shapeDist,0.0) * 80.0) * 0.6;

    // ---- Zemin ----------------------------------------------
    vec2 groundUV = rot(uvRaw, u_time) * (sin(u_time)*0.5+1.5);
    vec3 ground   = groundColor(groundUV*3.0, chaos, u_time);
    ground += chaos*chaos*0.3 * vec3(0.3,0.05,0.1);

    // ---- Birleştir ------------------------------------------
    vec3 glowCol = finalColor * glow;
    vec3 dotCol  = finalColor * (1.0 + 0.3*sin(u_time*0.7));
    vec3 col     = mix(ground, dotCol, inside) + glowCol;

    col = pow(max(col,0.0), vec3(0.88));
    gl_FragColor = vec4(col, 1.0);
}
