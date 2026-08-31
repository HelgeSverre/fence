import { Elm } from "../src/Main.elm";
import { wirePorts } from "./ports.js";
import { initMermaid } from "./mermaid-init.js";
import { applyFontFamily, applyFontSizesFromState } from "./font-settings.js";

const initialState = window.electronAPI?.getInitialState?.() ?? {};

// "" is a valid theme value (Catppuccin Mocha, the no-attribute default).
const theme = initialState.theme ?? "github-dark";
if (theme) {
  document.documentElement.setAttribute("data-theme", theme);
}

const app = Elm.Main.init({
  node: document.getElementById("app"),
  flags: {
    windowWidth: window.innerWidth,
    theme: theme,
    sidebarFraction: initialState.sidebarFraction ?? null,
    editorFraction: initialState.editorFraction ?? null,
    font: initialState.font ?? "",
    editorFontSize: initialState.editorFontSize ?? null,
    previewFontSize: initialState.previewFontSize ?? null,
    uiFontSize: initialState.uiFontSize ?? null,
    rightSidebarFraction: initialState.rightSidebarFraction ?? null,
    leftSidebarVisible: initialState.leftSidebarVisible ?? null,
    rightSidebarVisible: initialState.rightSidebarVisible ?? null,
    outlineMaxLevel: initialState.outlineMaxLevel ?? null,
    leftToggleKey: initialState.leftToggleKey ?? null,
    rightToggleKey: initialState.rightToggleKey ?? null,
  },
});

applyFontFamily(initialState.font);
applyFontSizesFromState(initialState);

wirePorts(app);
initMermaid();
