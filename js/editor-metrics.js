// Measure the editor's monospace metrics (once per font or size change) and
// its viewport (on any resize), and hand them to Elm through the editorMetrics
// port. The probe is a hidden span styled like the editor, so a measurement
// costs one layout read rather than touching the document itself.
let app = null;
let probe = null;
let observer = null;
let observed = null;

const CONTAINER = ".editor-container";
const SCROLLER = "[data-testid=veditor]";

function metricsProbe() {
  if (!probe) {
    probe = document.createElement("span");
    probe.className = "editor-metrics-probe";
    probe.textContent = "x".repeat(100);
    document.body.appendChild(probe);
  }
  return probe;
}

function measure() {
  if (!app?.ports?.editorMetrics) return;
  const container = document.querySelector(CONTAINER);

  // The editor pane resizes when a divider is dragged, which leaves the body
  // untouched, so follow the pane itself and re-attach if Elm replaces it.
  if (container && container !== observed) {
    observer?.disconnect();
    observer = new ResizeObserver(() => measure());
    observer.observe(container);
    observed = container;
  }

  const rect = metricsProbe().getBoundingClientRect();
  // The scroller carries the padding, so the document's origin is its
  // content-box corner; a pointer anywhere in the window is measured from it.
  const scroller = document.querySelector(SCROLLER);
  const box = scroller?.getBoundingClientRect();
  const padding = scroller ? getComputedStyle(scroller) : null;
  const metrics = {
    lineHeight: parseFloat(getComputedStyle(probe).lineHeight) || rect.height,
    charWidth: rect.width / 100,
    viewportHeight: container ? container.clientHeight : window.innerHeight,
    viewportWidth: container ? container.clientWidth : window.innerWidth,
    viewportTop: box ? box.top + parseFloat(padding.paddingTop) : 0,
    viewportLeft: box ? box.left + parseFloat(padding.paddingLeft) : 0,
  };

  // A zero or missing measurement (probe not laid out yet, editor hidden)
  // would make every click resolve to the end of the line; keep the last
  // good values and try again on the next frame instead.
  const usable = ["lineHeight", "charWidth"].every((k) => Number.isFinite(metrics[k]) && metrics[k] > 0) && Boolean(box);
  if (!usable) {
    requestAnimationFrame(measure);
    return;
  }
  for (const k of ["viewportTop", "viewportLeft"]) {
    if (!Number.isFinite(metrics[k])) metrics[k] = 0;
  }
  for (const k of ["viewportHeight", "viewportWidth"]) {
    if (!Number.isFinite(metrics[k]) || metrics[k] <= 0) metrics[k] = 1;
  }
  app.ports.editorMetrics.send(metrics);
}

export function setupEditorMetrics(elmApp) {
  app = elmApp;
  requestAnimationFrame(measure);
  document.fonts?.ready?.then(() => requestAnimationFrame(measure));
  window.addEventListener("resize", measure);
}

export function remeasureEditorMetrics() {
  requestAnimationFrame(measure);
}
