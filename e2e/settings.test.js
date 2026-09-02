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
