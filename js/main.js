import { Elm } from "../src/Main.elm";
import { wirePorts } from "./ports.js";

document.documentElement.setAttribute("data-theme", "github-dark");

const initialState = window.electronAPI?.getInitialState?.() ?? {};

const app = Elm.Main.init({
  node: document.getElementById("app"),
  flags: {
    windowWidth: window.innerWidth,
    sidebarFraction: initialState.sidebarFraction ?? null,
    editorFraction: initialState.editorFraction ?? null,
    font: initialState.font ?? "",
  },
});

// Apply persisted font on startup
if (initialState.font) {
  document.documentElement.style.setProperty("--font-mono", `"${initialState.font}", monospace`);
}

wirePorts(app);
