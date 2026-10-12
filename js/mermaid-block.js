import { attachFullscreenButton, refreshExpandedDiagram } from "./mermaid-fullscreen.js";

const states = new WeakMap();
const sizes = new ResizeObserver((entries) => {
  for (const { target } of entries) fitDiagram(target);
});

function fitDiagram(block) {
  const state = states.get(block);
  if (!state || state.manualSize || block.dataset.view === "source") return;
  const width = block.querySelector(".mermaid-diagram svg")?.viewBox.baseVal.width;
  const room = block.clientWidth - 32;
  if (!width || room <= 0) return;
  block.dataset.size = room / width < 0.7 ? "actual" : "fit";
  state.sizeButton.setAttribute("aria-pressed", String(block.dataset.size === "actual"));
}

export function mountDiagram(block, svg, source) {
  const previous = states.get(block);
  const sameSource = previous?.source === source;
  const view = sameSource ? block.dataset.view : "diagram";
  const target = document.createElement("div");
  target.className = "mermaid-diagram";
  target.tabIndex = 0;
  target.setAttribute("role", "region");
  target.setAttribute("aria-label", "Diagram; scroll to see the full width");
  target.append(svg);
  const code = document.createElement("pre");
  code.className = "mermaid-source md-code-block";
  code.tabIndex = 0;
  code.textContent = source;
  const bar = document.createElement("div");
  bar.className = "mermaid-bar";
  const sourceButton = document.createElement("button");
  sourceButton.type = "button";
  sourceButton.textContent = "Source";
  sourceButton.setAttribute("aria-label", "Show diagram source");
  sourceButton.setAttribute("aria-pressed", String(view === "source"));
  sourceButton.addEventListener("click", () => {
    const show = block.dataset.view !== "source";
    block.dataset.view = show ? "source" : "diagram";
    sourceButton.setAttribute("aria-pressed", String(show));
    if (!show) fitDiagram(block);
  });
  const sizeButton = document.createElement("button");
  sizeButton.type = "button";
  sizeButton.className = "mermaid-size";
  sizeButton.textContent = "Actual size";
  sizeButton.setAttribute("aria-label", "Show diagram at actual size");
  sizeButton.addEventListener("click", () => {
    states.get(block).manualSize = true;
    block.dataset.size = block.dataset.size === "actual" ? "fit" : "actual";
    sizeButton.setAttribute("aria-pressed", String(block.dataset.size === "actual"));
  });
  states.set(block, { source, sizeButton, manualSize: sameSource && previous.manualSize });
  block.dataset.view = view || "diagram";
  if (!sameSource) block.dataset.size = "fit";
  sizeButton.setAttribute("aria-pressed", String(block.dataset.size === "actual"));
  bar.append(sizeButton, sourceButton);
  block.replaceChildren(bar, target, code);
  attachFullscreenButton(bar, block);
  sizes.observe(block);
  observedBlocks.add(block);
  fitDiagram(block);
  refreshExpandedDiagram(block);
}

// ResizeObserver holds its targets strongly, even after DOM removal.
export function releaseDiagrams() {
  for (const block of observedBlocks) {
    if (!block.isConnected || block.dataset.state !== "rendered") {
      sizes.unobserve(block);
      observedBlocks.delete(block);
    }
  }
}

const observedBlocks = new Set();
