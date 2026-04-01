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
 */
export class MediaLoader {
  /** @param {WebGLRenderingContext} gl */
  constructor(gl) {
    this.gl = gl;
    /** @type {Map<number, {tex: WebGLTexture, type: string, update?: Function}>} */
    this.channels = new Map();
    this._audioCtx = null;
    this._audioElements = [];
  }

  /** Remove all loaded channels and free GL/audio resources. */
  dispose() {
    const gl = this.gl;
    for (const ch of this.channels.values()) {
      gl.deleteTexture(ch.tex);
    }
    this.channels.clear();
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

  /** Load an image into a texture on the given channel. */
  async _loadImage(channel, url) {
    const gl = this.gl;
    const img = new Image();
    img.crossOrigin = 'anonymous';
    await new Promise((resolve, reject) => {
      img.onload = resolve;
      img.onerror = () => reject(new Error(`Failed to load image: ${url}`));
      img.src = url;
    });

    const tex = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, tex);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, img);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
    gl.bindTexture(gl.TEXTURE_2D, null);

    this.channels.set(channel, { tex, type: 'image' });
  }

  /** Load audio, create FFT analyser, and produce a 256×2 FFT texture. */
  async _loadAudio(channel, url) {
    const gl = this.gl;

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

    const tex = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, tex);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.LUMINANCE, 256, 2, 0,
                  gl.LUMINANCE, gl.UNSIGNED_BYTE, null);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.bindTexture(gl.TEXTURE_2D, null);

    // Don't auto-play — wait for user gesture via play button
    // try { await audio.play(); } catch (_) { /* user gesture required — deferred */ }

    const update = () => {
      analyser.getByteFrequencyData(freqData);
      analyser.getByteTimeDomainData(waveData);
      texData.set(freqData, 0);
      texData.set(waveData, 256);
      gl.bindTexture(gl.TEXTURE_2D, tex);
      gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, 256, 2,
                       gl.LUMINANCE, gl.UNSIGNED_BYTE, texData);
    };

    this.channels.set(channel, { tex, type: 'audio', update });
  }

  /** Call once per frame to update any audio FFT textures. */
  updateAudio() {
    for (const ch of this.channels.values()) {
      if (ch.update) ch.update();
    }
  }

  /**
   * Bind loaded media textures to GL texture units.
   * @param {number} startUnit  First texture unit to use (e.g. 0 for single-pass)
   */
  bind(startUnit) {
    const gl = this.gl;
    for (const [channel, ch] of this.channels) {
      const unit = startUnit + channel;
      gl.activeTexture(gl.TEXTURE0 + unit);
      gl.bindTexture(gl.TEXTURE_2D, ch.tex);
    }
  }

  /**
   * Set sampler uniform values for loaded channels.
   * @param {WebGLProgram} prog
   * @param {number} startUnit
   */
  setUniforms(prog, startUnit) {
    const gl = this.gl;
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
