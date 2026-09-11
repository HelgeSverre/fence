const assert = require("node:assert/strict");
const { test, describe } = require("node:test");
const { launchFence, openSettings } = require("./helpers");

describe("settings and layout", () => {
  test("choosing a theme applies it immediately and persists across a restart", async () => {
    const first = await launchFence();
    let userDataDir;
    try {
      const { window } = first;
      userDataDir = first.userDataDir;
      await openSettings(window);
      await window.getByTestId("settings-picker-theme").click();
      await window.getByTestId("settings-option-theme-github-dark").click();
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

  test("choosing a UI font applies it to the sans stack and persists across a restart", async () => {
    const first = await launchFence();
    let userDataDir;
    try {
      const { window } = first;
      userDataDir = first.userDataDir;
      await openSettings(window);
      await window.getByTestId("settings-picker-ui-font").click();
      await window.getByTestId("settings-picker-search").fill("inter");
      await window.getByTestId("settings-option-ui-font-Inter").click();
      await window.waitForFunction(() => getComputedStyle(document.documentElement).getPropertyValue("--font-sans").includes("Inter"));
    } finally {
      await first.close({ keepUserData: true });
    }

    const second = await launchFence({ userDataDir });
    try {
      assert.ok((await second.window.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue("--font-sans"))).includes("Inter"));
    } finally {
      await second.close();
    }
  });

  test("limiting the preview width centers the document at the configured width", async () => {
    const fence = await launchFence({ state: { previewWidth: "custom", previewMaxWidth: 500 } });
    try {
      const { window } = fence;
      const content = window.getByTestId("preview-content");
      await window.waitForFunction(() => getComputedStyle(document.querySelector('[data-testid="preview-content"]')).maxWidth === "500px");
      const box = await content.boundingBox();
      const container = await window.getByTestId("preview-container").boundingBox();
      assert.ok(box.width <= 500 && Math.abs((box.x - container.x) - (container.x + container.width - box.x - box.width)) < 20, "the document is centered");
      await openSettings(window);
      await window.getByTestId("preview-width-narrow").click();
      await window.waitForFunction(() => getComputedStyle(document.querySelector('[data-testid="preview-content"]')).maxWidth === "560px");
      assert.equal(await window.getByTestId("preview-width-input").count(), 0);
      await window.getByTestId("preview-width-full").click();
      await window.waitForFunction(() => getComputedStyle(document.querySelector('[data-testid="preview-content"]')).maxWidth !== "560px");
    } finally {
      await fence.close();
    }
  });

  test("hiding pane headings removes them and persists across a restart", async () => {
    const first = await launchFence();
    let userDataDir;
    try {
      const { window } = first;
      userDataDir = first.userDataDir;
      await window.getByTestId("editor-header").waitFor();
      await openSettings(window);
      await window.getByTestId("pane-headers-toggle").click();
      await window.getByTestId("editor-header").waitFor({ state: "hidden" });
    } finally {
      await first.close({ keepUserData: true });
    }

    const second = await launchFence({ userDataDir });
    try {
      await second.window.getByTestId("veditor").waitFor();
      assert.equal(await second.window.getByTestId("editor-header").isVisible(), false);
    } finally {
      await second.close();
    }
  });

  test("the open-folder button lives in the title bar, not the sidebar", async () => {
    const fence = await launchFence();
    try {
      const { window } = fence;
      await window.getByTestId("titlebar").getByTestId("open-folder-button").waitFor();
      assert.equal(await window.getByTestId("sidebar").getByTestId("open-folder-button").count(), 0);
    } finally {
      await fence.close();
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

test("hovering a setting shows its tooltip and title bar buttons describe themselves", async () => {
  const fence = await launchFence();
  try {
    const { window } = fence;
    await openSettings(window);
    const label = window.locator('[aria-describedby="tip-pane-headers-toggle"]');
    await label.hover();
    await window.locator("#tip-pane-headers-toggle").waitFor({ state: "visible" });
    await label.click();
    await window.locator("#tip-pane-headers-toggle").waitFor({ state: "hidden" });

    const split = window.getByTestId("layout-split");
    assert.equal(await split.getAttribute("title"), null, "the native title must be gone");
    assert.equal(await split.getAttribute("aria-describedby"), "tip-layout-split");
    assert.match(await window.locator("#tip-layout-split").textContent(), /Editor and preview/);
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
