/**
 * GPU Audio — renders Shadertoy-style sound shaders on the GPU.
 *
 * Shader annotation (in the image shader):
 *   // @gpu-audio path/to/sound.glsl [duration]
 *
 * The referenced .glsl file must define:
 *   vec2 mainSound(in int samp, float time)
 * returning stereo samples in [-1, 1].
 *
 * How it works:
 *   1. The sound shader source is wrapped in a fragment shader that maps
 *      pixel coordinates to sample indices, calls mainSound(), and encodes
 *      the stereo output as 16-bit-per-channel RGBA.
 *   2. The wrapper is compiled on an offscreen WebGL canvas and rendered
 *      to produce all audio samples at once (chunked for large durations).
 *   3. readPixels decodes the texture back into Float32 PCM buffers.
 *   4. An AudioBufferSourceNode plays the result through an AnalyserNode
 *      so FFT data is available for visual feedback via u_channel0.
 */

const SAMPLE_RATE = 44100;
const TEX_WIDTH   = 512;
const DEFAULT_DURATION = 60;

const VERTEX_SRC = `
attribute vec2 a_position;
void main() { gl_Position = vec4(a_position, 0.0, 1.0); }
`;

/**
 * Wrap user sound shader code in a fragment shader that encodes
 * mainSound() output as 16-bit stereo RGBA.
 */
function makeFragSrc(userCode) {
  return `precision highp float;
uniform float u_sampleRate;
uniform float u_texWidth;
uniform float u_totalSamples;
uniform float u_chunkOffset;

${userCode}

void main() {
  float localIdx  = floor(gl_FragCoord.y) * u_texWidth + floor(gl_FragCoord.x);
  float sampleIdx = u_chunkOffset + localIdx;
  if (sampleIdx >= u_totalSamples) {
    // Encode silence (0.0 → midpoint)
    gl_FragColor = vec4(0.0, 128.0/255.0, 0.0, 128.0/255.0);
    return;
  }
  float t = sampleIdx / u_sampleRate;
  int   s = int(sampleIdx);
  vec2  y = clamp(mainSound(s, t), -1.0, 1.0);
  // 16-bit encoding per channel: low byte in R/B, high byte in G/A
  vec2 v  = min(floor((0.5 + 0.5 * y) * 65536.0), 65535.0);
  vec2 vl = mod(v, 256.0) / 255.0;
  vec2 vh = floor(v / 256.0) / 255.0;
  gl_FragColor = vec4(vl.x, vh.x, vl.y, vh.y);
}
`;
}

// ── Annotation parser ─────────────────────────────────────

/**
 * Parse a // @gpu-audio annotation from shader source.
 * @param {string} src  Raw shader source
 * @returns {{path: string, duration: number}|null}
 */
export function parseGpuAudioAnnotation(src) {
  const re = /^\s*\/\/\s*@gpu-audio\s+(?:"([^"]+)"|(\S+))(?:\s+(\d+(?:\.\d+)?))?/m;
  const m = src.match(re);
  if (!m) return null;
  return {
    path:     m[1] || m[2],
    duration: m[3] ? parseFloat(m[3]) : DEFAULT_DURATION,
  };
}

// ── GpuAudio class ────────────────────────────────────────

export default class GpuAudio {
  constructor() {
    // Offscreen WebGL
    this._canvas  = null;
    this._gl      = null;
    this._program = null;
    this._lastLog = '';

    // Web Audio
    this._audioCtx = null;
    this._buffer   = null;   // AudioBuffer
    this._source   = null;   // AudioBufferSourceNode (one-shot; recreated on play)
    this._analyser = null;
    this._gainNode = null;

    // Playback state
    this._playing     = false;
    this._startTime   = 0;   // audioCtx.currentTime when play() was called
    this._startOffset = 0;   // offset into buffer at play()
    this._pauseOffset = 0;   // saved offset when paused
    this._duration    = 0;

    // FFT data (256-bin, same layout as MediaLoader)
    this._freqData = null;
    this._waveData = null;
    this._texData  = null;

    this._hasAudio = false;
  }

  // ── Public getters ──────────────────────────────────────

  get hasAudio()  { return this._hasAudio; }
  get playing()   { return this._playing; }
  get duration()  { return this._duration; }

  get currentTime() {
    if (!this._playing) return this._pauseOffset;
    const elapsed = this._audioCtx.currentTime - this._startTime;
    return Math.min(this._startOffset + elapsed, this._duration);
  }

  // ── Load & render ───────────────────────────────────────

  /**
   * Compile a sound shader and render the full audio buffer.
   * @param {string} soundSrc   Raw GLSL source (must define mainSound)
   * @param {number} sampleRate Sample rate (default 44100)
   * @param {number} duration   Duration in seconds (default 60)
   */
  async load(soundSrc, sampleRate = SAMPLE_RATE, duration = DEFAULT_DURATION) {
    this.dispose();
    this._duration = duration;

    // Lazy-init offscreen WebGL context
    if (!this._canvas) {
      this._canvas = document.createElement('canvas');
      this._gl = this._canvas.getContext('webgl', {
        preserveDrawingBuffer: true,
        antialias: false,
      });
      if (!this._gl) throw new Error('WebGL not available for GPU audio');
      this._initGeometry();
    }

    // Compile
    const fragSrc = makeFragSrc(soundSrc);
    const err = this._compile(fragSrc);
    if (err) throw new Error('GPU audio shader error:\n' + err);

    // Render all samples
    const totalSamples = Math.ceil(duration * sampleRate);
    const { left, right } = this._renderAudio(totalSamples, sampleRate);

    // Create AudioBuffer
    if (!this._audioCtx) {
      this._audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    }
    this._buffer = this._audioCtx.createBuffer(2, totalSamples, sampleRate);
    this._buffer.copyToChannel(left,  0);
    this._buffer.copyToChannel(right, 1);

    // Analyser (FFT feedback for potential u_channel0 use)
    this._analyser = this._audioCtx.createAnalyser();
    this._analyser.fftSize = 512;
    this._analyser.smoothingTimeConstant = 0.8;

    this._gainNode = this._audioCtx.createGain();
    this._gainNode.connect(this._analyser);
    this._analyser.connect(this._audioCtx.destination);

    this._freqData = new Uint8Array(256);
    this._waveData = new Uint8Array(256);
    this._texData  = new Uint8Array(256 * 2);

    this._hasAudio    = true;
    this._pauseOffset = 0;
  }

  // ── Playback ────────────────────────────────────────────

  play(offset = 0) {
    if (!this._hasAudio || !this._buffer) return;
    this._stopSource();
    this.resumeContext();

    const source  = this._audioCtx.createBufferSource();
    source.buffer = this._buffer;
    source.connect(this._gainNode);
    source.onended = () => {
      if (this._playing && this._source === source) {
        this._playing     = false;
        this._pauseOffset = this._duration;
      }
    };

    this._source      = source;
    this._startTime   = this._audioCtx.currentTime;
    this._startOffset = Math.max(0, Math.min(offset, this._duration));
    source.start(0, this._startOffset);
    this._playing = true;
  }

  pause() {
    if (!this._playing) return;
    this._pauseOffset = this.currentTime;
    this._stopSource();
    this._playing = false;
  }

  resume() {
    if (this._playing) return;
    this.play(this._pauseOffset);
  }

  seekTo(t) {
    this._pauseOffset = Math.max(0, Math.min(t, this._duration));
    if (this._playing) {
      this.play(this._pauseOffset);
    }
  }

  /** Resume AudioContext after user gesture (autoplay policy). */
  resumeContext() {
    if (this._audioCtx && this._audioCtx.state === 'suspended') {
      this._audioCtx.resume();
    }
  }

  /** @returns {{currentTime: number, duration: number}|null} */
  getState() {
    if (!this._hasAudio) return null;
    return { currentTime: this.currentTime, duration: this._duration };
  }

  // ── FFT (for potential u_channel0 feedback) ─────────────

  /** Call once per frame to capture FFT data. */
  updateAudio() {
    if (!this._analyser || !this._playing) return;
    this._analyser.getByteFrequencyData(this._freqData);
    this._analyser.getByteTimeDomainData(this._waveData);
    this._texData.set(this._freqData, 0);
    this._texData.set(this._waveData, 256);
  }

  // ── Cleanup ─────────────────────────────────────────────

  dispose() {
    this._stopSource();
    // Disconnect audio graph nodes to prevent leaks
    if (this._analyser) { try { this._analyser.disconnect(); } catch (_) {} this._analyser = null; }
    if (this._gainNode) { try { this._gainNode.disconnect(); } catch (_) {} this._gainNode = null; }
    this._hasAudio    = false;
    this._buffer      = null;
    this._playing     = false;
    this._pauseOffset = 0;
    this._duration    = 0;
    // Keep audioCtx + GL context alive for reuse
  }

  // ── Internal: WebGL ─────────────────────────────────────

  _initGeometry() {
    const gl  = this._gl;
    const buf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    gl.bufferData(gl.ARRAY_BUFFER,
      new Float32Array([-1,-1, 1,-1, -1,1, 1,1]), gl.STATIC_DRAW);
  }

  _compile(fragSrc) {
    const gl = this._gl;
    const vs = this._compileShader(gl.VERTEX_SHADER, VERTEX_SRC);
    if (!vs) return 'Vertex shader failed';
    const fs = this._compileShader(gl.FRAGMENT_SHADER, fragSrc);
    if (!fs) {
      const log = this._lastLog;
      gl.deleteShader(vs);
      return log || 'Fragment shader failed';
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
      return log || 'Linking failed';
    }
    if (this._program) gl.deleteProgram(this._program);
    this._program = prog;
    return null;
  }

  _compileShader(type, src) {
    const gl = this._gl;
    const s  = gl.createShader(type);
    gl.shaderSource(s, src);
    gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) {
      this._lastLog = gl.getShaderInfoLog(s);
      gl.deleteShader(s);
      return null;
    }
    return s;
  }

  /**
   * Render all audio samples via the compiled sound shader.
   * Returns { left: Float32Array, right: Float32Array }.
   */
  _renderAudio(totalSamples, sampleRate) {
    const gl         = this._gl;
    const maxTexSize = gl.getParameter(gl.MAX_TEXTURE_SIZE);
    const texWidth   = TEX_WIDTH;
    const chunkH     = Math.min(Math.ceil(totalSamples / texWidth), maxTexSize);
    const chunkSize  = texWidth * chunkH;

    this._canvas.width  = texWidth;
    this._canvas.height = chunkH;

    gl.useProgram(this._program);
    const aPos = gl.getAttribLocation(this._program, 'a_position');
    gl.enableVertexAttribArray(aPos);
    gl.vertexAttribPointer(aPos, 2, gl.FLOAT, false, 0, 0);
    gl.viewport(0, 0, texWidth, chunkH);

    gl.uniform1f(gl.getUniformLocation(this._program, 'u_sampleRate'),   sampleRate);
    gl.uniform1f(gl.getUniformLocation(this._program, 'u_texWidth'),     texWidth);
    gl.uniform1f(gl.getUniformLocation(this._program, 'u_totalSamples'), totalSamples);
    const uOffset = gl.getUniformLocation(this._program, 'u_chunkOffset');

    const left   = new Float32Array(totalSamples);
    const right  = new Float32Array(totalSamples);
    const pixels = new Uint8Array(texWidth * chunkH * 4);

    let offset = 0;
    while (offset < totalSamples) {
      gl.uniform1f(uOffset, offset);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
      gl.readPixels(0, 0, texWidth, chunkH, gl.RGBA, gl.UNSIGNED_BYTE, pixels);

      const count = Math.min(chunkSize, totalSamples - offset);
      for (let i = 0; i < count; i++) {
        const b = i * 4;
        left [offset + i] = ((pixels[b]   + pixels[b+1] * 256) / 65536.0) * 2.0 - 1.0;
        right[offset + i] = ((pixels[b+2] + pixels[b+3] * 256) / 65536.0) * 2.0 - 1.0;
      }
      offset += count;
    }

    return { left, right };
  }

  // ── Internal: playback helpers ──────────────────────────

  _stopSource() {
    if (this._source) {
      try { this._source.stop(); } catch (_) { /* already stopped */ }
      this._source.disconnect();
      this._source = null;
    }
  }
}
