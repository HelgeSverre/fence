const { app, BrowserWindow, ipcMain, dialog, shell, Menu } = require("electron");
const path = require("path");
const fs = require("fs");
const fsOps = require("./fs-ops");
const { autoUpdater } = require("electron-updater");

const MAX_RECENT_WORKSPACES = 20;

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

// Load → mutate → save the persisted state file. Use for any IPC handler
// that needs to update one or more fields without dropping the others.
function updateState(updater) {
  const state = loadState();
  const updates = updater(state) || {};
  saveState({ ...state, ...updates });
}

let mainWindow;

// Open a folder as the active workspace: point fs-ops at it, push the
// listing to the renderer, and record it in the recents list.
function openWorkspace(folderPath) {
  try {
    fsOps.setWorkspace(folderPath);
    const entries = fsOps.readDir(folderPath);
    sendToRenderer({ tag: "folderOpened", path: folderPath, entries });
    updateState((state) => {
      const recents = (state.recentWorkspaces || []).filter(
        (p) => p !== folderPath,
      );
      recents.unshift(folderPath);
      return {
        lastWorkspace: folderPath,
        recentWorkspaces: recents.slice(0, MAX_RECENT_WORKSPACES),
      };
    });
    buildMenu();
  } catch (err) {
    sendToRenderer({ tag: "error", message: err.message });
  }
}

// (Re)build the application menu. Called again whenever the recent
// workspaces list changes so File > Open Recent stays current.
function buildMenu() {
  const isMac = process.platform === "darwin";
  const recents = loadState().recentWorkspaces || [];

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
        {
          label: "Open Recent",
          submenu:
            recents.length > 0
              ? recents.map((p) => ({
                  label: p,
                  click: () => openWorkspace(p),
                }))
              : [{ label: "No Recent Workspaces", enabled: false }],
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
}

// First existing path in a CLI argv (e.g. `fence README.md`, `fence ~/notes`),
// resolved against the invoking shell's working directory. Null if none.
function cliPathFrom(argv, cwd) {
  for (const arg of argv.slice(app.isPackaged ? 1 : 2)) {
    if (arg.startsWith("-")) continue;
    const resolved = path.resolve(cwd, arg);
    if (fs.existsSync(resolved)) return resolved;
  }
  return null;
}

// Open a CLI path: a folder becomes the workspace; a file opens its parent
// folder as the workspace and loads the file into the editor.
function openCliPath(cliPath) {
  const isDir = fs.statSync(cliPath).isDirectory();
  openWorkspace(isDir ? cliPath : path.dirname(cliPath));
  if (!isDir) {
    try {
      sendToRenderer({
        tag: "fileContent",
        path: cliPath,
        content: fsOps.readFile(cliPath),
      });
    } catch (err) {
      sendToRenderer({ tag: "error", message: err.message });
    }
  }
}

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

  if (process.env.VITE_DEV_SERVER_URL) {
    mainWindow.loadURL(process.env.VITE_DEV_SERVER_URL);
    if (process.env.DEVTOOLS) {
      mainWindow.webContents.openDevTools({ mode: "detach" });
    }
  } else {
    mainWindow.loadFile(path.join(__dirname, "../dist/index.html"));
  }

  // Open the CLI-supplied path, or restore the last workspace
  mainWindow.webContents.on("did-finish-load", () => {
    const cliPath = cliPathFrom(process.argv, process.cwd());
    if (cliPath) {
      openCliPath(cliPath);
      return;
    }
    const state = loadState();
    if (state.lastWorkspace) {
      try {
        fsOps.setWorkspace(state.lastWorkspace);
        const entries = fsOps.readDir(state.lastWorkspace);
        sendToRenderer({
          tag: "folderOpened",
          path: state.lastWorkspace,
          entries,
        });
      } catch {
        // Workspace vanished — forget it, but keep every other setting.
        fsOps.setWorkspace(null);
        updateState(() => ({ lastWorkspace: null }));
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
            openWorkspace(result.filePaths[0]);
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
      try {
        fsOps.watchDir(data.path, (event, filePath) => {
          sendToRenderer({
            tag: "fsEvent",
            event,
            path: filePath,
          });
        });
      } catch (err) {
        sendToRenderer({ tag: "error", message: err.message });
      }
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
      updateState(() => ({
        sidebarFraction: data.sidebarFraction,
        editorFraction: data.editorFraction,
        rightSidebarFraction: data.rightSidebarFraction,
        leftSidebarVisible: data.leftSidebarVisible,
        rightSidebarVisible: data.rightSidebarVisible,
        outlineMaxLevel: data.outlineMaxLevel,
        leftToggleKey: data.leftToggleKey,
        rightToggleKey: data.rightToggleKey,
      }));
      break;
    }

    case "setTheme": {
      updateState(() => ({ theme: data.theme }));
      break;
    }

    case "setFont": {
      updateState(() => ({ font: data.font }));
      break;
    }

    case "setFontSize": {
      updateState(() => {
        const updates = {};
        if (data.editorFontSize) updates.editorFontSize = data.editorFontSize;
        if (data.previewFontSize) updates.previewFontSize = data.previewFontSize;
        if (data.uiFontSize) updates.uiFontSize = data.uiFontSize;
        return updates;
      });
      break;
    }
  }
});

const gotLock = app.requestSingleInstanceLock();

if (!gotLock) {
  app.quit();
} else {
  // `fence <path>` while the app is running: the new process forwards its
  // argv here and exits; open the path in the existing window.
  app.on("second-instance", (_event, argv, workingDirectory) => {
    if (mainWindow) {
      if (mainWindow.isMinimized()) mainWindow.restore();
      mainWindow.focus();
    }
    const cliPath = cliPathFrom(argv, workingDirectory);
    if (cliPath) openCliPath(cliPath);
  });

  app.whenReady().then(() => {
    app.setAboutPanelOptions({
      applicationName: "Fence",
      applicationVersion: app.getVersion(),
      copyright: "Copyright © 2026 Helge Sverre",
      website: "https://github.com/HelgeSverre/fence",
      iconPath: path.join(__dirname, "../build/icons/icon.png"),
    });

    buildMenu();
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
