/**
 * Draggable splitter helper.
 * Makes the #hsplit bar resize the preview and editor panes.
 */

export function initSplitter(splitEl, topPane, bottomPane, onResize) {
  let dragging = false;

  const onPointerDown = (e) => {
    e.preventDefault();
    dragging = true;
    splitEl.classList.add("dragging");
    document.addEventListener("pointermove", onPointerMove);
    document.addEventListener("pointerup", onPointerUp);
  };

  const onPointerMove = (e) => {
    if (!dragging) return;
    const parent = splitEl.parentElement;
    const rect = parent.getBoundingClientRect();
    const splitH = splitEl.offsetHeight;
    const y = e.clientY - rect.top;
    const minH = 80;

    const topH = Math.max(minH, Math.min(y, rect.height - splitH - minH));
    const bottomH = rect.height - topH - splitH;

    topPane.style.flex = "none";
    topPane.style.height = topH + "px";
    bottomPane.style.flex = "none";
    bottomPane.style.height = bottomH + "px";

    if (onResize) onResize();
  };

  const onPointerUp = () => {
    dragging = false;
    splitEl.classList.remove("dragging");
    document.removeEventListener("pointermove", onPointerMove);
    document.removeEventListener("pointerup", onPointerUp);
  };

  splitEl.addEventListener("pointerdown", onPointerDown);
}
