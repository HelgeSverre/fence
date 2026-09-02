const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { test } = require("node:test");
const { _electron: electron } = require("playwright");

const projectRoot = path.resolve(__dirname, "..");

async function waitForFile(filePath, expected, timeoutMs = 5000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if ((await fs.promises.readFile(filePath, "utf-8")) === expected) return;
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  assert.fail("Timed out waiting for Fence to save the document");
}

test("opens, edits, previews, and saves a large document", async () => {
  const workspace = await fs.promises.mkdtemp(path.join(os.tmpdir(), "fence-e2e-"));
  const filePath = path.join(workspace, "note.md");
  await fs.promises.writeFile(filePath, "# Original\n", "utf-8");

  const electronApp = await electron.launch({
    args: [path.join(projectRoot, "dist-electron/main.js"), filePath],
    cwd: projectRoot,
    env: { ...process.env, ELECTRON_DISABLE_SECURITY_WARNINGS: "true" },
  });

  try {
    const window = await electronApp.firstWindow();
    const editor = window.locator("textarea.editor-textarea");
    await editor.waitFor();
    // The CLI path is read and pushed over IPC after the window loads, so
    // wait for the content rather than asserting it immediately.
    await window.waitForFunction(
      () => document.querySelector("textarea.editor-textarea")?.value === "# Original\n",
      undefined,
      { timeout: 10000 },
    );

    const content = `# Large Document\n\n${"word ".repeat(60000)}`;
    const renderMs = await editor.evaluate(async (element, value) => {
      const setter = Object.getOwnPropertyDescriptor(
        HTMLTextAreaElement.prototype,
        "value",
      ).set;
      const started = performance.now();
      setter.call(element, value);
      element.dispatchEvent(new Event("input", { bubbles: true }));
      await new Promise((resolve) => requestAnimationFrame(resolve));
      await new Promise((resolve) => requestAnimationFrame(resolve));
      return performance.now() - started;
    }, content);

    assert.ok(renderMs < 1500, `large-document input render took ${renderMs}ms`);
    await window
      .locator(".preview-content h1", { hasText: "Large Document" })
      .waitFor({ timeout: 5000 });

    await window.keyboard.press(process.platform === "darwin" ? "Meta+s" : "Control+s");
    await waitForFile(filePath, content);
  } finally {
    await electronApp.close();
    await fs.promises.rm(workspace, { recursive: true, force: true });
  }
});
