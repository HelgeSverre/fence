const assert = require("node:assert/strict");
const { test, describe } = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const { launchFence, setEditorContent, openSettings } = require("./helpers");

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

  test("C and C++ fenced code blocks are syntax highlighted", async () => {
    const fence = await launchFence();
    try {
      const { window } = fence;
      await setEditorContent(
        window,
        "```c\n#include <stdio.h>\ntypedef struct { uint32_t len; } Row;\nint main(void) { return 0; }\n```\n\n" +
          "```cpp\nclass Widget final : public Base {\npublic:\n    explicit Widget(int n) noexcept : n_(n) {}\n};\n```\n",
      );
      const blocks = window.getByTestId("preview-content").locator(".md-code-block");
      await blocks.first().waitFor();
      assert.equal(await blocks.count(), 2);
      // A highlighter that recognized nothing (the old Kotlin fallback for
      // c/cpp) would still wrap tokens, so check the actual C/C++ keywords
      // and the preprocessor directive got a real, non-default style class.
      assert.ok(await blocks.nth(0).locator("span.elmsh3", { hasText: "typedef" }).count());
      assert.ok(await blocks.nth(0).locator("span.elmsh3", { hasText: "#include <stdio.h>" }).count());
      assert.ok(await blocks.nth(1).locator("span.elmsh3", { hasText: "class" }).count());
      assert.match(await blocks.nth(0).textContent(), /typedef struct \{ uint32_t len; \} Row;/);
      assert.match(await blocks.nth(1).textContent(), /explicit Widget\(int n\) noexcept : n_\(n\) \{\}/);
    } finally {
      await fence.close();
    }
  });

  test("a table wider than the pane scrolls instead of being clipped", async () => {
    const row = (cell) => `| ${Array.from({ length: 30 }, (_, i) => `${cell}${i + 1}`).join(" | ")} |`;
    const wide = [row("col"), `| ${Array.from({ length: 30 }, () => "---").join(" | ")} |`, row("v")].join("\n");
    const fence = await launchFence();
    try {
      const { window } = fence;
      await setEditorContent(window, `| A | B |\n| --- | --- |\n| 1 | 2 |\n\n${wide}\n`);
      const preview = window.getByTestId("preview-content");
      await preview.locator(".md-table-scroll").first().waitFor();
      const state = await preview.evaluate((el) => {
        const [narrow, wideTable] = el.querySelectorAll(".md-table-scroll");
        wideTable.scrollLeft = 99999;
        return {
          narrowScrolls: narrow.scrollWidth > narrow.clientWidth + 1,
          wideScrolls: wideTable.scrollWidth > wideTable.clientWidth + 1,
          scrolledTo: Math.round(wideTable.scrollLeft),
          maxScroll: Math.round(wideTable.scrollWidth - wideTable.clientWidth),
          focusable: wideTable.getAttribute("tabindex"),
          // the pane itself must not be dragged wider by the table
          paneOverflows: el.scrollWidth > el.clientWidth + 1,
        };
      });
      assert.equal(state.narrowScrolls, false, "a table that fits must not become a scroll region");
      assert.equal(state.wideScrolls, true, "a wide table must scroll");
      assert.equal(state.scrolledTo, state.maxScroll, "the full width must be reachable");
      assert.equal(state.focusable, "0", "the scroll region must be keyboard reachable");
      assert.equal(state.paneOverflows, false, "the pane must not overflow horizontally");
    } finally {
      await fence.close();
    }
  });

  test("a mermaid diagram expands to fill the preview pane and Escape closes it", async () => {
    const fence = await launchFence();
    try {
      const { window } = fence;
      await setEditorContent(window, "```mermaid\nflowchart LR\n  A[One] --> B[Two]\n```\n");
      const preview = window.getByTestId("preview-content");
      await preview.locator(".mermaid[data-state=rendered]").waitFor({ timeout: 20000 });
      const button = preview.locator(".mermaid-fullscreen-btn");
      await button.waitFor();

      // Revealed on hover, not permanently on screen.
      assert.equal(await button.evaluate((b) => getComputedStyle(b).opacity), "0");
      await preview.locator(".mermaid").hover();
      await window.waitForFunction(() => getComputedStyle(document.querySelector(".mermaid-fullscreen-btn")).opacity === "1");

      await button.click();
      await window.waitForFunction(() => document.querySelector("#mermaid-fullscreen")?.matches(":popover-open"));
      const open = await window.evaluate(() => {
        const overlay = document.querySelector("#mermaid-fullscreen");
        const pane = document.querySelector(".preview-pane").getBoundingClientRect();
        const box = overlay.getBoundingClientRect();
        return {
          isOpen: overlay.matches(":popover-open"),
          coversPane: Math.abs(box.width - pane.width) < 2 && Math.abs(box.height - pane.height) < 2,
          hasDiagram: !!overlay.querySelector("svg"),
          focused: document.activeElement?.className,
        };
      });
      assert.equal(open.isOpen, true);
      assert.equal(open.coversPane, true, "the overlay must cover the preview pane");
      assert.equal(open.hasDiagram, true);
      assert.match(open.focused, /mermaid-fullscreen-close/, "focus must move into the overlay");

      await window.keyboard.press("Escape");
      await window.waitForFunction(() => !document.querySelector("#mermaid-fullscreen").matches(":popover-open"));
      // Escape must not also reach Elm's document-level handler.
      assert.equal(await window.getByTestId("settings-dropdown").count(), 0);
      assert.equal(await window.evaluate(() => !!document.querySelector("#mermaid-fullscreen svg")), false, "the clone must be released");
    } finally {
      await fence.close();
    }
  });

  test("an expanded diagram zooms and pans, and resets", async () => {
    const fence = await launchFence();
    try {
      const { window } = fence;
      await setEditorContent(window, "```mermaid\nflowchart LR\n  A[One] --> B[Two] --> C[Three]\n```\n");
      const preview = window.getByTestId("preview-content");
      await preview.locator(".mermaid[data-state=rendered]").waitFor({ timeout: 20000 });
      await preview.locator(".mermaid").hover();
      await preview.locator(".mermaid-fullscreen-btn").click();
      await window.waitForFunction(() => document.querySelector("#mermaid-fullscreen")?.matches(":popover-open"));

      const view = () => window.evaluate(() => ({
        transform: document.querySelector("#mermaid-fullscreen svg").style.transform,
        label: document.querySelector(".mermaid-fullscreen-level").textContent,
      }));
      assert.deepEqual(await view(), { transform: "translate(0px, 0px) scale(1)", label: "100%" });

      await window.locator(".mermaid-fullscreen-zoom[aria-label='Zoom in']").click();
      assert.equal((await view()).label, "125%", "the zoom button must zoom in");

      await window.keyboard.press("ArrowRight");
      assert.match((await view()).transform, /translate\(-40px, 0px\)/, "arrow keys must pan");

      await window.keyboard.press("0");
      assert.deepEqual(await view(), { transform: "translate(0px, 0px) scale(1)", label: "100%" }, "0 must reset");

      // Drag to pan, then double-click to reset.
      const box = await window.locator(".mermaid-fullscreen-figure").boundingBox();
      const [cx, cy] = [box.x + box.width / 2, box.y + box.height / 2];
      await window.mouse.move(cx, cy);
      await window.mouse.down();
      await window.mouse.move(cx + 100, cy + 50, { steps: 5 });
      await window.mouse.up();
      assert.match((await view()).transform, /translate\(100px, 50px\)/, "dragging must pan by the cursor delta");

      await window.mouse.dblclick(cx, cy);
      assert.equal((await view()).transform, "translate(0px, 0px) scale(1)", "double-click must reset");
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
      await openSettings(window);
      await window.getByTestId("settings-picker-theme").click();
      await window.getByTestId("settings-option-theme-light").click();
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
