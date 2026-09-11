// Applies persisted preferences as CSS custom properties on <html>. Shared
// between init (js/main.js) and the runtime port handler (js/ports.js) so the
// two stay in sync.

const root = document.documentElement;
const SANS_FALLBACK = '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif';
const setVar = (name, value) => (value ? root.style.setProperty(name, value) : root.style.removeProperty(name));

export function applyPreferences(p) {
  if (p.theme) root.setAttribute("data-theme", p.theme);
  else root.removeAttribute("data-theme");
  setVar("--font-mono", p.editorFont && `"${p.editorFont}", monospace`);
  setVar("--font-sans", p.uiFont && `"${p.uiFont}", ${SANS_FALLBACK}`);
  setVar("--font-size-editor", p.editorFontSize && p.editorFontSize + "px");
  setVar("--font-size-preview", p.previewFontSize && p.previewFontSize + "px");
  setVar("--font-size-ui", p.uiFontSize && p.uiFontSize + "px");
}

// Load only the faces in use; the bundle ships ~60 faces and eagerly loading
// all of them costs startup time.
export function preloadFonts(families) {
  try {
    for (const face of document.fonts) {
      if (families.includes(face.family.replace(/^"|"$/g, ""))) face.load().catch(() => {});
    }
  } catch {
    /* no FontFaceSet (tests) */
  }
}
