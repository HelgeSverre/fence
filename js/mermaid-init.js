import mermaid from "mermaid";

function getMermaidTheme() {
  const appTheme = document.documentElement.getAttribute("data-theme");
  return appTheme === "light" ? "default" : "dark";
}

let renderTimeout = null;
let observer = null;

async function renderMermaidBlocks() {
  const blocks = document.querySelectorAll("pre.mermaid:not([data-processed])");
  if (blocks.length === 0) return;

  // Save source text before mermaid replaces innerHTML with SVG
  blocks.forEach((el) => {
    if (!el.getAttribute("data-source")) {
      el.setAttribute("data-source", el.textContent);
    }
  });

  try {
    mermaid.initialize({
      startOnLoad: false,
      theme: getMermaidTheme(),
      securityLevel: "strict",
    });
    await mermaid.run({ nodes: blocks });
  } catch (e) {
    console.warn("[mermaid] render error:", e.message);
  }
}

function scheduleRender() {
  clearTimeout(renderTimeout);
  renderTimeout = setTimeout(renderMermaidBlocks, 50);
}

function observePreview(target) {
  // Disconnect any previous observer
  if (observer) observer.disconnect();

  observer = new MutationObserver(scheduleRender);
  observer.observe(target, { childList: true, subtree: true });
  renderMermaidBlocks();
}

export function initMermaid() {
  mermaid.initialize({
    startOnLoad: false,
    theme: getMermaidTheme(),
    securityLevel: "strict",
  });

  // Retry until .preview-content appears (Elm may not have rendered yet)
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
  document.querySelectorAll("pre.mermaid[data-processed]").forEach((el) => {
    el.removeAttribute("data-processed");
    const source = el.getAttribute("data-source");
    if (source) el.textContent = source;
  });
  renderMermaidBlocks();
}
