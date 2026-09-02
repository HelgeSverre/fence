const assert = require("node:assert/strict");
const fs = require("node:fs");
const { test, describe } = require("node:test");
const { launchFence, waitForEditorValue } = require("./helpers");

const files = { "a.md": "# A\n", "b.md": "# B\n", "sub/c.md": "# C\n" };

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
