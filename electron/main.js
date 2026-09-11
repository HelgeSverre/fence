const { app, BrowserWindow, ipcMain, dialog, shell, Menu, clipboard, session, protocol, net } = require("electron");
const path = require("path");
const fs = require("fs");
const crypto = require("node:crypto");
const { pathToFileURL, fileURLToPath } = require("node:url");
const fsOps = require("./fs-ops");
const { parseCliArgs, help: cliHelp } = require("./cli");
const { autoUpdater } = require("electron-updater");

// Tests point this at a temp dir so they never touch the real state.json,
// recovery drafts or single-instance lock. Must run before the lock below.
if (process.env.FENCE_USER_DATA) {
  app.setPath("userData", process.env.FENCE_USER_DATA);
}

// Set by the e2e suite and profiling scripts: run fully headless. The window
// is never shown and renders offscreen into a buffer, and the Dock icon is
// hidden, so automation cannot appear on screen or take focus.
const QUIET_WINDOW = !!process.env.FENCE_QUIET_WINDOW;

const MAX_RECENT_WORKSPACES = 20;

// Where a pasted or dropped image is written, beside the open document.
const ATTACHMENT_DIR = "assets";

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

let recoveryWrites = Promise.resolve();

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
  await recoveryWrites.catch(() => {});
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

let navigationQueue = Promise.resolve();
let saveQueue = Promise.resolve();

function queuedSave(payload) {
  const task = saveQueue.then(() => saveDocument(payload));
  saveQueue = task.catch(() => {});
  return task;
}
let snapshotId = 0;
const snapshots = new Map();
let currentSession = null;
let sessionTimer;

function requestDocumentState() {
  if (!liveWindow() || !rendererReady) return Promise.resolve({ path: null, content: "", dirty: false });
  return new Promise((resolve, reject) => {
    const id = ++snapshotId;
    const timer = setTimeout(() => { snapshots.delete(id); reject(new Error("Editor did not respond; navigation cancelled.")); }, 5000);
    snapshots.set(id, (data) => { clearTimeout(timer); resolve(data); });
    sendToRenderer({ tag: "requestDocumentState", id });
  });
}

function flushSession() {
  clearTimeout(sessionTimer);
  if (currentSession !== null) updateState(() => ({ lastDocument: currentSession }));
}

function rememberSession(data) {
  currentSession = {
    path: typeof data.path === "string" ? data.path : null,
    ...Object.fromEntries(["line", "col", "top", "left"].map(key => [key, Number.isFinite(data[key]) ? Math.max(0, data[key]) : 0])),
  };
  clearTimeout(sessionTimer);
  sessionTimer = setTimeout(flushSession, 150);
}

async function confirmNavigation(closing = false) {
  for (;;) {
    await saveQueue;
    const snapshot = await requestDocumentState();
    rememberSession(snapshot);
    flushSession();
    if (!snapshot.dirty) return snapshot;
    const { response } = await dialog.showMessageBox(liveWindow(), {
      type: "warning", buttons: ["Save", "Discard", "Cancel"], defaultId: 0, cancelId: 2,
      title: "Unsaved Changes", message: closing ? "Save changes before closing?" : "Save changes before opening another document or workspace?",
    });
    if (response === 2) return false;
    const latest = await requestDocumentState();
    if (latest.path !== snapshot.path || latest.content !== snapshot.content) continue;
    if (response === 1) {
      if (snapshot.path) await clearRecoveryDraft(snapshot.path);
      return latest;
    }
    if (!(await queuedSave(snapshot))) return false;
    // The save acknowledgement precedes this next snapshot, so edits made
    // during the write are checked again rather than discarded.
  }
}

function navigate(action, closing = false) {
  const task = navigationQueue.then(async () => {
    for (;;) {
      const approved = await confirmNavigation(closing);
      if (!approved) { sendToRenderer({ tag: "navigationCancelled" }); return; }
      await saveQueue;
      sendToRenderer({ tag: "navigationBusy", busy: true });
      try {
        const locked = await requestDocumentState();
        if (locked.path !== approved.path || locked.content !== approved.content) continue;
        await action();
        return;
      } finally { sendToRenderer({ tag: "navigationBusy", busy: false }); }
    }
  });
  navigationQueue = task.catch(error => sendToRenderer({ tag: "error", message: error.message }));
  return navigationQueue;
}

async function switchWorkspace(folderPath) {
  if (await openWorkspace(folderPath)) sendToRenderer({ tag: "documentClosed" });
}

// A directory confirmed to hold markdown after its parent's listing was
// already sent; the tree inserts it like a directory created on disk.
function announceDir(dirPath) {
  sendToRenderer({ tag: "fsEvent", event: "addDir", path: dirPath });
}

// Open a folder as the active workspace: point fs-ops at it, push the
// listing to the renderer, and record it in the recents list.
async function openWorkspace(folderPath) {
  try {
    await fsOps.setWorkspace(folderPath);
    const entries = await fsOps.readDir(folderPath, announceDir);
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
    return true;
  } catch (err) {
    sendToRenderer({ tag: "error", message: err.message });
    return false;
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
          label: "New File",
          accelerator: "CmdOrCtrl+N",
          click: () => sendToRenderer({ tag: "treeCommand", command: "newFile", path: null }),
        },
        {
          label: "New Folder",
          accelerator: "CmdOrCtrl+Shift+N",
          click: () => sendToRenderer({ tag: "treeCommand", command: "newFolder", path: null }),
        },
        { type: "separator" },
        { label: "Save", accelerator: "CmdOrCtrl+S", click: () => sendToRenderer({ tag: "saveRequested" }) },
        { label: "Save As...", accelerator: "CmdOrCtrl+Shift+S", click: () => sendToRenderer({ tag: "saveAsRequested" }) },
        {
          label: "Open Recent",
          submenu:
            recents.length > 0
              ? recents.map((p) => ({
                  label: p,
                  click: () => navigate(() => switchWorkspace(p)),
                }))
              : [{ label: "No Recent Workspaces", enabled: false }],
        },
        { type: "separator" },
        {
          label: "Export",
          submenu: [
            {
              label: "PDF...",
              click: () => sendToRenderer({ tag: "exportRequested", format: "pdf" }),
            },
            {
              label: "HTML...",
              click: () => sendToRenderer({ tag: "exportRequested", format: "html" }),
            },
          ],
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
        { type: "separator" },
        {
          label: "Copy Document as Rich Text",
          click: () => sendToRenderer({ tag: "exportRequested", format: "clipboard" }),
        },
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

// Validate the optional CLI path relative to the invoking shell's directory.
function cliPathFrom(argv, cwd) {
  return parseCliArgs(argv.slice(app.isPackaged ? 1 : 2), cwd).path;
}

// The path a second `fence <path>` launch forwarded, relative to its shell's
// directory; its own process already reported any bad input.
function forwardedCliPath(argv, cwd) {
  // In development the forwarded argv also names this script or the app
  // directory, and Electron's switches push it off its usual slot.
  const isSelf = (arg) =>
    !app.isPackaged && [app.getAppPath(), process.argv[1]].some((own) => own && path.resolve(cwd, arg) === path.resolve(own));
  try {
    return parseCliArgs(argv.slice(1).filter((arg) => !isSelf(arg)), cwd, { forwarded: true }).path;
  } catch {
    return null;
  }
}

// Open a CLI path: a folder becomes the workspace; a file opens its parent
// folder as the workspace and loads the file into the editor.
async function openCliPath(cliPath) {
  const isDir = fs.statSync(cliPath).isDirectory();
  if (!(await openWorkspace(isDir ? cliPath : path.dirname(cliPath)))) return;
  if (isDir) sendToRenderer({ tag: "documentClosed" });
  if (!isDir) {
    try {
      await sendFileContent(cliPath);
    } catch (err) {
      sendToRenderer({ tag: "error", message: err.message });
    }
  }
}

function createWindow() {
  rendererReady = false;
  mainWindow = new BrowserWindow({
    width: 1400,
    height: 900,
    show: false,
    backgroundColor: "#0d1117", // dark canvas before the renderer's first paint
    title: "Fence",
    titleBarStyle: "hiddenInset",
    trafficLightPosition: { x: 12, y: 10 },
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      spellcheck: false,
      backgroundThrottling: !QUIET_WINDOW, // keep frames flowing while hidden
      offscreen: QUIET_WINDOW, // headless: paint to a buffer, never a native window
    },
  });

  mainWindow.once("ready-to-show", () => {
    if (!QUIET_WINDOW) mainWindow.show();
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
        const entries = await fsOps.readDir(state.lastWorkspace, announceDir);
        sendToRenderer({
          tag: "folderOpened",
          path: state.lastWorkspace,
          entries,
        });
        if (state.lastDocument?.path) {
          try {
            await sendFileContent(state.lastDocument.path);
            sendToRenderer({ tag: "restoreSession", ...state.lastDocument });
          } catch { /* A removed or moved document leaves the workspace open. */ }
        }
      } catch {
        // Workspace vanished — forget it, but keep every other setting.
        await fsOps.setWorkspace(null);
        updateState(() => ({ lastWorkspace: null }));
      }
    }
  });

  // Read the renderer's current document before closing: the cached dirty IPC
  // can lag behind the last keystroke, particularly on Linux.
  const window = mainWindow;
  let checkingClose = false;
  window.on("close", (event) => {
    flushSession();
    if (window._closeApproved || !rendererReady) return;
    event.preventDefault();
    if (checkingClose) return;
    checkingClose = true;
    navigate(async () => {
      window._closeApproved = true;
      window.close();
    }, true).finally(() => { checkingClose = false; });
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

// On macOS the app outlives its window, so `mainWindow` can reference a
// destroyed object. Every use has to go through this.
function liveWindow() {
  return mainWindow && !mainWindow.isDestroyed() ? mainWindow : null;
}

function sendToRenderer(data) {
  liveWindow()?.webContents.send("fromElm", data);
}

function isTrustedIpcEvent(event) {
  const win = liveWindow();
  return Boolean(win && event.sender === win.webContents && event.senderFrame === win.webContents.mainFrame);
}

function requireString(payload, key, maxLength = 100 * 1024 * 1024) {
  const value = payload?.[key];
  if (typeof value !== "string" || value.length > maxLength) {
    throw new TypeError(`Invalid ${key}`);
  }
  return value;
}

// Preview images: Elm renders `fence-image://local/?doc=<document>&src=<source>`
// and Chromium streams the file from here, so no image bytes cross IPC.
// Must be registered before app is ready.
protocol.registerSchemesAsPrivileged([{ scheme: "fence-image", privileges: { standard: true, secure: true } }]);

async function serveImage(request) {
  const { searchParams } = new URL(request.url);
  try {
    const { imagePath } = await fsOps.resolveImagePath(searchParams.get("doc") ?? "", searchParams.get("src") ?? "");
    // Elm adds a `v=<parse generation>` query so a re-rendered chunk gets a
    // fresh URL: Blink reuses an image by URL for the document's lifetime.
    return await net.fetch(pathToFileURL(imagePath).toString());
  } catch {
    // A missing/unsupported image is a broken image, never a banner.
    return new Response(null, { status: 404 });
  }
}

// Exports must stand on their own: swap every preview image URL for the
// file's data URL. The HTML is serialized DOM, so `&` arrives as `&amp;`.
async function inlineImages(html) {
  const pattern = /src="(fence-image:\/\/[^"]*)"/g;
  const inlined = await Promise.all([...html.matchAll(pattern)].map(async ([, raw]) => {
    try {
      const url = new URL(raw.replace(/&amp;/g, "&"));
      return await fsOps.readImage(url.searchParams.get("doc") ?? "", (url.searchParams.get("src") ?? "") + url.hash);
    } catch {
      return "";
    }
  }));
  let i = 0;
  return html.replace(pattern, () => `src="${inlined[i++]}"`);
}

function registerIpc(channel, handler) {
  ipcMain.on(channel, (event, payload = {}) => {
    if (!isTrustedIpcEvent(event)) return;
    Promise.resolve(handler(payload)).catch((error) => {
      sendToRenderer({ tag: "error", message: error.message });
    });
  });
}

async function sendFileContent(filePath, offerRecovery = true, line = null) {
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

  await watchDirectory(path.dirname(file.path));
  sendToRenderer({ tag: "fileContent", ...file, content, dirty, line });
}

async function saveDocument(payload) {
  const originalPath = typeof payload.path === "string" ? payload.path : null;
  let filePath = originalPath;
  const content = requireString(payload, "content");
  const saveAs = !filePath || payload.saveAs === true;
  let expectedRevision = typeof payload.expectedRevision === "string" ? payload.expectedRevision : (typeof payload.revision === "string" ? payload.revision : null);
  if (saveAs) {
    const result = await dialog.showSaveDialog(liveWindow(), {
      defaultPath: originalPath || path.join(loadState().lastWorkspace || app.getPath("documents"), "Untitled.md"),
      filters: [{ name: "Markdown", extensions: ["md", "markdown"] }],
    });
    if (result.canceled || !result.filePath) { sendToRenderer({ tag: "saveCancelled" }); return false; }
    filePath = result.filePath;
    expectedRevision = null;
  }
  try {
    const saved = await fsOps.writeFile(filePath, content, expectedRevision, saveAs);
    if (originalPath) await clearRecoveryDraft(originalPath);
    if (saveAs) {
      try { await fsOps.resolvePath(saved.path); }
      catch { await openWorkspace(path.dirname(saved.path)); }
    }
    sendToRenderer({ tag: saveAs ? "fileSavedAs" : "fileSaved", ...saved, content, dirty: false, originalPath });
    return true;
  } catch (error) {
    if (!(error instanceof fsOps.FileConflictError)) throw error;
    const { response } = await dialog.showMessageBox(liveWindow(), {
      type: "warning", buttons: ["Overwrite", "Reload from Disk", "Cancel"], defaultId: 2, cancelId: 2,
      title: "File Changed on Disk", message: `${path.basename(filePath)} changed outside Fence.`,
      detail: "Overwrite the external changes, reload the disk version, or cancel and keep editing your draft.",
    });
    if (response === 0) {
      const saved = await fsOps.writeFile(filePath, content, null);
      await clearRecoveryDraft(saved.path);
      sendToRenderer({ tag: "fileSaved", ...saved, content });
      return true;
    }
    if (response === 1) {
      await clearRecoveryDraft(filePath);
      await sendFileContent(filePath, false);
    } else sendToRenderer({ tag: "saveCancelled" });
    return false;
  }
}

registerIpc("fence:document-state", data => {
  const resolve = snapshots.get(data.id);
  if (resolve) { snapshots.delete(data.id); resolve(data); }
});
registerIpc("fence:save-session", data => { if (rendererReady) rememberSession(data); });

ipcMain.on("fence:get-initial-state", (event) => {
  event.returnValue = isTrustedIpcEvent(event) ? loadState() : {};
});

registerIpc("fence:open-folder", async () => {
  const result = await dialog.showOpenDialog(mainWindow, {
    properties: ["openDirectory"],
  });
  if (!result.canceled && result.filePaths.length > 0) {
    await navigate(() => switchWorkspace(result.filePaths[0]));
  }
});

registerIpc("fence:read-dir", async (data) => {
  const dirPath = requireString(data, "path", 32768);
  const entries = await fsOps.readDir(dirPath, announceDir);
  sendToRenderer({ tag: "dirContents", path: dirPath, entries });
});

registerIpc("fence:open-link", async data => {
  const documentPath = await fsOps.resolvePath(requireString(data, "documentPath", 32768));
  const url = new URL(requireString(data, "href", 32768), pathToFileURL(documentPath));
  if (url.protocol !== "file:") return;
  const target = await fs.promises.realpath(fileURLToPath(url));
  if (!fsOps.isMarkdownFile(target)) return;
  const fragment = decodeURIComponent(url.hash.slice(1));
  if (target === documentPath) {
    sendToRenderer({ tag: "navigateHeading", path: target, fragment });
  } else {
    await navigate(async () => {
      // Following a clicked local link can open a neighboring workspace, just
      // like opening that same file through Finder or the CLI.
      let inside = true;
      try { await fsOps.resolvePath(target); } catch { inside = false; }
      if (inside) await sendFileContent(target);
      else await openCliPath(target);
      sendToRenderer({ tag: "navigateHeading", path: target, fragment });
    });
  }
});

registerIpc("fence:read-file", async (data) => {
  const filePath = requireString(data, "path", 32768);
  if (Number.isSafeInteger(data.reloadId)) {
    // Background refreshes never open recovery dialogs or navigate the editor.
    const file = await fsOps.readFile(filePath);
    sendToRenderer({ tag: "fileReloaded", ...file, dirty: false, reloadId: data.reloadId });
    return;
  }
  const line = Number.isInteger(data.line) ? data.line : null;
  await navigate(() => sendFileContent(filePath, true, line));
});

registerIpc("fence:write-file", queuedSave);

async function watchDirectory(dirPath) {
  await fsOps.watchDir(dirPath, async (event, filePath) => {
    if (event === "addDir" && !(await fsOps.containsMarkdown(filePath))) return;
    if ((event === "add" || event === "change") && !fsOps.isMarkdownFile(filePath)) return;
    sendToRenderer({ tag: "fsEvent", event, path: filePath });
  });
}
registerIpc("fence:watch-dir", data => watchDirectory(requireString(data, "path", 32768)));

registerIpc("fence:unwatch-dir", async (data) => {
  await fsOps.unwatchDir(requireString(data, "path", 32768));
});

registerIpc("fence:create-file", data => navigate(async () => {
  const created = await fsOps.createFile(requireString(data, "dir", 32768), requireString(data, "name", 255));
  await sendFileContent(created.path, false);
}));

registerIpc("fence:create-dir", async (data) => {
  await fsOps.createDir(requireString(data, "dir", 32768), requireString(data, "name", 255));
});

registerIpc("fence:rename-path", async data => {
  await recoveryWrites.catch(() => {});
  const snapshot = await requestDocumentState();
  const renamed = await fsOps.renamePath(requireString(data, "path", 32768), requireString(data, "name", 255));
  sendToRenderer({ tag: "renamed", from: renamed.from, path: renamed.path });
  const follow = candidate => candidate === renamed.from ? renamed.path :
    candidate?.startsWith(renamed.from + path.sep) ? renamed.path + candidate.slice(renamed.from.length) : candidate;
  const directory = path.join(app.getPath("userData"), "recovery");
  for (const name of await fs.promises.readdir(directory).catch(() => [])) {
    if (!name.endsWith(".json")) continue;
    const file = path.join(directory, name);
    const draft = await fs.promises.readFile(file, "utf8").then(JSON.parse).catch(() => null);
    if (draft?.path && follow(draft.path) !== draft.path) {
      const target = follow(draft.path);
      await saveRecoveryDraft({ ...draft, path: target });
      await fs.promises.unlink(file);
    }
  }
  if (snapshot.path && follow(snapshot.path) !== snapshot.path) {
    const target = follow(snapshot.path);
    if (snapshot.dirty) await saveRecoveryDraft({ ...snapshot, path: target });
    await watchDirectory(path.dirname(target));
  }
});

registerIpc("fence:trash-path", async (data) => {
  // Trash, never unlink: a misclick has to stay undoable.
  await shell.trashItem(await fsOps.resolvePath(requireString(data, "path", 32768)));
});

registerIpc("fence:reveal-path", async (data) => {
  shell.showItemInFolder(await fsOps.resolvePath(requireString(data, "path", 32768)));
});

registerIpc("fence:list-files", async (data) => {
  const root = requireString(data, "path", 32768);
  sendToRenderer({ tag: "fileList", files: await fsOps.listMarkdownFiles(root) });
});

registerIpc("fence:search-workspace", async (data) => {
  const root = requireString(data, "path", 32768);
  const query = requireString(data, "query", 1024);
  sendToRenderer({ tag: "searchResults", query, hits: await fsOps.grep(root, query) });
});

// Build a standalone HTML document from the rendered preview: the renderer
// hands over the pane's markup and the stylesheet text it is using, so the
// export looks exactly like what is on screen, mermaid diagrams included.
async function exportDocument(data) {
  const html = await inlineImages(requireString(data, "html"));
  const css = requireString(data, "css");
  const title = requireString(data, "title", 512);
  const theme = typeof data.theme === "string" ? data.theme : "";
  const base = typeof data.base === "string" ? data.base : "";

  return `<!doctype html>
<html${theme ? ` data-theme="${escapeAttribute(theme)}"` : ""}>
<head>
<meta charset="utf-8">
<title>${escapeHtml(title)}</title>
${base ? `<base href="${escapeAttribute(base)}">` : ""}
<style>${css}
@page { margin: 1.5cm; }
body { margin: 0; }
.preview-pane, .preview-content { overflow: visible !important; height: auto !important; }
</style>
</head>
<body><div class="preview-pane"><div class="preview-content">${html}</div></div></body>
</html>`;
}

function escapeHtml(value) {
  return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function escapeAttribute(value) {
  return escapeHtml(value).replace(/"/g, "&quot;");
}

async function renderPdf(document_) {
  const printer = new BrowserWindow({ show: false, webPreferences: { javascript: false } });
  try {
    await printer.loadURL(`data:text/html;charset=utf-8,${encodeURIComponent(document_)}`);
    return await printer.webContents.printToPDF({ printBackground: true });
  } finally {
    printer.destroy();
  }
}

async function saveExport(defaultName, extension, contents) {
  const result = await dialog.showSaveDialog(mainWindow, {
    defaultPath: defaultName,
    filters: [{ name: extension.toUpperCase(), extensions: [extension] }],
  });
  if (result.canceled || !result.filePath) return;
  await fs.promises.writeFile(result.filePath, contents);
}

registerIpc("fence:export", async (data) => {
  const format = requireString(data, "format", 32);
  const name = requireString(data, "title", 512).replace(/\.[^.]*$/, "") || "document";
  const document_ = await exportDocument(data);

  if (format === "pdf") {
    await saveExport(`${name}.pdf`, "pdf", await renderPdf(document_));
  } else if (format === "html") {
    await saveExport(`${name}.html`, "html", Buffer.from(document_, "utf-8"));
  } else if (format === "clipboard") {
    clipboard.write({ text: requireString(data, "text"), html: document_ });
  } else {
    throw new Error(`Unknown export format: ${format}`);
  }
});

registerIpc("fence:save-attachment", async (data) => {
  const documentPath = await fsOps.resolvePath(requireString(data, "documentPath", 32768));
  const name = requireString(data, "name", 255);
  const bytes = data.bytes;
  if (!(bytes instanceof ArrayBuffer) && !ArrayBuffer.isView(bytes)) throw new TypeError("Invalid bytes");

  const written = await fsOps.writeBinary(
    path.join(path.dirname(documentPath), ATTACHMENT_DIR),
    name,
    Buffer.from(ArrayBuffer.isView(bytes) ? bytes.buffer : bytes),
  );
  sendToRenderer({ tag: "attachmentSaved", path: written.path, relative: `${ATTACHMENT_DIR}/${name}` });
});

registerIpc("fence:open-path", async (data) => {
  const target = requireString(data, "path", 32768);
  if (!fs.existsSync(target)) throw new Error(`No such path: ${target}`);
  await navigate(() => openCliPath(target));
});

registerIpc("fence:tree-context-menu", async (data) => {
  const filePath = await fsOps.resolvePath(requireString(data, "path", 32768));
  const isDirectory = (await fs.promises.stat(filePath)).isDirectory();
  const command = (command_) => () => sendToRenderer({ tag: "treeCommand", command: command_, path: filePath });
  Menu.buildFromTemplate([
    { label: "New File", click: command("newFile") },
    { label: "New Folder", click: command("newFolder") },
    { type: "separator" },
    { label: "Rename...", click: command("rename") },
    { label: isDirectory ? "Move Folder to Trash" : "Move to Trash", click: command("trash") },
    { type: "separator" },
    {
      label: process.platform === "darwin" ? "Reveal in Finder" : "Show in Folder",
      click: () => shell.showItemInFolder(filePath),
    },
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
  if (["editor", "split", "preview"].includes(data.layoutMode)) {
    updates.layoutMode = data.layoutMode;
  }
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
  for (const key of ["leftToggleKey", "rightToggleKey", "layoutCycleKey"]) {
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

// Invalid or missing keys are skipped silently, as in save-splits above.
const string = (max) => (v) => typeof v === "string" && v.length <= max;
const number = (lo, hi) => (v) => typeof v === "number" && v >= lo && v <= hi;
const integer = (lo, hi) => (v) => Number.isInteger(v) && v >= lo && v <= hi;
const boolean = (v) => typeof v === "boolean";
const oneOf = (values) => (v) => values.includes(v);

const preferenceRules = {
  theme: string(128), editorFont: string(256), uiFont: string(256),
  editorFontSize: number(8, 32), previewFontSize: number(8, 32), uiFontSize: number(8, 24),
  previewWidth: oneOf(["full", "narrow", "normal", "wide", "custom"]), previewMaxWidth: integer(320, 2000),
  showPaneHeaders: boolean, previewUsesEditorFont: boolean, softWrap: boolean,
  revealInSidebar: boolean,
};

registerIpc("fence:set-preferences", (data) => {
  const updates = {};
  for (const [key, valid] of Object.entries(preferenceRules)) {
    if (valid(data[key])) updates[key] = data[key];
  }
  updateState(() => updates);
});

registerIpc("fence:save-recovery-draft", data => {
  recoveryWrites = recoveryWrites.catch(() => {}).then(() => saveRecoveryDraft(data));
  return recoveryWrites;
});

let cliRequest;
try { cliRequest = parseCliArgs(process.argv.slice(app.isPackaged ? 1 : 2), process.cwd()); }
catch (error) { process.stderr.write(`fence: ${error.message}\n`); app.exit(2); }
if (cliRequest?.help) { process.stdout.write(cliHelp); app.exit(0); }
if (cliRequest?.version) { process.stdout.write(`${app.isPackaged ? app.getVersion() : require("../package.json").version}\n`); app.exit(0); }
const gotLock = app.requestSingleInstanceLock();

// macOS delivers Finder double-clicks and "Open With" via open-file, not
// argv; it can fire before the window exists, so hold the path until then.
app.on("open-file", (event, filePath) => {
  event.preventDefault();
  revealPath(filePath);
});

// Show `target` (a file or folder, possibly null) in a window, opening one if
// the app is running without a window, as macOS allows. Before the renderer
// has loaded, the path is parked for `did-finish-load` to pick up.
function revealPath(target) {
  const win = liveWindow();
  if (!win) {
    pendingOpenPath = target;
    if (app.isReady()) createWindow();
    return;
  }
  if (win.isMinimized()) win.restore();
  if (!QUIET_WINDOW) win.focus();
  if (!rendererReady) {
    pendingOpenPath = target;
  } else if (target) {
    navigate(() => openCliPath(target));
  }
}

if (!gotLock) {
  app.quit();
} else {
  // `fence <path>` while the app is running: the new process forwards its
  // argv here and exits; open the path in the existing window.
  app.on("second-instance", (_event, argv, workingDirectory) => {
    revealPath(forwardedCliPath(argv, workingDirectory));
  });

  app.whenReady().then(() => {
    if (QUIET_WINDOW) app.dock?.hide();
    app.setAboutPanelOptions({
      applicationName: "Fence",
      applicationVersion: app.getVersion(),
      copyright: "Copyright © 2026 Helge Sverre",
      website: "https://github.com/HelgeSverre/fence",
    });

    protocol.handle("fence-image", serveImage);
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
    if (!liveWindow()) createWindow();
  });
}
