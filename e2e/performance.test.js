const { test, describe } = require("node:test");
const { withFence, setEditorContent, waitForFile, save } = require("./helpers");

describe("performance", () => {
  test("a 300KB document is inserted, previewed, and saved without stalling", async () => {
    await withFence({}, async (fence) => {
      const { window } = fence;
      const content = `# Large Document\n\n${"word ".repeat(60000)}`;
      await setEditorContent(window, content);
      await window.getByTestId("preview-content").locator("h1").filter({ hasText: "Large Document" }).waitFor();
      await save(window);
      await waitForFile(fence.file("note.md"), content);
    });
  });
});
