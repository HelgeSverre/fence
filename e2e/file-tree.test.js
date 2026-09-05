const assert = require("node:assert/strict");
const fs = require("node:fs");
const { test, describe } = require("node:test");
const path = require("node:path");
const { launchFence, waitForEditorValue } = require("./helpers");

// Exactly what the File menu and the tree's context menu do: push a command
// to the renderer from the main process. Playwright cannot click native menus.
const treeCommand = (app, command, target = null) =>
  app.evaluate(({ BrowserWindow }, message) => BrowserWindow.getAllWindows()[0].webContents.send("fromElm", message), {
    tag: "treeCommand",
    command,
    path: target,
  });

async function typeName(window, name) {
  const input = window.getByTestId("tree-name-input");
  await input.waitFor();
  await input.fill(name);
  await input.press("Enter");
}

const files = { "a.md": "# A\n", "b.md": "# B\n", "sub/c.md": "# C\n" };

const waitForTitle = (window, name) =>
  window.waitForFunction((want) => document.querySelector("[data-testid=titlebar-filename]")?.textContent === want, name, {
    timeout: 10000,
  });

async function waitForPath(target, timeoutMs = 10000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (fs.existsSync(target)) return;
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  assert.fail(`Timed out waiting for ${path.basename(target)}`);
}

describe("file tree", () => {
  test("clicking a file loads it into the editor and selects it", async () => {
    const fence = await launchFence({ files, open: "a.md" });
    try {
      const { window } = fence;
      await window.getByTestId("tree-file").filter({ hasText: "b.md" }).click();
      await waitForEditorValue(window, "# B\n");
      assert.equal(await window.getByTestId("titlebar-filename").textContent(), "b.md");
      await window.locator("[data-testid=tree-file].selected", { hasText: "b.md" }).waitFor();
    } finally {
      await fence.close();
    }
  });

  test("expanding a directory lists its markdown files", async () => {
    const fence = await launchFence({ files, open: "a.md" });
    try {
      const { window } = fence;
      assert.equal(await window.getByTestId("tree-file").filter({ hasText: "c.md" }).count(), 0);
      await window.getByTestId("tree-dir").filter({ hasText: "sub" }).click();
      await window.getByTestId("tree-file").filter({ hasText: "c.md" }).waitFor();
      await window.getByTestId("tree-file").filter({ hasText: "c.md" }).click();
      await waitForEditorValue(window, "# C\n");
    } finally {
      await fence.close();
    }
  });

  test("arrow keys move focus and Enter opens the focused file", async () => {
    const fence = await launchFence({ files, open: "a.md" });
    try {
      const { window } = fence;
      await window.getByTestId("tree-file").filter({ hasText: "a.md" }).click();
      // a.md -> b.md is the next visible row after the root and a.md.
      await window.keyboard.press("ArrowDown");
      await window.keyboard.press("Enter");
      await waitForEditorValue(window, "# B\n");
      await window.keyboard.press("ArrowUp");
      await window.keyboard.press("Enter");
      await waitForEditorValue(window, "# A\n");
    } finally {
      await fence.close();
    }
  });

  test("New File creates the file, shows it in the tree and opens it", async () => {
    const fence = await launchFence({ files, open: "a.md" });
    try {
      const { window } = fence;
      await treeCommand(fence.app, "newFile");
      await typeName(window, "fresh.md");

      await window.getByTestId("tree-file").filter({ hasText: "fresh.md" }).waitFor({ timeout: 10000 });
      assert.equal(await fs.promises.readFile(fence.file("fresh.md"), "utf-8"), "");
      await waitForTitle(window, "fresh.md");
    } finally {
      await fence.close();
    }
  });

  test("New File lands in the selected directory", async () => {
    const fence = await launchFence({ files, open: "a.md" });
    try {
      const { window } = fence;
      await window.getByTestId("tree-dir").filter({ hasText: "sub" }).click();
      await treeCommand(fence.app, "newFile", fence.file("sub"));
      await typeName(window, "inner.md");

      await window.getByTestId("tree-file").filter({ hasText: "inner.md" }).waitFor({ timeout: 10000 });
      assert.equal(await fs.promises.readFile(fence.file("sub/inner.md"), "utf-8"), "");
    } finally {
      await fence.close();
    }
  });

  test("New Folder creates a directory", async () => {
    const fence = await launchFence({ files, open: "a.md" });
    try {
      await treeCommand(fence.app, "newFolder");
      await typeName(fence.window, "ideas");

      // The tree only shows directories holding markdown, so check the disk.
      await waitForPath(fence.file("ideas"));
      assert.equal((await fs.promises.stat(fence.file("ideas"))).isDirectory(), true);
    } finally {
      await fence.close();
    }
  });

  test("Escape cancels a creation and nothing is written", async () => {
    const fence = await launchFence({ files, open: "a.md" });
    try {
      const { window } = fence;
      await treeCommand(fence.app, "newFile");
      const input = window.getByTestId("tree-name-input");
      await input.waitFor();
      await input.fill("cancelled.md");
      await input.press("Escape");

      await window.getByTestId("tree-name-input").waitFor({ state: "detached" });
      assert.equal(fs.existsSync(fence.file("cancelled.md")), false);
    } finally {
      await fence.close();
    }
  });

  test("renaming the open file moves it on disk and follows it in the title", async () => {
    const fence = await launchFence({ files, open: "a.md" });
    try {
      const { window } = fence;
      await treeCommand(fence.app, "rename", fence.file("a.md"));
      await typeName(window, "renamed.md");

      await waitForPath(fence.file("renamed.md"));
      assert.equal(await fs.promises.readFile(fence.file("renamed.md"), "utf-8"), "# A\n");
      assert.equal(fs.existsSync(fence.file("a.md")), false);
      await waitForTitle(window, "renamed.md");
    } finally {
      await fence.close();
    }
  });

  test("a name that already exists is reported and changes nothing", async () => {
    const fence = await launchFence({ files, open: "a.md" });
    try {
      const { window } = fence;
      await treeCommand(fence.app, "newFile");
      await typeName(window, "b.md");

      await window.getByTestId("error-banner").waitFor({ timeout: 10000 });
      assert.match(await window.getByTestId("error-banner").textContent(), /already exists/);
      assert.equal(await fs.promises.readFile(fence.file("b.md"), "utf-8"), "# B\n");
    } finally {
      await fence.close();
    }
  });

  test("Move to Trash removes the file from the workspace and the tree", async () => {
    const fence = await launchFence({ files, open: "a.md" });
    try {
      const { window } = fence;
      await treeCommand(fence.app, "trash", fence.file("b.md"));

      await window.getByTestId("tree-file").filter({ hasText: "b.md" }).waitFor({ state: "detached", timeout: 10000 });
      assert.equal(fs.existsSync(fence.file("b.md")), false);
    } finally {
      await fence.close();
    }
  });

  test("files created and deleted on disk appear and disappear", async () => {
    const fence = await launchFence({ files, open: "a.md" });
    try {
      const { window } = fence;
      await fs.promises.writeFile(fence.file("new.md"), "# New\n", "utf-8");
      await window.getByTestId("tree-file").filter({ hasText: "new.md" }).waitFor({ timeout: 10000 });
      await fs.promises.rm(fence.file("new.md"));
      await window.getByTestId("tree-file").filter({ hasText: "new.md" }).waitFor({ state: "detached", timeout: 10000 });
    } finally {
      await fence.close();
    }
  });
});
