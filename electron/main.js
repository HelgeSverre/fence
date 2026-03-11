const { app, BrowserWindow, ipcMain, dialog } = require("electron");
const path = require("path");
const fs = require("fs");
const fsOps = require("./fs-ops");

function getStatePath() {
  return path.join(app.getPath("userData"), "state.json");
}

function loadState() {
  try {
    return JSON.parse(fs.readFileSync(getStatePath(), "utf-8"));
  } catch {
    return {};
  }
}

function saveState(state) {
  try {
    fs.writeFileSync(getStatePath(), JSON.stringify(state));
  } catch {
    /* ignore */
  }
}

let mainWindow;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1400,
    height: 900,
    title: "Fence",
    titleBarStyle: "hiddenInset",
    trafficLightPosition: { x: 12, y: 10 },
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  const isDev = !app.isPackaged;
  if (isDev) {
    mainWindow.loadURL("http://localhost:5173");
    if (process.env.DEVTOOLS) {
      mainWindow.webContents.openDevTools({ mode: "detach" });
    }
  } else {
    mainWindow.loadFile(path.join(__dirname, "../dist/index.html"));
  }

  // Restore last workspace on launch
  mainWindow.webContents.on("did-finish-load", () => {
    const state = loadState();
    if (state.lastWorkspace) {
      try {
        const entries = fsOps.readDir(state.lastWorkspace);
        sendToRenderer({
          tag: "folderOpened",
          path: state.lastWorkspace,
          entries,
        });
      } catch {
        saveState({});
      }
    }
  });

  // Prevent close if dirty — Elm sends setDirty state
  mainWindow.on("close", (e) => {
    if (mainWindow._isDirty) {
      e.preventDefault();
      dialog
        .showMessageBox(mainWindow, {
          type: "warning",
          buttons: ["Save", "Don't Save", "Cancel"],
          defaultId: 0,
          cancelId: 2,
          title: "Unsaved Changes",
          message: "You have unsaved changes. What would you like to do?",
        })
        .then(({ response }) => {
          if (response === 0) {
            // Save — tell Elm to save, then close
            sendToRenderer({ tag: "saveAndClose" });
          } else if (response === 1) {
            // Don't save — force close
            mainWindow._isDirty = false;
            mainWindow.close();
          }
          // Cancel — do nothing
        });
    }
  });
}

function sendToRenderer(data) {
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send("fromElm", data);
  }
}

ipcMain.on("getInitialState", (event) => {
  event.returnValue = loadState();
});

ipcMain.on("toElm", (_event, data) => {
  const { tag } = data;

  switch (tag) {
    case "openFolder": {
      dialog
        .showOpenDialog(mainWindow, {
          properties: ["openDirectory"],
        })
        .then((result) => {
          if (!result.canceled && result.filePaths.length > 0) {
            const folderPath = result.filePaths[0];
            try {
              const entries = fsOps.readDir(folderPath);
              sendToRenderer({
                tag: "folderOpened",
                path: folderPath,
                entries,
              });
              const state = loadState();
              const recents = (state.recentWorkspaces || []).filter(p => p !== folderPath);
              recents.unshift(folderPath);
              saveState({
                ...state,
                lastWorkspace: folderPath,
                recentWorkspaces: recents.slice(0, 20),
              });
            } catch (err) {
              sendToRenderer({
                tag: "error",
                message: err.message,
              });
            }
          }
        });
      break;
    }

    case "readDir": {
      try {
        const entries = fsOps.readDir(data.path);
        sendToRenderer({
          tag: "dirContents",
          path: data.path,
          entries,
        });
      } catch (err) {
        sendToRenderer({ tag: "error", message: err.message });
      }
      break;
    }

    case "readFile": {
      try {
        const content = fsOps.readFile(data.path);
        sendToRenderer({
          tag: "fileContent",
          path: data.path,
          content,
        });
      } catch (err) {
        sendToRenderer({ tag: "error", message: err.message });
      }
      break;
    }

    case "writeFile": {
      try {
        fsOps.writeFile(data.path, data.content);
        sendToRenderer({
          tag: "fileSaved",
          path: data.path,
        });
      } catch (err) {
        sendToRenderer({ tag: "error", message: err.message });
      }
      break;
    }

    case "watchDir": {
      fsOps.watchDir(data.path, (event, filePath) => {
        sendToRenderer({
          tag: "fsEvent",
          event,
          path: filePath,
        });
      });
      break;
    }

    case "unwatchDir": {
      fsOps.unwatchDir(data.path);
      break;
    }

    case "setTitle": {
      if (mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.setTitle(data.title);
      }
      break;
    }

    case "setDirty": {
      if (mainWindow) {
        mainWindow._isDirty = data.dirty;
      }
      break;
    }

    case "closeWindow": {
      if (mainWindow) {
        mainWindow._isDirty = false;
        mainWindow.close();
      }
      break;
    }

    case "saveSplits": {
      const state = loadState();
      saveState({
        ...state,
        sidebarFraction: data.sidebarFraction,
        editorFraction: data.editorFraction,
      });
      break;
    }

    case "setFont": {
      const state = loadState();
      saveState({ ...state, font: data.font });
      break;
    }
  }
});

app.whenReady().then(createWindow);

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});

app.on("activate", () => {
  if (BrowserWindow.getAllWindows().length === 0) {
    createWindow();
  }
});
