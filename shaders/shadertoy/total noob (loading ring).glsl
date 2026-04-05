/*
  "Total Noob (Loading Ring)" by Aidan Hall
  https://www.shadertoy.com/view/7sXyWf
*/

precision highp float;
uniform vec2 u_resolution;
uniform float u_time;

#define iTime u_time
#define iResolution vec3(u_resolution, 1.0)

void main()
{
    vec2 fragCoord = gl_FragCoord.xy;
    vec4 fragColor;
    float tau = radians(180.)*2.0;
	vec2 p = (2.0*fragCoord.xy-iResolution.xy)/iResolution.y;
    float a = atan(p.x,p.y);
    float r = length(p);
    vec2 uv = vec2(a/tau,r);
	
    float tri = mod((uv.x - (iTime / 3.0)) * 3.0,3.);
	vec3 hColour = vec3(0.25+clamp(-0.333+2.0*abs(0.5-smoothstep(0.0,3.0,tri)),0.0,1.0)*1.5,
                        0.25+2.0*(0.5-abs(0.5-smoothstep(0.0,2.0,tri))),
                        0.25+2.0*(0.5-abs(0.5-smoothstep(1.0,3.0,tri))));
	uv = (2.0 * uv) -0.5;
	float beamWidth = (0.7+0.5*cos(uv.x*10.0*tau*0.15*clamp(floor(5.0 + 10.0*cos(iTime)), 0.0, 10.0)))
                        * abs(1.0 / (30.0 * uv.y));
	fragColor = vec4((vec3(beamWidth) * hColour), 1.0);
    gl_FragColor = fragColor;
}