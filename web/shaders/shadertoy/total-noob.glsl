/*
    * "Total Noob"
    * https://www.shadertoy.com/view/XdlSDs
    *
    * A simple shader that demonstrates how to create a colorful, animated pattern using basic trigonometric functions and color manipulation. The shader generates a dynamic, swirling pattern that changes over time, creating a visually appealing effect.
    *
    * The shader uses the following uniforms:
    * - `u_resolution`: A vec2 representing the resolution of the viewport (width and height).
    * - `u_time`: A float representing the elapsed time since the shader started running.
    *
    * The main function calculates the color for each pixel based on its position and the elapsed time, creating a dynamic and colorful pattern that evolves over time.

    * it is also referred from https://shader-slang.org/slang-playground/
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
	vec2 p = (2.0*fragCoord.xy-iResolution.xy)/iResolution.y;
    float tau = 3.1415926535*2.0;
    float a = atan(p.x,p.y);
    float r = length(p)*0.75;
    vec2 uv = vec2(a/tau,r);
	
	//get the color
	float xCol = (uv.x - (iTime / 3.0)) * 3.0;
	xCol = mod(xCol, 3.0);
	vec3 horColour = vec3(0.25, 0.25, 0.25);
	
	if (xCol < 1.0) {
		
		horColour.r += 1.0 - xCol;
		horColour.g += xCol;
	}
	else if (xCol < 2.0) {
		
		xCol -= 1.0;
		horColour.g += 1.0 - xCol;
		horColour.b += xCol;
	}
	else {
		
		xCol -= 2.0;
		horColour.b += 1.0 - xCol;
		horColour.r += xCol;
	}

	// draw color beam
	uv = (2.0 * uv) - 1.0;
	float beamWidth = (0.7+0.5*cos(uv.x*10.0*tau*0.15*clamp(floor(5.0 + 10.0*cos(iTime)), 0.0, 10.0))) * abs(1.0 / (30.0 * uv.y));
	vec3 horBeam = vec3(beamWidth);
	fragColor = vec4((( horBeam) * horColour), 1.0);
	gl_FragColor = fragColor;
}
