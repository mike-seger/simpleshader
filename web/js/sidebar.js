/**
 * Sidebar — collapsible tree with keyboard navigation.
 * Renders built-in shaders from the index + custom shaders from localStorage.
 */

import SHADER_INDEX from "../shaders/index.js";
import { loadCustomShaders, upsertCustomShader, renameCustomShader } from "./store.js";

export default class Sidebar {
  /**
   * @param {HTMLElement} container
   * @param {(path: string, source?: string) => void} onSelect
   */
  constructor(container, onSelect) {
    this._container = container;
    this._onSelect = onSelect;
    this._activeEl = null;
    this._items = [];
    this._build();
    this._initKeyboard();
  }

  /* ── Build the tree ──────────────────────────────────── */

  _build() {
    this._container.innerHTML = "";
    this._items = [];

    const frag = document.createDocumentFragment();

    for (const group of SHADER_INDEX) {
      frag.appendChild(this._buildFolder(group.folder, group.shaders, false));
    }

    frag.appendChild(this._buildCustomFolder());

    this._container.appendChild(frag);
    this._items = Array.from(this._container.querySelectorAll(".tree-item"));
  }

  _buildFolder(label, shaders, isCustom) {
    const folder = document.createElement("div");
    folder.className = "tree-folder";

    const lbl = document.createElement("div");
    lbl.className = "tree-folder-label";
    lbl.innerHTML = `<span class="arrow">▼</span> ${this._esc(label)}`;
    lbl.addEventListener("click", () => folder.classList.toggle("collapsed"));

    if (isCustom) {
      const addBtn = document.createElement("button");
      addBtn.className = "tree-add-btn";
      addBtn.textContent = "+";
      addBtn.title = "New shader";
      addBtn.addEventListener("click", (e) => { e.stopPropagation(); this._createNew(); });
      lbl.appendChild(addBtn);
    }

    folder.appendChild(lbl);

    const children = document.createElement("div");
    children.className = "tree-children";

    for (const shader of shaders) {
      const item = document.createElement("div");
      item.className = "tree-item";
      item.textContent = shader.name;
      item.tabIndex = -1;

      if (isCustom) {
        item.dataset.custom = shader.name;
        item.addEventListener("click", () => this._selectCustom(item, shader.name));
        item.addEventListener("dblclick", () => this._renameItem(item, shader.name));
        item.addEventListener("contextmenu", (e) => {
          e.preventDefault();
          this._renameItem(item, shader.name);
        });
      } else {
        item.dataset.path = shader.path;
        item.addEventListener("click", () => this._select(item, shader.path));
      }
      children.appendChild(item);
    }

    folder.appendChild(children);
    return folder;
  }

  _buildCustomFolder() {
    const customs = loadCustomShaders();
    const shaders = customs.map((c) => ({ name: c.name }));
    return this._buildFolder("custom", shaders, true);
  }

  /* ── Selection ───────────────────────────────────────── */

  _select(el, path) {
    this._setActive(el);
    this._onSelect(path, undefined);
  }

  _selectCustom(el, name) {
    this._setActive(el);
    const customs = loadCustomShaders();
    const entry = customs.find((c) => c.name === name);
    this._onSelect("custom:" + name, entry ? entry.source : "");
  }

  _setActive(el) {
    if (this._activeEl) this._activeEl.classList.remove("active");
    el.classList.add("active");
    this._activeEl = el;
    el.focus();
  }

  selectFirst() {
    const first = this._container.querySelector(".tree-item");
    if (!first) return;
    if (first.dataset.path) {
      this._select(first, first.dataset.path);
    } else if (first.dataset.custom) {
      this._selectCustom(first, first.dataset.custom);
    }
  }

  /* ── Keyboard navigation ─────────────────────────────── */

  _initKeyboard() {
    this._container.addEventListener("keydown", (e) => {
      if (e.key === "ArrowDown" || e.key === "ArrowUp") {
        e.preventDefault();
        this._navigate(e.key === "ArrowDown" ? 1 : -1);
      }
    });
  }

  _navigate(dir) {
    this._items = Array.from(this._container.querySelectorAll(".tree-item"));
    const idx = this._items.indexOf(this._activeEl);
    const next = idx + dir;
    if (next < 0 || next >= this._items.length) return;

    const el = this._items[next];
    const folder = el.closest(".tree-folder");
    if (folder && folder.classList.contains("collapsed")) {
      folder.classList.remove("collapsed");
    }

    if (el.dataset.path) {
      this._select(el, el.dataset.path);
    } else if (el.dataset.custom) {
      this._selectCustom(el, el.dataset.custom);
    }
  }

  /* ── Custom shader management ────────────────────────── */

  _createNew() {
    const name = prompt("New shader name:");
    if (!name || !name.trim()) return;
    const trimmed = name.trim();
    const defaultSrc = [
      "precision highp float;",
      "",
      "uniform vec2 u_resolution;",
      "uniform float u_time;",
      "",
      "void main() {",
      "    vec2 uv = gl_FragCoord.xy / u_resolution;",
      "    gl_FragColor = vec4(uv, 0.5 + 0.5 * sin(u_time), 1.0);",
      "}",
    ].join("\n");
    upsertCustomShader(trimmed, defaultSrc);
    this._build();
    // Find and select the newly created entry
    const items = this._container.querySelectorAll(".tree-item[data-custom]");
    for (const el of items) {
      if (el.dataset.custom === trimmed) {
        this._selectCustom(el, trimmed);
        return;
      }
    }
  }

  _renameItem(el, oldName) {
    const newName = prompt("Rename shader:", oldName);
    if (!newName || !newName.trim() || newName.trim() === oldName) return;
    renameCustomShader(oldName, newName.trim());
    this._rebuild();
    const newEl = this._container.querySelector(`[data-custom="${CSS.escape(newName.trim())}"]`);
    if (newEl) this._selectCustom(newEl, newName.trim());
  }

  saveToCustom(name, source) {
    upsertCustomShader(name, source);
    this._rebuild();
  }

  getActiveCustomName() {
    return this._activeEl && this._activeEl.dataset.custom
      ? this._activeEl.dataset.custom
      : null;
  }

  getActivePath() {
    return this._activeEl ? this._activeEl.dataset.path || null : null;
  }

  _rebuild() {
    const activePath = this._activeEl?.dataset.path;
    const activeCustom = this._activeEl?.dataset.custom;
    this._build();
    if (activePath) {
      const el = this._container.querySelector(`[data-path="${CSS.escape(activePath)}"]`);
      if (el) { el.classList.add("active"); this._activeEl = el; }
    } else if (activeCustom) {
      const el = this._container.querySelector(`[data-custom="${CSS.escape(activeCustom)}"]`);
      if (el) { el.classList.add("active"); this._activeEl = el; }
    }
  }

  _esc(text) {
    const d = document.createElement("span");
    d.textContent = text;
    return d.innerHTML;
  }
}
