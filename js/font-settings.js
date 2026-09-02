// Helpers for applying persisted font preferences as CSS custom properties on
// <html>. Shared between init (js/main.js) and the runtime port handler
// (js/ports.js) so the two stay in sync.

const root = document.documentElement;

export function applyFontFamily(font) {
  if (font) {
    root.style.setProperty("--font-mono", `"${font}", monospace`);
  } else {
    root.style.removeProperty("--font-mono");
  }
}

export function applyFontSize(name, size) {
  if (size) {
    root.style.setProperty(`--font-size-${name}`, size + "px");
  }
}

export function applyFontSizesFromState(state) {
  applyFontSize("editor", state.editorFontSize);
  applyFontSize("preview", state.previewFontSize);
  applyFontSize("ui", state.uiFontSize);
}

// Load every bundled @font-face up front. Otherwise a face loads lazily the
// first time a document needs it (a bold span, or a glyph the earlier fonts
// in the stack lack), and each arrival relayouts the whole editor overlay.
export function preloadBundledFonts() {
  try {
    for (const face of document.fonts) face.load().catch(() => {});
  } catch {
    /* no FontFaceSet (tests) */
  }
}
