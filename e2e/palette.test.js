const assert = require("node:assert/strict");
const { test, describe } = require("node:test");
const { MOD, launchFence, waitForEditorValue } = require("./helpers");

const files = {
  "a.md": "# A\nalpha here\n",
  "b.md": "# B\nbeta here\n",
  "docs/plan.md": "# Plan\nalpha again\n",
};

const rows = (window) => window.getByTestId("palette-row").allTextContents();

describe("command palette", () => {
  test("quick-open lists every markdown file and filters as you type", async () => {
    const fence = await launchFence({ files, open: "a.md" });
    try {
      const { window } = fence;
      await window.keyboard.press(`${MOD}+p`);
      await window.getByTestId("palette-input").waitFor();
      await window.waitForFunction(() => document.querySelectorAll("[data-testid=palette-row]").length === 3, undefined, { timeout: 10000 });

      await window.getByTestId("palette-input").fill("plan");
      await window.waitForFunction(() => document.querySelectorAll("[data-testid=palette-row]").length === 1);
      assert.match((await rows(window))[0], /plan\.md/);
    } finally {
      await fence.close();
    }
  });

  test("Enter opens the highlighted file", async () => {
    const fence = await launchFence({ files, open: "a.md" });
    try {
      const { window } = fence;
      await window.keyboard.press(`${MOD}+p`);
      await window.getByTestId("palette-input").fill("b.md");
      await window.waitForFunction(() => document.querySelectorAll("[data-testid=palette-row]").length === 1);
      await window.keyboard.press("Enter");
      await waitForEditorValue(window, "# B\nbeta here\n");
      await window.getByTestId("palette").waitFor({ state: "detached" });
    } finally {
      await fence.close();
    }
  });

  test("arrow keys move the highlight", async () => {
    const fence = await launchFence({ files, open: "a.md" });
    try {
      const { window } = fence;
      await window.keyboard.press(`${MOD}+p`);
      await window.waitForFunction(() => document.querySelectorAll("[data-testid=palette-row]").length === 3, undefined, { timeout: 10000 });
      await window.keyboard.press("ArrowDown");
      await window.waitForFunction(() => document.querySelectorAll("[data-testid=palette-row]")[1]?.classList.contains("active"));
      await window.keyboard.press("ArrowUp");
      await window.waitForFunction(() => document.querySelectorAll("[data-testid=palette-row]")[0]?.classList.contains("active"));
    } finally {
      await fence.close();
    }
  });

  test("workspace search finds matching lines and opens one at its line", async () => {
    const fence = await launchFence({ files, open: "b.md" });
    try {
      const { window } = fence;
      await window.keyboard.press(`${MOD}+Shift+f`);
      await window.getByTestId("palette-input").waitFor();
      await window.getByTestId("palette-input").fill("alpha");
      await window.waitForFunction(() => document.querySelectorAll("[data-testid=palette-row]").length === 2, undefined, { timeout: 10000 });

      const labels = await rows(window);
      assert.ok(labels.some((l) => l.includes("a.md:2")), labels.join(" | "));

      await window.keyboard.press("Enter");
      await waitForEditorValue(window, "# A\nalpha here\n");
      // opened at the hit: the caret sits on line 2
      await window.waitForFunction(() => {
        const caret = document.querySelector("[data-testid=veditor-caret]");
        return caret && Math.round(parseFloat(caret.style.top)) > 0;
      });
    } finally {
      await fence.close();
    }
  });

  test("Escape closes the palette", async () => {
    const fence = await launchFence({ files, open: "a.md" });
    try {
      const { window } = fence;
      await window.keyboard.press(`${MOD}+p`);
      await window.getByTestId("palette-input").waitFor();
      await window.keyboard.press("Escape");
      await window.getByTestId("palette").waitFor({ state: "detached" });
    } finally {
      await fence.close();
    }
  });

  test("back and forward walk the recently opened files", async () => {
    const fence = await launchFence({ files, open: "a.md" });
    try {
      const { window } = fence;
      await window.getByTestId("tree-file").filter({ hasText: "b.md" }).click();
      await waitForEditorValue(window, "# B\nbeta here\n");

      await window.keyboard.press(`${MOD}+[`);
      await waitForEditorValue(window, "# A\nalpha here\n");
      await window.keyboard.press(`${MOD}+]`);
      await waitForEditorValue(window, "# B\nbeta here\n");
    } finally {
      await fence.close();
    }
  });

  test("the outline pane reports the document's counts", async () => {
    const fence = await launchFence({ files, open: "a.md" });
    try {
      await fence.window.waitForFunction(
        () => document.querySelector("[data-testid=word-count]")?.textContent === "4 words · 3 lines · 15 characters",
        undefined,
        { timeout: 10000 },
      );
    } finally {
      await fence.close();
    }
  });
});
