import { setupPreviewFind } from "./preview-find.js";
import { setupLayout } from "./layout.js";
import { reRenderMermaid, finishMermaidRendering } from "./mermaid-init.js";
import { withoutFullscreenButtons } from "./mermaid-fullscreen.js";
import { applyPreferences, preloadFonts } from "./preferences.js";
import { setupEditorMetrics, remeasureEditorMetrics } from "./editor-metrics.js";
import { setupVirtualInput } from "./virtual-input.js";

export function wirePorts(app, initialState = {}) {
  if (!app.ports) return;
  const previewFind = setupPreviewFind(app);
  const layout = setupLayout(initialState);

  // Elm → Electron
  if (app.ports.toElectron) {
    app.ports.toElectron.subscribe((data) => {
      // Preference changes apply locally, then fall through to IPC so the
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
      if (data.tag === "setPreferences") {
        const themeChanged =
          (data.theme ?? "") !== (document.documentElement.getAttribute("data-theme") ?? "");
        applyPreferences(data);
        preloadFonts([data.editorFont, data.uiFont].filter(Boolean));
        remeasureEditorMetrics();
        if (themeChanged) reRenderMermaid();
      } else if (data.tag === "exportDocument") {
        exportPreview(data, app);
        return;
      }

      if (window.electronAPI) {
        const method = {
          openFolder: "openFolder",
          readDir: "readDir",
          readFile: "readFile",
          documentState: "documentState",
          saveSession: "saveSession",
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
          setPreferences: "setPreferences",
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
      if (data.tag === "navigateHeading") {
        navigatePreviewHeading(data);
      } else {
        app.ports.fromElectron.send(data);
      }
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
  document.addEventListener("click", event => {
    const link = event.target.closest?.(".preview-content a[href]");
    if (!link || event.button !== 0) return;
    const href = link.getAttribute("href");
    if (/^[a-z][a-z0-9+.-]*:/i.test(href) && !href.startsWith("file:")) return;
    if (href.startsWith("//")) return;
    event.preventDefault();
    const documentPath = link.closest(".preview-content").dataset.documentPath;
    if (documentPath) window.electronAPI?.openLink({ documentPath, href });
  });
}

// Export takes the preview exactly as rendered - mermaid diagrams included -
// plus the stylesheet text behind it, and lets the main process turn that into
// a PDF, an HTML file or rich text on the clipboard.
async function exportPreview(data, app) {
  // the rendered document itself, without the pane's own header
  await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
  const pane = document.querySelector(".preview-content");
  if (!pane || !window.electronAPI || pane.dataset.documentPath !== data.path) return;
  const documentPath = pane.dataset.documentPath;
  // Local images stay as fence-image:// URLs here; main inlines them.
  await finishMermaidRendering();
  if (!pane.isConnected || pane.dataset.documentPath !== documentPath) return;
  if (pane.closest(".preview-pane-wrap").dataset.renderGeneration !== String(data.generation)) {
    app.ports.fromElectron.send({ tag: "exportRequested", format: data.format });
    return;
  }
  window.electronAPI.exportDocument({
    format: data.format,
    title: data.title || "document",
    base: data.base || "",
    theme: document.documentElement.getAttribute("data-theme") || "",
    html: withoutFullscreenButtons(pane),
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

let headingObserver;
let headingTimeout;
function navigatePreviewHeading({ path, fragment }) {
  headingObserver?.disconnect();
  clearTimeout(headingTimeout);
  if (!fragment) return;
  const find = () => {
    const pane = document.querySelector(".preview-content");
    if (pane?.dataset.documentPath !== path) return false;
    const heading = [...pane.querySelectorAll("[id]")].find(el => el.id === fragment);
    if (!heading) return false;
    heading.scrollIntoView({ block: "start" });
    headingObserver?.disconnect();
    clearTimeout(headingTimeout);
    return true;
  };
  if (!find()) {
    headingObserver = new MutationObserver(find);
    headingObserver.observe(document.body, { subtree: true, childList: true, attributes: true, attributeFilter: ["data-document-path"] });
    headingTimeout = setTimeout(() => headingObserver.disconnect(), 5000);
  }
}
