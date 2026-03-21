/**
 * Monaco editor wrapper.
 * Loads Monaco from CDN and provides a GLSL editing surface.
 */

const MONACO_CDN = "https://cdn.jsdelivr.net/npm/monaco-editor@0.45.0/min";

let monacoReady = null;

/** Load Monaco AMD loader once, returns a Promise<monaco> */
function loadMonaco() {
  if (monacoReady) return monacoReady;
  monacoReady = new Promise((resolve, reject) => {
    const script = document.createElement("script");
    script.src = `${MONACO_CDN}/vs/loader.js`;
    script.onload = () => {
      window.require.config({ paths: { vs: `${MONACO_CDN}/vs` } });
      window.require(["vs/editor/editor.main"], () => resolve(window.monaco), reject);
    };
    script.onerror = reject;
    document.head.appendChild(script);
  });
  return monacoReady;
}

export default class Editor {
  /**
   * @param {HTMLElement} container
   * @param {(source: string) => void} onApply — called when user hits Apply
   */
  constructor(container, onApply) {
    this._container = container;
    this._onApply = onApply;
    this._editor = null;
    this._monaco = null;
  }

  async init() {
    this._monaco = await loadMonaco();

    this._editor = this._monaco.editor.create(this._container, {
      value: "// Select a shader from the sidebar",
      language: "c", // closest built-in to GLSL
      theme: "vs-dark",
      minimap: { enabled: false },
      fontSize: 13,
      scrollBeyondLastLine: false,
      automaticLayout: true,
      tabSize: 4,
      renderWhitespace: "none",
      lineNumbers: "on",
    });

    // Ctrl/Cmd+Enter to apply
    this._editor.addAction({
      id: "shader-apply",
      label: "Apply Shader",
      keybindings: [
        this._monaco.KeyMod.CtrlCmd | this._monaco.KeyCode.Enter,
      ],
      run: () => this._onApply(this._editor.getValue()),
    });
  }

  /** Replace editor contents */
  setValue(source) {
    if (!this._editor) return;
    this._editor.setValue(source);
  }

  /** Get current editor contents */
  getValue() {
    return this._editor ? this._editor.getValue() : "";
  }

  /** Force layout recalculation (after resize) */
  layout() {
    if (this._editor) this._editor.layout();
  }
}
