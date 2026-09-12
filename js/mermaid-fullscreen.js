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

let overlay = null;
let figure = null;
let paneObserver = null;

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

  overlay.append(figure, close);

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
