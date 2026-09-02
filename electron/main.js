const { app, BrowserWindow, ipcMain, dialog, shell, Menu, clipboard } = require("electron");
const path = require("path");
const fs = require("fs");
const crypto = require("node:crypto");
const { pathToFileURL } = require("node:url");
const fsOps = require("./fs-ops");
const { autoUpdater } = require("electron-updater");

// Tests point this at a temp dir so they never touch the real state.json,
// recovery drafts or single-instance lock. Must run before the lock below.
if (process.env.FENCE_USER_DATA) {
  app.setPath("userData", process.env.FENCE_USER_DATA);
}

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
    // Write-then-rename so a crash mid-write can't leave a truncated state.json.
    const statePath = getStatePath();
    fs.writeFileSync(`${statePath}.tmp`, JSON.stringify(state));
    fs.renameSync(`${statePath}.tmp`, statePath);
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

function recoveryPathFor(filePath) {
  const key = crypto.createHash("sha256").update(filePath).digest("hex");
  return path.join(app.getPath("userData"), "recovery", `${key}.json`);
}

async function saveRecoveryDraft(payload) {
  const filePath = requireString(payload, "path", 32768);
  const content = requireString(payload, "content");
  const revision = payload.revision;
  const canonical = await fsOps.resolvePath(filePath);
  const destination = recoveryPathFor(canonical);
  const temp = `${destination}.${process.pid}.tmp`;
  await fs.promises.mkdir(path.dirname(destination), { recursive: true });
  await fs.promises.writeFile(
    temp,
    JSON.stringify({
      path: canonical,
      content,
      revision: typeof revision === "string" ? revision : null,
      savedAt: new Date().toISOString(),
    }),
    "utf-8",
  );
  await fs.promises.rename(temp, destination);
}

async function clearRecoveryDraft(filePath) {
  await fs.promises.unlink(recoveryPathFor(filePath)).catch((error) => {
    if (error.code !== "ENOENT") throw error;
  });
}

async function loadRecoveryDraft(filePath) {
  try {
    return JSON.parse(
      await fs.promises.readFile(recoveryPathFor(filePath), "utf-8"),
    );
  } catch {
    return null;
  }
}

let mainWindow;
let pendingOpenPath = null; // open-file path received before the renderer loaded
let rendererReady = false;

// Open a folder as the active workspace: point fs-ops at it, push the
// listing to the renderer, and record it in the recents list.
async function openWorkspace(folderPath) {
  try {
    await fsOps.setWorkspace(folderPath);
    const entries = await fsOps.readDir(folderPath);
    const canonicalPath = entries.length > 0
      ? path.dirname(entries[0].path)
      : await fs.promises.realpath(folderPath);
    sendToRenderer({ tag: "folderOpened", path: canonicalPath, entries });
    updateState((state) => {
      const recents = (state.recentWorkspaces || []).filter(
        (p) => p !== canonicalPath,
      );
      recents.unshift(canonicalPath);
      return {
        lastWorkspace: canonicalPath,
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
async function openCliPath(cliPath) {
  const isDir = fs.statSync(cliPath).isDirectory();
  await openWorkspace(isDir ? cliPath : path.dirname(cliPath));
  if (!isDir) {
    try {
      await sendFileContent(cliPath);
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
      sandbox: true,
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

  // Open the Finder/CLI-supplied path, or restore the last workspace
  mainWindow.webContents.on("did-finish-load", async () => {
    rendererReady = true;
    const cliPath = pendingOpenPath || cliPathFrom(process.argv, process.cwd());
    pendingOpenPath = null;
    if (cliPath) {
      await openCliPath(cliPath);
      return;
    }
    const state = loadState();
    if (state.lastWorkspace) {
      try {
        await fsOps.setWorkspace(state.lastWorkspace);
        const entries = await fsOps.readDir(state.lastWorkspace);
        sendToRenderer({
          tag: "folderOpened",
          path: state.lastWorkspace,
          entries,
        });
      } catch {
        // Workspace vanished — forget it, but keep every other setting.
        await fsOps.setWorkspace(null);
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
    openExternalIfSafe(url);
    return { action: "deny" };
  });

  mainWindow.webContents.on("will-navigate", (event, url) => {
    if (isAppUrl(url)) return;
    event.preventDefault();
    openExternalIfSafe(url);
  });
}

function isAppUrl(candidate) {
  try {
    const url = new URL(candidate);
    if (process.env.VITE_DEV_SERVER_URL) {
      return url.origin === new URL(process.env.VITE_DEV_SERVER_URL).origin;
    }
    const appUrl = pathToFileURL(path.join(__dirname, "../dist/index.html"));
    return url.protocol === "file:" && url.pathname === appUrl.pathname;
  } catch {
    return false;
  }
}

function openExternalIfSafe(candidate) {
  try {
    const url = new URL(candidate);
    if (url.protocol === "https:" || url.protocol === "mailto:") {
      void shell.openExternal(url.toString()).catch(() => {});
    }
  } catch {
    // Invalid or relative external URLs are intentionally ignored.
  }
}

function sendToRenderer(data) {
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send("fromElm", data);
  }
}

function isTrustedIpcEvent(event) {
  return Boolean(
    mainWindow &&
      !mainWindow.isDestroyed() &&
      event.sender === mainWindow.webContents &&
      event.senderFrame === mainWindow.webContents.mainFrame,
  );
}

function requireString(payload, key, maxLength = 100 * 1024 * 1024) {
  const value = payload?.[key];
  if (typeof value !== "string" || value.length > maxLength) {
    throw new TypeError(`Invalid ${key}`);
  }
  return value;
}

function registerIpc(channel, handler) {
  ipcMain.on(channel, (event, payload = {}) => {
    if (!isTrustedIpcEvent(event)) return;
    Promise.resolve(handler(payload)).catch((error) => {
      sendToRenderer({ tag: "error", message: error.message });
    });
  });
}

async function sendFileContent(filePath, offerRecovery = true) {
  const file = await fsOps.readFile(filePath);
  let content = file.content;
  let dirty = false;
  const draft = offerRecovery ? await loadRecoveryDraft(file.path) : null;

  if (draft && typeof draft.content === "string" && draft.content !== content) {
    const { response } = await dialog.showMessageBox(mainWindow, {
      type: "question",
      buttons: ["Restore Draft", "Discard Draft"],
      defaultId: 0,
      cancelId: 1,
      title: "Recover Unsaved Changes",
      message: `Fence found unsaved changes for ${path.basename(file.path)}.`,
      detail:
        "Restore the recovery draft or discard it and open the file from disk.",
    });
    if (response === 0) {
      content = draft.content;
      dirty = true;
    } else {
      await clearRecoveryDraft(file.path);
    }
  } else if (draft) {
    await clearRecoveryDraft(file.path);
  }

  sendToRenderer({ tag: "fileContent", ...file, content, dirty });
}

async function saveDocument(payload) {
  const filePath = requireString(payload, "path", 32768);
  const content = requireString(payload, "content");
  const expectedRevision =
    typeof payload.expectedRevision === "string"
      ? payload.expectedRevision
      : null;

  try {
    const saved = await fsOps.writeFile(filePath, content, expectedRevision);
    await clearRecoveryDraft(saved.path);
    sendToRenderer({ tag: "fileSaved", ...saved });
  } catch (error) {
    if (!(error instanceof fsOps.FileConflictError)) throw error;
    const { response } = await dialog.showMessageBox(mainWindow, {
      type: "warning",
      buttons: ["Overwrite", "Reload from Disk", "Cancel"],
      defaultId: 2,
      cancelId: 2,
      title: "File Changed on Disk",
      message: `${path.basename(filePath)} changed outside Fence.`,
      detail:
        "Overwrite the external changes, reload the disk version, or cancel and keep editing your draft.",
    });
    if (response === 0) {
      const saved = await fsOps.writeFile(filePath, content, null);
      await clearRecoveryDraft(saved.path);
      sendToRenderer({ tag: "fileSaved", ...saved });
    } else if (response === 1) {
      await clearRecoveryDraft(filePath);
      await sendFileContent(filePath, false);
    } else {
      sendToRenderer({ tag: "saveCancelled" });
    }
  }
}

ipcMain.on("fence:get-initial-state", (event) => {
  event.returnValue = isTrustedIpcEvent(event) ? loadState() : {};
});

registerIpc("fence:open-folder", async () => {
  const result = await dialog.showOpenDialog(mainWindow, {
    properties: ["openDirectory"],
  });
  if (!result.canceled && result.filePaths.length > 0) {
    await openWorkspace(result.filePaths[0]);
  }
});

registerIpc("fence:read-dir", async (data) => {
  const dirPath = requireString(data, "path", 32768);
  const entries = await fsOps.readDir(dirPath);
  sendToRenderer({ tag: "dirContents", path: dirPath, entries });
});

registerIpc("fence:read-file", async (data) => {
  await sendFileContent(requireString(data, "path", 32768));
});

registerIpc("fence:write-file", saveDocument);

registerIpc("fence:watch-dir", async (data) => {
  await fsOps.watchDir(
    requireString(data, "path", 32768),
    (event, filePath) => sendToRenderer({ tag: "fsEvent", event, path: filePath }),
  );
});

registerIpc("fence:unwatch-dir", async (data) => {
  await fsOps.unwatchDir(requireString(data, "path", 32768));
});

registerIpc("fence:tree-context-menu", async (data) => {
  const filePath = await fsOps.resolvePath(requireString(data, "path", 32768));
  Menu.buildFromTemplate([
    { label: "Copy Path", click: () => clipboard.writeText(filePath) },
  ]).popup({ window: mainWindow });
});

registerIpc("fence:set-title", (data) => {
  mainWindow.setTitle(requireString(data, "title", 512));
});

registerIpc("fence:set-dirty", (data) => {
  if (typeof data.dirty !== "boolean") throw new TypeError("Invalid dirty state");
  mainWindow._isDirty = data.dirty;
});

registerIpc("fence:close-window", () => {
  mainWindow._isDirty = false;
  mainWindow.close();
});

registerIpc("fence:save-splits", (data) => {
  const updates = {};
  for (const key of [
    "sidebarFraction",
    "editorFraction",
    "rightSidebarFraction",
  ]) {
    if (typeof data[key] === "number" && data[key] >= 0 && data[key] <= 1) {
      updates[key] = data[key];
    }
  }
  for (const key of ["leftSidebarVisible", "rightSidebarVisible"]) {
    if (typeof data[key] === "boolean") updates[key] = data[key];
  }
  if (
    Number.isInteger(data.outlineMaxLevel) &&
    data.outlineMaxLevel >= 1 &&
    data.outlineMaxLevel <= 6
  ) {
    updates.outlineMaxLevel = data.outlineMaxLevel;
  }
  for (const key of ["leftToggleKey", "rightToggleKey"]) {
    const binding = data[key];
    if (
      binding &&
      typeof binding.key === "string" &&
      binding.key.length <= 32 &&
      ["meta", "ctrl", "shift", "alt"].every(
        (modifier) => typeof binding[modifier] === "boolean",
      )
    ) {
      updates[key] = binding;
    }
  }
  updateState(() => updates);
});

registerIpc("fence:set-theme", (data) => {
  updateState(() => ({ theme: requireString(data, "theme", 128) }));
});

registerIpc("fence:set-font", (data) => {
  updateState(() => ({ font: requireString(data, "font", 256) }));
});

registerIpc("fence:set-font-size", (data) => {
  updateState(() => {
    const updates = {};
    for (const key of ["editorFontSize", "previewFontSize", "uiFontSize"]) {
      if (typeof data[key] === "number" && Number.isFinite(data[key])) {
        updates[key] = Math.min(32, Math.max(8, data[key]));
      }
    }
    return updates;
  });
});

registerIpc("fence:save-recovery-draft", saveRecoveryDraft);

const gotLock = app.requestSingleInstanceLock();

// macOS delivers Finder double-clicks and "Open With" via open-file, not
// argv; it can fire before the window exists, so hold the path until then.
app.on("open-file", (event, filePath) => {
  event.preventDefault();
  if (rendererReady && mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.focus();
    openCliPath(filePath);
  } else {
    pendingOpenPath = filePath;
  }
});

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
