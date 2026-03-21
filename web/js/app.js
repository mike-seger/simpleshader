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

// ── State ─────────────────────────────────────────────────
let currentName = null;   // active custom shader name (null = built-in)
let popoutWin = null;     // reference to pop-out window

// ── Renderer ──────────────────────────────────────────────
const renderer = new Renderer(canvas);
renderer.onFps = (fps) => {
  fpsDisplay.textContent = fps + " FPS";
  const t = renderer.getTime();
  const mins = Math.floor(t / 60);
  const secs = Math.floor(t % 60);
  timeDisplay.textContent =
    String(mins).padStart(2, "0") + ":" +
    String(secs).padStart(2, "0");
};
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
  renderer.togglePause();
  btnPlayPause.textContent = renderer.paused ? "\u25B6" : "\u25A0";
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

// ── Apply / compile ───────────────────────────────────────

function applyShader(source) {
  // Save to custom storage if editing a custom shader
  if (currentName) {
    sidebar.saveToCustom(currentName, source);
  }

  const err = renderer.compile(source);
  if (err) {
    showError(err);
  } else {
    hideError();
  }

  // Mirror to pop-out if open
  if (popoutWin && !popoutWin.closed && popoutWin._renderer) {
    popoutWin._renderer.compile(source);
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
  r.compile(editor.getValue());
  r.start();

  popoutWin.addEventListener("beforeunload", () => {
    chkPopout.checked = false;
    restoreEmbedded();
    popoutWin = null;
  });
}

function closePopout() {
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
