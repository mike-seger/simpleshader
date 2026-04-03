/**
 * Sidebar — collapsible tree with keyboard navigation and accordion behavior.
 * Renders built-in shaders from the index + custom shaders from localStorage.
 */

import SHADER_INDEX from "../shaders/index.js";
import { loadCustomShaders, upsertCustomShader, renameCustomShader, deleteCustomShader } from "./store.js";

let defaultTemplate = null;

async function getDefaultTemplate() {
  if (defaultTemplate !== null) return defaultTemplate;
  try {
    const res = await fetch("web/shaders/default.glsl");
    if (res.ok) defaultTemplate = await res.text();
    else defaultTemplate = "";
  } catch { defaultTemplate = ""; }
  return defaultTemplate;
}

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
    this._folders = [];
    this._build();
    this._initKeyboard();
  }

  /* ── Build the tree ──────────────────────────────────── */

  _build() {
    this._container.innerHTML = "";
    this._items = [];
    this._folders = [];

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
    folder.className = "tree-folder collapsed";

    const lbl = document.createElement("div");
    lbl.className = "tree-folder-label";
    lbl.innerHTML = `<span class="arrow">▼</span> ${this._esc(label)}`;
    lbl.addEventListener("click", () => this._toggleFolder(folder));

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
    this._folders.push(folder);
    return folder;
  }

  _buildCustomFolder() {
    const customs = loadCustomShaders();
    const shaders = customs.map((c) => ({ name: c.name }));
    return this._buildFolder("custom", shaders, true);
  }

  /* ── Accordion: only one folder open ─────────────────── */

  _toggleFolder(folder) {
    if (folder.classList.contains("collapsed")) {
      // Close all others first
      for (const f of this._folders) {
        f.classList.add("collapsed");
      }
      folder.classList.remove("collapsed");
    } else {
      folder.classList.add("collapsed");
    }
  }

  _expandFolderOf(el) {
    const folder = el.closest(".tree-folder");
    if (folder && folder.classList.contains("collapsed")) {
      for (const f of this._folders) f.classList.add("collapsed");
      folder.classList.remove("collapsed");
    }
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
    this._expandFolderOf(first);
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
        return;
      }

      if (e.key === "Delete") {
        e.preventDefault();
        this.deleteSelected();
      }
    });
  }

  _navigate(dir) {
    this._items = Array.from(this._container.querySelectorAll(".tree-item"));
    const idx = this._items.indexOf(this._activeEl);
    const next = idx + dir;
    if (next < 0 || next >= this._items.length) return;

    const el = this._items[next];
    this._expandFolderOf(el);

    if (el.dataset.path) {
      this._select(el, el.dataset.path);
    } else if (el.dataset.custom) {
      this._selectCustom(el, el.dataset.custom);
    }
  }

  /* ── Custom shader management (public API) ───────────── */

  async createNew() {
    const src = await getDefaultTemplate();
    const customs = loadCustomShaders();
    const existing = new Set(customs.map((c) => c.name));
    let name;
    for (let i = 1; i <= 999; i++) {
      const candidate = "new " + String(i).padStart(3, "0");
      if (!existing.has(candidate)) { name = candidate; break; }
    }
    if (!name) return;
    upsertCustomShader(name, src);
    this._rebuild();
    this._selectCustomByName(name);
  }

  duplicateSelected(currentSource) {
    if (!this._activeEl) return;
    const baseName = this._activeEl.dataset.custom
      || this._activeEl.textContent.trim();
    const customs = loadCustomShaders();
    const existing = new Set(customs.map((c) => c.name));
    let name;
    for (let i = 2; i <= 99; i++) {
      const candidate = baseName + "_" + i;
      if (!existing.has(candidate)) { name = candidate; break; }
    }
    if (!name) return;
    upsertCustomShader(name, currentSource);
    this._rebuild();
    this._selectCustomByName(name);
  }

  deleteSelected() {
    if (!this._activeEl || !this._activeEl.dataset.custom) return;
    const name = this._activeEl.dataset.custom;
    if (!confirm(`Delete "${name}"?`)) return;
    // Find the item above the active one before rebuilding
    this._items = Array.from(this._container.querySelectorAll(".tree-item"));
    const idx = this._items.indexOf(this._activeEl);
    const prevEl = idx > 0 ? this._items[idx - 1] : null;
    deleteCustomShader(name);
    this._activeEl = null;
    this._rebuild();
    // Select the shader above, or fall back to first
    if (prevEl && prevEl.dataset.path) {
      const el = this._container.querySelector(`[data-path="${CSS.escape(prevEl.dataset.path)}"]`);
      if (el) { this._expandFolderOf(el); this._select(el, el.dataset.path); return; }
    } else if (prevEl && prevEl.dataset.custom) {
      const items = this._container.querySelectorAll(".tree-item[data-custom]");
      for (const el of items) {
        if (el.dataset.custom === prevEl.dataset.custom) {
          this._expandFolderOf(el); this._selectCustom(el, el.dataset.custom); return;
        }
      }
    }
    this.selectFirst();
  }

  _renameItem(el, oldName) {
    const newName = prompt("Rename shader:", oldName);
    if (!newName || !newName.trim() || newName.trim() === oldName) return;
    renameCustomShader(oldName, newName.trim());
    this._rebuild();
    this._selectCustomByName(newName.trim());
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

  getActiveDisplayName() {
    return this._activeEl ? this._activeEl.textContent.trim() : null;
  }

  rebuild() {
    this._rebuild();
  }

  isCustomSelected() {
    return !!(this._activeEl && this._activeEl.dataset.custom);
  }

  /** Select a shader by its key (path or "custom:name"). Returns true if found. */
  selectByKey(key) {
    if (key.startsWith("custom:")) {
      const name = key.slice(7);
      const items = this._container.querySelectorAll(".tree-item[data-custom]");
      for (const el of items) {
        if (el.dataset.custom === name) {
          this._expandFolderOf(el);
          this._selectCustom(el, name);
          return true;
        }
      }
    } else {
      const el = this._container.querySelector(`[data-path="${CSS.escape(key)}"]`);
      if (el) {
        this._expandFolderOf(el);
        this._select(el, key);
        return true;
      }
    }
    return false;
  }

  _selectCustomByName(name) {
    const items = this._container.querySelectorAll(".tree-item[data-custom]");
    for (const el of items) {
      if (el.dataset.custom === name) {
        this._expandFolderOf(el);
        this._selectCustom(el, name);
        return;
      }
    }
  }

  _rebuild() {
    const activePath = this._activeEl?.dataset.path;
    const activeCustom = this._activeEl?.dataset.custom;
    this._build();
    if (activePath) {
      const el = this._container.querySelector(`[data-path="${CSS.escape(activePath)}"]`);
      if (el) { el.classList.add("active"); this._activeEl = el; this._expandFolderOf(el); }
    } else if (activeCustom) {
      const items = this._container.querySelectorAll(".tree-item[data-custom]");
      for (const el of items) {
        if (el.dataset.custom === activeCustom) {
          el.classList.add("active"); this._activeEl = el; this._expandFolderOf(el); break;
        }
      }
    }
  }

  /**
   * Import an array of {name, source} into custom shaders.
   * Deduplicates names by appending _2, _3, etc.
   * Selects the last imported shader.
   */
  importShaders(entries) {
    if (!entries.length) return;
    const customs = loadCustomShaders();
    const existing = new Set(customs.map(c => c.name));
    let lastName;
    for (const { name, source } of entries) {
      let finalName = name;
      if (existing.has(finalName)) {
        for (let i = 2; i <= 999; i++) {
          const candidate = name + "_" + i;
          if (!existing.has(candidate)) { finalName = candidate; break; }
        }
      }
      upsertCustomShader(finalName, source);
      existing.add(finalName);
      lastName = finalName;
    }
    this._rebuild();
    if (lastName) this._selectCustomByName(lastName);
  }

  _esc(text) {
    const d = document.createElement("span");
    d.textContent = text;
    return d.innerHTML;
  }
}
