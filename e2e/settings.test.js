const assert = require("node:assert/strict");
const { test, describe } = require("node:test");
const { launchFence } = require("./helpers");

describe("settings and layout", () => {
  test("choosing a theme applies it immediately and persists across a restart", async () => {
    const first = await launchFence();
    let userDataDir;
    try {
      const { window } = first;
      userDataDir = first.userDataDir;
      await window.getByTestId("settings-button").click();
      await window.getByTestId("settings-dropdown").waitFor();
      await window.getByTestId("settings-item-github-dark").click();
      await window.waitForFunction(() => document.documentElement.dataset.theme === "github-dark");
    } finally {
      await first.close({ keepUserData: true });
    }

    const second = await launchFence({ userDataDir });
    try {
      assert.equal(await second.window.evaluate(() => document.documentElement.dataset.theme), "github-dark");
    } finally {
      await second.close();
    }
  });

  test("the sidebar toggle shortcut hides and shows the file tree", async () => {
    const fence = await launchFence();
    try {
      const { window } = fence;
      await window.getByTestId("sidebar").waitFor();
      await window.keyboard.press("Meta+1"); // default left-sidebar toggle
      await window.getByTestId("sidebar").waitFor({ state: "detached" });
      await window.keyboard.press("Meta+1");
      await window.getByTestId("sidebar").waitFor();
    } finally {
      await fence.close();
    }
  });

  test("the outline pane is hidden by default and its toggle shows it", async () => {
    const fence = await launchFence();
    try {
      const { window } = fence;
      assert.equal(await window.getByTestId("outline-pane").count(), 0);
      await window.keyboard.press("Meta+3");
      await window.getByTestId("outline-pane").waitFor();
      await window.getByTestId("outline-entry").filter({ hasText: "Original" }).waitFor();
    } finally {
      await fence.close();
    }
  });
});

test("opening settings keeps its button and dropdown anchor stationary", async () => {
  const fence = await launchFence();
  try {
    const button = fence.window.getByTestId("settings-button");
    const before = await button.boundingBox();
    await button.click();
    await fence.window.getByTestId("settings-dropdown").waitFor();
    const after = await button.boundingBox();
    assert.deepEqual(after, before, "opening the menu must not shift its toolbar anchor");
    const menu = await fence.window.getByTestId("settings-dropdown").boundingBox();
    assert.ok(Math.abs(menu.x + menu.width - before.x - before.width) < 1);
    await fence.window.keyboard.press("Escape");
    await fence.window.getByTestId("settings-dropdown").waitFor({ state: "detached" });
    assert.deepEqual(await button.boundingBox(), before);
  } finally { await fence.close(); }
});

test("the editor scrollbar corner matches the editor background", async () => {
  const fence = await launchFence({ files: { "note.md": ("long line ".repeat(150) + "\n").repeat(100) }, state: { softWrap: false, theme: "fleet-dark" } });
  try {
    const editor = fence.window.getByTestId("veditor");
    assert.equal(await editor.evaluate(e => e.scrollWidth > e.clientWidth && e.scrollHeight > e.clientHeight), true);
    const png = await editor.screenshot();
    const pixels = await fence.app.evaluate(({ nativeImage }, base64) => {
      const image = nativeImage.createFromBuffer(Buffer.from(base64, "base64"));
      const { width, height } = image.getSize();
      const bitmap = image.toBitmap();
      const pixel = (x, y) => [...bitmap.subarray((y * width + x) * 4, (y * width + x) * 4 + 4)];
      return { corner: pixel(width - 3, height - 3), background: pixel(2, 2) };
    }, png.toString("base64"));
    assert.deepEqual(pixels.corner, pixels.background, "the scrollbar intersection must not paint a white square");
  } finally { await fence.close(); }
});
