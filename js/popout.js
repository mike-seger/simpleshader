/**
 * Pop-out preview window manager.
 */

export default class PopoutManager {
  /**
   * @param {object} opts
   * @param {object} opts.renderer       Embedded Renderer instance
   * @param {Function} opts.Renderer     Renderer constructor
   * @param {object} opts.mediaLoader    MediaLoader instance
   * @param {object} opts.editor         Editor instance
   * @param {Function} opts.fpsHandler   FPS callback for the pop-out renderer
   * @param {Element} opts.btnPopout     Pop-out toggle button
   * @param {Element} opts.previewPane   Preview pane element
   * @param {Element} opts.editorPane    Editor pane element
   * @param {Element} opts.hsplit        Horizontal splitter element
   * @param {Function} opts.compileSource Async (renderer) => void — compiles current source
   */
  constructor({ renderer, Renderer, mediaLoader, editor, fpsHandler,
                btnPopout, previewPane, editorPane, hsplit, compileSource }) {
    this._renderer = renderer;
    this._Renderer = Renderer;
    this._mediaLoader = mediaLoader;
    this._editor = editor;
    this._fpsHandler = fpsHandler;
    this._btnPopout = btnPopout;
    this._previewPane = previewPane;
    this._editorPane = editorPane;
    this._hsplit = hsplit;
    this._compileSource = compileSource;
    this._win = null;
    this._poll = null;
    this._savedFlex = "";
    this._savedHeight = "";
  }

  /** The pop-out Window reference (null when closed). */
  get win() { return this._win; }

  /** Returns the pop-out renderer if active, otherwise the embedded renderer. */
  activeRenderer() {
    return (this._win && !this._win.closed && this._win._renderer)
      ? this._win._renderer
      : this._renderer;
  }

  /** Open the pop-out preview window. */
  open(debugVisible) {
    if (this._win && !this._win.closed) return;

    // Stop embedded rendering
    this._renderer.stop();
    this._previewPane.style.display = "none";
    this._hsplit.style.display = "none";
    // Let editor fill the full height
    this._savedFlex = this._editorPane.style.flex;
    this._savedHeight = this._editorPane.style.height;
    this._editorPane.style.flex = "1";
    this._editorPane.style.height = "";
    this._btnPopout.classList.add("active");
    this._editor.layout();

    this._win = window.open("", "shader_preview", "width=800,height=600");
    const doc = this._win.document;
    doc.title = "Shader Preview";
    doc.body.style.cssText = "margin:0;background:#000;overflow:hidden";

    // Debug overlay
    const dbg = doc.createElement("div");
    dbg.id = "debug-box";
    dbg.style.cssText = "position:fixed;top:8px;right:8px;background:rgba(0,0,0,0.65);color:#0f0;font-family:monospace;font-size:12px;padding:4px 8px;border-radius:4px;z-index:5;pointer-events:none;display:none";
    const fpsEl = doc.createElement("div");
    const timeEl = doc.createElement("div");
    const resEl = doc.createElement("div");
    dbg.appendChild(fpsEl);
    dbg.appendChild(timeEl);
    dbg.appendChild(resEl);
    doc.body.appendChild(dbg);
    this._win._debugBox = dbg;
    this._win._fpsEl = fpsEl;
    this._win._timeEl = timeEl;
    this._win._resEl = resEl;
    // Sync current debug visibility
    dbg.style.display = debugVisible ? "" : "none";

    const c = doc.createElement("canvas");
    c.style.cssText = "display:block;width:100%;height:100%";
    doc.body.appendChild(c);

    // Double-click to enter fullscreen, ESC to exit
    c.addEventListener("dblclick", () => {
      if (!doc.fullscreenElement) c.requestFullscreen();
    });
    doc.addEventListener("keydown", (e) => {
      if (e.key === "Escape" && doc.fullscreenElement) {
        e.preventDefault();
        doc.exitFullscreen();
      }
    });

    const r = new this._Renderer(c);
    this._win._renderer = r;
    r.mediaLoader = this._mediaLoader;
    r.onFps = this._fpsHandler;
    this._compileSource(r);
    // Sync pause state
    if (this._renderer.paused) r.togglePause();
    r.start();

    // Poll to detect the pop-out being closed (beforeunload is unreliable)
    this._poll = setInterval(() => {
      if (!this._win || this._win.closed) {
        clearInterval(this._poll);
        this._poll = null;
        this._btnPopout.classList.remove("active");
        this._restoreEmbedded();
        this._win = null;
      }
    }, 300);
  }

  /** Close the pop-out preview window. */
  close() {
    if (this._poll) { clearInterval(this._poll); this._poll = null; }
    if (this._win && !this._win.closed) this._win.close();
    this._win = null;
    this._btnPopout.classList.remove("active");
    this._restoreEmbedded();
  }

  /** Sync debug overlay visibility to the pop-out window. */
  syncDebug(visible) {
    if (this._win && !this._win.closed && this._win._debugBox) {
      this._win._debugBox.style.display = visible ? "" : "none";
    }
  }

  /** Close pop-out on page unload. */
  destroy() {
    if (this._win && !this._win.closed) this._win.close();
  }

  /** @private */
  _restoreEmbedded() {
    this._previewPane.style.display = "";
    this._hsplit.style.display = "";
    this._editorPane.style.flex = this._savedFlex;
    this._editorPane.style.height = this._savedHeight;
    // Recompile current source into embedded renderer so it's in sync
    this._compileSource(this._renderer).then(() => this._renderer.start());
    this._editor.layout();
  }
}
