// macOS keeps the app running after its last window closes, so every path that
// touches the window has to cope with it being gone.
const assert = require("node:assert/strict");
const { test, describe } = require("node:test");
const fs = require("node:fs/promises");
const { launchFence, setEditorContent, editorText, waitFor } = require("./helpers");

async function quitFence(fence) {
  const exited = fence.app.waitForEvent("close", { timeout: 5000 });
  // The native Quit menu role (Cmd+Q) calls app.quit(). Schedule it so
  // the evaluation can return before the process exits.
  await fence.app.evaluate(({ app }) => { setTimeout(() => app.quit(), 50); });
  await exited;
}

// Only macOS keeps the app alive without windows; elsewhere window-all-closed
// quits it, so there is no destroyed window left to trip over.
describe("window lifecycle", { skip: process.platform !== "darwin" && "macOS-only behaviour" }, () => {
  test("opening a path from a second `fence` invocation reopens a closed window instead of crashing", async () => {
    const fence = await launchFence({ files: { "note.md": "# First\n", "other.md": "# Other\n" }, open: "note.md" });
    try {
      // close the window the way a user would, leaving the app running
      await fence.app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].destroy());
      await fence.app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows().length === 0);

      const opened = fence.app.waitForEvent("window");
      // `fence other.md` from a shell reaches the running app as second-instance
      // argv as a development run sees it: [electron, <switches Electron adds>, main.js, ...args]
      await fence.app.evaluate(
        ({ app }, target) => app.emit("second-instance", {}, ["electron", "--allow-file-access-from-files", "dist-electron/main.js", target], process.cwd()),
        fence.file("other.md"),
      );

      const page = await opened;
      await page.waitForFunction(
        () => document.querySelector(".veditor-row")?.textContent === "# Other",
        undefined,
        { timeout: 15000 },
      );
      await page.evaluate(() => window.electronAPI?.setDirty({ dirty: false })).catch(() => {});
    } finally {
      await fence.close();
    }
  });

  test("quitting a clean document exits the process after the close guard", async () => {
    const fence = await launchFence();
    try {
      await quitFence(fence);
    } finally {
      await fence.close();
    }
  });

  for (const [choice, response] of [["Save", 0], ["Discard", 1]]) {
    test(`quitting with ${choice} exits and ${choice === "Save" ? "writes" : "preserves"} the file`, async () => {
      const fence = await launchFence();
      try {
        await setEditorContent(fence.window, "# Unsaved\n");
        await fence.app.evaluate(({ dialog }, answer) => {
          dialog.showMessageBox = async () => ({ response: answer });
        }, response);
        await quitFence(fence);
        assert.equal(await fs.readFile(fence.file("note.md"), "utf8"), response === 0 ? "# Unsaved\n" : "# Original\n");
      } finally {
        await fence.close();
      }
    });
  }

  for (const nextAction of ["close", "quit"]) {
    test(`Cancel keeps unsaved edits and allows a later ${nextAction}`, async () => {
      const fence = await launchFence();
      try {
        await setEditorContent(fence.window, "# Unsaved\n");
        await fence.app.evaluate(({ app, dialog }) => {
          globalThis.__quitPrompts = 0;
          dialog.showMessageBox = async () => { globalThis.__quitPrompts++; return { response: 2 }; };
          app.quit();
        });
        await waitFor(() => fence.app.evaluate(() => globalThis.__quitPrompts === 1));
        // A fresh renderer round trip ensures the cancelled guard has settled.
        assert.equal(await editorText(fence.window), "# Unsaved\n");
        await fence.app.evaluate(({ dialog }) => { dialog.showMessageBox = async () => ({ response: 1 }); });
        if (nextAction === "quit") {
          await quitFence(fence);
        } else {
          const closed = fence.window.waitForEvent("close");
          await fence.app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].close());
          await closed;
          assert.equal(await fence.app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows().length), 0);
        }
        assert.equal(await fs.readFile(fence.file("note.md"), "utf8"), "# Original\n");
      } finally {
        await fence.close();
      }
    });
  }
});
