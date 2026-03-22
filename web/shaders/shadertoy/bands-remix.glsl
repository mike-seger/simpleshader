precision highp float;
uniform vec2 u_resolution;
uniform float u_time;

#define iTime u_time
#define iResolution vec3(u_resolution, 1.0)

float squared(float value) { return value * value; }

float getAmp(float frequency) { return 0.0; } // iChannel0 not available

float getWeight(float f) {
    return (+ getAmp(f-2.0) + getAmp(f-1.0) + getAmp(f+2.0) + getAmp(f+1.0) + getAmp(f)) / 5.0; }

void main()
{
    vec4 fragColor;
    vec2 fragCoord = gl_FragCoord.xy;
	vec2 uvTrue = fragCoord.xy / iResolution.xy;
    vec2 uv = -1.0 + 2.0 * uvTrue;
    
	float lineIntensity;
    float glowWidth;
    vec3 color = vec3(0.0);
    
	for(float i = 0.0; i < 5.0; i++) {
        
		uv.y += (0.2 * sin(uv.x + i/7.0 - iTime * 0.6));
        float Y = uv.y + getWeight(squared(i) * 20.0) *
            (0.5 - 0.5); // iChannel0 stubbed to 0.5
        lineIntensity = 0.4 + squared(1.6 * abs(mod(uvTrue.x + i / 1.3 + iTime,2.0) - 1.0));
		glowWidth = abs(lineIntensity / (150.0 * Y));
		color += vec3(glowWidth * (2.0 + sin(iTime )),
                      glowWidth * (2.0 - sin(iTime)),
                      glowWidth * (2.0 - cos(iTime)));
	}	
	
	fragColor = vec4(color, 1.0);
    gl_FragColor = fragColor;
}
