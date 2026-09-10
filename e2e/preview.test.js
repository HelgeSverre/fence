const assert = require("node:assert/strict");
const { test, describe } = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const { launchFence, setEditorContent } = require("./helpers");

describe("preview", () => {
  test("the virtualized editor plan renders instead of showing the welcome screen", async () => {
    const source = fs.readFileSync(path.join(__dirname, "../docs/plans/2026-09-02-virtualized-editor.md"), "utf8");
    const fence = await launchFence({ files: { "plan.md": source }, open: "plan.md" });
    try {
      const preview = fence.window.getByTestId("preview-content");
      await preview.locator("h1#virtualized-editor-in-elm").waitFor();
      assert.match(await preview.innerText(), /<2ms of layout/);
      assert.equal(await preview.locator("h2").count(), 5);
      assert.equal(await fence.window.getByTestId("preview-welcome").count(), 0);
      assert.equal(fs.readFileSync(fence.file("plan.md"), "utf8"), source);
    } finally {
      await fence.close();
    }
  });

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
      await setEditorContent(window, "```mermaid\ngraph TD\n  A & B --> C\n```\n");
      const diagram = window.getByTestId("preview-content").locator('.mermaid[data-state="rendered"]');
      await diagram.locator("svg .node").first().waitFor({ timeout: 15000 });
      assert.equal(await diagram.locator("svg .node").count(), 3);
      assert.equal(await diagram.locator(".error-icon, .error-text").count(), 0);
      assert.match(await diagram.getAttribute("data-source"), /A & B --> C/);
    } finally {
      await fence.close();
    }
  });

  test("invalid Mermaid shows a safe error and source while neighboring diagrams render", async () => {
    const invalid = 'graph TD\n A[unfinished\n <img src=x onerror="window.mermaidInjected=true">\n';
    const source = `\`\`\`mermaid\n${invalid}\`\`\`\n\n\`\`\`mermaid\ngraph TD\n X --> Y\n\`\`\`\n`;
    const fence = await launchFence({ files: { "note.md": source } });
    try {
      const { window } = fence;
      const error = window.locator('.mermaid[data-state="error"]');
      await error.locator(".mermaid-error-title").waitFor();
      assert.equal(await error.locator(".mermaid-error-title").textContent(), "Couldn’t render diagram");
      assert.match(await error.locator(".mermaid-error-message").textContent(), /Parse error|Lexical error/);
      assert.equal(await error.locator("details").getAttribute("open"), null);
      await error.locator("summary").click();
      assert.equal(await error.locator(".mermaid-source").textContent(), invalid);
      assert.equal(await error.locator("img, script, svg").count(), 0);
      assert.equal(await window.evaluate(() => window.mermaidInjected), undefined);
      const valid = window.locator('.mermaid[data-state="rendered"]');
      await valid.locator("svg .node").first().waitFor();
      assert.equal(await valid.locator("svg .node").count(), 2);
      assert.equal(await window.locator("svg .error-icon, svg .error-text").count(), 0);

      const previousId = await valid.locator("svg").getAttribute("id");
      await window.getByTestId("settings-button").click();
      await window.getByTestId("settings-item-light").click();
      await window.waitForFunction((id) => {
        const svg = document.querySelector('.mermaid[data-state="rendered"] svg');
        return svg && svg.id !== id;
      }, previousId);
      await error.locator(".mermaid-error-title").waitFor();
      assert.equal(await error.locator(".mermaid-source").textContent(), invalid);
    } finally {
      await fence.close();
    }
  });

  test("editing Mermaid recovers from errors and updates an existing diagram", async () => {
    const fence = await launchFence({ files: { "note.md": "```mermaid\ngraph TD\n A[unfinished\n```\n" } });
    try {
      const { window } = fence;
      await window.locator('.mermaid[data-state="error"]').waitFor();
      await setEditorContent(window, "```mermaid\ngraph TD\n A & B --> Fixed\n```\n");
      await window.locator('.mermaid[data-state="rendered"] svg .node').filter({ hasText: "Fixed" }).waitFor();
      assert.equal(await window.locator(".mermaid-error-title").count(), 0);
      await setEditorContent(window, "```mermaid\ngraph TD\n A --> Updated\n```\n");
      await window.locator('.mermaid[data-state="rendered"] svg .node').filter({ hasText: "Updated" }).waitFor();
      assert.equal(await window.locator(".mermaid svg .node").count(), 2);
      await setEditorContent(window, "```mermaid\ngraph TD\n A[broken again\n```\n");
      await window.locator('.mermaid[data-state="error"]').waitFor();
      assert.equal(await window.locator(".mermaid svg").count(), 0);
      assert.match(await window.locator(".mermaid-source").textContent(), /broken again/);
    } finally {
      await fence.close();
    }
  });

});
