/**
 * App entry point — wires together sidebar, renderer, editor, and splitter.
 */

import Renderer from "./renderer.js";
import Editor from "./editor.js";
import Sidebar from "./sidebar.js";
import { initSplitter } from "./splitter.js";

// ── DOM refs ──────────────────────────────────────────────
const canvas       = document.getElementById("glcanvas");
const errorOverlay = document.getElementById("error-overlay");
const debugBox     = document.getElementById("debug-box");
const fpsDisplay   = document.getElementById("fps-display");
const btnApply     = document.getElementById("btn-apply");
const chkDebug     = document.getElementById("chk-debug");

// ── Renderer ──────────────────────────────────────────────
const renderer = new Renderer(canvas);
renderer.onFps = (fps) => { fpsDisplay.textContent = fps + " FPS"; };
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
  loadShader,
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
chkDebug.addEventListener("change", () => {
  debugBox.classList.toggle("hidden", !chkDebug.checked);
});

// ── Shader loading ────────────────────────────────────────
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

function applyShader(source) {
  const err = renderer.compile(source);
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

// ── Boot ──────────────────────────────────────────────────
sidebar.selectFirst();
