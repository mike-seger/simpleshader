#include <stdio.h>

//#include <stdio.h>
#include <math.h>

// ---------- tiny GLSL-like layer ----------

struct vec2 {
    float x, y;

    vec2() : x(0), y(0) {}
    vec2(float s) : x(s), y(s) {}
    vec2(float x_, float y_) : x(x_), y(y_) {}
};

struct vec4 {
    float x, y, z, w;

    vec4() : x(0), y(0), z(0), w(0) {}
    vec4(float s) : x(s), y(s), z(s), w(s) {}
    vec4(float x_, float y_, float z_, float w_) : x(x_), y(y_), z(z_), w(w_) {}
};

// vec2 operators
inline vec2 operator+(vec2 a, vec2 b) { return vec2(a.x + b.x, a.y + b.y); }
inline vec2 operator-(vec2 a, vec2 b) { return vec2(a.x - b.x, a.y - b.y); }
inline vec2 operator*(vec2 a, vec2 b) { return vec2(a.x * b.x, a.y * b.y); }
inline vec2 operator/(vec2 a, vec2 b) { return vec2(a.x / b.x, a.y / b.y); }

inline vec2 operator+(vec2 a, float b) { return vec2(a.x + b, a.y + b); }
inline vec2 operator-(vec2 a, float b) { return vec2(a.x - b, a.y - b); }
inline vec2 operator*(vec2 a, float b) { return vec2(a.x * b, a.y * b); }
inline vec2 operator/(vec2 a, float b) { return vec2(a.x / b, a.y / b); }

inline vec2 operator+(float a, vec2 b) { return vec2(a + b.x, a + b.y); }
inline vec2 operator-(float a, vec2 b) { return vec2(a - b.x, a - b.y); }
inline vec2 operator*(float a, vec2 b) { return vec2(a * b.x, a * b.y); }
inline vec2 operator/(float a, vec2 b) { return vec2(a / b.x, a / b.y); }

inline vec2& operator+=(vec2& a, vec2 b) { a.x += b.x; a.y += b.y; return a; }
inline vec2& operator-=(vec2& a, vec2 b) { a.x -= b.x; a.y -= b.y; return a; }
inline vec2& operator*=(vec2& a, float b) { a.x *= b; a.y *= b; return a; }
inline vec2& operator/=(vec2& a, float b) { a.x /= b; a.y /= b; return a; }

// vec4 operators
inline vec4 operator+(vec4 a, vec4 b) { return vec4(a.x + b.x, a.y + b.y, a.z + b.z, a.w + b.w); }
inline vec4 operator-(vec4 a, vec4 b) { return vec4(a.x - b.x, a.y - b.y, a.z - b.z, a.w - b.w); }
inline vec4 operator*(vec4 a, vec4 b) { return vec4(a.x * b.x, a.y * b.y, a.z * b.z, a.w * b.w); }
inline vec4 operator/(vec4 a, vec4 b) { return vec4(a.x / b.x, a.y / b.y, a.z / b.z, a.w / b.w); }

inline vec4 operator+(vec4 a, float b) { return vec4(a.x + b, a.y + b, a.z + b, a.w + b); }
inline vec4 operator-(vec4 a, float b) { return vec4(a.x - b, a.y - b, a.z - b, a.w - b); }
inline vec4 operator*(vec4 a, float b) { return vec4(a.x * b, a.y * b, a.z * b, a.w * b); }
inline vec4 operator/(vec4 a, float b) { return vec4(a.x / b, a.y / b, a.z / b, a.w / b); }

inline vec4 operator+(float a, vec4 b) { return vec4(a + b.x, a + b.y, a + b.z, a + b.w); }
inline vec4 operator-(float a, vec4 b) { return vec4(a - b.x, a - b.y, a - b.z, a - b.w); }
inline vec4 operator*(float a, vec4 b) { return vec4(a * b.x, a * b.y, a * b.z, a * b.w); }
inline vec4 operator/(float a, vec4 b) { return vec4(a / b.x, a / b.y, a / b.z, a / b.w); }

inline vec4& operator+=(vec4& a, vec4 b) { a.x += b.x; a.y += b.y; a.z += b.z; a.w += b.w; return a; }
inline vec4& operator-=(vec4& a, vec4 b) { a.x -= b.x; a.y -= b.y; a.z -= b.z; a.w -= b.w; return a; }
inline vec4& operator*=(vec4& a, float b) { a.x *= b; a.y *= b; a.z *= b; a.w *= b; return a; }
inline vec4& operator/=(vec4& a, float b) { a.x /= b; a.y /= b; a.z /= b; a.w /= b; return a; }

// GLSL-like functions
inline float dot(vec2 a, vec2 b) {
    return a.x * b.x + a.y * b.y;
}

inline vec2  abs(vec2 v)  { return vec2(fabsf(v.x), fabsf(v.y)); }
inline vec4  abs(vec4 v)  { return vec4(fabsf(v.x), fabsf(v.y), fabsf(v.z), fabsf(v.w)); }

inline vec2  sin(vec2 v)  { return vec2(sinf(v.x), sinf(v.y)); }
inline vec4  sin(vec4 v)  { return vec4(sinf(v.x), sinf(v.y), sinf(v.z), sinf(v.w)); }

inline vec2  cos(vec2 v)  { return vec2(cosf(v.x), cosf(v.y)); }
inline vec4  cos(vec4 v)  { return vec4(cosf(v.x), cosf(v.y), cosf(v.z), cosf(v.w)); }

inline vec2  tanh(vec2 v)  { return vec2(tanhf(v.x), tanhf(v.y)); }
inline vec4  tanh(vec4 v)  { return vec4(tanhf(v.x), tanhf(v.y), tanhf(v.z), tanhf(v.w)); }

inline vec2  exp(vec2 v)  { return vec2(expf(v.x), expf(v.y)); }
inline vec4  exp(vec4 v)  { return vec4(expf(v.x), expf(v.y), expf(v.z), expf(v.w)); }



int main() {
    char buf[256];
    for (int i=0; i<60; ++i) {
        snprintf(buf, sizeof(buf), "output/output-%02d.ppm", i); 
        const char *outputPath = buf;
        FILE *f = fopen(outputPath, "wb");
        int w = 16 * 60;
        int h = 9 * 60;
        fprintf(f, "P6\n");
        fprintf(f, "%d %d\n", w, h);
        fprintf(f, "255\n");
        for (int y=0; y<h; ++y) {
            for (int x=0; x<w; ++x) {
                vec4 o;
                float t = i / 60.f;
                vec2 FC(x, y), r(w, h);
                vec2 p=(FC*2.-r)/r.y,l,
                    v=p*(1.-(l+=abs(.7-dot(p,p))))/.2;
                for(float i;i++<8.;o+=(sin(vec4(v.x,v.y,v.y,v.x))+1.)*abs(v.x-v.y)*.2)
                    v+=cos(vec2(v.y,v.x)*i+vec2(0,i)+t)/i+.7;
                    
                o=tanh(exp(p.y*vec4(1,-1,-2,0))*exp(-4.*l.x)/o);
                fputc(o.x * 255, f);
                fputc(o.y * 255, f);
                fputc(o.z * 255, f);
            }
        }
        fclose(f);
        printf("Generated %s\n", outputPath);
    }

    return 0;
}
