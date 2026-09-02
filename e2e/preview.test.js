const assert = require("node:assert/strict");
const { test, describe } = require("node:test");
const { launchFence, setEditorContent } = require("./helpers");

describe("preview", () => {
  test("headings get anchor ids and repeated headings are disambiguated", async () => {
    const fence = await launchFence();
    try {
      const { window } = fence;
      await setEditorContent(window, "# Added\n\ntext\n\n## Added\n\n# Fixed\n");
      const preview = window.getByTestId("preview-content");
      await preview.locator("h1#fixed").waitFor();
      assert.equal(await preview.locator("h1#added").count(), 1);
      assert.equal(await preview.locator("h2#added-1").count(), 1);
    } finally {
      await fence.close();
    }
  });

  test("the outline lists headings and clicking one scrolls the preview to it", async () => {
    const fence = await launchFence();
    try {
      const { window } = fence;
      const sections = Array.from({ length: 40 }, (_, i) => `## Section ${i}\n\n${"filler text ".repeat(40)}\n`);
      await setEditorContent(window, `# Top\n\n${sections.join("\n")}`);
      await window.getByTestId("preview-content").locator("h2#section-39").waitFor();

      await window.keyboard.press("Meta+3"); // default right-sidebar toggle
      await window.getByTestId("outline-pane").waitFor();
      assert.equal(await window.getByTestId("outline-entry").count(), 41);

      const container = window.getByTestId("preview-container");
      assert.equal(await container.evaluate((el) => el.scrollTop), 0);
      await window.getByTestId("outline-entry").filter({ hasText: "Section 39" }).click();
      await window.waitForFunction(
        () => document.querySelector("[data-testid=preview-container]").scrollTop > 1000,
        undefined,
        { timeout: 5000 },
      );
    } finally {
      await fence.close();
    }
  });

  test("fenced code blocks are syntax highlighted", async () => {
    const fence = await launchFence();
    try {
      const { window } = fence;
      await setEditorContent(window, "```js\nconst x = 1;\n```\n");
      const block = window.getByTestId("preview-content").locator(".md-code-block");
      await block.waitFor();
      // The highlighter wraps tokens in spans; plain text would have none.
      assert.ok((await block.locator("span").count()) > 1);
      assert.match(await block.textContent(), /const x = 1;/);
    } finally {
      await fence.close();
    }
  });

  test("mermaid blocks render to an SVG diagram", async () => {
    const fence = await launchFence();
    try {
      const { window } = fence;
      await setEditorContent(window, "```mermaid\ngraph TD\n  A --> B\n```\n");
      await window.getByTestId("preview-content").locator("pre.mermaid svg").waitFor({ timeout: 15000 });
    } finally {
      await fence.close();
    }
  });
});
