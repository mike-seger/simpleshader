/** 

    License: Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License
    
    Year of Truchets #038
    06/15/2023  @byt3_m3chanic
    Truchet Core \M/->.<-\M/ 2023 
    
    Ok so the pistons have truchets on them - otherwise remixing
    some parts of my last shader to make a fun audio reactive 
    thing.
    
    Noise/FBM Based on Morgan McGuire @morgan3d
    https://www.shadertoy.com/view/4dS3Wd (in common tab)
*/

// @iChannel0 "../../media/audio/California Sunshine - The Gate To The Past (Remix).mp3"  audio


precision highp float;

uniform vec2  u_resolution;
uniform float u_time;

#define R           u_resolution
#define T           u_time

#define PI         3.141592653
#define PI2        6.283185307

#define MAX_DIST    35.
#define MIN_DIST    1e-5

// globals
vec3 hit,hitPoint;
vec2 sid,gid;
mat2 r90,r45;
float ghs,shs,sd,gd,gtk,stk,speed,flow,sfr,gfr;

// constants
const float size = 1.1;
const float hlf = size/2.;

float rnd (in vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// Based on Morgan McGuire @morgan3d
// https://www.shadertoy.com/view/4dS3Wd
// this works on OSX/PC without fracture lines.
float noise (in vec2 uv) {
    vec2 i = floor(uv), f = fract(uv);
    float a = rnd(i);
    float b = rnd(i + vec2(1, 0));
    float c = rnd(i + vec2(0, 1));
    float d = rnd(i + vec2(1, 1));
    vec2 u = f * f * (3. - 2. * f);
    return mix(a, b, u.x) + (c - a)* u.y * (1. - u.x) + (d - b) * u.x * u.y;
}

const vec2 shift = vec2(100.);
const mat2 r3 = mat2(cos(.5), sin(.5),-sin(.5), cos(.5));
float fbm ( in vec2 uv) {
    float v = .0, a = .5;
    for (float i = 0.; i < 3.; ++i) {
        v += a * noise(uv);
        uv = r3 * uv * 2. + shift;
        a *= 0.5;
    }
    return v;
}

float sampleFreq(float freq) { return texture2D(u_channel0, vec2(freq, .25)).x;}
mat2 rot(float a){return mat2(cos(a),sin(a),-sin(a),cos(a));}
float hash21(vec2 p){return fract(sin(dot(p, vec2(27.609,47.983)+floor(u_time)))*478.53);}

//@iq extrude
float opx(in float sdf, in float pz, in float h){
    vec2 w = vec2( sdf, abs(pz) - h );
  	return min(max(w.x, w.y), 0.) + length(max(w, 0.));
}

vec2 map(vec3 pos){
    vec2 res = vec2(1e5,0);
    pos.xz += vec2(speed,0);
    
    vec2 uv = pos.xz;


    float idx = floor((uv.x+hlf)/size);
    float rx = mod(uv.x+hlf,size)-hlf;
    
    float idz = floor((uv.y+hlf)/size)-2.;
    float rz = uv.y-size*clamp(floor(uv.y/size+.5),-2.,2.);
    
    vec2 id = vec2(idx,idz);
    vec2 r = vec2(rx,rz);
    
    float fr = sampleFreq(mod((idz*.2)+(idx*.1),1.))*1.85;

    gfr=fr;

    float b = length(r)-.2;
    float b1= opx(abs(b)-.01,pos.y,fr)-.0025;
    if(b1<res.x) {
        gd = b;
        res = vec2(b1,4.);
        hit=vec3(r.x,pos.y-fr,r.y);
        gid = id;
    }

    float gnd = pos.y+.01;
    if(gnd<res.x) {
        res = vec2(gnd,1.);
        hit=pos;
        gid = id;
    }

    return res;
}

vec3 normal(vec3 p, float t) {
    float e = MIN_DIST*t;
    vec2 h =vec2(1,-1)*.5773;
    vec3 n = h.xyy * map(p+h.xyy*e).x+
             h.yyx * map(p+h.yyx*e).x+
             h.yxy * map(p+h.yxy*e).x+
             h.xxx * map(p+h.xxx*e).x;
    return normalize(n);
}

vec2 marcher(vec3 ro, vec3 rd) {
    float d = 0., m = 0.;
    for(int i=0;i<100;i++){
        vec2 ray = map(ro + rd * d);
        if(ray.x<MIN_DIST*d||d>MAX_DIST) break;
        d += i<32?ray.x*.35:ray.x*.9;
        m  = ray.y;
    }
    return vec2(d,m);
}

vec3 hue(in vec3 t) { 
    t.x+=10.;
    return .45 + .375*cos(PI2*t.x*(vec3(.985,.98,.95)*vec3(0.941,0.835,0.157))); 
}

vec4 render(inout vec3 ro, inout vec3 rd, inout vec3 ref, inout float d, vec2 uv) {

    vec3 C = vec3(0);
    float m = 0.;
    vec2 ray = marcher(ro,rd);
    d=ray.x;m=ray.y;
    
    // save globals post march
    hitPoint = hit;  
    shs = ghs;sd = gd;
    sid = gid;sfr=gfr;
    
    if(d<MAX_DIST)
    {
        vec3 p = ro + rd * d;
        vec3 n = normal(p,d);
        vec3 lpos =vec3(2.,12.,5.);
        vec3 l = normalize(lpos-p);
        
        float diff = clamp(dot(n,l),.09,.99);
        
        float shdw = 1.;
        float st = .01;
        for( int si=0; si < 64; si++) {
            float h = map(p + l*st).x;
            if( h<MIN_DIST ) { shdw = 0.; break; }
            shdw = min(shdw, 14.*h/st);
            st += h;
            if( shdw<MIN_DIST || st >= 12. ) break;
        }
        diff = mix(diff,diff*shdw,.65);
        
        vec3 h = vec3(.25);
        
        if(m==1.) {
            float px = 4./R.x;
            
            vec3 clr = hue(vec3(hitPoint.x*.08,1.,.5));
            vec3 cld = clr*.5;
            float ff = fbm(hitPoint.xz);
            
            ff=smoothstep(.15,.16,.5+.5*sin(ff*22.));
            h = mix(clr*.1,vec3(.01),ff);  
            vec2 f = mod(hitPoint.xz+hlf,size)-hlf;

            vec2 d = abs(vec2(f.x,hitPoint.z))-vec2(hlf*5.);
            float d1 = length(max(d,0.)) + min(max(d.x,d.y),0.);
            float d2 = abs(max(abs(f.x),abs(f.y))-hlf)-.0125;
            float fr = sfr*.5;
            vec3 lfr = (fr<.5) ? vec3(0.) : cld;
            h = mix(h,lfr,smoothstep(px,-px,d1));
            h = mix(h,cld*.5,smoothstep(px,-px,max(d2,d1)));    
            h = mix(h,cld*.5,smoothstep(px,-px,abs(d1)-.0125));  
        
            float d4 = smoothstep(px,-px,abs(sd-.045)-.05);
            float d5 = smoothstep(px,-px,abs(sd)-.05);
            h = mix(h, vec3(.03), d4);
            h = mix(h, cld, d5);
            
            ref = vec3(clamp(.55-d4,0.,1.) );
        }
        
  
        if(m==4.) { 
     
            vec2 uv = vec2(atan(hitPoint.z,hitPoint.x)/PI2,hitPoint.y);
            vec2 id = floor(uv*10.)+sid;
            vec2 q = fract(uv*10.)-.5;
            vec3 clr = hue(vec3((p.x+T*.4)*.08,1.,.5));
            float ck =mod(id.x+id.y,2.)*2.-1.;
            float rnd = hash21(id);
            float rhs = hash21(sid);
            float fr = sfr*.5;
            float px = d*.01;
            
            if (rnd>.5) q.x=-q.x; 
            
            vec2 cv = vec2(length(q-.5),length(q+.5));
            vec2 p2 = cv.x<cv.y ? q-.5:q+.5;
    
            float d = abs(length(p2)-.5)-.2;
            if(fract(rnd*32.381)>.75) d = min(length(q.x),length(q.y))-.2;
            if(rhs>.5) {
              d=smoothstep(px,-px,d);
            } else if(rhs>.3){
              d = length(p2)-.5;
              d = (ck>.5^^rnd<.5) ? smoothstep(-px,px,d): smoothstep(px,-px,d);
            } else {
              d = smoothstep(-px,px,abs(abs(d)-.15)-.05);
            }
            
            vec3 ph = mix(clr,vec3(.001),d); 
            h = mix(vec3(.05),ph,fr<.5 ? .1:fr);
            ref = vec3(1.-d)*.25; 
        }
 
        C = (diff*h);

        ro = p+n*.005;
        rd = reflect(rd,n);
    } 
    return vec4(C,d);
}

vec3 FC = vec3(.075);
void main()
{   
    vec2 F = gl_FragCoord.xy;

    speed = T*.4;
    
    vec2 uv = (2.*F-R)/max(R.x,R.y);
    vec3 ro = vec3(0,-.25,5.25);
    vec3 rd = normalize(vec3(uv,-1));

    float x = 0.;
    float y = 0.;

    float ff = .3*sin(T*.08);
    mat2 rx = rot(-(.56+ff-x)), ry = rot(-ff-.1-y);//-.38
    ro.zy *= rx; ro.xz *= ry; 
    rd.zy *= rx; rd.xz *= ry;
    
    // reflection loop (@BigWings)
    vec3 C = vec3(0), ref = vec3(0), fil = vec3(.95);
    float d = 0., a = 0.;
    
    // up to 4 is good - 2 average bounce
    for(float i=0.; i<2.; i++) {
        vec4 pass = render(ro, rd, ref, d, uv);
        C += pass.rgb*fil;
        fil*=ref;
        if(i==0.)a=pass.w;
    }
           
    C = mix(FC,C,exp(-.00025*a*a*a));
    C = pow(C, vec3(.4545));
    gl_FragColor = vec4(C,1);
}
