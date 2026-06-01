/**
 * AHX Player — plays AHX (Abyss' Highest eXperience) tracker files.
 *
 * Shader annotation (via @iChannel):
 *   // @iChannel0 path/to/song.ahx  ahx
 *
 * The ahx.js library (from bryc/ahx-web-player) is loaded once as a <script>
 * tag since it uses globals (AHXSong, AHXPlayer, AHXOutput, AHXWaves).
 *
 * Audio is routed through an AnalyserNode for FFT data, matching the same
 * 256×2 LUMINANCE texture layout as mod-player.js and media-loader.js.
 *
 * Seeking is implemented via restart + silent fast-forward since AHX has
 * no native seek API.
 */

const AHX_SCRIPT_URL = "js/ahx.js";

let ahxLoaded = false;
let ahxLoadPromise = null;

function loadAhxLib() {
  if (ahxLoaded) return Promise.resolve();
  if (ahxLoadPromise) return ahxLoadPromise;
  ahxLoadPromise = new Promise((resolve, reject) => {
    const script = document.createElement("script");
    script.src = AHX_SCRIPT_URL;
    script.onload = () => { ahxLoaded = true; resolve(); };
    script.onerror = () => reject(new Error("Failed to load ahx.js"));
    document.head.appendChild(script);
  });
  return ahxLoadPromise;
}

// ── AhxPlayer class ───────────────────────────────────────

export default class AhxPlayer {
  constructor() {
    this._audioCtx    = null;
    this._scriptNode  = null;
    this._analyser    = null;
    this._gainNode    = null;
    this._song        = null;
    this._player      = null;   // AHXPlayer instance
    this._output      = null;   // AHXOutput instance

    this._playing     = false;
    this._hasAudio    = false;
    this._paused      = false;

    // Playback tracking
    this._playingTime = 0;      // IRQ frames elapsed
    this._sampleRate  = 0;
    this._songEnded   = false;

    // Seek state
    this._rawData     = null;   // raw binary string for replay-from-start seek

    // FFT data (256-bin, same layout as MediaLoader)
    this._freqData = null;
    this._waveData = null;
    this._texData  = null;
  }

  // ── Public getters ──────────────────────────────────────

  get hasAudio()    { return this._hasAudio; }
  get playing()     { return this._playing; }

  /** Current playback time in seconds. */
  get currentTime() {
    if (!this._player) return 0;
    // PlayingTime increments at 50 Hz (Amiga VBlank rate) × SpeedMultiplier
    const mult = this._song ? this._song.SpeedMultiplier : 1;
    return this._player.PlayingTime / (50 * mult);
  }

  /** Estimated song duration in seconds (not always exact). */
  get duration() {
    // AHX has no built-in duration field. Estimate from structure.
    if (!this._song) return 0;
    // Rough heuristic: PositionNr × TrackLength × default tempo ticks / 50Hz
    const mult = this._song.SpeedMultiplier || 1;
    const ticks = this._song.PositionNr * this._song.TrackLength * 6; // 6 = default tempo
    return ticks / (50 * mult);
  }

  get songEnded() { return this._songEnded; }

  // ── AudioContext ────────────────────────────────────────

  get audioContext() { return this._audioCtx; }
  get gain() { return this._gainNode; }

  _ensureAudioCtx() {
    if (!this._audioCtx) {
      this._audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    }
    this._sampleRate = this._audioCtx.sampleRate;
  }

  // ── Load ────────────────────────────────────────────────

  /**
   * Load an AHX file from binary data (ArrayBuffer) and prepare for playback.
   * @param {ArrayBuffer} buffer  Raw .ahx file data
   * @param {number} [gain=1]  Linear gain multiplier
   */
  async loadFromBuffer(buffer, gain) {
    this.stop();
    await loadAhxLib();
    this._ensureAudioCtx();

    // Convert ArrayBuffer → binary string (ahx.js expects charCodeAt-based data)
    const bytes = new Uint8Array(buffer);
    let binStr = "";
    for (let i = 0; i < bytes.length; i++) {
      binStr += String.fromCharCode(bytes[i]);
    }
    this._rawData = binStr;

    // Create AHX structures
    const song = new window.AHXSong();
    const stream = new window.dataType();
    stream.data = binStr;
    song.InitSong(stream);
    this._song = song;

    // Create player + output
    const waves = new window.AHXWaves();
    this._player = window.AHXPlayer(waves);
    this._output = window.AHXOutput(this._player);

    this._player.InitSong(song);
    this._player.InitSubsong(0);
    this._output.Init(this._sampleRate, 16);

    // Audio graph: ScriptProcessor → GainNode → AnalyserNode → destination
    if (this._scriptNode) this._scriptNode.disconnect();

    this._gainNode = this._audioCtx.createGain();
    this._gainNode.gain.value = gain || 1;

    this._analyser = this._audioCtx.createAnalyser();
    this._analyser.fftSize = 512;
    this._analyser.smoothingTimeConstant = 0.8;

    this._freqData = new Uint8Array(256);
    this._waveData = new Uint8Array(256);
    this._texData  = new Uint8Array(256 * 2);

    // ScriptProcessor drives the AHX mixer
    const bufferSize = 8192;
    this._scriptNode = this._audioCtx.createScriptProcessor(bufferSize, 0, 2);

    // Mixer state
    let bufferFull = 0;
    let bufferOffset = 0;
    const output = this._output;
    const player = this._player;
    const self = this;

    this._scriptNode.onaudioprocess = (e) => {
      if (!self._playing) {
        // Output silence when paused
        e.outputBuffer.getChannelData(0).fill(0);
        e.outputBuffer.getChannelData(1).fill(0);
        return;
      }

      const left = e.outputBuffer.getChannelData(0);
      const right = e.outputBuffer.getChannelData(1);
      let want = e.outputBuffer.length;
      let out = 0;

      while (want > 0) {
        if (bufferFull === 0) {
          output.MixBuffer();
          bufferFull = output.BufferSize;
          bufferOffset = 0;
        }

        const can = Math.min(bufferFull - bufferOffset, want);
        want -= can;
        for (let i = 0; i < can; i++) {
          const sample = output.MixingBuffer[bufferOffset++] / (128 * 4);
          left[out] = right[out] = sample;
          out++;
        }
        if (bufferOffset >= bufferFull) {
          bufferFull = 0;
          bufferOffset = 0;
        }
      }

      // Check end-of-song
      if (player.SongEndReached) {
        self._songEnded = true;
      }
    };

    this._scriptNode.connect(this._gainNode);
    this._gainNode.connect(this._analyser);
    this._analyser.connect(this._audioCtx.destination);

    this._hasAudio = true;
    this._playing = false;
    this._paused = false;
    this._songEnded = false;
  }

  /**
   * Fetch an AHX file by URL and prepare for playback.
   * @param {string} url  URL to the .ahx file
   * @param {number} [gain=1]  Linear gain multiplier
   */
  async load(url, gain) {
    const res = await fetch(url);
    if (!res.ok) throw new Error(`AHX fetch failed: HTTP ${res.status}`);
    const buffer = await res.arrayBuffer();
    await this.loadFromBuffer(buffer, gain);
  }

  // ── Playback ────────────────────────────────────────────

  play() {
    if (!this._hasAudio) return;
    this.resumeContext();
    this._playing = true;
    this._paused = false;
    this._songEnded = false;
  }

  pause() {
    if (!this._playing) return;
    this._playing = false;
    this._paused = true;
  }

  unpause() {
    if (!this._paused || !this._hasAudio) return;
    this.resumeContext();
    this._playing = true;
    this._paused = false;
  }

  stop() {
    this._playing = false;
    this._paused = false;
    if (this._scriptNode) {
      this._scriptNode.disconnect();
      this._scriptNode = null;
    }
    if (this._gainNode) {
      this._gainNode.disconnect();
      this._gainNode = null;
    }
    if (this._analyser) {
      this._analyser.disconnect();
      this._analyser = null;
    }
    this._hasAudio = false;
    this._song = null;
    this._player = null;
    this._output = null;
    this._rawData = null;
  }

  /**
   * Seek to a target time in seconds.
   * Since AHX has no native seek, this re-initialises the song and
   * fast-forwards the mixer silently to the target position.
   */
  seekTo(targetTime) {
    if (!this._hasAudio || !this._rawData || !this._song) return;
    const wasPaused = this._paused;

    // Re-init player state
    this._player.InitSong(this._song);
    this._player.InitSubsong(0);
    this._output.Init(this._sampleRate, 16);
    this._songEnded = false;

    // Fast-forward: each MixBuffer call advances by BufferSize samples
    // and calls PlayIRQ (SpeedMultiplier times)
    if (targetTime > 0) {
      const samplesNeeded = Math.floor(targetTime * this._sampleRate);
      let samplesAdvanced = 0;
      while (samplesAdvanced < samplesNeeded && !this._player.SongEndReached) {
        this._output.MixBuffer();
        samplesAdvanced += this._output.BufferSize;
      }
    }

    if (!wasPaused && this._playing) {
      // Keep playing
    } else {
      this._playing = !wasPaused && this._hasAudio;
      this._paused = wasPaused;
    }
  }

  resumeContext() {
    if (this._audioCtx && this._audioCtx.state === "suspended") {
      this._audioCtx.resume();
    }
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

  /** @returns {{currentTime: number, duration: number}|null} */
  getState() {
    if (!this._hasAudio) return null;
    return { currentTime: this.currentTime, duration: this.duration };
  }
}
