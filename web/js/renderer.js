/**
 * WebGL fragment-shader renderer.
 * Manages the GL context, compiles shaders, and runs the animation loop.
 */

const VERTEX_SRC = `
attribute vec2 a_position;
void main() { gl_Position = vec4(a_position, 0.0, 1.0); }
`;

export default class Renderer {
  /** @param {HTMLCanvasElement} canvas */
  constructor(canvas) {
    this.canvas = canvas;
    this.gl = canvas.getContext("webgl", { antialias: false, preserveDrawingBuffer: false });
    if (!this.gl) throw new Error("WebGL not supported");

    this._program = null;
    this._uTime = null;
    this._uResolution = null;
    this._animId = null;
    this._startTime = performance.now();
    this._error = null;
    this._paused = false;
    this._pauseTime = 0;

    // FPS tracking
    this._frames = 0;
    this._lastFpsTime = performance.now();
    this.fps = 0;
    this.onFps = null; // callback(fps)

    this._initGeometry();
  }

  /** Create fullscreen quad */
  _initGeometry() {
    const gl = this.gl;
    const buf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1,-1, 1,-1, -1,1, 1,1]), gl.STATIC_DRAW);
  }

  /** Compile & link a fragment shader source. Returns error string or null.
   *  @param {boolean} [keepTime=false] — preserve u_time across recompile */
  compile(fragSrc, keepTime) {
    const gl = this.gl;

    // Enable extensions that shaders may request
    gl.getExtension("OES_standard_derivatives");

    const vs = this._compileShader(gl.VERTEX_SHADER, VERTEX_SRC);
    if (!vs) return "Vertex shader compilation failed";

    const fs = this._compileShader(gl.FRAGMENT_SHADER, fragSrc);
    if (!fs) {
      const log = this._lastLog;
      gl.deleteShader(vs);
      return log || "Fragment shader compilation failed";
    }

    const prog = gl.createProgram();
    gl.attachShader(prog, vs);
    gl.attachShader(prog, fs);
    gl.linkProgram(prog);
    gl.deleteShader(vs);
    gl.deleteShader(fs);

    if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) {
      const log = gl.getProgramInfoLog(prog);
      gl.deleteProgram(prog);
      return log || "Program linking failed";
    }

    if (this._program) gl.deleteProgram(this._program);
    this._program = prog;
    this._uTime = gl.getUniformLocation(prog, "u_time");
    this._uResolution = gl.getUniformLocation(prog, "u_resolution");

    const aPos = gl.getAttribLocation(prog, "a_position");
    gl.enableVertexAttribArray(aPos);
    gl.vertexAttribPointer(aPos, 2, gl.FLOAT, false, 0, 0);

    this._error = null;
    if (!keepTime) this._startTime = performance.now();
    // Draw one frame immediately so new shader is visible even when paused
    if (this._paused) {
      this._draw();
      this.canvas.style.backgroundImage = `url(${this.canvas.toDataURL()})`;
      this.canvas.style.backgroundSize = "100% 100%";
    }
    return null;
  }

  _compileShader(type, src) {
    const gl = this.gl;
    const shader = gl.createShader(type);
    gl.shaderSource(shader, src);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
      this._lastLog = gl.getShaderInfoLog(shader);
      gl.deleteShader(shader);
      return null;
    }
    return shader;
  }

  /** Start the render loop */
  start() {
    if (this._animId) return;
    const loop = () => {
      this._animId = requestAnimationFrame(loop);
      this._draw();
    };
    loop();
  }

  /** Stop the render loop */
  stop() {
    if (this._animId) {
      cancelAnimationFrame(this._animId);
      this._animId = null;
    }
  }

  /** Pause / resume the time uniform (rendering continues for FPS) */
  get paused() { return this._paused; }
  togglePause() {
    if (this._paused) {
      // Resume: remove snapshot, shift time, restart loop
      this.canvas.style.backgroundImage = "";
      this._startTime += performance.now() - this._pauseTime;
      this._paused = false;
      this.start();
    } else {
      this._pauseTime = performance.now();
      this._paused = true;
      // Draw final frame, snapshot it as CSS background, then stop
      this._draw();
      this.canvas.style.backgroundImage = `url(${this.canvas.toDataURL()})`;
      this.canvas.style.backgroundSize = "100% 100%";
      this.stop();
    }
  }

  /** Current u_time value in seconds */
  getTime() {
    const ref = this._paused ? this._pauseTime : performance.now();
    return (ref - this._startTime) / 1000;
  }

  _draw() {
    const gl = this.gl;
    if (!this._program) return;

    // Resize canvas to match display size
    const dpr = window.devicePixelRatio || 1;
    const w = this.canvas.clientWidth * dpr | 0;
    const h = this.canvas.clientHeight * dpr | 0;
    if (this.canvas.width !== w || this.canvas.height !== h) {
      this.canvas.width = w;
      this.canvas.height = h;
    }
    gl.viewport(0, 0, w, h);

    gl.useProgram(this._program);
    if (this._uTime !== null)
      gl.uniform1f(this._uTime, this.getTime());
    if (this._uResolution !== null)
      gl.uniform2f(this._uResolution, w, h);

    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);

    // FPS counter
    this._frames++;
    const now = performance.now();
    if (now - this._lastFpsTime >= 1000) {
      this.fps = this._frames;
      this._frames = 0;
      this._lastFpsTime = now;
      if (this.onFps) this.onFps(this.fps);
    }
  }
}
