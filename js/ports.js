import { setupEditorKeys } from "./editor-keys.js";
import { reRenderMermaid } from "./mermaid-init.js";
import { applyFontFamily, applyFontSizesFromState } from "./font-settings.js";
import { setupEditorMetrics, remeasureEditorMetrics } from "./editor-metrics.js";
import { setupVirtualInput } from "./virtual-input.js";

export function wirePorts(app) {
  if (!app.ports) return;

  // Elm → Electron
  if (app.ports.toElectron) {
    app.ports.toElectron.subscribe((data) => {
      // Theme/font changes apply locally, then fall through to IPC so the
      // main process persists them to state.json.
      if (data.tag === "setTheme") {
        if (data.theme) {
          document.documentElement.setAttribute("data-theme", data.theme);
        } else {
          document.documentElement.removeAttribute("data-theme");
        }
        reRenderMermaid();
      } else if (data.tag === "setFont") {
        applyFontFamily(data.font);
        remeasureEditorMetrics();
      } else if (data.tag === "setFontSize") {
        applyFontSizesFromState(data);
        remeasureEditorMetrics();
      }

      if (window.electronAPI) {
        const method = {
          openFolder: "openFolder",
          readDir: "readDir",
          readFile: "readFile",
          writeFile: "writeFile",
          watchDir: "watchDir",
          unwatchDir: "unwatchDir",
          treeContextMenu: "showTreeContextMenu",
          setTitle: "setTitle",
          setDirty: "setDirty",
          closeWindow: "closeWindow",
          saveSplits: "saveSplits",
          setTheme: "setTheme",
          setFont: "setFont",
          setFontSize: "setFontSize",
          saveRecoveryDraft: "saveRecoveryDraft",
        }[data.tag];
        if (method && typeof window.electronAPI[method] === "function") {
          window.electronAPI[method](data);
        } else {
          console.warn("[ports] unknown Electron command:", data.tag);
        }
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

  // Right-click on a file-tree item -> native context menu in main process
  document.addEventListener("contextmenu", (e) => {
    const item = e.target.closest(".file-tree-item[data-path]");
    if (!item || !window.electronAPI) return;
    e.preventDefault();
    window.electronAPI.showTreeContextMenu({ path: item.dataset.path });
  });

  setupEditorKeys();
  setupEditorMetrics(app);
  setupVirtualInput();
}
