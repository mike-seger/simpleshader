// https://www.shadertoy.com/view/XsXXDn
// http://www.pouet.net/prod.php?which=57245
// If you intend to reuse this shader, please add credits to 'Danilo Guanabara'
precision highp float;
uniform vec2 u_resolution;
uniform float u_time;

// @lil-gui-start
const int   ITERATIONS = 3;    // @range(1, 10, 1)
const float OFFSET1    = 0.07; // @range(0, 1.0, 0.01)
const float FREQUENCY1 = 1.0;  // @range(0, 20.0, 0.01)
const float FREQUENCY2 = 9.0;  // @range(0, 20.0, 0.01)
const float RADIUS     = 1.0;  // @range(0, 1.0, 0.01)
// @lil-gui-end

void main(){
	vec3 c;
	float l,z=u_time;
	for(int i=0;i<ITERATIONS;i++) {
		vec2 uv,p=gl_FragCoord.xy/u_resolution.xy;
		uv=p;
		p-=.5;
		p.x*=u_resolution.x/u_resolution.y;
		z+=OFFSET1;
		l=length(p);
		uv+=p/l*(sin(z)+FREQUENCY1)*abs(sin(l*FREQUENCY2-z-z));
		c[i]=.01/length(mod(uv,RADIUS)-.5);
	}
	gl_FragColor=vec4(c/l,1.0);
}