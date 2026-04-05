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
    this._textureConfigs = [];
  }

  /** Set audio track switching configuration. Call before build(). */
  setAudioConfig(config) {
    this._audioConfig = config;
  }

  /** Set texture switching configurations (one per @iChannel texture). Call before build(). */
  setTextureConfigs(configs) {
    this._textureConfigs = configs || [];
  }

  async build() {
    this.destroy();

    const source = this._getSource();
    this._parsed = parseConstants(source);

    const hasAudio = this._audioConfig &&
      (this._audioConfig.modTracks.length > 0 || this._audioConfig.audioTracks.length > 0);
    const hasTextures = this._textureConfigs.length > 0;

    if (this._parsed.length === 0 && !hasAudio && !hasTextures) {
      return false;
    }

    const GUI = await loadLilGui();
    this._gui = new GUI({ container: this._container, autoPlace: false, width: 200 });
    this._gui.title("Controls");
    this._proxyObj = {};
    this._sliderInputs = [];

    // Audio/MOD track selector (if audio is active)
    if (hasAudio) {
      const ac = this._audioConfig;
      const currentType = ac.defaultType;  // 'mod' | 'audio'
      const tracks = currentType === 'mod' ? ac.modTracks : ac.audioTracks;
      const trackMap = {};
      const pathMap = {};
      const gainMap = {};
      for (const t of tracks) {
        trackMap[t.label] = t.url;
        pathMap[t.label] = t.annPath;
        gainMap[t.label] = t.gain || 1;
      }
      // Find current label
      const cur = tracks.find(t => t.url === ac.currentUrl);
      this._proxyObj.__audioTrack = cur ? cur.label : (tracks[0]?.label || '');
      const folderTitle = 'Sound';
      const folder = this._gui.addFolder(folderTitle);

      // Type selector (Audio file / Tracker) — hide when an unmanaged entry is present
      const hasUnmanaged = tracks.some(t => t.label.startsWith('! '));
      if (!hasUnmanaged) {
        this._proxyObj.__audioType = currentType === 'mod' ? 'Tracker: MOD/XM...' : 'Audio URL';
        const typeCtrl = folder.add(this._proxyObj, '__audioType', ['Audio URL', 'Tracker: MOD/XM...'])
          .name('Type')
          .onChange((label) => {
            const newType = label === 'Tracker: MOD/XM...' ? 'mod' : 'audio';
            if (newType !== currentType) ac.onSwitchType(newType);
          });
        this._enhanceSelect(typeCtrl);
      }

      // Track selector
      const trackCtrl = folder.add(this._proxyObj, "__audioTrack", Object.keys(trackMap))
        .name("Track")
        .onChange((label) => {
          const url = trackMap[label];
          const annPath = pathMap[label];
          if (url) ac.onSwitch(url, annPath, gainMap[label] || 1);
        });
      this._trackSelect = this._enhanceSelect(trackCtrl);
    }

    // Texture channel selectors (one per @iChannel texture)
    for (const tc of this._textureConfigs) {
      const texMap = {};
      const texFileMap = {};
      for (const t of tc.tracks) {
        texMap[t.label] = t.url;
        texFileMap[t.label] = t.file;
      }
      const cur = tc.tracks.find(t => t.url === tc.currentUrl);
      const propName = `__texture_ch${tc.channel}`;
      this._proxyObj[propName] = cur ? cur.label : (tc.tracks[0]?.label || '');
      const folder = this._gui.addFolder(`Texture ch${tc.channel}`);
      const ctrl = folder.add(this._proxyObj, propName, Object.keys(texMap))
        .name('Image')
        .onChange((label) => {
          const url = texMap[label];
          const file = texFileMap[label];
          if (url) tc.onSwitch(url, file);
        });
      this._enhanceSelect(ctrl);
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
        this._enhanceSelect(c);
      } else {
        const range = getRange(p.name, p.value, p.comment);
        c = parent.add(this._proxyObj, p.name, range.min, range.max, range.step)
          .name(label)
          .onChange(() => { if (p.type === "int") this._proxyObj[p.name] = Math.round(this._proxyObj[p.name]); this._apply(p); });
        this._enhanceSlider(c);
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
        const bc = parent.add(this._proxyObj, scaleKey, 0.01, maxC * 3, 0.01)
          .name(label.replace(/Tint\d*$|Color\d*$/, "").trim() + " Bright")
          .onChange(() => this._applyColor(p));
        this._enhanceSlider(bc);
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
        const bc = parent.add(this._proxyObj, scaleKey, 0.01, maxC * 3, 0.01)
          .name(label.replace(/Color\d*$/, "").trim() + " Bright")
          .onChange(() => this._applyColor(p));
        this._enhanceSlider(bc);
      }
      const alphaLabel = label.replace(/Color\d*$/, "Alpha").trim() || "Alpha";
      const ac = parent.add(this._proxyObj, alphaKey, 0, 1, 0.01).name(alphaLabel)
        .onChange(() => this._applyColor(p));
      this._enhanceSlider(ac);
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
      const vc = folder.add(this._proxyObj, key, range.min, range.max, range.step)
        .name(labels[i].toUpperCase())
        .onChange(() => this._applyVec(p, dim, labels));
      this._enhanceSlider(vc);
    }
  }

  /** Add arrow-key cycling and label-click-to-focus on a select controller. */
  _enhanceSelect(ctrl) {
    const selectEl = ctrl.$widget.querySelector('select');
    if (!selectEl) return null;
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
    ctrl.$name.style.cursor = 'pointer';
    ctrl.$name.addEventListener('click', () => selectEl.focus());
    return selectEl;
  }

  /** Enhance a slider: label-click-to-focus, left/right to adjust, up/down to navigate. */
  _enhanceSlider(ctrl) {
    // lil-gui renders sliders as <div class="slider"> not <input type="range">
    const sliderEl = ctrl.$slider;
    if (!sliderEl) return;
    sliderEl.tabIndex = 0;
    sliderEl.style.outline = 'none';
    this._sliderInputs.push(sliderEl);
    ctrl.$name.style.cursor = 'pointer';
    ctrl.$name.addEventListener('click', () => sliderEl.focus());
    sliderEl.addEventListener('keydown', (e) => {
      if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
        e.preventDefault();
        const step = ctrl._step || ((ctrl._max - ctrl._min) / 100);
        const dir = e.key === 'ArrowLeft' ? -1 : 1;
        const v = ctrl.getValue() + dir * step;
        ctrl.setValue(Math.max(ctrl._min, Math.min(ctrl._max, v)));
        return;
      }
      if (e.key === 'ArrowUp' || e.key === 'ArrowDown') {
        e.preventDefault();
        const idx = this._sliderInputs.indexOf(sliderEl);
        if (idx < 0) return;
        const next = e.key === 'ArrowUp' ? idx - 1 : idx + 1;
        if (next >= 0 && next < this._sliderInputs.length) {
          this._sliderInputs[next].focus();
        }
      }
    });
  }

  /** Focus the topmost interactive control. If audio, focus the Track selector. */
  focusFirstControl() {
    if (this._trackSelect) {
      this._trackSelect.focus();
      return;
    }
    if (this._gui) {
      const el = this._gui.$children.querySelector('input, select');
      if (el) el.focus();
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
    this._trackSelect = null;
    this._sliderInputs = [];
  }
}

/**
 * Build audio/mod track config for the shader tuner panel.
 * Loads both mod and audio folder indexes so the user can switch
 * between track types via the Type selector in the tuner.
 *
 * @param {object}   annotations  Parsed @iChannel media annotations
 * @param {string}   baseUrl      Base URL for resolving relative paths
 * @param {object}   deps         External dependencies
 * @param {object}   deps.mediaLoader  MediaLoader instance
 * @param {Function} deps.getSource    Returns current editor source
 * @param {Function} deps.setSource    Sets editor source
 * @param {Function} deps.applyShader  Compiles & applies shader source
 */
export async function buildAudioConfig(annotations, baseUrl, { mediaLoader, getSource, setSource, applyShader }) {
  if (!mediaLoader.hasAudio) return null;
  const currentType = mediaLoader.audioType;  // 'audio' | 'mod'
  const ann = annotations.find(a => a.type === 'audio' || a.type === 'mod');
  if (!ann) return null;

  // Derive the folder path from the annotation (e.g. "../../media/mod/song.mod" → "../../media/mod/")
  const lastSlash = ann.path.lastIndexOf('/');
  const folder = lastSlash >= 0 ? ann.path.substring(0, lastSlash + 1) : '';

  // Derive both mod and audio folder paths.
  // If the annotation path already lives under a recognized media folder, swap between them.
  // Otherwise fall back to the well-known ../../media/{audio,mod}/ paths relative to the shader.
  let modFolder, audioFolder;
  if (/audio\/$/i.test(folder)) {
    audioFolder = folder;
    modFolder = folder.replace(/audio\/$/, 'mod/');
  } else if (/mod\/$/i.test(folder)) {
    modFolder = folder;
    audioFolder = folder.replace(/mod\/$/, 'audio/');
  } else {
    // Unmanaged path — use standard media locations relative to shaders/
    modFolder = '../../media/mod/';
    audioFolder = '../../media/audio/';
  }

  async function loadIndex(folderPath) {
    try {
      const indexUrl = new URL(folderPath + 'index.js', baseUrl).href;
      const mod = await import(indexUrl);
      return mod.default || [];
    } catch (e) {
      console.warn('Could not load media index:', folderPath, e);
      return [];
    }
  }

  function buildTracks(entries, folderPath) {
    return entries.map(entry => {
      const file = typeof entry === 'string' ? entry : entry.file;
      const gain = typeof entry === 'string' ? 1 : (entry.gain || 1);
      return {
        label: file.replace(/\.[^.]+$/, ''),
        file,
        annPath: folderPath + file,
        gain,
        url: new URL((folderPath + file).replace(/#/g, '%23'), baseUrl).href,
      };
    });
  }

  const [modFiles, audioFiles] = await Promise.all([
    loadIndex(modFolder),
    loadIndex(audioFolder),
  ]);

  const modTracks = buildTracks(modFiles, modFolder);
  const audioTracks = buildTracks(audioFiles, audioFolder);
  const currentUrl = new URL(ann.path.replace(/#/g, '%23'), baseUrl).href;
  const allTracks = currentType === 'mod' ? modTracks : audioTracks;
  const currentTrack = allTracks.find(t => t.url === currentUrl);
  const currentGain = currentTrack ? currentTrack.gain : 1;

  // If the current path isn't in the index, prepend it as an unmanaged entry
  if (!currentTrack) {
    const file = ann.path.substring(ann.path.lastIndexOf('/') + 1);
    allTracks.unshift({
      label: '! ' + file.replace(/\.[^.]+$/, ''),
      file,
      annPath: ann.path,
      gain: 1,
      url: currentUrl,
    });
  }

  return {
    modTracks,
    audioTracks,
    defaultType: currentType,
    currentUrl,
    currentGain,
    onSwitch: (url, annPath, gain) => {
      if (currentType === 'mod') {
        mediaLoader.switchModSource(url, gain);
      } else {
        mediaLoader.switchAudioSource(url, gain);
      }
      const src = getSource();
      const re = new RegExp(
        '(//\\s*@iChannel' + ann.channel + '\\s+)(?:"[^"]+"|\\S+)(\\s+(?:audio|mod))',
      );
      const updated = src.replace(re, `$1"${annPath}"$2`);
      if (updated !== src) setSource(updated);
    },
    onSwitchType: (newType) => {
      const tracks = newType === 'mod' ? modTracks : audioTracks;
      if (tracks.length === 0) return;
      const newPath = tracks[0].annPath;
      const src = getSource();
      const re = new RegExp(
        '(//\\s*@iChannel' + ann.channel + '\\s+)(?:"[^"]+"|\\S+)\\s+(?:audio|mod)',
      );
      const updated = src.replace(re, `$1"${newPath}" ${newType}`);
      if (updated !== src) {
        setSource(updated);
        applyShader(updated, true);
      }
    },
  };
}

/**
 * Build texture switching configs for all @iChannel texture annotations.
 * Returns an array (one per texture channel) for the tuner panel.
 *
 * @param {Array}    annotations  Parsed @iChannel media annotations
 * @param {string}   baseUrl      Base URL for resolving relative paths
 * @param {object}   deps         External dependencies
 * @param {object}   deps.mediaLoader  MediaLoader instance
 * @param {Function} deps.getSource    Returns current editor source
 * @param {Function} deps.setSource    Sets editor source
 */
export async function buildTextureConfigs(annotations, baseUrl, { mediaLoader, getSource, setSource }) {
  const textureAnns = annotations.filter(a => a.type === 'texture');
  if (textureAnns.length === 0) return [];

  const configs = [];
  for (const ann of textureAnns) {
    // Derive folder path from annotation path
    const lastSlash = ann.path.lastIndexOf('/');
    const folder = lastSlash >= 0 ? ann.path.substring(0, lastSlash + 1) : '';

    let entries;
    try {
      const indexUrl = new URL(folder + 'index.js', baseUrl).href;
      const mod = await import(indexUrl);
      entries = mod.default || [];
    } catch (e) {
      console.warn('Could not load texture index:', folder, e);
      continue;
    }

    const tracks = entries.map(entry => {
      const file = typeof entry === 'string' ? entry : entry.file;
      return {
        label: file.replace(/\.[^.]+$/, ''),
        file,
        url: new URL((folder + file).replace(/#/g, '%23'), baseUrl).href,
      };
    });

    const currentUrl = new URL(ann.path.replace(/#/g, '%23'), baseUrl).href;

    // If the current path isn't in the index, prepend it as an unmanaged entry
    if (!tracks.some(t => t.url === currentUrl)) {
      const file = ann.path.substring(ann.path.lastIndexOf('/') + 1);
      tracks.unshift({
        label: '! ' + file.replace(/\.[^.]+$/, ''),
        file,
        url: currentUrl,
      });
    }

    configs.push({
      channel: ann.channel,
      tracks,
      currentUrl,
      onSwitch: (url, file) => {
        mediaLoader.switchImageSource(ann.channel, url);
        const src = getSource();
        const newPath = folder + file;
        const re = new RegExp(
          '(//\\s*@iChannel' + ann.channel + '\\s+)(?:"[^"]+"|\\S+)(\\s+texture)',
        );
        const updated = src.replace(re, `$1"${newPath}"$2`);
        if (updated !== src) setSource(updated);
      },
    });
  }

  return configs;
}
