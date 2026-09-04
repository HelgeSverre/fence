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
    env: { ...process.env, ELECTRON_DISABLE_SECURITY_WARNINGS: "true", FENCE_USER_DATA: stateDir, FENCE_QUIET_WINDOW: "1" },
  });
  const window = await app.firstWindow();
  await window.getByTestId("veditor").waitFor();
  try {
    if (open) await waitForEditorValue(window, files[open]);
  } catch (error) {
    await app.close().catch(() => {});
    throw error;
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

// The document text as the editor shows it: the visible rows, which is the
// whole document for the short files these tests use.
function editorText(window) {
  return window.evaluate(() => [...document.querySelectorAll(".veditor-row")].map((r) => r.textContent).join("\n"));
}

// Only visible rows are in the DOM, so compare the exposed document length and
// require the visible rows to be a prefix of the text (tests read from the top).
function waitForEditorValue(window, expected, timeout = 10000) {
  return window.waitForFunction(
    (value) => {
      const ve = document.querySelector("[data-testid=veditor]");
      if (!ve || Number(ve.dataset.length) !== value.length) return false;
      const rows = [...document.querySelectorAll(".veditor-row")].map((r) => r.textContent).join("\n");
      return value.startsWith(rows) || ve.scrollTop > 0;
    },
    expected,
    { timeout },
  );
}

// Put the caret in the document and the focus on the hidden input that
// receives keys, which is what a click does.
async function focusEditor(window) {
  await window.locator(".veditor-spacer").click({ position: { x: 2, y: 2 } });
  await window.waitForFunction(() => document.activeElement?.id === "veditor-input");
}

// Replace the whole document: focus, select all, and insert the text as one input.
async function setEditorContent(window, content) {
  await focusEditor(window);
  await window.keyboard.press(`${MOD}+a`);
  await window.keyboard.insertText(content);
  await waitForEditorValue(window, content, 5000);
}

// Elm renders on the next animation frame, so poll rather than reading straight
// after a keystroke. Falls back to a plain assert so failures show both texts.
async function expectEditorText(window, expected) {
  await window
    .waitForFunction((want) => [...document.querySelectorAll(".veditor-row")].map((r) => r.textContent).join("\n") === want, expected, { timeout: 3000 })
    .catch(async () => assert.equal(await editorText(window), expected));
}

// A ready-to-type editor holding `content`, for tests that only need one file.
async function openEditor(content) {
  const fence = await launchFence({ files: { "note.md": content }, open: "note.md" });
  await focusEditor(fence.window);
  return fence;
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

module.exports = { MOD, launchFence, openEditor, focusEditor, editorText, expectEditorText, waitForEditorValue, setEditorContent, waitForFile, save };
