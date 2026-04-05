/*
    This shader is derived from https://www.shadertoy.com/view/ff2GWV by DSwerer
*/

precision highp float;

uniform vec2  u_resolution;
uniform float u_time;

vec3 tanh3(vec3 x) {
    vec3 e2x = exp(2.0 * x);
    return (e2x - 1.0) / (e2x + 1.0);
}

mat2 rotate(float a){
    return mat2(cos(a),-sin(a),
                sin(a),cos(a));
}

// ── Tweakable constants ────────────────────────────────────
// @lil-gui-start
const int   TURB_NUM    = 8;
const float TURB_AMP    = 1.4;    // @range(0.1, 3.0, 0.05)
const float TURB_SPEED  = 0.7;    // @range(0.0, 3.0, 0.05)
const float TURB_FREQ   = 4.0;    // @range(0.5, 12.0, 0.1)
const float TURB_EXP    = 2.0;    // @range(1.0, 3.0, 0.05)
const float PASSTHROUGH = 0.11;   // @range(0.01, 0.5, 0.01)
const float BRIGHTNESS  = 0.0005; // @range(0.00005, 0.005, 0.00005)
const vec3  STAR_COLOR  = vec3(0.8308, 0.9819, 3.0841);
// @lil-gui-end

float freq = TURB_FREQ;
mat3 E=mat3(1.);
mat3 rotx = mat3(1.,0.,0.,
                0.,0.6, -0.8,
                0.,0.8, 0.6);
mat3 rotz = mat3(0.8, -0.6,0.,
                 0.6, 0.8,0.,
                 0.,0.,1.);
mat3 roty = mat3(0.8, 0.,-0.6,
                0.,1.,0.,
                 0.6, 0.,0.8);

vec3 torsion(vec3 pos){
    float WAVE_SPEED = TURB_SPEED;
    float WAVE_AMP   = TURB_AMP;
    E*=rotx;
    E*=rotz;
    for(int i=0; i<TURB_NUM; i++){
        if(i>=2 && i<=4) continue;
        float phase=freq * (pos*E).y + WAVE_SPEED*u_time;
        pos+=WAVE_AMP * E[0] * sin(phase) / freq;
        E*=rotx;
        E*=rotz;
        E*=roty;
        freq*=TURB_EXP;
    }
    freq=TURB_FREQ;

    return pos;
}

float sphere(vec3 p){
    float d=length(p)-3.;
    if(d<0.){
        return (-d*.7)+PASSTHROUGH;
    }else{
        return d*.7+PASSTHROUGH*2.;
    }
}

void main() {
    vec3 col=vec3(0.);
    vec2 u=(gl_FragCoord.xy-.5*u_resolution)/u_resolution.y;
    vec3 dir = normalize(vec3(u+u,1.));
    vec3 pos = vec3(0.,0.,-5);
    pos.xz*=rotate(u_time*.1);
    dir.xz*=rotate(u_time*.1);
    for(int i=0; i<30; i++){
        float vol=sphere(torsion(pos));
        pos+=dir*(vol)/2.5;
        col+=STAR_COLOR/vol;
    }

    col=tanh3(BRIGHTNESS*sqrt(col*col*col));

    gl_FragColor=vec4(col,1.);
}
