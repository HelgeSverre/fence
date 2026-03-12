import { Elm } from "../src/Main.elm";
import { wirePorts } from "./ports.js";
import { initMermaid } from "./mermaid-init.js";

document.documentElement.setAttribute("data-theme", "github-dark");

const initialState = window.electronAPI?.getInitialState?.() ?? {};

const app = Elm.Main.init({
  node: document.getElementById("app"),
  flags: {
    windowWidth: window.innerWidth,
    sidebarFraction: initialState.sidebarFraction ?? null,
    editorFraction: initialState.editorFraction ?? null,
    font: initialState.font ?? "",
    editorFontSize: initialState.editorFontSize ?? null,
    previewFontSize: initialState.previewFontSize ?? null,
    uiFontSize: initialState.uiFontSize ?? null,
  },
});

// Apply persisted font on startup
if (initialState.font) {
  document.documentElement.style.setProperty("--font-mono", `"${initialState.font}", monospace`);
}
if (initialState.editorFontSize) {
  document.documentElement.style.setProperty("--font-size-editor", initialState.editorFontSize + "px");
}
if (initialState.previewFontSize) {
  document.documentElement.style.setProperty("--font-size-preview", initialState.previewFontSize + "px");
}
if (initialState.uiFontSize) {
  document.documentElement.style.setProperty("--font-size-ui", initialState.uiFontSize + "px");
}

wirePorts(app);
initMermaid();
