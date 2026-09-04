// macOS keeps the app running after its last window closes, so every path that
// touches the window has to cope with it being gone.
const assert = require("node:assert/strict");
const { test, describe } = require("node:test");
const { launchFence } = require("./helpers");

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
      // argv as a development run sees it: [electron, main.js, ...args]
      await fence.app.evaluate(({ app }, target) => app.emit("second-instance", {}, ["electron", "main.js", target], "/"), fence.file("other.md"));

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
});
