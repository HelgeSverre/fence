import { setupEditorKeys } from "./editor-keys.js";
import { reRenderMermaid } from "./mermaid-init.js";
import { applyFontFamily, applyFontSizesFromState } from "./font-settings.js";

export function wirePorts(app) {
  if (!app.ports) return;

  // Elm → Electron
  if (app.ports.toElectron) {
    app.ports.toElectron.subscribe((data) => {
      // Handle theme changes locally (no IPC needed)
      if (data.tag === "setTheme") {
        if (data.theme) {
          document.documentElement.setAttribute("data-theme", data.theme);
        } else {
          document.documentElement.removeAttribute("data-theme");
        }
        reRenderMermaid();
        return;
      }

      // Handle font changes locally
      if (data.tag === "setFont") {
        applyFontFamily(data.font);
        return;
      }

      // Handle font size changes locally
      if (data.tag === "setFontSize") {
        applyFontSizesFromState(data);
        return;
      }

      if (window.electronAPI) {
        window.electronAPI.send(data);
      } else {
        console.warn("[ports] electronAPI not available, message:", data);
      }
    });
  }

  // Electron → Elm
  if (window.electronAPI && app.ports.fromElectron) {
    window.electronAPI.onMessage((data) => {
      app.ports.fromElectron.send(data);
    });
  }

  // Prevent browser default for Cmd+S
  document.addEventListener("keydown", (e) => {
    if ((e.metaKey || e.ctrlKey) && e.key === "s") {
      e.preventDefault();
    }
  });

  setupEditorKeys();
}
