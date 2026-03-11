const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("electronAPI", {
  send: (data) => ipcRenderer.send("toElm", data),
  onMessage: (callback) => ipcRenderer.on("fromElm", (_event, data) => callback(data)),
  getInitialState: () => ipcRenderer.sendSync("getInitialState"),
});
