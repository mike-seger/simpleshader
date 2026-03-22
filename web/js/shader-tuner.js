/**
 * ShaderTuner — parses GLSL constants between @lil-gui-start / @lil-gui-end
 * markers and builds a lil-gui panel from them. Changes rewrite the constant
 * values in the editor source and re-apply the shader in real time.
 *
 * Naming conventions for automatic widget types:
 *   vec4 *_COLOR  → color picker  (rgb) + opacity slider (a)
 *   vec3 *_DIR    → three sliders (x, y, z)
 *   vec4 (other)  → four sliders
 *   vec3 (other)  → three sliders
 *   float         → slider
 *   bool          → checkbox
 */

let lilGuiModule = null;

async function loadLilGui() {
  if (lilGuiModule) return lilGuiModule;
  lilGuiModule = (await import("https://cdn.jsdelivr.net/npm/lil-gui@0.19/+esm")).default;
  return lilGuiModule;
}

/**
 * Parse the @lil-gui-start … @lil-gui-end block from GLSL source.
 * Returns an array of { name, type, value, line, raw } objects.
 */
function parseConstants(source) {
  const lines = source.split("\n");
  let inside = false;
  const result = [];

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (/\/\/\s*@lil-gui-start/.test(line)) { inside = true; continue; }
    if (/\/\/\s*@lil-gui-end/.test(line)) { inside = false; continue; }
    if (!inside) continue;

    // Match: const <type> <NAME> = <value>;  // optional comment
    const m = line.match(
      /^\s*const\s+(float|int|bool|vec[234])\s+(\w+)\s*=\s*(.+?)\s*;\s*(\/\/.*)?$/
    );
    if (!m) continue;

    const type = m[1];
    const name = m[2];
    const rawVal = m[3].trim();
    const comment = m[4] || "";

    let value;
    if (type === "float") {
      value = parseFloat(rawVal);
    } else if (type === "int") {
      value = parseInt(rawVal, 10);
    } else if (type === "bool") {
      value = rawVal === "true";
    } else {
      // vec2/vec3/vec4 — extract components
      const inner = rawVal.match(/vec[234]\s*\(([^)]+)\)/);
      if (inner) {
        value = inner[1].split(",").map(s => parseFloat(s.trim()));
      }
    }

    if (value === undefined || value === null) continue;

    result.push({ name, type, value, lineIndex: i, raw: rawVal, comment });
  }

  return result;
}

/**
 * Determine slider range — first checks for @range(min, max[, step]) in the
 * line comment, then falls back to name-based heuristics.
 */
function getRange(name, value, comment) {
  // Explicit range annotation in comment: @range(min, max) or @range(min, max, step)
  if (comment) {
    const m = comment.match(/@range\(\s*([^,)]+),\s*([^,)]+)(?:,\s*([^)]+))?\s*\)/);
    if (m) {
      const min  = parseFloat(m[1]);
      const max  = parseFloat(m[2]);
      const step = m[3] ? parseFloat(m[3]) : (max - min) / 200;
      return { min, max, step };
    }
  }
  const n = name.toUpperCase();
  if (n.includes("OPACITY") || n.includes("ALPHA")) return { min: 0, max: 1, step: 0.01 };
  if (n.includes("RATIO")) return { min: 0, max: 1, step: 0.01 };
  if (n.includes("REFLECT")) return { min: 0, max: 1, step: 0.01 };
  if (n.includes("SIZE")) return { min: 0.1, max: 5, step: 0.01 };
  if (n.includes("INTENSITY")) return { min: 0, max: 20, step: 0.1 };
  if (n.includes("GLOSS")) return { min: 1, max: 500, step: 1 };
  if (n.includes("WIDTH")) return { min: 0.01, max: 3, step: 0.01 };
  if (n.includes("ANGLE")) return { min: -360, max: 360, step: 1 };
  if (n.includes("SPEED")) return { min: -360, max: 360, step: 0.5 };
  if (n.includes("FREQ"))  return { min: 0, max: 20, step: 0.1 };
  // Default: center on current value
  const absV = Math.abs(value);
  if (absV < 0.001) return { min: -1, max: 1, step: 0.001 };
  return { min: -absV * 3, max: absV * 3, step: absV * 0.01 };
}

function isColor(name) {
  return /_COLOR$/i.test(name);
}

function isDirection(name) {
  return /_DIR$/i.test(name);
}

/**
 * Format a float for GLSL (always with decimal point).
 */
function fmtFloat(v) {
  let s = v.toFixed(4);
  // Remove trailing zeros but keep at least one decimal
  s = s.replace(/(\.\d*?)0+$/, "$1");
  if (s.endsWith(".")) s += "0";
  return s;
}

/**
 * Rewrite one constant line in the source.
 */
function rewriteConstant(source, parsed, newValue) {
  const lines = source.split("\n");
  const line = lines[parsed.lineIndex];

  let valStr;
  if (parsed.type === "float") {
    valStr = fmtFloat(newValue);
  } else if (parsed.type === "int") {
    valStr = String(Math.round(newValue));
  } else if (parsed.type === "bool") {
    valStr = newValue ? "true" : "false";
  } else if (parsed.type === "vec4") {
    const arr = newValue;
    valStr = `vec4(${arr.map(fmtFloat).join(", ")})`;
  } else if (parsed.type === "vec3") {
    const arr = newValue;
    valStr = `vec3(${arr.map(fmtFloat).join(", ")})`;
  } else if (parsed.type === "vec2") {
    const arr = newValue;
    valStr = `vec2(${arr.map(fmtFloat).join(", ")})`;
  }

  // Replace the value between "=" and ";"
  const newLine = line.replace(
    /=\s*.+?\s*;/,
    `= ${valStr};`
  );
  lines[parsed.lineIndex] = newLine;
  return lines.join("\n");
}

/**
 * Pretty-display name: STAR_EDGE_WIDTH → Star Edge Width
 */
function prettyName(name) {
  return name
    .replace(/_/g, " ")
    .toLowerCase()
    .replace(/\b\w/g, c => c.toUpperCase());
}

/**
 * Strip the leading PREFIX_ from a name, then pretty-print.
 * e.g. strippedLabel("STAR_EDGE_WIDTH", "STAR") → "Edge Width"
 */
function strippedLabel(name, prefix) {
  if (name.startsWith(prefix + "_")) return prettyName(name.slice(prefix.length + 1));
  return prettyName(name);
}

export default class ShaderTuner {
  /**
   * @param {HTMLElement} container — DOM element to hold the lil-gui panel
   * @param {() => string} getSource — get current editor source
   * @param {(source: string) => void} setSourceAndApply — update editor + compile
   */
  constructor(container, getSource, setSourceAndApply) {
    this._container = container;
    this._getSource = getSource;
    this._setSourceAndApply = setSourceAndApply;
    this._gui = null;
    this._parsed = [];
    this._proxyObj = {};
  }

  async build() {
    this.destroy();

    const source = this._getSource();
    this._parsed = parseConstants(source);

    if (this._parsed.length === 0) {
      this._container.innerHTML =
        '<div style="padding:16px;color:#888;font-size:12px;">No <code>@lil-gui</code> block found in current shader.</div>';
      return;
    }

    const GUI = await loadLilGui();
    this._gui = new GUI({ container: this._container, autoPlace: false, width: 200 });
    this._gui.title("Shader Controls");
    this._proxyObj = {};

    // Group consecutive constants by first prefix (e.g. STAR from STAR_SIZE)
    const groups = [];
    for (const p of this._parsed) {
      const prefix = p.name.split("_")[0];
      const last = groups[groups.length - 1];
      if (last && last.prefix === prefix) {
        last.items.push(p);
      } else {
        groups.push({ prefix, items: [p] });
      }
    }

    for (const group of groups) {
      if (group.items.length > 1) {
        const folder = this._gui.addFolder(prettyName(group.prefix));
        for (const p of group.items) {
          this._addControl(p, folder, group.prefix);
        }
      } else {
        this._addControl(group.items[0], this._gui, null);
      }
    }
  }

  /** Add one control to `parent` (a GUI or folder).
   *  `prefix` is stripped from the label when inside a prefix folder. */
  _addControl(p, parent, prefix) {
    const label = prefix ? strippedLabel(p.name, prefix) : prettyName(p.name);
    const tip = p.comment ? p.comment.replace(/^\/\/\s*/, "").trim() : "";

    if (p.type === "bool") {
      this._proxyObj[p.name] = p.value;
      const c = parent.add(this._proxyObj, p.name).name(label)
        .onChange(() => this._apply(p));
      if (tip) c.domElement.setAttribute("title", tip);
      return;
    }

    if (p.type === "int") {
      this._proxyObj[p.name] = p.value;
      const range = getRange(p.name, p.value, p.comment);
      const c = parent.add(this._proxyObj, p.name, range.min, range.max, range.step)
        .name(label)
        .onChange(() => { this._proxyObj[p.name] = Math.round(this._proxyObj[p.name]); this._apply(p); });
      if (tip) c.domElement.setAttribute("title", tip);
      return;
    }

    if (p.type === "float") {
      this._proxyObj[p.name] = p.value;
      const range = getRange(p.name, p.value, p.comment);
      const c = parent.add(this._proxyObj, p.name, range.min, range.max, range.step)
        .name(label)
        .onChange(() => this._apply(p));
      if (tip) c.domElement.setAttribute("title", tip);
      return;
    }

    // vec4 color: inline color picker + opacity slider (no sub-folder)
    if (p.type === "vec4" && isColor(p.name)) {
      const colorKey = p.name + "__rgb";
      const alphaKey = p.name + "__a";
      this._proxyObj[colorKey] = { r: p.value[0], g: p.value[1], b: p.value[2] };
      this._proxyObj[alphaKey] = p.value[3];
      const cc = parent.addColor(this._proxyObj, colorKey).name(label)
        .onChange(() => this._applyColor(p));
      if (tip) cc.domElement.setAttribute("title", tip);
      const alphaLabel = label.replace(/Color$/, "Alpha").trim() || "Alpha";
      parent.add(this._proxyObj, alphaKey, 0, 1, 0.01).name(alphaLabel)
        .onChange(() => this._applyColor(p));
      return;
    }

    // vec3/vec4 — sub-folder with component sliders
    const dim = parseInt(p.type.charAt(3));
    const labels = ["x", "y", "z", "w"].slice(0, dim);
    const folder = parent.addFolder(label);
    if (tip) folder.domElement.setAttribute("title", tip);

    for (let i = 0; i < dim; i++) {
      const key = p.name + "__" + labels[i];
      this._proxyObj[key] = p.value[i];
      const range = isDirection(p.name)
        ? { min: -10, max: 10, step: 0.1 }
        : getRange(p.name, p.value[i], p.comment);
      folder.add(this._proxyObj, key, range.min, range.max, range.step)
        .name(labels[i].toUpperCase())
        .onChange(() => this._applyVec(p, dim, labels));
    }
  }

  _apply(p) {
    const newValue = this._proxyObj[p.name];
    p.value = newValue;
    const source = rewriteConstant(this._getSource(), p, newValue);
    this._setSourceAndApply(source);
  }

  _applyColor(p) {
    const rgb = this._proxyObj[p.name + "__rgb"];
    const a = this._proxyObj[p.name + "__a"];
    const newValue = [rgb.r, rgb.g, rgb.b, a];
    p.value = newValue;
    const source = rewriteConstant(this._getSource(), p, newValue);
    this._setSourceAndApply(source);
  }

  _applyVec(p, dim, labels) {
    const newValue = labels.map(l => this._proxyObj[p.name + "__" + l]);
    p.value = newValue;
    const source = rewriteConstant(this._getSource(), p, newValue);
    this._setSourceAndApply(source);
  }

  destroy() {
    if (this._gui) {
      this._gui.destroy();
      this._gui = null;
    }
    this._container.innerHTML = "";
    this._parsed = [];
    this._proxyObj = {};
  }
}
