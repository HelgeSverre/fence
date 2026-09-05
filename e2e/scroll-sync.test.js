const assert = require("node:assert/strict");
const { test, describe } = require("node:test");
const { launchFence } = require("./helpers");

// A document tall enough that both panes scroll well past their last screen,
// with headings spread through it. Each body line is its own paragraph, so the
// preview is tall rather than a few wrapped blocks.
const section = (n) => `## Section ${n}\n\n${Array.from({ length: 12 }, (_, i) => `Body line ${n}.${i}`).join("\n\n")}\n\n`;
const doc = `# Top\n\nIntro paragraph.\n\n${Array.from({ length: 8 }, (_, i) => section(i + 1)).join("")}`;

const previewTop = (window) => window.evaluate(() => document.querySelector("#preview-container").scrollTop);

async function scrollEditorTo(window, top) {
  await window.evaluate((y) => {
    document.querySelector("[data-testid=veditor]").scrollTop = y;
  }, top);
}

describe("scroll sync", () => {
  test("scrolling the editor moves the preview to the same place, and back", async () => {
    const fence = await launchFence({ files: { "note.md": doc }, open: "note.md" });
    try {
      const { window } = fence;
      await window.getByTestId("preview-content").waitFor();
      assert.equal(await previewTop(window), 0);

      await scrollEditorTo(window, 2000);
      const deep = await window.waitForFunction(
        () => {
          const top = document.querySelector("#preview-container").scrollTop;
          return top > 100 ? top : false;
        },
        undefined,
        { timeout: 10000 },
      );
      assert.ok((await deep.jsonValue()) > 100);

      await scrollEditorTo(window, 0);
      await window.waitForFunction(() => document.querySelector("#preview-container").scrollTop < 20, undefined, { timeout: 10000 });
    } finally {
      await fence.close();
    }
  });

  test("the preview lands on the heading the editor's top line sits under", async () => {
    const fence = await launchFence({ files: { "note.md": doc }, open: "note.md" });
    try {
      const { window } = fence;
      await window.getByTestId("preview-content").waitFor();

      const line = doc.split("\n").indexOf("## Section 5");
      const lineHeight = await window.evaluate(() => parseFloat(document.querySelector(".veditor-row")?.style.height) || 22.4);
      await scrollEditorTo(window, line * lineHeight);

      await window.waitForFunction(
        () => {
          const container = document.querySelector("#preview-container");
          const heading = document.getElementById("section-5");
          if (!heading) return false;
          // the heading sits at the top of the preview's viewport
          return Math.abs(heading.getBoundingClientRect().top - container.getBoundingClientRect().top) < 24;
        },
        undefined,
        { timeout: 10000 },
      );
    } finally {
      await fence.close();
    }
  });

  test("scrolling the preview alone does not move the editor", async () => {
    const fence = await launchFence({ files: { "note.md": doc }, open: "note.md" });
    try {
      const { window } = fence;
      await window.getByTestId("preview-content").waitFor();
      await window.evaluate(() => {
        document.querySelector("#preview-container").scrollTop = 500;
      });
      await new Promise((resolve) => setTimeout(resolve, 500));
      assert.equal(await window.evaluate(() => document.querySelector("[data-testid=veditor]").scrollTop), 0);
    } finally {
      await fence.close();
    }
  });
});
