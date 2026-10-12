import { closeStaleExpandedDiagram } from "./mermaid-fullscreen.js";
import { mountDiagram, releaseDiagrams } from "./mermaid-block.js";
import { diagramTheme, diagramConfig, polishDiagram } from "./mermaid-theme.js";
import { uniqueDiagramCopy } from "./mermaid-svg.js";

let mermaidModule = null;
function loadMermaid() {
  mermaidModule ??= import("mermaid").then((m) => m.default);
  return mermaidModule;
}

function renderingSettings() {
  return JSON.stringify(diagramTheme());
}

// Cache by source + appearance, capped at 64 entries and 4M characters.
const cache = new Map();
let cacheCharacters = 0;
function remember(key, value) {
  const characters = key.length + (value.svg?.length ?? value.error?.length ?? 0);
  if (characters > 4_000_000) return;
  while (cache.size && (cache.size >= 64 || cacheCharacters + characters > 4_000_000)) {
    const oldest = cache.keys().next().value;
    cacheCharacters -= cache.get(oldest).characters;
    cache.delete(oldest);
  }
  cache.set(key, { ...value, characters });
  cacheCharacters += characters;
}

async function drawDiagram(mermaid, source, settings) {
  const key = JSON.stringify([source, settings]);
  const hit = cache.get(key);
  if (hit) {
    cache.delete(key);
    cache.set(key, hit);
    return hit;
  }
  try {
    const theme = JSON.parse(settings);
    // Mermaid measures labels using the loaded font.
    await document.fonts.load(`${theme.size} ${theme.font}`).catch(() => {});
    await document.fonts.ready;
    mermaid.initialize(diagramConfig(theme));
    const { svg } = await mermaid.render(`fence-mermaid-${++nextDiagramId}`, source);
    const template = document.createElement("template");
    template.innerHTML = svg;
    const diagram = template.content.querySelector("svg");
    if (!diagram) throw new Error("Mermaid did not return an SVG");
    polishDiagram(diagram, theme);
    const result = { svg: diagram.outerHTML };
    remember(key, result);
    return result;
  } catch (error) {
    const result = { error: error?.message || error?.str || String(error) };
    remember(key, result);
    return result;
  }
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
    const settings = renderingSettings();
    const blocks = [...document.querySelectorAll(".preview-content .mermaid[data-source]")]
      .filter((el) => {
        const previous = rendered.get(el);
        return el.isConnected && !(previous?.source === (el.dataset.source ?? "") && previous?.theme === settings);
      });
    if (blocks.length === 0) return;
    const mermaid = await loadMermaid();
    for (const el of blocks) {
      if (!el.isConnected) continue;
      const source = el.dataset.source ?? "";
      const theme = renderingSettings();
      rendered.set(el, { source, theme });
      el.dataset.state = "rendering";
      el.removeAttribute("data-processed");
      el.textContent = "Rendering diagram…";

      const isCurrent = () => el.isConnected && el.dataset.source === source && renderingSettings() === theme;
      try {
        const result = await drawDiagram(mermaid, source, theme);
        if (!isCurrent()) {
          rendered.delete(el);
          renderAgain = true;
          continue;
        }
        if (result.error) {
          showRenderError(el, source, result.error);
        } else {
          const template = document.createElement("template");
          template.innerHTML = result.svg;
          mountDiagram(el, uniqueDiagramCopy(template.content.querySelector("svg")), source);
          el.dataset.state = "rendered";
        }
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
    releaseDiagrams();
    closeStaleExpandedDiagram();
    if (renderAgain) {
      renderAgain = false;
      scheduleRender();
    }
  }
}

function scheduleRender() {
  releaseDiagrams();
  closeStaleExpandedDiagram();
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
  // Elm applies mono-preview on its next paint, after the preference port.
  const appearanceObserver = new MutationObserver(scheduleRender);
  // Retry until .preview-content appears (Elm may not have rendered yet).
  function tryAttach() {
    const target = document.querySelector(".preview-content");
    if (target) {
      const shell = document.querySelector(".app-shell");
      if (shell) appearanceObserver.observe(shell, { attributes: true, attributeFilter: ["class"] });
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
    !["rendered", "error"].includes(el.dataset.state) || rendered.get(el)?.source !== el.dataset.source || rendered.get(el)?.theme !== renderingSettings()));
}
