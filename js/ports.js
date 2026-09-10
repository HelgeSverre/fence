import { setupPreviewFind } from "./preview-find.js";
import { setupLayout } from "./layout.js";
import { reRenderMermaid } from "./mermaid-init.js";
import { applyFontFamily, applyFontSizesFromState } from "./font-settings.js";
import { setupEditorMetrics, remeasureEditorMetrics } from "./editor-metrics.js";
import { setupVirtualInput } from "./virtual-input.js";

export function wirePorts(app, initialState = {}) {
  if (!app.ports) return;
  const previewFind = setupPreviewFind(app);
  const layout = setupLayout(initialState);

  // Elm → Electron
  if (app.ports.toElectron) {
    app.ports.toElectron.subscribe((data) => {
      // Theme/font changes apply locally, then fall through to IPC so the
      // main process persists them to state.json.
      if (data.tag === "previewFind") {
        previewFind(data);
        return;
      } else if (data.tag === "layoutChanged") {
        layout.changed(data);
        return;
      } else if (data.tag === "saveSplits" && data.layoutCycleKey) {
        layout.setBinding(data.layoutCycleKey);
      }
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
      } else if (data.tag === "exportDocument") {
        exportPreview(data);
        return;
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
          createFile: "createFile",
          createDir: "createDir",
          renamePath: "renamePath",
          trashPath: "trashPath",
          revealPath: "revealPath",
          listFiles: "listFiles",
          searchWorkspace: "searchWorkspace",
          setTitle: "setTitle",
          setDirty: "setDirty",
          closeWindow: "closeWindow",
          saveSplits: "saveSplits",
          setTheme: "setTheme",
          setFont: "setFont",
          setFontSize: "setFontSize",
          setSoftWrap: "setSoftWrap",
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

  setupEditorMetrics(app);
  setupVirtualInput();
  setupFileDrop();
}

// Export takes the preview exactly as rendered - mermaid diagrams included -
// plus the stylesheet text behind it, and lets the main process turn that into
// a PDF, an HTML file or rich text on the clipboard.
function exportPreview(data) {
  // the rendered document itself, without the pane's own header
  const pane = document.querySelector(".preview-content");
  if (!pane || !window.electronAPI) return;
  window.electronAPI.exportDocument({
    format: data.format,
    title: data.title || "document",
    base: data.base || "",
    theme: document.documentElement.getAttribute("data-theme") || "",
    html: pane.innerHTML,
    text: pane.textContent || "",
    css: collectStyles(),
  });
}

// Every same-origin rule on the page. Cross-origin sheets throw on access and
// are skipped; nothing the app ships is loaded that way.
function collectStyles() {
  return [...document.styleSheets]
    .map((sheet) => {
      try {
        return [...sheet.cssRules].map((rule) => rule.cssText).join("\n");
      } catch {
        return "";
      }
    })
    .join("\n");
}

// Dropping a folder opens it as the workspace; dropping a markdown file opens
// the file (and its folder, when it is outside the current workspace).
function setupFileDrop() {
  const stop = (e) => {
    e.preventDefault();
    e.stopPropagation();
  };
  document.addEventListener("dragover", stop);
  document.addEventListener("drop", (e) => {
    stop(e);
    const file = e.dataTransfer?.files?.[0];
    if (!file || !window.electronAPI) return;
    const path = window.electronAPI.pathForFile(file);
    if (path) window.electronAPI.openPath({ path });
  });
}
