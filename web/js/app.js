/**
 * App entry point — wires together sidebar, renderer, editor, and splitter.
 */

import Renderer from "./renderer.js";
import Editor from "./editor.js";
import Sidebar from "./sidebar.js";
import { initSplitter } from "./splitter.js";
import { upsertCustomShader, loadCustomShaders } from "./store.js";
import ShaderTuner, { buildAudioConfig } from "./shader-tuner.js";
import { MediaLoader, parseMediaAnnotations } from "./media-loader.js";
import GpuAudio, { parseGpuAudioAnnotation } from "./gpu-audio.js";
import { toShadertoy } from "./shadertoy-export.js";
import PopoutManager from "./popout.js";
import { resolveForPath, injectChannelUniforms } from "./shader-compiler.js";

// ── DOM refs ──────────────────────────────────────────────
const canvas        = document.getElementById("glcanvas");
const errorOverlay  = document.getElementById("error-overlay");
const debugBox      = document.getElementById("debug-box");
const fpsDisplay    = document.getElementById("fps-display");
const timeDisplay   = document.getElementById("time-display");
const resDisplay    = document.getElementById("res-display");
const btnApply      = document.getElementById("btn-apply");
const btnShadertoy  = document.getElementById("btn-shadertoy");
const btnPlayPause  = document.getElementById("btn-playpause");
const btnDebug      = document.getElementById("btn-debug");
const btnPopout     = document.getElementById("btn-popout");
const btnModeList   = document.getElementById("btn-mode-list");
const btnModeTune   = document.getElementById("btn-mode-tune");
const btnNew        = document.getElementById("btn-new");
const btnDownload   = document.getElementById("btn-download");
const btnDuplicate  = document.getElementById("btn-duplicate");
const btnSave       = document.getElementById("btn-save");
const btnDelete     = document.getElementById("btn-delete");
const sidebarList   = document.getElementById("sidebar-list");
const sidebarTuner  = document.getElementById("sidebar-tuner");
const tunerContainer = document.getElementById("tuner-container");
const timeSlider    = document.getElementById("time-slider");
const toolbarTime   = document.getElementById("toolbar-time");
const btnResetTime  = document.getElementById("btn-reset-time");
const audioControls    = document.getElementById("audio-controls");
const btnAudioPlayPause = document.getElementById("btn-audio-playpause");
const audioSlider      = document.getElementById("audio-slider");
const audioTimeEl      = document.getElementById("audio-time");

// ── State ─────────────────────────────────────────────────
let currentName = null;   // active custom shader name (null = built-in)
let currentPath = null;   // active built-in shader path
let debugVisible = false; // debug overlay state
let popout = null;        // pop-out preview manager (initialised below)

// ── Time slider state ─────────────────────────────────────
const SLIDER_INIT_MAX = 600;  // 10 minutes initial range
const SLIDER_EXTEND   = 600;  // extend by 10 minutes when reached
let sliderDragging = false;
let audioSliderDragging = false;

// ── Renderer ──────────────────────────────────────────────
const renderer = new Renderer(canvas);
const mediaLoader = new MediaLoader();
const gpuAudio = new GpuAudio();
renderer.mediaLoader = mediaLoader;
function fpsHandler(fps) {
  fpsDisplay.textContent = fps + " FPS";
  const pw = popout ? popout.win : null;
  const t = (popout ? popout.activeRenderer() : renderer).getTime();
  const mins = Math.floor(t / 60);
  const secs = Math.floor(t % 60);
  const timeStr =
    String(mins).padStart(2, "0") + ":" +
    String(secs).padStart(2, "0");
  timeDisplay.textContent = timeStr;
  const activeCanvas = (popout ? popout.activeRenderer() : renderer).canvas;
  const resStr = activeCanvas.width + "\xD7" + activeCanvas.height;
  resDisplay.textContent = resStr;
  // Mirror to pop-out
  if (pw && !pw.closed && pw._fpsEl) {
    pw._fpsEl.textContent = fps + " FPS";
    pw._timeEl.textContent = timeStr;
    if (pw._resEl) pw._resEl.textContent = resStr;
  }
}
renderer.onFps = fpsHandler;
renderer.start();

// Resume AudioContext on user interaction (autoplay policy)
document.addEventListener("click", () => {
  if (mediaLoader._audioCtx && mediaLoader._audioCtx.state === 'suspended') {
    mediaLoader._audioCtx.resume();
  }
  gpuAudio.resumeContext();
});

// Update toolbar time + slider at 10 Hz
function formatToolbarTime(t) {
  const mins = Math.floor(t / 60);
  const secs = Math.floor(t % 60);
  const cs   = Math.floor((t % 1) * 100);
  return String(mins).padStart(2, "0") + ":" +
         String(secs).padStart(2, "0") + "." +
         String(cs).padStart(2, "0");
}
function formatAudioTime(cur, dur) {
  const fmt = (t) => {
    const m = Math.floor(t / 60);
    const s = Math.floor(t % 60);
    return String(m).padStart(2, "0") + ":" + String(s).padStart(2, "0");
  };
  return fmt(cur) + " / " + fmt(dur);
}
setInterval(() => {
  const t = Math.max(0, activeRenderer().getTime());
  toolbarTime.textContent = formatToolbarTime(t);
  if (!sliderDragging) {
    const max = parseFloat(timeSlider.max);
    if (!activeRenderer().paused && t >= max) {
      timeSlider.max = String(max + SLIDER_EXTEND);
    }
    timeSlider.value = t;
  }
  // Audio slider update
  const as = mediaLoader.audioType === 'mod' ? mediaLoader.getModState()
           : gpuAudio.hasAudio ? gpuAudio.getState()
           : mediaLoader.getAudioState();
  if (as && !audioSliderDragging) {
    const dur = as.duration || 100;
    const ct = dur > 0 && as.currentTime >= dur ? as.currentTime % dur : as.currentTime;
    audioSlider.max = String(dur);
    audioSlider.value = String(ct);
    audioTimeEl.textContent = formatAudioTime(ct, dur);
  }
}, 100);

// ── Editor ────────────────────────────────────────────────
const editor = new Editor(
  document.getElementById("editor-container"),
  applyShader,
);
await editor.init();

// ── Sidebar ───────────────────────────────────────────────
const sidebar = new Sidebar(
  document.getElementById("shader-tree"),
  onShaderSelect,
);

// ── Splitter ──────────────────────────────────────────────
initSplitter(
  document.getElementById("hsplit"),
  document.getElementById("preview-pane"),
  document.getElementById("editor-pane"),
  () => { renderer.resize(); editor.layout(); },
);

// ── Toolbar ───────────────────────────────────────────────
btnApply.addEventListener("click", () => applyShader(editor.getValue()));

// ── Shadertoy export ──────────────────────────────────────
btnShadertoy.addEventListener("click", async () => {
  try {
    const shadertoyCode = await toShadertoy(editor.getValue(), src => resolveForPath(src, currentPath));
    await navigator.clipboard.writeText(shadertoyCode);
    const orig = btnShadertoy.textContent;
    btnShadertoy.textContent = '✓';
    setTimeout(() => { btnShadertoy.textContent = orig; }, 1500);
  } catch (e) {
    console.error('Shadertoy export failed:', e);
    btnShadertoy.textContent = '✗';
    setTimeout(() => { btnShadertoy.textContent = 'S'; }, 1500);
  }
});

// ── Time slider ───────────────────────────────────────────
timeSlider.addEventListener("pointerdown", () => { sliderDragging = true; });
document.addEventListener("pointerup", () => {
  sliderDragging = false;
  audioSliderDragging = false;
});
timeSlider.addEventListener("input", () => {
  const t = parseFloat(timeSlider.value);
  activeRenderer().seekTo(t);
  if (mediaLoader.audioType === 'mod') {
    const ms = mediaLoader.getModState();
    mediaLoader.seekMod(ms && ms.duration > 0 ? t % ms.duration : t);
  } else if (gpuAudio.hasAudio) {
    gpuAudio.seekTo(t);
  } else {
    const as = mediaLoader.getAudioState();
    if (as && as.duration > 0) mediaLoader.seekAudio(t % as.duration);
  }
});
btnResetTime.addEventListener("click", () => {
  activeRenderer().seekTo(0);
  if (mediaLoader.audioType === 'mod') mediaLoader.seekMod(0);
  else if (gpuAudio.hasAudio) gpuAudio.seekTo(0);
  else mediaLoader.seekAudio(0);
  timeSlider.max = String(SLIDER_INIT_MAX);
  timeSlider.value = "0";
  toolbarTime.textContent = "00:00.00";
});

// ── Audio slider ──────────────────────────────────────────
audioSlider.addEventListener("pointerdown", () => { audioSliderDragging = true; });
audioSlider.addEventListener("input", () => {
  if (mediaLoader.audioType === 'mod') mediaLoader.seekMod(parseFloat(audioSlider.value));
  else if (gpuAudio.hasAudio) gpuAudio.seekTo(parseFloat(audioSlider.value));
  else mediaLoader.seekAudio(parseFloat(audioSlider.value));
});

btnAudioPlayPause.addEventListener("click", () => {
  if (mediaLoader.audioType === 'mod') {
    if (mediaLoader.modPlaying) { mediaLoader.pauseMod(); btnAudioPlayPause.textContent = "play_arrow"; }
    else { mediaLoader.resumeMod(); btnAudioPlayPause.textContent = "pause"; }
  } else if (gpuAudio.hasAudio) {
    if (gpuAudio.playing) { gpuAudio.pause(); btnAudioPlayPause.textContent = "play_arrow"; }
    else { gpuAudio.resume(); btnAudioPlayPause.textContent = "pause"; }
  } else if (mediaLoader.audioPlaying) {
    mediaLoader.pauseAudio();
    btnAudioPlayPause.textContent = "play_arrow";
  } else {
    mediaLoader.resumeAudio();
    btnAudioPlayPause.textContent = "pause";
  }
});

btnPlayPause.addEventListener("click", () => {
  const r = activeRenderer();
  r.togglePause();
  btnPlayPause.textContent = r.paused ? "play_arrow" : "pause";
  localStorage.setItem("simpleshader_paused", r.paused ? "1" : "0");
  // Sync audio playback with renderer pause state
  if (mediaLoader.audioType === 'mod') {
    if (r.paused) { mediaLoader.pauseMod(); btnAudioPlayPause.textContent = "play_arrow"; }
    else { mediaLoader.resumeMod(); btnAudioPlayPause.textContent = "pause"; }
  } else if (gpuAudio.hasAudio) {
    if (r.paused) { gpuAudio.pause(); btnAudioPlayPause.textContent = "play_arrow"; }
    else { gpuAudio.resume(); btnAudioPlayPause.textContent = "pause"; }
  } else if (mediaLoader.hasAudio) {
    if (r.paused) {
      mediaLoader.pauseAudio();
      btnAudioPlayPause.textContent = "play_arrow";
    } else {
      mediaLoader.resumeAudio();
      btnAudioPlayPause.textContent = "pause";
    }
  }
});

// ── Icon bar ──────────────────────────────────────────────
btnDebug.addEventListener("click", () => {
  debugVisible = !debugVisible;
  btnDebug.classList.toggle("active", debugVisible);
  debugBox.classList.toggle("hidden", !debugVisible);
  popout.syncDebug(debugVisible);
});

btnPopout.addEventListener("click", () => {
  if (popout.win && !popout.win.closed) {
    popout.close();
  } else {
    popout.open(debugVisible);
  }
});

// ── Panel toggle (list / tune — independent, 4 states) ────
const tuner = new ShaderTuner(
  tunerContainer,
  () => editor.getValue(),
  async (source) => {
    editor.setValue(source);
    if (currentName) sidebar.saveToCustom(currentName, source);
    let resolved;
    try { resolved = await resolveForPath(source, currentPath); }
    catch (e) { showError(String(e)); return; }
    resolved = injectChannelUniforms(resolved, mediaLoader);
    const err = activeRenderer().compile(resolved, true);
    if (err) showError(err); else hideError();
  },
);

function applyPanelState() {
  const listOn = btnModeList.classList.contains("active");
  const tuneOn = btnModeTune.classList.contains("active");
  sidebarList.classList.toggle("hidden", !listOn);
  sidebarTuner.classList.toggle("hidden", !tuneOn);
  // Shader-action icons visible only when list panel is open
  document.body.classList.toggle("panel-list", listOn);
  document.body.classList.toggle("panel-tune", tuneOn);
  // Only build tuner controls when the editor already has a shader loaded.
  // applyShader() handles the rebuild after async shader fetch completes.
  if (tuneOn && editor.getValue().trim()) {
    tuner.build().then(hasControls => {
      if (!hasControls) sidebarTuner.classList.add("hidden");
    });
  }
  localStorage.setItem("simpleshader_panels", JSON.stringify({ list: listOn, tune: tuneOn }));
}

btnModeList.addEventListener("click", () => {
  btnModeList.classList.toggle("active");
  applyPanelState();
});

btnModeTune.addEventListener("click", () => {
  btnModeTune.classList.toggle("active");
  applyPanelState();
});

// Restore panel state from localStorage (default: list + tune open)
{
  let saved = { list: true, tune: true };
  try {
    const raw = localStorage.getItem("simpleshader_panels");
    if (raw) {
      const parsed = JSON.parse(raw);
      saved.list = parsed.list ?? true;
      saved.tune = parsed.tune ?? true;
    }
  } catch { /* ignore */ }
  // Default to list open if nothing is active
  if (!saved.list && !saved.tune) saved.list = true;
  btnModeList.classList.toggle("active", saved.list);
  btnModeTune.classList.toggle("active", saved.tune);
  applyPanelState();
}

btnNew.addEventListener("click", () => sidebar.createNew());
btnDownload.addEventListener("click", downloadCustomShaders);
if (btnDuplicate) btnDuplicate.addEventListener("click", () => sidebar.duplicateSelected(editor.getValue()));

// ── Save button ───────────────────────────────────────────
btnSave.addEventListener("click", () => {
  let source = editor.getValue();
  if (currentName) {
    // Already a custom shader — update in place
    sidebar.saveToCustom(currentName, source);
  } else {
    // Built-in shader — normalize relative @iChannel / @include paths to root-relative
    if (currentPath) {
      const shaderDir = currentPath.replace(/[^/]*$/, '');
      source = source.replace(
        /^(\s*\/\/\s*@(?:iChannel\d+|include)\s+)(?:"([^"]+)"|(\S+))/gm,
        (match, prefix, quoted, bare) => {
          const raw = quoted || bare;
          if (!raw || /^https?:\/\//.test(raw)) return match;
          // Resolve the relative path against the shader directory
          const parts = (shaderDir + raw).split('/');
          const resolved = [];
          for (const p of parts) {
            if (p === '..') resolved.pop();
            else if (p !== '.') resolved.push(p);
          }
          const abs = resolved.join('/');
          return prefix + '"' + abs + '"';
        }
      );
      editor.setValue(source);
    }
    // Derive name from active element or path
    let baseName = sidebar.getActiveDisplayName() || 'shader';
    const customs = loadCustomShaders();
    const existing = new Set(customs.map(c => c.name));
    let name = baseName;
    if (existing.has(name)) {
      for (let i = 2; i <= 999; i++) {
        const candidate = baseName + " (" + i + ")";
        if (!existing.has(candidate)) { name = candidate; break; }
      }
    }
    upsertCustomShader(name, source);
    currentName = name;
    currentPath = null;
    localStorage.setItem("simpleshader_last", "custom:" + name);
    sidebar.rebuild();
    sidebar.selectByKey("custom:" + name);
  }
  // brief visual feedback
  const orig = btnSave.textContent;
  btnSave.textContent = 'check_circle';
  setTimeout(() => { btnSave.textContent = orig; }, 1000);
});

// ── Drag-and-drop import ──────────────────────────────────
let dragCounter = 0;
sidebarList.addEventListener("dragenter", (e) => {
  e.preventDefault();
  dragCounter++;
  sidebarList.classList.add("drag-over");
});
sidebarList.addEventListener("dragover", (e) => e.preventDefault());
sidebarList.addEventListener("dragleave", () => {
  dragCounter--;
  if (dragCounter <= 0) { dragCounter = 0; sidebarList.classList.remove("drag-over"); }
});
sidebarList.addEventListener("drop", async (e) => {
  e.preventDefault();
  dragCounter = 0;
  sidebarList.classList.remove("drag-over");
  const files = Array.from(e.dataTransfer.files);
  const entries = [];
  for (const file of files) {
    if (file.name.endsWith(".glsl")) {
      const source = await file.text();
      const name = file.name.replace(/\.glsl$/, "");
      entries.push({ name, source });
    } else if (file.name.endsWith(".zip")) {
      try {
        const JSZip = await loadJSZip();
        const zip = await JSZip.loadAsync(file);
        const promises = [];
        zip.forEach((path, entry) => {
          if (!entry.dir && path.endsWith(".glsl")) {
            promises.push(entry.async("string").then(source => {
              const name = path.split("/").pop().replace(/\.glsl$/, "");
              entries.push({ name, source });
            }));
          }
        });
        await Promise.all(promises);
      } catch (err) {
        console.error("Failed to read zip:", err);
      }
    }
  }
  if (entries.length) sidebar.importShaders(entries);
});
btnDelete.addEventListener("click", () => sidebar.deleteSelected());

// ── Shader selection ──────────────────────────────────────

async function onShaderSelect(path, source) {
  if (source !== undefined) {
    // Custom shader — source comes from localStorage
    currentName = path.replace("custom:", "");
    currentPath = null;
    localStorage.setItem("simpleshader_last", "custom:" + currentName);
    editor.setValue(source);
    applyShader(source, true);
  } else {
    currentName = null;
    currentPath = path;
    localStorage.setItem("simpleshader_last", path);
    await loadShader(path);
  }
}

async function loadShader(path) {
  try {
    const res = await fetch(path);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const source = await res.text();
    editor.setValue(source);
    applyShader(source, true);
  } catch (err) {
    showError("Failed to load shader:\n" + err.message);
  }
}

// ── Active renderer helper ────────────────────────────────

function activeRenderer() {
  return popout ? popout.activeRenderer() : renderer;
}

// ── Apply / compile ───────────────────────────────────────

async function applyShader(source, focusTuner) {
  // Save to custom storage if editing a custom shader
  if (currentName) {
    sidebar.saveToCustom(currentName, source);
  }

  // Parse and load @iChannel media annotations
  const baseUrl = currentPath
    ? new URL(currentPath, window.location.href).href
    : window.location.href;
  const mediaAnns = parseMediaAnnotations(source);
  try {
    await mediaLoader.load(mediaAnns, baseUrl);
  } catch (e) {
    showError(String(e));
    return;
  }
  // Assign to active renderer
  activeRenderer().mediaLoader = mediaLoader;

  // Parse and load @gpu-audio annotation
  const gpuAudioAnn = parseGpuAudioAnnotation(source);
  if (gpuAudioAnn) {
    try {
      const soundUrl = new URL(gpuAudioAnn.path, baseUrl).href;
      const soundRes = await fetch(soundUrl);
      if (!soundRes.ok) throw new Error(`HTTP ${soundRes.status}`);
      const soundSrc = await soundRes.text();
      await gpuAudio.load(soundSrc, 44100, gpuAudioAnn.duration);
    } catch (e) {
      console.warn('GPU audio load failed:', e);
      gpuAudio.dispose();
    }
  } else {
    gpuAudio.dispose();
  }

  // Show/hide audio toolbar controls
  const hasAudio = mediaLoader.hasAudio || gpuAudio.hasAudio;
  audioControls.classList.toggle("hidden", !hasAudio);

  // Set audio config for tuner panel
  const audioConfig = hasAudio ? await buildAudioConfig(mediaAnns, baseUrl, {
    mediaLoader,
    getSource: () => editor.getValue(),
    setSource: (s) => editor.setValue(s),
    applyShader,
  }) : null;
  tuner.setAudioConfig(audioConfig);

  // Apply per-track gain normalization
  if (audioConfig && audioConfig.currentGain !== 1) {
    mediaLoader.setGain(audioConfig.currentGain);
  }

  let resolved;
  try {
    resolved = await resolveForPath(source, currentPath);
  } catch (e) {
    showError(String(e));
    return;
  }

  resolved = injectChannelUniforms(resolved, mediaLoader);

  const err = activeRenderer().compile(resolved);
  if (err) {
    showError(err);
  } else {
    hideError();
    // Reset slider when time resets
    timeSlider.max = String(SLIDER_INIT_MAX);
    timeSlider.value = "0";
    toolbarTime.textContent = "00:00.00";
    // Rebuild tuner controls for the newly loaded shader
    if (btnModeTune.classList.contains("active")) {
      tuner.build().then(hasControls => {
        if (!hasControls) sidebarTuner.classList.add("hidden");
        else {
          sidebarTuner.classList.remove("hidden");
          if (focusTuner) tuner.focusFirstControl();
        }
      });
    }
  }
}

function showError(msg) {
  errorOverlay.textContent = msg;
  errorOverlay.classList.remove("hidden");
}

function hideError() {
  errorOverlay.classList.add("hidden");
  errorOverlay.textContent = "";
}

// ── Pop-out preview ───────────────────────────────────────

popout = new PopoutManager({
  renderer,
  Renderer,
  mediaLoader,
  editor,
  fpsHandler,
  btnPopout,
  previewPane: document.getElementById("preview-pane"),
  editorPane:  document.getElementById("editor-pane"),
  hsplit:      document.getElementById("hsplit"),
  compileSource: async (r) => {
    const src = await resolveForPath(editor.getValue(), currentPath);
    r.compile(injectChannelUniforms(src, mediaLoader));
  },
});

// ── Download custom shaders as ZIP ────────────────────────
let jsZipPromise;
function loadJSZip() {
  if (!jsZipPromise) {
    jsZipPromise = import("https://cdn.jsdelivr.net/npm/jszip@3/+esm")
      .then(m => m.default);
  }
  return jsZipPromise;
}

async function downloadCustomShaders() {
  const shaders = loadCustomShaders();
  if (!shaders.length) return;
  const JSZip = await loadJSZip();
  const zip = new JSZip();
  const folder = zip.folder("custom");
  for (const { name, source } of shaders) {
    folder.file(name.endsWith(".glsl") ? name : name + ".glsl", source);
  }
  const blob = await zip.generateAsync({ type: "blob" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = "custom-shaders.zip";
  a.click();
  URL.revokeObjectURL(url);
}

// ── Boot ──────────────────────────────────────────────────

window.addEventListener("beforeunload", () => popout.destroy());

// Check for ?shader= query parameter first, then fall back to localStorage
{
  const params = new URLSearchParams(window.location.search);
  const shaderParam = params.get("shader");
  let booted = false;
  if (shaderParam) {
    // Resolve relative to web/shaders/
    const path = "web/shaders/" + shaderParam;
    booted = sidebar.selectByKey(path);
  }
  if (!booted) {
    const lastKey = localStorage.getItem("simpleshader_last");
    if (!lastKey || !sidebar.selectByKey(lastKey)) {
      sidebar.selectFirst();
    }
  }
}

// Restore paused state
if (localStorage.getItem("simpleshader_paused") === "1") {
  if (!renderer.paused) renderer.togglePause();
  btnPlayPause.textContent = "play_arrow";
}
