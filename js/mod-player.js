/**
 * MOD Player — plays MOD/XM/S3M/IT tracker files via chiptune3.js (libopenmpt).
 *
 * Shader annotation (in the image shader):
 *   // @mod-audio path/to/file.mod
 *   // @mod-audio "path with spaces/file.xm"
 *
 * Supports: .mod .xm .s3m .it and other formats handled by libopenmpt.
 *
 * The chiptune3 library is lazy-loaded from CDN on first use.
 * Audio is routed through an AnalyserNode for FFT data.
 */

const CDN_URL = "https://cdn.jsdelivr.net/npm/chiptune3@0.8/chiptune3.js";

let chiptuneModule = null;
async function loadChiptuneLib() {
  if (!chiptuneModule) {
    chiptuneModule = await import(CDN_URL);
  }
  return chiptuneModule;
}

// ── Annotation parser ─────────────────────────────────────

/**
 * Parse a // @mod-audio annotation from shader source.
 * @param {string} src  Raw shader source
 * @returns {{path: string}|null}
 */
export function parseModAudioAnnotation(src) {
  const re = /^\s*\/\/\s*@mod-audio\s+(?:"([^"]+)"|(\S+))/m;
  const m = src.match(re);
  if (!m) return null;
  return { path: m[1] || m[2] };
}

// ── ModPlayer class ───────────────────────────────────────

export default class ModPlayer {
  constructor() {
    this._player      = null;
    this._audioCtx    = null;
    this._analyser    = null;
    this._buffer      = null;   // ArrayBuffer of the loaded file
    this._initialized = false;

    // Playback state
    this._playing     = false;
    this._hasAudio    = false;
    this._duration    = 0;
    this._currentTime = 0;

    // FFT data (256-bin, same layout as MediaLoader / GpuAudio)
    this._freqData = null;
    this._waveData = null;
    this._texData  = null;

    // Per-GL-context texture (256×2 LUMINANCE, same as MediaLoader audio)
    /** @type {WeakMap<WebGLRenderingContext, WebGLTexture>} */
    this._textures = new WeakMap();
  }

  // ── Public getters ──────────────────────────────────────

  get hasAudio()    { return this._hasAudio; }
  get playing()     { return this._playing; }
  get duration()    { return this._duration; }
  get currentTime() { return this._currentTime; }

  // ── Initialisation (once) ───────────────────────────────

  async _ensurePlayer() {
    if (this._initialized) return;

    const { ChiptuneJsPlayer } = await loadChiptuneLib();

    // Lazy-init AudioContext
    if (!this._audioCtx) {
      this._audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    }

    // AnalyserNode for FFT feedback
    this._analyser = this._audioCtx.createAnalyser();
    this._analyser.fftSize = 512;
    this._analyser.smoothingTimeConstant = 0.8;
    this._analyser.connect(this._audioCtx.destination);

    this._freqData = new Uint8Array(256);
    this._waveData = new Uint8Array(256);
    this._texData  = new Uint8Array(256 * 2);

    // Create player sharing our AudioContext
    this._player = new ChiptuneJsPlayer({
      context: this._audioCtx,
      repeatCount: 0,   // play once, do not loop
    });

    // Wait for AudioWorklet initialisation
    await new Promise((resolve, reject) => {
      this._player.onInitialized(() => resolve());
      this._player.onError((e) => reject(new Error('ChiptuneJs init: ' + (e?.type || e))));
      setTimeout(() => reject(new Error('ChiptuneJs init timeout')), 10000);
    });

    // Route audio: processNode → gain → analyser → destination
    // (chiptune3 already wires processNode → gain; we replace gain's output)
    this._player.gain.disconnect();
    this._player.gain.connect(this._analyser);

    // Persistent event handlers
    this._player.onMetadata((meta) => {
      this._duration = meta.dur || 0;
    });
    this._player.onProgress(() => {
      this._currentTime = this._player.currentTime || 0;
    });
    this._player.onEnded(() => {
      this._playing = false;
    });

    this._initialized = true;
  }

  // ── Load ────────────────────────────────────────────────

  /**
   * Fetch a tracker file and prepare it for playback (paused).
   * @param {string} url  URL to the .mod/.xm/.s3m/.it file
   * @param {number} [gain=1]  Linear gain multiplier for volume normalization
   */
  async load(url, gain) {
    // Stop current playback
    if (this._hasAudio && this._player) {
      this._player.stop();
    }
    this._hasAudio    = false;
    this._playing     = false;
    this._duration    = 0;
    this._currentTime = 0;
    this._gain        = gain || 1;

    await this._ensurePlayer();

    // Fetch the tracker file
    const res = await fetch(url);
    if (!res.ok) throw new Error(`MOD fetch failed: HTTP ${res.status}`);
    this._buffer = await res.arrayBuffer();

    // Play silently to trigger decoding and obtain metadata, then pause
    const metaReady = new Promise((resolve) => {
      this._player.addHandler('onMetadata', () => resolve());
      setTimeout(resolve, 5000);  // fallback if metadata never arrives
    });
    this._player.gain.gain.value = 0;
    this._player.play(this._buffer);
    await metaReady;
    this._player.pause();
    this._player.gain.gain.value = this._gain;
    this._player.setPos(0);

    this._hasAudio    = true;
    this._playing     = false;
    this._currentTime = 0;
  }

  // ── Playback ────────────────────────────────────────────

  pause() {
    if (!this._playing || !this._player) return;
    this._player.pause();
    this._playing = false;
  }

  resume() {
    if (this._playing || !this._player || !this._hasAudio) return;
    this.resumeContext();
    this._player.unpause();
    this._playing = true;
  }

  seekTo(t) {
    if (!this._player || !this._hasAudio) return;
    const pos = Math.max(0, Math.min(t, this._duration));
    this._player.setPos(pos);
    this._currentTime = pos;
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
    return { currentTime: this._currentTime, duration: this._duration };
  }

  // ── FFT ─────────────────────────────────────────────────

  /** Call once per frame to capture FFT data. */
  updateAudio() {
    if (!this._analyser || !this._playing) return;
    this._analyser.getByteFrequencyData(this._freqData);
    this._analyser.getByteTimeDomainData(this._waveData);
    this._texData.set(this._freqData, 0);
    this._texData.set(this._waveData, 256);
  }

  // ── GL texture (FFT → u_channel0) ──────────────────────

  /** Lazily create a 256×2 LUMINANCE texture for the given GL context. */
  _getTexture(gl) {
    let tex = this._textures.get(gl);
    if (!tex) {
      tex = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, tex);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.LUMINANCE, 256, 2, 0,
                    gl.LUMINANCE, gl.UNSIGNED_BYTE, null);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      gl.bindTexture(gl.TEXTURE_2D, null);
      this._textures.set(gl, tex);
    }
    return tex;
  }

  /**
   * Upload FFT data and bind texture to a GL texture unit (channel 0).
   * @param {WebGLRenderingContext} gl
   * @param {number} startUnit  First texture unit offset
   */
  bind(gl, startUnit) {
    if (!this._hasAudio || !this._texData) return;
    const unit = startUnit + 0;  // always channel 0
    gl.activeTexture(gl.TEXTURE0 + unit);
    const tex = this._getTexture(gl);
    gl.bindTexture(gl.TEXTURE_2D, tex);
    gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, 256, 2,
                     gl.LUMINANCE, gl.UNSIGNED_BYTE, this._texData);
  }

  /**
   * Set the u_channel0 sampler uniform.
   * @param {WebGLRenderingContext} gl
   * @param {WebGLProgram} prog
   * @param {number} startUnit
   */
  setUniforms(gl, prog, startUnit) {
    if (!this._hasAudio) return;
    const loc = gl.getUniformLocation(prog, 'u_channel0');
    if (loc !== null) gl.uniform1i(loc, startUnit + 0);
  }

  // ── Cleanup ─────────────────────────────────────────────

  dispose() {
    if (this._player && this._hasAudio) {
      this._player.stop();
    }
    this._buffer      = null;
    this._hasAudio    = false;
    this._playing     = false;
    this._duration    = 0;
    this._currentTime = 0;
    // Keep player + audioCtx alive for reuse
  }
}
