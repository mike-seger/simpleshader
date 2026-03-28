/**
 * WebGL fragment-shader renderer.
 * Manages the GL context, compiles shaders, and runs the animation loop.
 *
 * Supports single-pass and multi-pass shaders.
 * Multi-pass shaders split their source with:
 *   // @pass <name> [size=W,H]
 * where W and H are literal integers or GLSL const names found in the preamble
 * (e.g. size=NUM_X,NUM_Y).  Each pass except the last renders into an FBO;
 * the last pass renders to the screen.  Pass i receives the output of pass i-1
 * as uniform sampler2D u_channel0 (and earlier passes as u_channel1, etc.).
 */

const VERTEX_SRC = `
attribute vec2 a_position;
void main() { gl_Position = vec4(a_position, 0.0, 1.0); }
`;

export default class Renderer {
  /** @param {HTMLCanvasElement} canvas */
  constructor(canvas) {
    this.canvas = canvas;
    this.gl = canvas.getContext("webgl", { antialias: false, preserveDrawingBuffer: true });
    if (!this.gl) throw new Error("WebGL not supported");

    this._program = null;   // single-pass program
    this._uTime = null;
    this._uResolution = null;
    this._passes = [];       // multi-pass descriptors
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

    // Auto-resize canvas when its CSS size changes (avoids resize inside draw)
    this._resizeObserver = new ResizeObserver(() => this.resize());
    this._resizeObserver.observe(this.canvas);
  }

  /** Create fullscreen quad buffer */
  _initGeometry() {
    const gl = this.gl;
    const buf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1,-1, 1,-1, -1,1, 1,1]), gl.STATIC_DRAW);
  }

  // ---------------------------------------------------------------------------
  // Multi-pass parsing
  // ---------------------------------------------------------------------------

  /**
   * Split a fragment shader source at // @pass <name> [size=W,H] markers.
   * Returns [] for a single-pass shader (no markers found).
   * Otherwise returns [{name, src, pw, ph}, ...] where:
   *   src  = shared preamble + this pass's body (contains exactly one void main)
   *   pw/ph = fixed FBO pixel size (null = use current screen resolution)
   */
  _parsePasses(fragSrc) {
    const passRe = /^\/\/\s*@pass\s+(\w+)(?:\s+size=([\w.]+),([\w.]+))?/;
    const lines = fragSrc.split('\n');
    const preamble = [];
    const raw = [];
    let cur = null;

    for (const line of lines) {
      const m = line.match(passRe);
      if (m) {
        if (cur) raw.push(cur);
        cur = { name: m[1], sizeW: m[2] || null, sizeH: m[3] || null, body: [] };
      } else if (cur) {
        cur.body.push(line);
      } else {
        preamble.push(line);
      }
    }
    if (cur) raw.push(cur);
    if (raw.length === 0) return [];

    const preambleSrc = preamble.join('\n');

    // Resolve a token: literal integer, or name of a GLSL const float/int
    const resolve = (token) => {
      if (!token) return null;
      const n = parseInt(token, 10);
      if (!isNaN(n)) return n;
      const re = new RegExp(`\\bconst\\s+(?:float|int)\\s+${token}\\s*=\\s*([0-9.]+)`, 'm');
      const match = preambleSrc.match(re);
      return match ? Math.round(parseFloat(match[1])) : null;
    };

    return raw.map(p => ({
      name: p.name,
      src:  preambleSrc + '\n' + p.body.join('\n'),
      pw:   resolve(p.sizeW),
      ph:   resolve(p.sizeH),
    }));
  }

  // ---------------------------------------------------------------------------
  // Compile
  // ---------------------------------------------------------------------------

  /** Compile & link a fragment shader source. Returns error string or null.
   *  @param {boolean} [keepTime=false] — preserve u_time across recompile */
  compile(fragSrc, keepTime) {
    const gl = this.gl;
    gl.getExtension("OES_standard_derivatives");

    // Dispose any previously compiled programs / FBOs
    this._disposeAll();

    const passes = this._parsePasses(fragSrc);

    if (passes.length === 0) {
      // ── Single-pass (original behaviour, unchanged) ──
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

      this._program = prog;
      this._uTime = gl.getUniformLocation(prog, "u_time");
      this._uResolution = gl.getUniformLocation(prog, "u_resolution");

      const aPos = gl.getAttribLocation(prog, "a_position");
      gl.enableVertexAttribArray(aPos);
      gl.vertexAttribPointer(aPos, 2, gl.FLOAT, false, 0, 0);

    } else {
      // ── Multi-pass ──
      const err = this._compileMultipass(passes);
      if (err) return err;
    }

    this._error = null;
    if (!keepTime) this._startTime = performance.now();
    // Draw one frame immediately so the new shader is visible even when paused
    if (this._paused) {
      this._draw();
      this.canvas.style.backgroundImage = `url(${this.canvas.toDataURL()})`;
      this.canvas.style.backgroundSize = "100% 100%";
    }
    return null;
  }

  /**
   * Compile all passes for a multi-pass shader and store in this._passes.
   * Returns an error string on failure, null on success.
   */
  _compileMultipass(passes) {
    const gl = this.gl;
    const compiled = [];

    for (let i = 0; i < passes.length; i++) {
      const p = passes[i];
      const isLast = (i === passes.length - 1);

      // Inject sampler2D uniforms for input channels from earlier passes
      let src = p.src;
      for (let c = 0; c < i; c++) {
        src = src.replace(
          /(precision\s+\S+\s+\S+;)/,
          `$1\nuniform sampler2D u_channel${c};`
        );
      }

      const vs = this._compileShader(gl.VERTEX_SHADER, VERTEX_SRC);
      const fs = this._compileShader(gl.FRAGMENT_SHADER, src);
      if (!vs || !fs) {
        if (vs) gl.deleteShader(vs);
        if (fs) gl.deleteShader(fs);
        for (const c of compiled) this._deletePass(c);
        return `Pass '${p.name}': ${this._lastLog || 'shader compilation failed'}`;
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
        for (const c of compiled) this._deletePass(c);
        return `Pass '${p.name}' link: ${log || 'failed'}`;
      }

      const uTime       = gl.getUniformLocation(prog, 'u_time');
      const uResolution = gl.getUniformLocation(prog, 'u_resolution');
      const uChannels   = Array.from({ length: i }, (_, c) =>
        gl.getUniformLocation(prog, `u_channel${c}`)
      );
      const aPos = gl.getAttribLocation(prog, 'a_position');

      // Intermediate passes render into an FBO; the last pass renders to screen
      let fbo = null, tex = null;
      if (!isLast) {
        tex = gl.createTexture();
        gl.bindTexture(gl.TEXTURE_2D, tex);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        // 1×1 placeholder — resized to the correct dimensions on the first draw
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
        gl.bindTexture(gl.TEXTURE_2D, null);

        fbo = gl.createFramebuffer();
        gl.bindFramebuffer(gl.FRAMEBUFFER, fbo);
        gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, tex, 0);
        gl.bindFramebuffer(gl.FRAMEBUFFER, null);
      }

      compiled.push({
        prog, uTime, uResolution, uChannels, aPos,
        fbo, tex,
        pw: p.pw, ph: p.ph,   // null = use screen resolution
        _texW: 0, _texH: 0,   // current texture allocation (for resize detection)
      });
    }

    this._passes = compiled;
    return null;
  }

  /** Delete a single pass's GL objects */
  _deletePass(pass) {
    const gl = this.gl;
    if (pass.prog) gl.deleteProgram(pass.prog);
    if (pass.fbo)  gl.deleteFramebuffer(pass.fbo);
    if (pass.tex)  gl.deleteTexture(pass.tex);
  }

  /** Delete all programs and FBOs (called before recompile) */
  _disposeAll() {
    const gl = this.gl;
    if (this._program) { gl.deleteProgram(this._program); this._program = null; }
    this._uTime = null;
    this._uResolution = null;
    for (const pass of this._passes) this._deletePass(pass);
    this._passes = [];
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

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /** Immediately resize the canvas pixel buffer to match its CSS size. */
  resize() {
    const dpr = window.devicePixelRatio || 1;
    const w = this.canvas.clientWidth * dpr | 0;
    const h = this.canvas.clientHeight * dpr | 0;
    if (w === 0 || h === 0) return;
    if (this.canvas.width !== w || this.canvas.height !== h) {
      this.canvas.width = w;
      this.canvas.height = h;
      // Immediately draw to fill the new buffer (resize clears it)
      if (!this._paused) this._draw();
    }
    if (this._paused) this._draw();
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

  /** Seek u_time to a specific value in seconds */
  seekTo(seconds) {
    if (this._paused) {
      this._startTime = this._pauseTime - seconds * 1000;
      this._draw();
      this.canvas.style.backgroundImage = `url(${this.canvas.toDataURL()})`;
      this.canvas.style.backgroundSize = "100% 100%";
    } else {
      this._startTime = performance.now() - seconds * 1000;
    }
  }

  // ---------------------------------------------------------------------------
  // Draw
  // ---------------------------------------------------------------------------

  _draw() {
    const gl = this.gl;
    if (!this._program && this._passes.length === 0) return;

    // Use the current canvas buffer dimensions — resize is handled
    // externally by resize() to avoid mid-frame buffer clears
    const w = this.canvas.width;
    const h = this.canvas.height;
    if (w === 0 || h === 0) return;

    if (this._passes.length > 0) {
      this._drawMultipass(w, h);
    } else {
      this._drawSingle(w, h);
    }

    // FPS counter (skip when paused to avoid erratic readings)
    if (!this._paused) {
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

  _drawSingle(w, h) {
    const gl = this.gl;
    gl.viewport(0, 0, w, h);
    gl.useProgram(this._program);
    if (this._uTime !== null)       gl.uniform1f(this._uTime, this.getTime());
    if (this._uResolution !== null)  gl.uniform2f(this._uResolution, w, h);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  }

  _drawMultipass(w, h) {
    const gl = this.gl;
    const t = this.getTime();

    for (let i = 0; i < this._passes.length; i++) {
      const pass = this._passes[i];
      const isLast = (i === this._passes.length - 1);

      // Determine this pass's output resolution (fixed or screen-sized)
      const pw = pass.pw !== null ? pass.pw : w;
      const ph = pass.ph !== null ? pass.ph : h;

      if (!isLast) {
        // Resize the FBO texture if the target dimensions have changed
        if (pass._texW !== pw || pass._texH !== ph) {
          gl.bindTexture(gl.TEXTURE_2D, pass.tex);
          gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, pw, ph, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
          gl.bindTexture(gl.TEXTURE_2D, null);
          pass._texW = pw;
          pass._texH = ph;
        }
        gl.bindFramebuffer(gl.FRAMEBUFFER, pass.fbo);
      } else {
        gl.bindFramebuffer(gl.FRAMEBUFFER, null);
      }

      gl.viewport(0, 0, pw, ph);
      gl.useProgram(pass.prog);
      if (pass.uTime !== null)       gl.uniform1f(pass.uTime, t);
      if (pass.uResolution !== null)  gl.uniform2f(pass.uResolution, pw, ph);

      // Bind output textures from all earlier passes as input samplers
      for (let c = 0; c < i; c++) {
        if (pass.uChannels[c] !== null) {
          gl.activeTexture(gl.TEXTURE0 + c);
          gl.bindTexture(gl.TEXTURE_2D, this._passes[c].tex);
          gl.uniform1i(pass.uChannels[c], c);
        }
      }

      // Configure the vertex attribute for this program
      gl.enableVertexAttribArray(pass.aPos);
      gl.vertexAttribPointer(pass.aPos, 2, gl.FLOAT, false, 0, 0);

      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    }

    // Ensure nothing is left bound to the offscreen framebuffer
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
  }
}
