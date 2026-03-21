/**
 * App entry point — wires together sidebar, renderer, editor, and splitter.
 */

import Renderer from "./renderer.js";
import Editor from "./editor.js";
import Sidebar from "./sidebar.js";
import { initSplitter } from "./splitter.js";
import { upsertCustomShader, loadCustomShaders } from "./store.js";

// ── DOM refs ──────────────────────────────────────────────
const canvas        = document.getElementById("glcanvas");
const errorOverlay  = document.getElementById("error-overlay");
const debugBox      = document.getElementById("debug-box");
const fpsDisplay    = document.getElementById("fps-display");
const timeDisplay   = document.getElementById("time-display");
const btnApply      = document.getElementById("btn-apply");
const btnPlayPause  = document.getElementById("btn-playpause");
const btnDebug      = document.getElementById("btn-debug");
const btnPopout     = document.getElementById("btn-popout");
const btnToggleList = document.getElementById("btn-toggle-list");
const btnNew        = document.getElementById("btn-new");
const btnDownload   = document.getElementById("btn-download");
const btnDuplicate  = document.getElementById("btn-duplicate");
const btnDelete     = document.getElementById("btn-delete");
const sidebarList   = document.getElementById("sidebar-list");

// ── State ─────────────────────────────────────────────────
let currentName = null;   // active custom shader name (null = built-in)
let currentPath = null;   // active built-in shader path
let popoutWin = null;     // reference to pop-out window
let popoutPoll = null;    // interval to detect pop-out closure
let debugVisible = false; // debug overlay state

// ── Renderer ──────────────────────────────────────────────
const renderer = new Renderer(canvas);
function fpsHandler(fps) {
  fpsDisplay.textContent = fps + " FPS";
  const t = activeRenderer().getTime();
  const mins = Math.floor(t / 60);
  const secs = Math.floor(t % 60);
  const timeStr =
    String(mins).padStart(2, "0") + ":" +
    String(secs).padStart(2, "0");
  timeDisplay.textContent = timeStr;
  // Mirror to pop-out
  if (popoutWin && !popoutWin.closed && popoutWin._fpsEl) {
    popoutWin._fpsEl.textContent = fps + " FPS";
    popoutWin._timeEl.textContent = timeStr;
  }
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

// ── Icon bar ──────────────────────────────────────────────
btnDebug.addEventListener("click", () => {
  debugVisible = !debugVisible;
  btnDebug.classList.toggle("active", debugVisible);
  debugBox.classList.toggle("hidden", !debugVisible);
  if (popoutWin && !popoutWin.closed && popoutWin._debugBox) {
    popoutWin._debugBox.style.display = debugVisible ? "" : "none";
  }
});

btnPopout.addEventListener("click", () => {
  if (popoutWin && !popoutWin.closed) {
    closePopout();
  } else {
    openPopout();
  }
});

btnToggleList.addEventListener("click", () => {
  const hidden = sidebarList.classList.toggle("hidden");
  btnToggleList.textContent = hidden ? "left_panel_open" : "left_panel_close";
  btnNew.classList.toggle("hidden", hidden);
  btnDownload.classList.toggle("hidden", hidden);
  btnDuplicate.classList.toggle("hidden", hidden);
  btnDelete.classList.toggle("hidden", hidden);
});

btnNew.addEventListener("click", () => sidebar.createNew());
btnDownload.addEventListener("click", downloadCustomShaders);
btnDuplicate.addEventListener("click", () => sidebar.duplicateSelected(editor.getValue()));

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
    applyShader(source);
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
const hsplit = document.getElementById("hsplit");

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

function openPopout() {
  if (popoutWin && !popoutWin.closed) return;

  // Stop embedded rendering
  renderer.stop();
  previewPane.style.display = "none";
  hsplit.style.display = "none";
  btnPopout.classList.add("active");
  editor.layout();

  popoutWin = window.open("", "shader_preview", "width=800,height=600");
  const doc = popoutWin.document;
  doc.title = "Shader Preview";
  doc.body.style.cssText = "margin:0;background:#000;overflow:hidden";

  // Debug overlay
  const dbg = doc.createElement("div");
  dbg.id = "debug-box";
  dbg.style.cssText = "position:fixed;top:8px;right:8px;background:rgba(0,0,0,0.65);color:#0f0;font-family:monospace;font-size:12px;padding:4px 8px;border-radius:4px;z-index:5;pointer-events:none;display:none";
  const fpsEl = doc.createElement("div");
  const timeEl = doc.createElement("div");
  dbg.appendChild(fpsEl);
  dbg.appendChild(timeEl);
  doc.body.appendChild(dbg);
  popoutWin._debugBox = dbg;
  popoutWin._fpsEl = fpsEl;
  popoutWin._timeEl = timeEl;
  // Sync current debug visibility
  dbg.style.display = debugVisible ? "" : "none";

  const c = doc.createElement("canvas");
  c.style.cssText = "display:block;width:100%;height:100%";
  doc.body.appendChild(c);

  const r = new Renderer(c);
  popoutWin._renderer = r;
  r.onFps = fpsHandler;
  r.compile(editor.getValue());
  // Sync pause state
  if (renderer.paused) r.togglePause();
  r.start();

  // Poll to detect the pop-out being closed (beforeunload is unreliable)
  popoutPoll = setInterval(() => {
    if (!popoutWin || popoutWin.closed) {
      clearInterval(popoutPoll);
      popoutPoll = null;
      btnPopout.classList.remove("active");
      restoreEmbedded();
      popoutWin = null;
    }
  }, 300);
}

function closePopout() {
  if (popoutPoll) { clearInterval(popoutPoll); popoutPoll = null; }
  if (popoutWin && !popoutWin.closed) popoutWin.close();
  popoutWin = null;
  btnPopout.classList.remove("active");
  restoreEmbedded();
}

function restoreEmbedded() {
  previewPane.style.display = "";
  hsplit.style.display = "";
  // Recompile current source into embedded renderer so it's in sync
  renderer.compile(editor.getValue());
  renderer.start();
  editor.layout();
}

// ── Boot ──────────────────────────────────────────────────

// Close any orphaned pop-out from a previous session
const orphan = window.open("", "shader_preview");
if (orphan && !orphan.closed && orphan.location.href !== "about:blank") {
  orphan.close();
}

// Close pop-out when the main window unloads (reload / close)
window.addEventListener("beforeunload", () => {
  if (popoutWin && !popoutWin.closed) popoutWin.close();
});

const lastKey = localStorage.getItem("simpleshader_last");
if (!lastKey || !sidebar.selectByKey(lastKey)) {
  sidebar.selectFirst();
}
