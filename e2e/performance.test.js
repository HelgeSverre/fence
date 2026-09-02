const assert = require("node:assert/strict");
const { test, describe } = require("node:test");
const { launchFence, waitForFile, save } = require("./helpers");

describe("performance", () => {
  test("a 300KB document loads into the editor, previews, and saves without stalling", async () => {
    const fence = await launchFence();
    try {
      const { window } = fence;
      const content = `# Large Document\n\n${"word ".repeat(60000)}`;
      const renderMs = await window.getByTestId("editor-textarea").evaluate(async (element, value) => {
        Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, "value").set.call(element, value);
        const started = performance.now();
        element.dispatchEvent(new Event("input", { bubbles: true }));
        await new Promise((resolve) => requestAnimationFrame(resolve));
        await new Promise((resolve) => requestAnimationFrame(resolve));
        return performance.now() - started;
      }, content);
      assert.ok(renderMs < 1500, `large-document input render took ${renderMs}ms`);

      await window.getByTestId("preview-content").locator("h1", { hasText: "Large Document" }).waitFor();
      await save(window);
      await waitForFile(fence.file("note.md"), content);
    } finally {
      await fence.close();
    }
  });

  test("keystrokes in a large document stay under a frame", async () => {
    const fence = await launchFence();
    try {
      const { window } = fence;
      const lines = Array.from({ length: 4000 }, (_, i) => `- item ${i} with some **bold** text and \`code\``);
      const editor = window.getByTestId("editor-textarea");
      await editor.evaluate((element, value) => {
        Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, "value").set.call(element, value);
        element.dispatchEvent(new Event("input", { bubbles: true }));
      }, lines.join("\n"));
      await window.getByTestId("preview-content").locator("li", { hasText: "item 3999" }).waitFor();

      const medianMs = await editor.evaluate((element) => {
        element.focus();
        element.setSelectionRange(1000, 1000);
        const samples = [];
        for (let i = 0; i < 5; i++) {
          document.body.offsetHeight;
          const t = performance.now();
          document.execCommand("insertText", false, "x");
          document.body.offsetHeight;
          samples.push(performance.now() - t);
        }
        return samples.sort((a, b) => a - b)[2];
      });
      assert.ok(medianMs < 16, `median keystroke cost ${medianMs.toFixed(1)}ms`);
    } finally {
      await fence.close();
    }
  });
});
