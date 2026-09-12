// Expanding a single diagram to fill the preview pane.
//
// Elm owns a mermaid block's `data-source` attribute and nothing inside it, so
// this whole feature lives in JS: the button is injected after each render (a
// re-render replaces the block's innerHTML and takes the button with it), and
// the overlay is a top-layer popover rather than an element inside the pane,
// which would otherwise be clipped by the pane's own scrolling.
//
// `popover="auto"` is what makes this small: it brings Esc, dismissal on an
// outside click, and returning focus to the button with it. It carries no
// backdrop, so the editor stays visible and usable beside it.

const BUTTON_CLASS = "mermaid-fullscreen-btn";
const MIN_SCALE = 0.2;
const MAX_SCALE = 12;

let overlay = null;
let figure = null;
let paneObserver = null;
let zoomLabel = null;

// Pan/zoom of the expanded diagram, as a transform on the SVG. The SVG stays
// laid out by flex + preserveAspectRatio, so scale 1 is always "fitted".
const view = { scale: 1, x: 0, y: 0 };

function applyView() {
  const svg = figure?.firstElementChild;
  if (!svg) return;
  svg.style.transform = `translate(${view.x}px, ${view.y}px) scale(${view.scale})`;
  if (zoomLabel) zoomLabel.textContent = `${Math.round(view.scale * 100)}%`;
  figure.dataset.zoomed = view.scale !== 1 || view.x !== 0 || view.y !== 0 ? "true" : "false";
}

function resetView() {
  view.scale = 1;
  view.x = 0;
  view.y = 0;
  applyView();
}

/** Zoom to `scale`, keeping the point under (cx, cy) in place. The transform
    origin is the figure's centre, which is what the maths below assumes. */
function zoomTo(scale, cx, cy) {
  const next = Math.min(MAX_SCALE, Math.max(MIN_SCALE, scale));
  const box = figure.getBoundingClientRect();
  const originX = box.left + box.width / 2;
  const originY = box.top + box.height / 2;
  // The content point currently under the cursor, in unscaled coordinates.
  const px = (cx - originX - view.x) / view.scale;
  const py = (cy - originY - view.y) / view.scale;
  view.x = cx - originX - px * next;
  view.y = cy - originY - py * next;
  view.scale = next;
  applyView();
}

function zoomBy(factor) {
  const box = figure.getBoundingClientRect();
  zoomTo(view.scale * factor, box.left + box.width / 2, box.top + box.height / 2);
}

function paneRect() {
  const pane = document.querySelector(".preview-pane");
  return pane ? pane.getBoundingClientRect() : null;
}

/** Keep the overlay over the preview pane as the divider or window moves. */
function trackPane() {
  const box = paneRect();
  if (!box || !overlay) return;
  overlay.style.top = `${box.top}px`;
  overlay.style.left = `${box.left}px`;
  overlay.style.width = `${box.width}px`;
  overlay.style.height = `${box.height}px`;
}

function ensureOverlay() {
  if (overlay) return overlay;

  overlay = document.createElement("div");
  overlay.className = "mermaid-fullscreen";
  overlay.id = "mermaid-fullscreen";
  overlay.setAttribute("popover", "auto");
  overlay.setAttribute("aria-label", "Diagram, expanded");

  figure = document.createElement("div");
  figure.className = "mermaid-fullscreen-figure";

  const close = document.createElement("button");
  close.type = "button";
  close.className = "mermaid-fullscreen-close";
  // The popover's show algorithm focuses this, so focus lands inside the
  // overlay in the same task rather than a tick later.
  close.setAttribute("autofocus", "");
  close.setAttribute("aria-label", "Close expanded diagram (Escape)");
  close.textContent = "✕";
  close.addEventListener("click", () => overlay.hidePopover());

  const controls = document.createElement("div");
  controls.className = "mermaid-fullscreen-controls";

  const zoomOut = document.createElement("button");
  zoomOut.type = "button";
  zoomOut.className = "mermaid-fullscreen-zoom";
  zoomOut.setAttribute("aria-label", "Zoom out");
  zoomOut.textContent = "−";
  zoomOut.addEventListener("click", () => zoomBy(1 / 1.25));

  zoomLabel = document.createElement("button");
  zoomLabel.type = "button";
  zoomLabel.className = "mermaid-fullscreen-zoom mermaid-fullscreen-level";
  zoomLabel.setAttribute("aria-label", "Reset zoom");
  zoomLabel.textContent = "100%";
  zoomLabel.addEventListener("click", resetView);

  const zoomIn = document.createElement("button");
  zoomIn.type = "button";
  zoomIn.className = "mermaid-fullscreen-zoom";
  zoomIn.setAttribute("aria-label", "Zoom in");
  zoomIn.textContent = "+";
  zoomIn.addEventListener("click", () => zoomBy(1.25));

  controls.append(zoomOut, zoomLabel, zoomIn);

  // Pinch on a trackpad arrives as a wheel event with ctrlKey set; a plain
  // wheel pans, the way diagram editors behave.
  figure.addEventListener("wheel", (event) => {
    event.preventDefault();
    if (event.ctrlKey || event.metaKey) {
      zoomTo(view.scale * Math.exp(-event.deltaY / 200), event.clientX, event.clientY);
    } else {
      view.x -= event.deltaX;
      view.y -= event.deltaY;
      applyView();
    }
  }, { passive: false });

  // Drag to pan. Pointer capture keeps the drag alive if the cursor leaves
  // the diagram, and touch-action in the CSS stops the gesture scrolling.
  let dragging = null;
  figure.addEventListener("pointerdown", (event) => {
    if (event.button !== 0) return;
    dragging = { id: event.pointerId, x: event.clientX, y: event.clientY };
    figure.setPointerCapture(event.pointerId);
    figure.dataset.dragging = "true";
  });
  figure.addEventListener("pointermove", (event) => {
    if (!dragging || dragging.id !== event.pointerId) return;
    view.x += event.clientX - dragging.x;
    view.y += event.clientY - dragging.y;
    dragging.x = event.clientX;
    dragging.y = event.clientY;
    applyView();
  });
  const endDrag = (event) => {
    if (!dragging || dragging.id !== event.pointerId) return;
    dragging = null;
    delete figure.dataset.dragging;
  };
  figure.addEventListener("pointerup", endDrag);
  figure.addEventListener("pointercancel", endDrag);
  figure.addEventListener("dblclick", resetView);

  // Keyboard equivalents: the overlay is focusable, so pan and zoom must not
  // be mouse-only.
  overlay.addEventListener("keydown", (event) => {
    const step = event.shiftKey ? 120 : 40;
    const keys = {
      "+": () => zoomBy(1.25),
      "=": () => zoomBy(1.25),
      "-": () => zoomBy(1 / 1.25),
      _: () => zoomBy(1 / 1.25),
      0: resetView,
      ArrowLeft: () => { view.x += step; applyView(); },
      ArrowRight: () => { view.x -= step; applyView(); },
      ArrowUp: () => { view.y += step; applyView(); },
      ArrowDown: () => { view.y -= step; applyView(); },
    };
    const action = keys[event.key];
    if (!action) return;
    event.preventDefault();
    action();
  });

  overlay.append(figure, controls, close);

  // Elm listens for keydown on the document and closes the settings menu, the
  // palette and the find bar on Escape. The popover handles its own Escape,
  // so stop it here rather than letting Elm act on it too.
  overlay.addEventListener("keydown", (event) => {
    if (event.key === "Escape") event.stopPropagation();
  });

  // beforetoggle rather than toggle: it runs synchronously as part of the
  // show/hide algorithm, so the overlay is positioned before it is painted
  // and the clone is released by the time the popover reports itself closed.
  overlay.addEventListener("beforetoggle", (event) => {
    if (event.newState === "open") {
      trackPane();
      paneObserver ??= new ResizeObserver(trackPane);
      const pane = document.querySelector(".preview-pane");
      if (pane) paneObserver.observe(pane);
      window.addEventListener("resize", trackPane);
    } else {
      paneObserver?.disconnect();
      window.removeEventListener("resize", trackPane);
      // Release the clone: a large diagram is a lot of SVG to hold onto.
      figure.replaceChildren();
    }
  });

  document.body.appendChild(overlay);
  return overlay;
}

/** A copy of the block's SVG, freed from the intrinsic size mermaid gave it
    so it scales to the space instead of sitting small in the middle. */
function scalableCopy(svg) {
  const copy = svg.cloneNode(true);
  copy.removeAttribute("style");
  copy.removeAttribute("width");
  copy.removeAttribute("height");
  copy.setAttribute("preserveAspectRatio", "xMidYMid meet");
  copy.classList.add("mermaid-fullscreen-svg");
  return copy;
}

function expand(block) {
  const svg = block.querySelector("svg");
  if (!svg) return;
  ensureOverlay();
  figure.replaceChildren(scalableCopy(svg));
  resetView();
  trackPane();
  overlay.showPopover();
}

/** Called after a block renders. The button is injected rather than rendered
    by Elm because mermaid replaces the block's innerHTML on every render. */
export function attachFullscreenButton(block) {
  if (block.querySelector(`.${BUTTON_CLASS}`)) return;

  const button = document.createElement("button");
  button.type = "button";
  button.className = BUTTON_CLASS;
  button.setAttribute("aria-label", "Expand diagram");
  button.title = "Expand diagram";
  button.textContent = "⤢";
  button.addEventListener("click", (event) => {
    event.preventDefault();
    expand(block);
  });
  block.appendChild(button);
}

/** Strip the injected buttons out of exported markup: the export path sends
    the pane's innerHTML verbatim, and a stray button would ship with it. */
export function withoutFullscreenButtons(pane) {
  const copy = pane.cloneNode(true);
  copy.querySelectorAll(`.${BUTTON_CLASS}`).forEach((node) => node.remove());
  return copy.innerHTML;
}
