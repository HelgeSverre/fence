import { Elm } from "../src/Main.elm";
import { wirePorts } from "./ports.js";
import { initPreviewImages } from "./preview-images.js";
import { initMermaid } from "./mermaid-init.js";
import { applyPreferences, preloadFonts } from "./preferences.js";

const initialState = window.electronAPI?.getInitialState?.() ?? {};

// The only default duplicated from Preferences.default in Elm: the theme must
// be set before first paint and Elm sends nothing on init.
applyPreferences({ theme: "github-dark", ...initialState });

const app = Elm.Main.init({
  node: document.getElementById("app"),
  // Elm decodes tolerantly; a legacy `font` key is handled by its decoder.
  flags: { windowWidth: window.innerWidth, ...initialState },
});

preloadFonts([initialState.editorFont, initialState.uiFont].filter(Boolean));

wirePorts(app, initialState);
initMermaid();
initPreviewImages();
