const assert = require("node:assert/strict");
const { test, describe } = require("node:test");
const { launchFence, setEditorContent, waitForFile, save } = require("./helpers");

describe("editing and saving", () => {
  test("typing updates the preview after the debounce", async () => {
    const fence = await launchFence();
    try {
      const { window } = fence;
      await setEditorContent(window, "# Hello\n\nSome **bold** and a [link](https://example.com).\n");
      const preview = window.getByTestId("preview-content");
      await preview.locator("h1", { hasText: "Hello" }).waitFor();
      await preview.locator("strong", { hasText: "bold" }).waitFor();
      assert.equal(await preview.locator("a").getAttribute("href"), "https://example.com");
    } finally {
      await fence.close();
    }
  });

  test("edits mark the document dirty and saving writes the file and clears the marker", async () => {
    const fence = await launchFence();
    try {
      const { window } = fence;
      await setEditorContent(window, "# Changed\n");
      await window.getByTestId("titlebar-filename").filter({ hasText: "note.md *" }).waitFor();
      await window.getByTestId("editor-header").filter({ hasText: "note.md *" }).waitFor();

      await save(window);
      await waitForFile(fence.file("note.md"), "# Changed\n");
      await window.getByTestId("titlebar-filename").filter({ hasText: /^note\.md$/ }).waitFor();
    } finally {
      await fence.close();
    }
  });

  test("YAML frontmatter is shown as metadata instead of being rendered as text", async () => {
    const fence = await launchFence();
    try {
      const { window } = fence;
      await setEditorContent(window, "---\ntitle: Frontmatter Demo\ntags: [a, b]\n---\n\n# Body\n");
      const frontmatter = window.getByTestId("frontmatter");
      await frontmatter.waitFor();
      // The metadata block is a collapsed <details>, so check the DOM rather than visibility.
      assert.deepEqual(await frontmatter.locator("dt").allTextContents(), ["title", "tags"]);
      assert.match(await frontmatter.locator("dd").first().textContent(), /Frontmatter Demo/);
      assert.deepEqual(await frontmatter.locator(".fm-tag").allTextContents(), ["a", "b"]);
      await frontmatter.locator("summary").click();
      await frontmatter.locator("dt").first().waitFor();
      await window.getByTestId("preview-content").locator("h1", { hasText: "Body" }).waitFor();
      assert.ok(!(await window.getByTestId("preview-content").textContent()).includes("---"));
    } finally {
      await fence.close();
    }
  });

  test("a file changed on disk reloads when the editor has no unsaved changes", async () => {
    const fence = await launchFence();
    try {
      const { window } = fence;
      await require("node:fs").promises.writeFile(fence.file("note.md"), "# From outside\n", "utf-8");
      await window.waitForFunction(
        () => document.querySelector("[data-testid=editor-textarea]").value === "# From outside\n",
        undefined,
        { timeout: 10000 },
      );
      await window.getByTestId("preview-content").locator("h1", { hasText: "From outside" }).waitFor();
    } finally {
      await fence.close();
    }
  });
});
