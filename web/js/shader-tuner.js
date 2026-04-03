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
  return /(?:^|_)COLOR\d*$/i.test(name) || /_TINT\d*$/i.test(name);
}

function isDirection(name) {
  return /_DIR$/i.test(name);
}

/**
 * Parse @options(v1, v2, ...) or @options(v1:Label1, v2:Label2, ...) from a comment.
 * Returns an array of numbers (plain) or a {value: label} object (labelled), or null.
 */
function parseOptions(comment, type) {
  if (!comment) return null;
  const m = comment.match(/@options\(\s*([^)]+)\s*\)/);
  if (!m) return null;
  const parts = m[1].split(",").map(s => s.trim());
  // Check if any part has a label (value:label)
  if (parts.some(p => p.includes(":"))) {
    const obj = {};
    for (const p of parts) {
      const [val, ...rest] = p.split(":");
      const label = rest.join(":").trim() || val.trim();
      const num = type === "int" ? parseInt(val.trim(), 10) : parseFloat(val.trim());
      obj[label] = num;
    }
    return obj;
  }
  return parts.map(s => type === "int" ? parseInt(s, 10) : parseFloat(s));
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
    /** @type {{tracks: {label:string, url:string}[], currentUrl: string, onSwitch: (url:string)=>void}|null} */
    this._audioConfig = null;
  }

  /** Set audio track switching configuration. Call before build(). */
  setAudioConfig(config) {
    this._audioConfig = config;
  }

  async build() {
    this.destroy();

    const source = this._getSource();
    this._parsed = parseConstants(source);

    const hasAudio = this._audioConfig && this._audioConfig.tracks.length > 0;

    if (this._parsed.length === 0 && !hasAudio) {
      return false;
    }

    const GUI = await loadLilGui();
    this._gui = new GUI({ container: this._container, autoPlace: false, width: 200 });
    this._gui.title("Controls");
    this._proxyObj = {};

    // Audio/MOD track selector (if audio is active)
    if (hasAudio) {
      const ac = this._audioConfig;
      const trackMap = {};
      const fileMap = {};
      for (const t of ac.tracks) {
        trackMap[t.label] = t.url;
        fileMap[t.label] = t.file;
      }
      // Find current label
      const cur = ac.tracks.find(t => t.url === ac.currentUrl);
      this._proxyObj.__audioTrack = cur ? cur.label : ac.tracks[0].label;
      const folderTitle = ac.mediaType === 'mod' ? 'MOD Tracks' : 'Audio';
      const folder = this._gui.addFolder(folderTitle);
      const trackCtrl = folder.add(this._proxyObj, "__audioTrack", Object.keys(trackMap))
        .name("Track")
        .onChange((label) => {
          const url = trackMap[label];
          const file = fileMap[label];
          if (url) ac.onSwitch(url, file);
        });

      // Left/right arrow keys cycle through tracks
      const selectEl = trackCtrl.$widget.querySelector('select');
      if (selectEl) {
        selectEl.addEventListener('keydown', (e) => {
          if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') return;
          e.preventDefault();
          const opts = Array.from(selectEl.options);
          let idx = selectEl.selectedIndex;
          if (e.key === 'ArrowLeft')  idx = (idx - 1 + opts.length) % opts.length;
          if (e.key === 'ArrowRight') idx = (idx + 1) % opts.length;
          selectEl.selectedIndex = idx;
          selectEl.dispatchEvent(new Event('change'));
        });
      }
    }

    if (this._parsed.length === 0) return true;

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
      // A "gate" is a bool whose name exactly matches the group prefix
      // (e.g. `const bool GRID = true;` gates all GRID_* siblings).
      const gateIdx = group.items.findIndex(
        p => p.type === 'bool' && p.name === group.prefix
      );
      const gate  = gateIdx !== -1 ? group.items[gateIdx] : null;
      const gated = gate
        ? group.items.filter((_, i) => i !== gateIdx)
        : group.items;

      if (gate && gated.length > 0) {
        // Use @label from the gate's comment as folder title, else prettyName
        let folderTitle = prettyName(group.prefix);
        if (gate.comment) {
          const lm = gate.comment.match(/@label\s+(.+?)(?:\s*@|\s*$)/);
          if (lm) folderTitle = lm[1].trim();
        }
        const folder = this._gui.addFolder(folderTitle);
        folder.open();

        // Inject checkbox into the folder title element
        const cb = document.createElement('input');
        cb.type = 'checkbox';
        cb.checked = gate.value;
        cb.style.cssText = 'margin-right:6px;cursor:pointer;vertical-align:middle;';
        // Prevent the click from bubbling to the title (which would open/close the folder)
        cb.addEventListener('click', e => e.stopPropagation());
        folder.$title.prepend(cb);

        // Show/hide folder content (not the whole folder) based on gate state
        const applyGate = (on) => {
          folder.$children.style.display = on ? '' : 'none';
        };
        applyGate(gate.value);

        cb.addEventListener('change', () => {
          this._proxyObj[gate.name] = cb.checked;
          this._apply(gate);
          applyGate(cb.checked);
        });

        this._proxyObj[gate.name] = gate.value;
        for (const p of gated) {
          this._addControl(p, folder, group.prefix);
        }
      } else if (gated.length > 2) {
        const folder = this._gui.addFolder(prettyName(group.prefix));
        for (const p of gated) {
          this._addControl(p, folder, group.prefix);
        }
      } else {
        // gated is empty only when gate exists with no siblings — fall back to gate itself
        const items = gated.length > 0 ? gated : (gate ? [gate] : []);
        for (const p of items) {
          this._addControl(p, this._gui, null);
        }
      }
    }

    return true;
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

    if (p.type === "int" || p.type === "float") {
      this._proxyObj[p.name] = p.value;
      const opts = parseOptions(p.comment, p.type);
      let c;
      if (opts) {
        c = parent.add(this._proxyObj, p.name, opts).name(label)
          .onChange(() => { this._proxyObj[p.name] = Number(this._proxyObj[p.name]); this._apply(p); });
        // Arrow left/right to cycle options without opening the dropdown
        const sel = c.domElement.querySelector("select");
        if (sel) {
          sel.addEventListener("keydown", (e) => {
            if (e.key === "ArrowLeft" || e.key === "ArrowRight") {
              e.preventDefault();
              const dir = e.key === "ArrowLeft" ? -1 : 1;
              const idx = sel.selectedIndex + dir;
              if (idx >= 0 && idx < sel.options.length) {
                sel.selectedIndex = idx;
                sel.dispatchEvent(new Event("change"));
              }
            }
          });
        }
      } else {
        const range = getRange(p.name, p.value, p.comment);
        c = parent.add(this._proxyObj, p.name, range.min, range.max, range.step)
          .name(label)
          .onChange(() => { if (p.type === "int") this._proxyObj[p.name] = Math.round(this._proxyObj[p.name]); this._apply(p); });
      }
      if (tip) c.domElement.setAttribute("title", tip);
      return;
    }

    // vec3 color: inline color picker (with brightness slider for HDR)
    if (p.type === "vec3" && isColor(p.name)) {
      const colorKey = p.name + "__rgb";
      const scaleKey = p.name + "__scale";
      const maxC = Math.max(p.value[0], p.value[1], p.value[2], 1.0);
      this._proxyObj[colorKey] = { r: p.value[0] / maxC, g: p.value[1] / maxC, b: p.value[2] / maxC };
      this._proxyObj[scaleKey] = maxC;
      const cc = parent.addColor(this._proxyObj, colorKey).name(label)
        .onChange(() => this._applyColor(p));
      if (tip) cc.domElement.setAttribute("title", tip);
      if (maxC > 1.0) {
        parent.add(this._proxyObj, scaleKey, 0.01, maxC * 3, 0.01)
          .name(label.replace(/Tint\d*$|Color\d*$/, "").trim() + " Bright")
          .onChange(() => this._applyColor(p));
      }
      return;
    }

    // vec4 color: inline color picker + opacity slider (with brightness for HDR)
    if (p.type === "vec4" && isColor(p.name)) {
      const colorKey = p.name + "__rgb";
      const alphaKey = p.name + "__a";
      const scaleKey = p.name + "__scale";
      const maxC = Math.max(p.value[0], p.value[1], p.value[2], 1.0);
      this._proxyObj[colorKey] = { r: p.value[0] / maxC, g: p.value[1] / maxC, b: p.value[2] / maxC };
      this._proxyObj[alphaKey] = p.value[3];
      this._proxyObj[scaleKey] = maxC;
      const cc = parent.addColor(this._proxyObj, colorKey).name(label)
        .onChange(() => this._applyColor(p));
      if (tip) cc.domElement.setAttribute("title", tip);
      if (maxC > 1.0) {
        parent.add(this._proxyObj, scaleKey, 0.01, maxC * 3, 0.01)
          .name(label.replace(/Color\d*$/, "").trim() + " Bright")
          .onChange(() => this._applyColor(p));
      }
      const alphaLabel = label.replace(/Color\d*$/, "Alpha").trim() || "Alpha";
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
    const scale = this._proxyObj[p.name + "__scale"] || 1.0;
    const newValue = p.type === "vec3"
      ? [rgb.r * scale, rgb.g * scale, rgb.b * scale]
      : [rgb.r * scale, rgb.g * scale, rgb.b * scale, this._proxyObj[p.name + "__a"]];
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
