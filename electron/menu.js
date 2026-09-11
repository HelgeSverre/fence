const { app, Menu } = require("electron");
const { loadState } = require("./session");

// (Re)build the application menu. Called again whenever the recent
// workspaces list changes so File > Open Recent stays current.
// `sendToRenderer` posts a message to the window; `openRecent(path)` switches
// workspace after the usual unsaved-changes check.
function buildMenu(sendToRenderer, openRecent) {
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
                  click: () => openRecent(p),
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

module.exports = { buildMenu };
