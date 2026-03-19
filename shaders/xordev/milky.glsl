precision highp float;

uniform vec2 u_resolution;
uniform float u_time;

void main(){
    vec4 o = vec4(0.0);
    vec2 r = u_resolution;
    float t = u_time;

    float j;
    float i0 = -fract(t / 0.1);
    for (int ii = 0; ii < 101; ii++) {
        float i = float(ii) + i0 + 1.0;
        j = floor(i + t / 0.1 + 0.5);
        float len = length((gl_FragCoord.xy - r * 0.5) / r.y + 0.05 * cos(j * j / 4.0 + vec2(0, 5)) * sqrt(i));
        o += (cos(j * j + vec4(0, 1, 2, 3)) + 1.0) * exp(cos(j * j / 0.1) / 0.6) * min(1e3 - i / 0.1 + 9.0, i) / 5e4 / len;
    }
    vec4 o2 = o * o;
    vec4 e2 = exp(2.0 * o2);
    o = (e2 - 1.0) / (e2 + 1.0);

    gl_FragColor = o;
}
