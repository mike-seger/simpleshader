/**
 * App entry point — wires together sidebar, renderer, editor, and splitter.
 */

import Renderer from "./renderer.js";
import Editor from "./editor.js";
import Sidebar from "./sidebar.js";
import { initSplitter } from "./splitter.js";
import { upsertCustomShader } from "./store.js";

// ── DOM refs ──────────────────────────────────────────────
const canvas        = document.getElementById("glcanvas");
const errorOverlay  = document.getElementById("error-overlay");
const debugBox      = document.getElementById("debug-box");
const fpsDisplay    = document.getElementById("fps-display");
const timeDisplay   = document.getElementById("time-display");
const btnApply      = document.getElementById("btn-apply");
const btnPlayPause  = document.getElementById("btn-playpause");
const chkDebug      = document.getElementById("chk-debug");
const chkPopout     = document.getElementById("chk-popout");
const btnToggleList = document.getElementById("btn-toggle-list");
const btnNew        = document.getElementById("btn-new");
const btnDuplicate  = document.getElementById("btn-duplicate");
const btnDelete     = document.getElementById("btn-delete");
const sidebarList   = document.getElementById("sidebar-list");

// ── State ─────────────────────────────────────────────────
let currentName = null;   // active custom shader name (null = built-in)
let popoutWin = null;     // reference to pop-out window
let popoutPoll = null;    // interval to detect pop-out closure

// ── Renderer ──────────────────────────────────────────────
const renderer = new Renderer(canvas);
function fpsHandler(fps) {
  fpsDisplay.textContent = fps + " FPS";
  const t = activeRenderer().getTime();
  const mins = Math.floor(t / 60);
  const secs = Math.floor(t % 60);
  timeDisplay.textContent =
    String(mins).padStart(2, "0") + ":" +
    String(secs).padStart(2, "0");
}
renderer.onFps = fpsHandler;
renderer.start();

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
  () => editor.layout(),
);

// ── Toolbar ───────────────────────────────────────────────
btnApply.addEventListener("click", () => applyShader(editor.getValue()));

btnPlayPause.addEventListener("click", () => {
  const r = activeRenderer();
  r.togglePause();
  btnPlayPause.textContent = r.paused ? "play_arrow" : "pause";
});

chkDebug.addEventListener("change", () => {
  debugBox.classList.toggle("hidden", !chkDebug.checked);
});

chkPopout.addEventListener("change", () => {
  if (chkPopout.checked) {
    openPopout();
  } else {
    closePopout();
  }
});

// ── Icon bar ──────────────────────────────────────────────
btnToggleList.addEventListener("click", () => {
  const hidden = sidebarList.classList.toggle("hidden");
  btnToggleList.textContent = hidden ? "left_panel_open" : "left_panel_close";
  btnNew.classList.toggle("hidden", hidden);
  btnDuplicate.classList.toggle("hidden", hidden);
  btnDelete.classList.toggle("hidden", hidden);
});

btnNew.addEventListener("click", () => sidebar.createNew());
btnDuplicate.addEventListener("click", () => sidebar.duplicateSelected(editor.getValue()));
btnDelete.addEventListener("click", () => sidebar.deleteSelected());

// ── Shader selection ──────────────────────────────────────

async function onShaderSelect(path, source) {
  if (source !== undefined) {
    // Custom shader — source comes from localStorage
    currentName = path.replace("custom:", "");
    editor.setValue(source);
    applyShader(source);
  } else {
    currentName = null;
    await loadShader(path);
  }
}

async function loadShader(path) {
  try {
    const res = await fetch(path);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const source = await res.text();
    editor.setValue(source);
    applyShader(source);
  } catch (err) {
    showError("Failed to load shader:\n" + err.message);
  }
}

// ── Active renderer helper ────────────────────────────────

function activeRenderer() {
  return (popoutWin && !popoutWin.closed && popoutWin._renderer)
    ? popoutWin._renderer
    : renderer;
}

// ── Apply / compile ───────────────────────────────────────

function applyShader(source) {
  // Save to custom storage if editing a custom shader
  if (currentName) {
    sidebar.saveToCustom(currentName, source);
  }

  const err = activeRenderer().compile(source);
  if (err) {
    showError(err);
  } else {
    hideError();
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

const previewPane = document.getElementById("preview-pane");

function openPopout() {
  if (popoutWin && !popoutWin.closed) return;

  // Stop embedded rendering
  renderer.stop();
  previewPane.style.display = "none";

  popoutWin = window.open("", "shader_preview", "width=800,height=600");
  const doc = popoutWin.document;
  doc.title = "Shader Preview";
  doc.body.style.cssText = "margin:0;background:#000;overflow:hidden";
  const c = doc.createElement("canvas");
  c.style.cssText = "display:block;width:100%;height:100%";
  doc.body.appendChild(c);

  const r = new Renderer(c);
  popoutWin._renderer = r;
  r.onFps = fpsHandler;
  r.compile(editor.getValue());
  r.start();

  // Poll to detect the pop-out being closed (beforeunload is unreliable)
  popoutPoll = setInterval(() => {
    if (!popoutWin || popoutWin.closed) {
      clearInterval(popoutPoll);
      popoutPoll = null;
      chkPopout.checked = false;
      restoreEmbedded();
      popoutWin = null;
    }
  }, 300);
}

function closePopout() {
  if (popoutPoll) { clearInterval(popoutPoll); popoutPoll = null; }
  if (popoutWin && !popoutWin.closed) popoutWin.close();
  popoutWin = null;
  restoreEmbedded();
}

function restoreEmbedded() {
  previewPane.style.display = "";
  renderer.start();
}

// ── Boot ──────────────────────────────────────────────────
sidebar.selectFirst();
