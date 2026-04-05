#extension GL_OES_standard_derivatives : enable
precision highp float;
uniform vec2 u_resolution;
uniform float u_time;

// @include ../lib/polyhedron.glsl

// @lil-gui-start
const float TIME_OFFSET = 218.7;      // @range(-100, 100, 1)

const vec4  EDGE_COLOR = vec4(1.0, 0.0, 0.0, 1.0);
const float EDGE_WIDTH = 0.008;       // @range(0.001, 0.1, 0.001)
const float EDGE_GLOW = 0.7;          // @range(0.0, 20.0, 0.1)

const vec4  SURFACE_COLOR = vec4(0.1882, 0.5961, 0.9098, 0.18);
const float SURFACE_GLOW = 7.4;       // @range(0.0, 10.0, 0.1)
const vec4  BODY_COLOR = vec4(0.0588, 0.0588, 0.0627, 0.55);

const vec3  AXIS1_DIR = vec3(0.0, 1.0, 0.3);
const float AXIS1_SPEED = 30.0;       // @range(-360, 360, 1)

const vec3  AXIS2_DIR = vec3(-2.9, 3.2, 0.5);
const float AXIS2_SPEED = 20.0;       // @range(-360, 360, 1)

const bool  ORTHO = false;

const vec3  LIGHT_DIR = vec3(1.0, 1.5, 2.0);
const vec4  LIGHT_COLOR = vec4(0.1608, 0.4549, 1.0, 1.0);
const float LIGHT_INTENSITY = 4.3;    // @range(0, 5, 0.05)
// @lil-gui-end

void main() {
    float s = min(u_resolution.x, u_resolution.y);
    vec2 uv = (2.0 * gl_FragCoord.xy - u_resolution) / s;

    // Common time factor (degrees → radians)
    float time = u_time + TIME_OFFSET;
    float t = time * 0.01745329252;

    // Camera
    vec3 ro = ORTHO ? vec3(uv * 2.5, 5.0) : vec3(0.0, 0.0, 3.5);
    vec3 rd = ORTHO ? vec3(0.0, 0.0, -1.0) : normalize(vec3(uv, -1.5));

    // Material + light from constants (edgeColor overridden per shape)
    Material mat = Material(EDGE_COLOR, EDGE_WIDTH, EDGE_GLOW, SURFACE_COLOR, SURFACE_GLOW, BODY_COLOR);
    Light light = Light(normalize(LIGHT_DIR), LIGHT_COLOR.rgb, LIGHT_INTENSITY);

    vec3 col = vec3(0.02, 0.02, 0.04);

    // All 5 Platonic solids in quincunx layout:
    //   4(tetra)   6(cube)
    //       20(icosa)
    //   8(octa)   12(dodeca)
    float sz = 0.85;
    vec3 p1 = vec3(-1.6,  1.2, 0.0);
    vec3 p2 = vec3( 1.6,  1.2, 0.0);
    vec3 p3 = vec3(-1.6, -1.2, 0.0);
    vec3 p4 = vec3( 1.6, -1.2, 0.0);
    vec3 p5 = vec3( 0.0,  0.0, 0.0);

    // 4: tetrahedron — amber
    mat.edgeColor = vec4(0.8941, 0.5059, 0.0667, 1.0);
    renderPolyhedron(ro - p1, rd, rotAxis(AXIS2_DIR, 10.0*t) * rotAxis(vec3(4.0, 5.0, 0.3), 8.0*t),
                     4, sz, mat, light, col);

    // 6: cube — blue
    mat.edgeColor = vec4(0.0, 0.298, 1.0, 1.0);
    renderPolyhedron(ro - p2, rd, rotAxis(AXIS2_DIR, 15.0*t) * rotAxis(vec3(0.0, 8.2, 0.3), 12.0*t),
                     6, sz, mat, light, col);

    // 8: octahedron — yellow
    mat.edgeColor = vec4(1.0, 0.9686, 0.0, 1.0);
    renderPolyhedron(ro - p3, rd, rotAxis(AXIS2_DIR, 12.0*t) * rotAxis(vec3(0.0, 1.0, 9.2), 18.0*t),
                     8, sz, mat, light, col);

    // 12: dodecahedron — green
    mat.edgeColor = vec4(0.0, 1.0, 0.349, 1.0);
    renderPolyhedron(ro - p4, rd, rotAxis(AXIS2_DIR, -10.0*t) * rotAxis(vec3(0.0, 1.0, 8.2), 24.0*t),
                     12, sz, mat, light, col);

    // 20: icosahedron — magenta
    mat.edgeColor = vec4(1.0, 0.0, 0.584, 1.0);
    renderPolyhedron(ro - p5, rd, rotAxis(AXIS2_DIR, 24.0*t) * rotAxis(AXIS1_DIR, 30.0*t),
                     20, sz, mat, light, col);

    // Tone mapping
    col = col / (col + vec3(1.0));
    col = pow(col, vec3(0.9));

    gl_FragColor = vec4(col, 1.0);
}
