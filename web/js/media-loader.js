/**
 * Media loader — parses @iChannel annotations and loads textures / audio FFT.
 *
 * Shader annotation syntax:
 *   // @iChannel0 path/to/image.jpg          — static image texture
 *   // @iChannel1 path/to/audio.mp3  audio   — audio FFT texture (256×2)
 *
 * Paths are resolved relative to the shader file URL.
 * Audio channels produce a 256×2 LUMINANCE texture updated every frame
 * (row 0 = frequency data, row 1 = waveform), similar to Shadertoy.
 */

/**
 * Parse @iChannel annotations from shader source.
 * @param {string} src  Raw shader source (before @include resolution)
 * @returns {Array<{channel: number, path: string, type: 'image'|'audio'}>}
 */
export function parseMediaAnnotations(src) {
  const re = /^\s*\/\/\s*@iChannel(\d+)\s+(?:"([^"]+)"|(\S+))(?:\s+(audio))?\s*$/gm;
  const results = [];
  let m;
  while ((m = re.exec(src)) !== null) {
    results.push({
      channel: parseInt(m[1], 10),
      path: m[2] || m[3],
      type: m[4] === 'audio' ? 'audio' : 'image',
    });
  }
  return results;
}

/**
 * Manages loading media into WebGL textures and updating audio FFT each frame.
 * Supports multiple GL contexts (e.g. main canvas + pop-out window) by lazily
 * creating per-context textures via a WeakMap keyed on the GL context.
 */
export class MediaLoader {
  constructor() {
    /** @type {Map<number, {type: string, analyser?: AnalyserNode, freqData?: Uint8Array, waveData?: Uint8Array, texData?: Uint8Array, img?: HTMLImageElement}>} */
    this.channels = new Map();
    this._audioCtx = null;
    this._audioElements = [];
    /** @type {WeakMap<WebGLRenderingContext, Map<number, WebGLTexture>>} */
    this._textures = new WeakMap();
  }

  /** Remove all loaded channels and free GL/audio resources. */
  dispose() {
    this.channels.clear();
    // Note: per-context textures are not explicitly deleted — they will be
    // garbage-collected when their GL context is lost (e.g. pop-out closed).
    this._textures = new WeakMap();
    for (const el of this._audioElements) {
      el.pause();
      el.src = '';
    }
    this._audioElements = [];
    // Don't close AudioContext — reuse it
  }

  /**
   * Load media for the given annotations.
   * @param {Array<{channel: number, path: string, type: string}>} annotations
   * @param {string} baseUrl  Base URL for resolving relative paths
   * @returns {Promise<void>}
   */
  async load(annotations, baseUrl) {
    this.dispose();
    await Promise.all(annotations.map(a => {
      const url = new URL(a.path, baseUrl).href;
      if (a.type === 'audio') {
        return this._loadAudio(a.channel, url);
      }
      return this._loadImage(a.channel, url);
    }));
  }

  /** Load an image into a channel (stores the Image for per-context texture creation). */
  async _loadImage(channel, url) {
    const img = new Image();
    img.crossOrigin = 'anonymous';
    await new Promise((resolve, reject) => {
      img.onload = resolve;
      img.onerror = () => reject(new Error(`Failed to load image: ${url}`));
      img.src = url;
    });
    this.channels.set(channel, { type: 'image', img });
  }

  /** Load audio, create FFT analyser, and store channel data for per-context textures. */
  async _loadAudio(channel, url) {
    if (!this._audioCtx) {
      this._audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    }

    const audio = new Audio();
    audio.crossOrigin = 'anonymous';
    audio.loop = true;
    audio.src = url;
    this._audioElements.push(audio);

    const source = this._audioCtx.createMediaElementSource(audio);
    const analyser = this._audioCtx.createAnalyser();
    analyser.fftSize = 512;  // 256 frequency bins
    analyser.smoothingTimeConstant = 0.8;
    source.connect(analyser);
    analyser.connect(this._audioCtx.destination);

    const freqData = new Uint8Array(256);
    const waveData = new Uint8Array(256);
    const texData  = new Uint8Array(256 * 2);

    // Don't auto-play — wait for user gesture via play button

    this.channels.set(channel, { type: 'audio', analyser, freqData, waveData, texData });
  }

  /** Call once per frame to capture audio FFT data (no GL operations). */
  updateAudio() {
    for (const ch of this.channels.values()) {
      if (ch.type === 'audio' && ch.analyser) {
        ch.analyser.getByteFrequencyData(ch.freqData);
        ch.analyser.getByteTimeDomainData(ch.waveData);
        ch.texData.set(ch.freqData, 0);
        ch.texData.set(ch.waveData, 256);
      }
    }
  }

  /**
   * Get or lazily create a texture for the given GL context and channel.
   * @param {WebGLRenderingContext} gl
   * @param {number} channel
   * @returns {WebGLTexture}
   */
  _getTexture(gl, channel) {
    let ctxMap = this._textures.get(gl);
    if (!ctxMap) {
      ctxMap = new Map();
      this._textures.set(gl, ctxMap);
    }
    let tex = ctxMap.get(channel);
    if (!tex) {
      const ch = this.channels.get(channel);
      tex = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, tex);
      if (ch.type === 'audio') {
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.LUMINANCE, 256, 2, 0,
                      gl.LUMINANCE, gl.UNSIGNED_BYTE, null);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      } else if (ch.type === 'image' && ch.img) {
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, ch.img);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
      }
      gl.bindTexture(gl.TEXTURE_2D, null);
      ctxMap.set(channel, tex);
    }
    return tex;
  }

  /**
   * Upload audio FFT data and bind textures to GL texture units.
   * @param {WebGLRenderingContext} gl  The active GL context
   * @param {number} startUnit  First texture unit to use
   */
  bind(gl, startUnit) {
    for (const [channel, ch] of this.channels) {
      const unit = startUnit + channel;
      gl.activeTexture(gl.TEXTURE0 + unit);
      const tex = this._getTexture(gl, channel);
      gl.bindTexture(gl.TEXTURE_2D, tex);
      // Upload latest FFT data for audio channels
      if (ch.type === 'audio' && ch.texData) {
        gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, 256, 2,
                         gl.LUMINANCE, gl.UNSIGNED_BYTE, ch.texData);
      }
    }
  }

  /**
   * Set sampler uniform values for loaded channels.
   * @param {WebGLRenderingContext} gl
   * @param {WebGLProgram} prog
   * @param {number} startUnit
   */
  setUniforms(gl, prog, startUnit) {
    for (const [channel] of this.channels) {
      const loc = gl.getUniformLocation(prog, `u_channel${channel}`);
      if (loc !== null) {
        gl.uniform1i(loc, startUnit + channel);
      }
    }
  }

  /** Resume audio playback (call on user gesture to satisfy autoplay policy). */
  resumeAudio() {
    if (this._audioCtx && this._audioCtx.state === 'suspended') {
      this._audioCtx.resume();
    }
    for (const el of this._audioElements) {
      if (el.paused) el.play().catch(() => {});
    }
  }

  /** Pause audio playback. */
  pauseAudio() {
    for (const el of this._audioElements) {
      if (!el.paused) el.pause();
    }
  }

  /** @returns {boolean} True if audio is currently playing. */
  get audioPlaying() {
    const el = this._audioElements[0];
    return el ? !el.paused : false;
  }

  /** @returns {boolean} True if any channels are loaded. */
  get hasMedia() {
    return this.channels.size > 0;
  }

  /** @returns {boolean} True if any audio channels are loaded. */
  get hasAudio() {
    return this._audioElements.length > 0;
  }

  /**
   * Get the first audio element's playback state.
   * @returns {{currentTime: number, duration: number}|null}
   */
  getAudioState() {
    const el = this._audioElements[0];
    if (!el) return null;
    return { currentTime: el.currentTime, duration: el.duration || 0 };
  }

  /** Seek audio to a specific time in seconds. */
  seekAudio(time) {
    for (const el of this._audioElements) {
      el.currentTime = time;
    }
  }

  /**
   * Switch the audio source on the first audio channel, preserving the
   * analyser graph. Only works if audio was previously loaded.
   * @param {string} url  Absolute or relative URL to the new audio file.
   */
  async switchAudioSource(url) {
    const el = this._audioElements[0];
    if (!el) return;
    const wasPlaying = !el.paused;
    el.pause();
    el.src = url;
    el.load();
    if (wasPlaying) {
      try { await el.play(); } catch (_) { /* autoplay policy */ }
    }
  }
}
