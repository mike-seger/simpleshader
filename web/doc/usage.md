## Usage

### Getting started

Serve the repository from its root directory:

```
python3 -m http.server 8080
```

Then open `http://localhost:8080` in a browser.

### Interface overview

The interface is split into three areas:

- **Sidebar** (left) — shader list and tuning controls
- **Preview** (top) — live WebGL canvas
- **Editor** (bottom) — Monaco code editor with GLSL syntax

### Selecting a shader

Click any shader name in the sidebar tree to load it. Folders collapse and expand; only one folder is open at a time. Use [[Arrow Up]] and [[Arrow Down]] to navigate with the keyboard.

### Editing and applying

Edit the GLSL source in the editor and press [[Ctrl]]+[[Enter]] (or click the **▲** button) to recompile. Errors appear as a red overlay on the preview.

### Play / Pause and time scrubbing

- Click the **pause** / **play** icon in the editor toolbar to toggle the render loop.
- Drag the time slider to scrub `u_time`.
- Click **skip_previous** to reset time to zero.

### Audio-reactive shaders

Shaders that include an `@iChannel` audio or MOD annotation automatically load and play audio. The audio toolbar appears with its own play/pause button and time scrubber.

### Tuning controls

Click the **tune** icon in the sidebar icon bar to open the tuning panel. Constants between `@lil-gui-start` and `@lil-gui-end` in the shader source are exposed as interactive sliders, color pickers, or checkboxes. Changes are applied in real time.

### Custom shaders

- Click **+** to create a new custom shader.
- Custom shaders are stored in `localStorage` and persist across sessions.
- Drag and drop `.glsl` files or `.zip` archives onto the shader list to import.
- Right-click a built-in shader and choose **Copy Shader Link** to share a direct URL.

### Pop-out preview

Click the **open_in_new** icon to open the preview in a separate window. The pop-out mirrors the main canvas and can be moved to a second monitor for full-screen viewing.

### Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| [[Ctrl]]+[[Enter]] | Apply / recompile shader |
| [[Arrow Up]] / [[Arrow Down]] | Navigate shader list |
| [[Delete]] | Delete selected custom shader |
