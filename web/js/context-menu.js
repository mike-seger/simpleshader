/**
 * Context menu — lightweight single-instance menu for sidebar tree items.
 */

export default class ContextMenu {
  constructor() {
    this._el = document.createElement("div");
    this._el.className = "ctx-menu";
    this._el.tabIndex = -1;
    document.body.appendChild(this._el);

    // Close on outside click / Escape
    document.addEventListener("mousedown", (e) => {
      if (!this._el.contains(e.target)) this.hide();
    });
    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape") this.hide();
    });
  }

  /**
   * Show the menu at (x, y) with the given items.
   * @param {number} x
   * @param {number} y
   * @param {Array<{label: string, icon?: string, action: () => void}>} items
   */
  show(x, y, items) {
    this._el.innerHTML = "";
    for (const item of items) {
      const row = document.createElement("div");
      row.className = "ctx-menu-item";
      if (item.icon) {
        const ico = document.createElement("span");
        ico.className = "ctx-menu-icon";
        ico.textContent = item.icon;
        row.appendChild(ico);
      }
      const txt = document.createElement("span");
      txt.textContent = item.label;
      row.appendChild(txt);
      row.addEventListener("click", (e) => {
        e.stopPropagation();
        this.hide();
        item.action();
      });
      this._el.appendChild(row);
    }

    this._el.style.display = "block";
    // Position, clamped to viewport
    const rect = this._el.getBoundingClientRect();
    const mx = Math.min(x, window.innerWidth - rect.width - 4);
    const my = Math.min(y, window.innerHeight - rect.height - 4);
    this._el.style.left = mx + "px";
    this._el.style.top = my + "px";
  }

  hide() {
    this._el.style.display = "none";
  }
}
