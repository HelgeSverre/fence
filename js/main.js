import { Elm } from "../src/Main.elm";
import { wirePorts } from "./ports.js";
import { initMermaid } from "./mermaid-init.js";
import { applyFontFamily, applyFontSizesFromState } from "./font-settings.js";

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

applyFontFamily(initialState.font);
applyFontSizesFromState(initialState);

wirePorts(app);
initMermaid();
