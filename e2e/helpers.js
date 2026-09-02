// Shared harness for the Electron end-to-end tests.
//
// Each test launches its own Fence process against a throwaway workspace and
// a throwaway user-data directory (FENCE_USER_DATA), so nothing touches the
// developer's real state.json, recovery drafts, or single-instance lock.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { _electron: electron } = require("playwright");

const projectRoot = path.resolve(__dirname, "..");
const MOD = process.platform === "darwin" ? "Meta" : "Control";

async function launchFence({ files = { "note.md": "# Original\n" }, open = "note.md", userDataDir, state } = {}) {
  const workspace = await fs.promises.mkdtemp(path.join(os.tmpdir(), "fence-e2e-"));
  for (const [rel, content] of Object.entries(files)) {
    const target = path.join(workspace, rel);
    await fs.promises.mkdir(path.dirname(target), { recursive: true });
    await fs.promises.writeFile(target, content, "utf-8");
  }
  const stateDir = userDataDir ?? (await fs.promises.mkdtemp(path.join(os.tmpdir(), "fence-e2e-state-")));
  // Pre-seed persisted settings (state.json) for tests that need a non-default setup.
  if (state) await fs.promises.writeFile(path.join(stateDir, "state.json"), JSON.stringify(state), "utf-8");

  const app = await electron.launch({
    args: [path.join(projectRoot, "dist-electron/main.js"), open ? path.join(workspace, open) : workspace],
    cwd: projectRoot,
    env: { ...process.env, ELECTRON_DISABLE_SECURITY_WARNINGS: "true", FENCE_USER_DATA: stateDir },
  });
  const window = await app.firstWindow();
  if (state?.virtualEditor) {
    await window.getByTestId("veditor").waitFor();
  } else {
    await window.getByTestId("editor-textarea").waitFor();
    if (open) await waitForEditorValue(window, files[open]);
  }

  return {
    app,
    window,
    workspace,
    userDataDir: stateDir,
    file: (rel) => path.join(workspace, rel),
    async close({ keepUserData = false } = {}) {
      // Unsaved edits would pop a native "save changes?" dialog on close.
      await window.evaluate(() => window.electronAPI?.setDirty({ dirty: false })).catch(() => {});
      await app.close();
      await fs.promises.rm(workspace, { recursive: true, force: true });
      if (!keepUserData) await fs.promises.rm(stateDir, { recursive: true, force: true });
    },
  };
}

function waitForEditorValue(window, expected, timeout = 10000) {
  return window.waitForFunction(
    (value) => document.querySelector("[data-testid=editor-textarea]")?.value === value,
    expected,
    { timeout },
  );
}

// Replace the editor content the way a paste would: through the native value
// setter plus an input event, so Elm's onInput fires.
function setEditorContent(window, content) {
  return window.getByTestId("editor-textarea").evaluate((element, value) => {
    Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, "value").set.call(element, value);
    element.dispatchEvent(new Event("input", { bubbles: true }));
  }, content);
}

async function waitForFile(filePath, expected, timeoutMs = 5000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if ((await fs.promises.readFile(filePath, "utf-8").catch(() => null)) === expected) return;
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  assert.fail(`Timed out waiting for ${path.basename(filePath)} to contain the expected content`);
}

const save = (window) => window.keyboard.press(`${MOD}+s`);

module.exports = { MOD, launchFence, waitForEditorValue, setEditorContent, waitForFile, save };
