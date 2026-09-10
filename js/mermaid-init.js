import mermaid from "mermaid";

function getMermaidTheme() {
  const appTheme = document.documentElement.getAttribute("data-theme");
  return appTheme === "light" ? "default" : "dark";
}

let renderTimeout = null;
let observer = null;
let rendering = false;
let renderAgain = false;
let nextDiagramId = 0;
const rendered = new WeakMap();

function showRenderError(el, source, error) {
  const title = document.createElement("strong");
  title.className = "mermaid-error-title";
  title.textContent = "Couldn’t render diagram";

  const message = document.createElement("pre");
  message.className = "mermaid-error-message";
  message.textContent = error?.message || error?.str || String(error);

  const details = document.createElement("details");
  const summary = document.createElement("summary");
  summary.textContent = "Show diagram source";
  const code = document.createElement("pre");
  code.className = "mermaid-source";
  code.textContent = source;
  details.append(summary, code);
  el.replaceChildren(title, message, details);
  el.dataset.state = "error";
}

async function renderMermaidBlocks() {
  // Serialize renders, including theme changes, because Mermaid has global config.
  if (rendering) {
    renderAgain = true;
    return;
  }
  rendering = true;
  try {
    for (const el of document.querySelectorAll(".preview-content .mermaid[data-source]")) {
      if (!el.isConnected) continue;
      const source = el.dataset.source ?? "";
      const theme = getMermaidTheme();
      const previous = rendered.get(el);
      if (previous?.source === source && previous?.theme === theme) continue;
      rendered.set(el, { source, theme });
      el.dataset.state = "rendering";
      el.removeAttribute("data-processed");
      el.textContent = "Rendering diagram…";

      // Source or theme may change while Mermaid is awaiting layout/imports.
      const isCurrent = () => el.isConnected && el.dataset.source === source && getMermaidTheme() === theme;
      try {
        mermaid.initialize({
          startOnLoad: false,
          theme,
          securityLevel: "strict",
          suppressErrorRendering: true,
        });
        const { svg, bindFunctions } = await mermaid.render(`fence-mermaid-${++nextDiagramId}`, source);
        if (!isCurrent()) {
          rendered.delete(el);
          renderAgain = true;
          continue;
        }
        el.innerHTML = svg;
        bindFunctions?.(el);
        el.dataset.state = "rendered";
      } catch (error) {
        if (!isCurrent()) {
          rendered.delete(el);
          renderAgain = true;
          continue;
        }
        showRenderError(el, source, error);
      }
      el.dataset.processed = "true";
    }
  } finally {
    rendering = false;
    if (renderAgain) {
      renderAgain = false;
      scheduleRender();
    }
  }
}

function scheduleRender() {
  clearTimeout(renderTimeout);
  renderTimeout = setTimeout(renderMermaidBlocks, 50);
}

function observePreview(target) {
  if (observer) observer.disconnect();
  observer = new MutationObserver(scheduleRender);
  observer.observe(target, { childList: true, subtree: true, attributes: true, attributeFilter: ["data-source"] });
  renderMermaidBlocks();
}

export function initMermaid() {
  // Retry until .preview-content appears (Elm may not have rendered yet).
  function tryAttach() {
    const target = document.querySelector(".preview-content");
    if (target) {
      observePreview(target);
    } else {
      requestAnimationFrame(tryAttach);
    }
  }
  tryAttach();
}

export function reRenderMermaid() {
  renderMermaidBlocks();
}

// Export joins any render already in flight, then handles newly parsed blocks.
export async function finishMermaidRendering() {
  do {
    while (rendering) await new Promise(resolve => requestAnimationFrame(resolve));
    clearTimeout(renderTimeout);
    await renderMermaidBlocks();
  } while (rendering || renderAgain || [...document.querySelectorAll(".preview-content .mermaid[data-source]")].some(el =>
    !["rendered", "error"].includes(el.dataset.state) || rendered.get(el)?.source !== el.dataset.source || rendered.get(el)?.theme !== getMermaidTheme()));
}
