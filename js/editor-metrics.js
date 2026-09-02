// Measure the editor's monospace metrics once per font/size change and the
// editor viewport on resize, and hand them to Elm for the virtual editor.
let app = null;
let probe = null;

function measure() {
  if (!app?.ports?.fromElectron) return;
  if (!probe) {
    probe = document.createElement("span");
    probe.className = "editor-metrics-probe";
    probe.textContent = "x".repeat(100);
    document.body.appendChild(probe);
  }
  const container = document.querySelector(".editor-container");
  const rect = probe.getBoundingClientRect();
  app.ports.fromElectron.send({
    tag: "editorMetrics",
    lineHeight: parseFloat(getComputedStyle(probe).lineHeight) || rect.height,
    charWidth: rect.width / 100,
    viewportHeight: container ? container.clientHeight : window.innerHeight,
  });
}

export function setupEditorMetrics(elmApp) {
  app = elmApp;
  requestAnimationFrame(measure);
  document.fonts?.ready?.then(() => requestAnimationFrame(measure));
  new ResizeObserver(() => measure()).observe(document.body);
}

export function remeasureEditorMetrics() {
  requestAnimationFrame(measure);
}
