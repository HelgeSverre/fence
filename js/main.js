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
  },
});

wirePorts(app);
