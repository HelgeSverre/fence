const { contextBridge, ipcRenderer, webUtils } = require("electron");

const send = (channel) => (payload = {}) => ipcRenderer.send(channel, payload);

contextBridge.exposeInMainWorld("electronAPI", {
  getInitialState: () => ipcRenderer.sendSync("fence:get-initial-state"),
  openFolder: send("fence:open-folder"),
  readDir: send("fence:read-dir"),
  readFile: send("fence:read-file"),
  writeFile: send("fence:write-file"),
  watchDir: send("fence:watch-dir"),
  unwatchDir: send("fence:unwatch-dir"),
  showTreeContextMenu: send("fence:tree-context-menu"),
  createFile: send("fence:create-file"),
  createDir: send("fence:create-dir"),
  renamePath: send("fence:rename-path"),
  trashPath: send("fence:trash-path"),
  revealPath: send("fence:reveal-path"),
  listFiles: send("fence:list-files"),
  searchWorkspace: send("fence:search-workspace"),
  exportDocument: send("fence:export"),
  saveAttachment: send("fence:save-attachment"),
  openPath: send("fence:open-path"),
  // Electron no longer exposes File.path; this is the supported replacement.
  pathForFile: (file) => webUtils.getPathForFile(file),
  setTitle: send("fence:set-title"),
  setDirty: send("fence:set-dirty"),
  closeWindow: send("fence:close-window"),
  saveSplits: send("fence:save-splits"),
  setTheme: send("fence:set-theme"),
  setFont: send("fence:set-font"),
  setFontSize: send("fence:set-font-size"),
  setSoftWrap: send("fence:set-soft-wrap"),
  saveRecoveryDraft: send("fence:save-recovery-draft"),
  onMessage: (callback) => {
    const listener = (_event, data) => callback(data);
    ipcRenderer.on("fromElm", listener);
    return () => ipcRenderer.removeListener("fromElm", listener);
  },
});
