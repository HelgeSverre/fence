const assert = require("node:assert/strict");
const { test, describe } = require("node:test");
const { launchFence, editorText } = require("./helpers");
const { execFile } = require("node:child_process");
const path = require("node:path");

describe("startup", () => {
  test("a second `fence <file>` launch opens the file in the running instance", async () => {
    const fence = await launchFence({ files: { "note.md": "# Original\n", "other.md": "# Other\n" } });
    try {
      const { window } = fence;
      // Electron splices its own Chromium switches into the argv it forwards;
      // the running app must not choke on them.
      const electron = require("electron");
      await new Promise((resolve, reject) =>
        execFile(electron, [path.join(__dirname, "..", "dist-electron", "main.js"), fence.file("other.md")], {
          env: { ...process.env, FENCE_USER_DATA: fence.userDataDir },
        }, (error, stdout, stderr) => (error ? reject(new Error(`${error.message}\n${stderr}`)) : resolve())),
      );
      await window.getByTestId("titlebar-filename").filter({ hasText: "other.md" }).waitFor();
    } finally {
      await fence.close();
    }
  });

  test("launching with a file opens its folder as the workspace and loads the file", async () => {
    const fence = await launchFence({ files: { "note.md": "# Original\n\nBody text.\n", "other.md": "# Other\n" } });
    try {
      const { window } = fence;
      assert.equal(await window.getByTestId("titlebar-filename").textContent(), "note.md");
      assert.match(await window.getByTestId("editor-header").textContent(), /^note\.md/);
      assert.equal(await window.getByTestId("word-count").textContent(), "4 words · 4 lines · 23 characters");

      const treeFiles = window.getByTestId("tree-file");
      assert.deepEqual(await treeFiles.allTextContents(), ["note.md", "other.md"]);
      await assert.doesNotReject(window.locator("[data-testid=tree-file].selected", { hasText: "note.md" }).waitFor());

      await window.getByTestId("preview-content").locator("h1", { hasText: "Original" }).waitFor();
      await window.getByTestId("preview-content").locator("p", { hasText: "Body text." }).waitFor();
    } finally {
      await fence.close();
    }
  });

  test("launching with a folder shows the tree, an empty editor, and the welcome preview", async () => {
    const fence = await launchFence({
      files: { "a.md": "# A\n", "notes/b.md": "# B\n", "ignored.txt": "x", "src/app.js": "x", "node_modules/pkg/README.md": "# noise\n" },
      open: null,
    });
    try {
      const { window } = fence;
      await window.getByTestId("tree-file").filter({ hasText: "a.md" }).waitFor();
      assert.equal(await window.getByTestId("titlebar-filename").count(), 0);
      assert.equal(await editorText(window), "");
      await window.getByTestId("preview-welcome").waitFor();

      // Only markdown files and directories that contain some are listed;
      // src/ (no markdown) and node_modules/ (noise) are hidden.
      assert.deepEqual(await window.getByTestId("tree-file").allTextContents(), ["a.md"]);
      assert.deepEqual(await window.getByTestId("tree-dir").allTextContents(), [fence.workspace.split("/").pop(), "notes"]);
    } finally {
      await fence.close();
    }
  });
});
