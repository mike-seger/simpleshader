/**
 * Media loader — parses @iChannel annotations and loads textures / audio / MOD.
 *
 * Shader annotation syntax:
 *   // @iChannel0 path/to/image.jpg          — static image texture
 *   // @iChannel1 path/to/audio.mp3  audio   — audio FFT texture (256×2)
 *   // @iChannel0 path/to/song.mod   mod     — MOD/XM/S3M/IT tracker via chiptune3
 *
 * Paths are resolved relative to the shader file URL.
 * Audio/mod channels produce a 256×2 LUMINANCE texture updated every frame
 * (row 0 = frequency data, row 1 = waveform), similar to Shadertoy.
 */

const CHIPTUNE_CDN = "https://cdn.jsdelivr.net/npm/chiptune3@0.8/chiptune3.js";
let chiptuneModule = null;
async function loadChiptuneLib() {
  if (!chiptuneModule) chiptuneModule = await import(CHIPTUNE_CDN);
  return chiptuneModule;
}

/**
 * Parse @iChannel annotations from shader source.
 * @param {string} src  Raw shader source (before @include resolution)
 * @returns {Array<{channel: number, path: string, type: 'image'|'audio'|'mod'|'texture'}>}
 */
export function parseMediaAnnotations(src) {
  const re = /^\s*\/\/\s*@iChannel(\d+)\s+(?:"([^"]+)"|(\S+))(?:\s+(audio|mod|texture))?\s*$/gm;
  const results = [];
  let m;
  while ((m = re.exec(src)) !== null) {
    const kind = m[4];
    results.push({
      channel: parseInt(m[1], 10),
      path: m[2] || m[3],
      type: kind === 'audio' ? 'audio' : kind === 'mod' ? 'mod' : kind === 'texture' ? 'texture' : 'image',
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
    /** @type {Map<number, {type: string, analyser?: AnalyserNode, freqData?: Uint8Array, waveData?: Uint8Array, texData?: Uint8Array, img?: HTMLImageElement, modPlayer?: any}>} */
    this.channels = new Map();
    this._audioCtx = null;
    this._audioElements = [];
    this._modPlayers = [];     // chiptune3 player instances
    /** @type {WeakMap<WebGLRenderingContext, Map<number, WebGLTexture>>} */
    this._textures = new WeakMap();
  }

  /** Remove all loaded channels and free GL/audio resources. */
  dispose() {
    // Disconnect audio graph nodes before clearing channels
    for (const ch of this.channels.values()) {
      if (ch.analyser) try { ch.analyser.disconnect(); } catch (_) {}
    }
    this.channels.clear();
    this._textures = new WeakMap();
    for (const el of this._audioElements) {
      el.pause();
      el.src = '';
    }
    this._audioElements = [];
    for (const mp of this._modPlayers) {
      try { mp.gain.disconnect(); } catch (_) {}
      try { mp.stop(); } catch (_) {}
    }
    this._modPlayers = [];
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
      // Encode # as %23 before URL construction (# is the fragment delimiter)
      const safePath = a.path.replace(/#/g, '%23');
      const url = new URL(safePath, baseUrl).href;
      if (a.type === 'audio') {
        return this._loadAudio(a.channel, url);
      } else if (a.type === 'mod') {
        return this._loadMod(a.channel, url);
      }
      return this._loadImage(a.channel, url);  // 'image' or 'texture'
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
    const gainNode = this._audioCtx.createGain();
    const analyser = this._audioCtx.createAnalyser();
    analyser.fftSize = 512;  // 256 frequency bins
    analyser.smoothingTimeConstant = 0.8;
    source.connect(gainNode);
    gainNode.connect(analyser);
    analyser.connect(this._audioCtx.destination);

    const freqData = new Uint8Array(256);
    const waveData = new Uint8Array(256);
    const texData  = new Uint8Array(256 * 2);

    // Don't auto-play — wait for user gesture via play button

    this.channels.set(channel, { type: 'audio', analyser, freqData, waveData, texData, gainNode });
  }

  /** Load a MOD/XM/S3M/IT tracker file via chiptune3. */
  async _loadMod(channel, url) {
    if (!this._audioCtx) {
      this._audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    }

    const { ChiptuneJsPlayer } = await loadChiptuneLib();
    const player = new ChiptuneJsPlayer({
      context: this._audioCtx,
      repeatCount: -1,   // loop
    });

    // Wait for AudioWorklet init
    await new Promise((resolve, reject) => {
      player.onInitialized(() => resolve());
      player.onError((e) => reject(new Error('ChiptuneJs init: ' + (e?.type || e))));
      setTimeout(() => reject(new Error('ChiptuneJs init timeout')), 10000);
    });

    // FFT analyser
    const analyser = this._audioCtx.createAnalyser();
    analyser.fftSize = 512;
    analyser.smoothingTimeConstant = 0.8;
    player.gain.disconnect();
    player.gain.connect(analyser);
    analyser.connect(this._audioCtx.destination);

    const freqData = new Uint8Array(256);
    const waveData = new Uint8Array(256);
    const texData  = new Uint8Array(256 * 2);

    // Fetch and prime the player (silent play to get metadata, then pause)
    const res = await fetch(url);
    if (!res.ok) throw new Error(`MOD fetch failed: HTTP ${res.status}`);
    const buffer = await res.arrayBuffer();

    const metaReady = new Promise((resolve) => {
      player.addHandler('onMetadata', () => resolve());
      setTimeout(resolve, 5000);
    });
    player.gain.gain.value = 0;
    player.play(buffer);
    await metaReady;
    player.pause();
    player.gain.gain.value = 1;
    player.setPos(0);

    this._modPlayers.push(player);

    // Track playback state via events
    let currentTime = 0;
    let duration = player.duration || 0;
    let playing = false;
    player.onMetadata((meta) => { duration = meta.dur || 0; });
    player.onProgress(() => { currentTime = player.currentTime || 0; });
    player.onEnded(() => { playing = false; });

    this.channels.set(channel, {
      type: 'mod', analyser, freqData, waveData, texData,
      modPlayer: player, modBuffer: buffer,
      get modPlaying() { return playing; },
      set modPlaying(v) { playing = v; },
      get modCurrentTime() { return currentTime; },
      get modDuration() { return duration; },
    });
  }

  /** Call once per frame to capture audio/mod FFT data (no GL operations). */
  updateAudio() {
    for (const ch of this.channels.values()) {
      if ((ch.type === 'audio' || ch.type === 'mod') && ch.analyser) {
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
      if (ch.type === 'audio' || ch.type === 'mod') {
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
      // Upload latest FFT data for audio/mod channels
      if ((ch.type === 'audio' || ch.type === 'mod') && ch.texData) {
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

  /** @returns {boolean} True if any audio or mod channels are loaded. */
  get hasAudio() {
    return this._audioElements.length > 0 || this._modPlayers.length > 0;
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
   * Switch the image on a texture channel, replacing the old image.
   * @param {number} channel  Channel number to update
   * @param {string} url  Absolute URL to the new image
   */
  async switchImageSource(channel, url) {
    const ch = this.channels.get(channel);
    if (!ch || ch.type !== 'image') return;
    const img = new Image();
    img.crossOrigin = 'anonymous';
    await new Promise((resolve, reject) => {
      img.onload = resolve;
      img.onerror = () => reject(new Error(`Failed to load image: ${url}`));
      img.src = url;
    });
    ch.img = img;
    // Invalidate per-context textures so they get recreated on next bind
    this._textures = new WeakMap();
  }

  /**
   * Switch the audio source on the first audio channel, preserving the
   * analyser graph. Only works if audio was previously loaded.
   * @param {string} url  Absolute or relative URL to the new audio file.
   */
  async switchAudioSource(url, gain) {
    const el = this._audioElements[0];
    if (!el) return;
    const wasPlaying = !el.paused;
    el.pause();
    el.src = url;
    el.load();
    // Apply gain normalization
    for (const ch of this.channels.values()) {
      if (ch.type === 'audio' && ch.gainNode) {
        ch.gainNode.gain.value = gain || 1;
        break;
      }
    }
    if (wasPlaying) {
      try { await el.play(); } catch (_) { /* autoplay policy */ }
    }
  }

  /** Resume mod playback (call on user gesture to satisfy autoplay policy). */
  resumeMod() {
    if (this._audioCtx && this._audioCtx.state === 'suspended') {
      this._audioCtx.resume();
    }
    for (const [, ch] of this.channels) {
      if (ch.type === 'mod' && ch.modPlayer) {
        ch.modPlayer.unpause();
        ch.modPlaying = true;
      }
    }
  }

  /** Pause mod playback. */
  pauseMod() {
    for (const [, ch] of this.channels) {
      if (ch.type === 'mod' && ch.modPlayer) {
        ch.modPlayer.pause();
        ch.modPlaying = false;
      }
    }
  }

  /** @returns {boolean} True if mod is currently playing. */
  get modPlaying() {
    for (const ch of this.channels.values()) {
      if (ch.type === 'mod') return ch.modPlaying;
    }
    return false;
  }

  /** Get the first mod channel's playback state. */
  getModState() {
    for (const ch of this.channels.values()) {
      if (ch.type === 'mod') {
        return { currentTime: ch.modCurrentTime, duration: ch.modDuration };
      }
    }
    return null;
  }

  /** Seek mod to a specific position (fraction 0-1). */
  seekMod(fraction) {
    for (const [, ch] of this.channels) {
      if (ch.type === 'mod' && ch.modPlayer) {
        ch.modPlayer.setPos(fraction);
      }
    }
  }

  /**
   * Switch the mod source on the first mod channel.
   * @param {string} url  Absolute URL to the new MOD file.
   */
  async switchModSource(url, gain) {
    // Find the mod channel number
    let modChannel = -1;
    for (const [channel, ch] of this.channels) {
      if (ch.type === 'mod') { modChannel = channel; break; }
    }
    if (modChannel < 0) return;

    const ch = this.channels.get(modChannel);
    ch.modPlayer.stop();
    ch.modPlaying = false;

    const res = await fetch(url);
    if (!res.ok) throw new Error(`MOD fetch failed: HTTP ${res.status}`);
    const buffer = await res.arrayBuffer();
    ch.modBuffer = buffer;

    ch.modPlayer.gain.gain.value = gain || 1;
    ch.modPlayer.play(buffer);
    ch.modPlaying = true;
  }

  /**
   * Set the playback gain for the first audio-like channel (audio or mod).
   * @param {number} gain  Linear gain multiplier (1 = unity)
   */
  setGain(gain) {
    for (const ch of this.channels.values()) {
      if (ch.type === 'mod' && ch.modPlayer) {
        ch.modPlayer.gain.gain.value = gain;
        return;
      }
      if (ch.type === 'audio' && ch.gainNode) {
        ch.gainNode.gain.value = gain;
        return;
      }
    }
  }

  /**
   * Get the media type for the first audio-like channel.
   * @returns {'audio'|'mod'|null}
   */
  get audioType() {
    for (const ch of this.channels.values()) {
      if (ch.type === 'audio' || ch.type === 'mod') return ch.type;
    }
    return null;
  }
}
