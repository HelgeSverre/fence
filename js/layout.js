import { remeasureEditorMetrics } from "./editor-metrics.js";

export function setupLayout(initialState) {
  const saved = initialState.layoutCycleKey;
  let binding = saved && typeof saved.key === "string" &&
    ["meta", "ctrl", "shift", "alt"].every((key) => typeof saved[key] === "boolean")
    ? saved : { key: "2", meta: true, ctrl: false, shift: false, alt: false };
  let generation = 0;
  document.addEventListener("keydown", (event) => {
    if (event.key.toLowerCase() === binding.key.toLowerCase() &&
        ["meta", "ctrl", "shift", "alt"].every((key) => event[`${key}Key`] === binding[key])) {
      event.preventDefault();
    }
  }, true);
  return {
    setBinding(value) { binding = value; },
    changed({ mode }) {
      const focusSelector = document.activeElement?.closest(".layout-selector");
      const current = ++generation;
      requestAnimationFrame(() => requestAnimationFrame(() => {
        if (current !== generation) return;
        remeasureEditorMetrics();
        const target = focusSelector
          ? document.getElementById(`layout-${mode}`)
          : document.getElementById("find-input") ?? document.getElementById(mode === "preview" ? "preview-container" : "veditor-input");
        target?.focus({ preventScroll: true });
      }));
    },
  };
}
