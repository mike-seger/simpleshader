/**
 * Sidebar — builds a collapsible tree from the shader index.
 */

import SHADER_INDEX from "../shaders/index.js";

export default class Sidebar {
  /**
   * @param {HTMLElement} container  — the #shader-tree element
   * @param {(path: string) => void} onSelect — called when a shader is clicked
   */
  constructor(container, onSelect) {
    this._container = container;
    this._onSelect = onSelect;
    this._activeEl = null;
    this._build();
  }

  _build() {
    const frag = document.createDocumentFragment();
    for (const group of SHADER_INDEX) {
      const folder = document.createElement("div");
      folder.className = "tree-folder";

      const label = document.createElement("div");
      label.className = "tree-folder-label";
      label.innerHTML = `<span class="arrow">▼</span> ${this._esc(group.folder)}`;
      label.addEventListener("click", () => folder.classList.toggle("collapsed"));
      folder.appendChild(label);

      const children = document.createElement("div");
      children.className = "tree-children";
      for (const shader of group.shaders) {
        const item = document.createElement("div");
        item.className = "tree-item";
        item.textContent = shader.name;
        item.dataset.path = shader.path;
        item.addEventListener("click", () => this._select(item, shader.path));
        children.appendChild(item);
      }
      folder.appendChild(children);
      frag.appendChild(folder);
    }
    this._container.appendChild(frag);
  }

  _select(el, path) {
    if (this._activeEl) this._activeEl.classList.remove("active");
    el.classList.add("active");
    this._activeEl = el;
    this._onSelect(path);
  }

  /** Select first shader in the tree */
  selectFirst() {
    const first = this._container.querySelector(".tree-item");
    if (first) this._select(first, first.dataset.path);
  }

  _esc(text) {
    const d = document.createElement("span");
    d.textContent = text;
    return d.innerHTML;
  }
}
