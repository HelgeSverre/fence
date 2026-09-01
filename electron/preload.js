const { contextBridge, ipcRenderer } = require("electron");

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
  setTitle: send("fence:set-title"),
  setDirty: send("fence:set-dirty"),
  closeWindow: send("fence:close-window"),
  saveSplits: send("fence:save-splits"),
  setTheme: send("fence:set-theme"),
  setFont: send("fence:set-font"),
  setFontSize: send("fence:set-font-size"),
  saveRecoveryDraft: send("fence:save-recovery-draft"),
  onMessage: (callback) => {
    const listener = (_event, data) => callback(data);
    ipcRenderer.on("fromElm", listener);
    return () => ipcRenderer.removeListener("fromElm", listener);
  },
});
