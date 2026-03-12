const { app, BrowserWindow, ipcMain, dialog, shell, Menu } = require("electron");
const path = require("path");
const fs = require("fs");
const fsOps = require("./fs-ops");
const { autoUpdater } = require("electron-updater");

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
    show: false,
    title: "Fence",
    titleBarStyle: "hiddenInset",
    trafficLightPosition: { x: 12, y: 10 },
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      spellcheck: false,
    },
  });

  mainWindow.once("ready-to-show", () => {
    mainWindow.show();
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

  // Open external links in system browser
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url);
    return { action: "deny" };
  });

  mainWindow.webContents.on("will-navigate", (event, url) => {
    if (!url.startsWith("http://localhost:")) {
      event.preventDefault();
      shell.openExternal(url);
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

    case "setFontSize": {
      const state = loadState();
      const updates = {};
      if (data.editorFontSize) updates.editorFontSize = data.editorFontSize;
      if (data.previewFontSize) updates.previewFontSize = data.previewFontSize;
      if (data.uiFontSize) updates.uiFontSize = data.uiFontSize;
      saveState({ ...state, ...updates });
      break;
    }
  }
});

const gotLock = app.requestSingleInstanceLock();

if (!gotLock) {
  app.quit();
} else {
  app.on("second-instance", () => {
    if (mainWindow) {
      if (mainWindow.isMinimized()) mainWindow.restore();
      mainWindow.focus();
    }
  });

  app.whenReady().then(() => {
    app.setAboutPanelOptions({
      applicationName: "Fence",
      applicationVersion: app.getVersion(),
      copyright: "Copyright © 2026 Helge Sverre",
      website: "https://github.com/HelgeSverre/fence",
      iconPath: path.join(__dirname, "../build/icons/icon.png"),
    });

    const isMac = process.platform === "darwin";

    const template = [
      ...(isMac
        ? [
            {
              label: app.name,
              submenu: [
                { role: "about" },
                { type: "separator" },
                {
                  label: "Settings...",
                  accelerator: "Cmd+,",
                  click: () => sendToRenderer({ tag: "toggleSettings" }),
                },
                { type: "separator" },
                { role: "hide" },
                { role: "hideOthers" },
                { role: "unhide" },
                { type: "separator" },
                { role: "quit" },
              ],
            },
          ]
        : []),
      {
        label: "File",
        submenu: [
          {
            label: "Open Folder...",
            accelerator: "CmdOrCtrl+O",
            click: () => sendToRenderer({ tag: "triggerOpenFolder" }),
          },
          { type: "separator" },
          isMac ? { role: "close" } : { role: "quit" },
        ],
      },
      {
        label: "Edit",
        submenu: [
          { role: "undo" },
          { role: "redo" },
          { type: "separator" },
          { role: "cut" },
          { role: "copy" },
          { role: "paste" },
          { role: "selectAll" },
        ],
      },
      {
        label: "View",
        submenu: [
          { role: "resetZoom" },
          { role: "zoomIn" },
          { role: "zoomOut" },
          { type: "separator" },
          { role: "togglefullscreen" },
        ],
      },
      {
        label: "Window",
        submenu: [
          { role: "minimize" },
          { role: "zoom" },
          ...(isMac
            ? [{ type: "separator" }, { role: "front" }]
            : [{ role: "close" }]),
        ],
      },
    ];

    Menu.setApplicationMenu(Menu.buildFromTemplate(template));
    createWindow();

    // Check for updates in production (silent check, prompts on available update)
    if (app.isPackaged) {
      autoUpdater.checkForUpdatesAndNotify();
    }
  });

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
}
