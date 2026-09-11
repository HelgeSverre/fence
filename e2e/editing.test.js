const assert = require("node:assert/strict");
const { test, describe } = require("node:test");
const { launchFence, setEditorContent, waitForEditorValue, waitForFile, sendFromElm, save } = require("./helpers");

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
      await waitForEditorValue(window, "# From outside\n", 10000);
      await window.getByTestId("preview-content").locator("h1", { hasText: "From outside" }).waitFor();
    } finally {
      await fence.close();
    }
  });

  test("a delayed notification of our save preserves visible rows, caret, and undo", async () => {
    const source = Array.from({ length: 500 }, (_, i) => `Line ${i}: editable text.`).join("\n");
    const fence = await launchFence({ files: { "note.md": source } });
    try {
      const { window, app } = fence;
      await window.locator(".veditor").evaluate(el => { el.scrollTop = 7000; });
      await window.waitForFunction(() => Number(document.querySelector(".veditor-row").dataset.sourceLine) > 100);
      const box = await window.locator(".veditor").boundingBox();
      await window.mouse.click(box.x + 130, box.y + 120);
      await window.keyboard.insertText("EDIT");
      await window.getByTestId("titlebar-filename").filter({ hasText: "*" }).waitFor();
      const before = await editorViewport(window);
      await save(window);
      await window.getByTestId("titlebar-filename").filter({ hasText: /^note\.md$/ }).waitFor();
      await window.evaluate(() => {
        window.reloadReceived = false;
        window.stopReloadListener = window.electronAPI.onMessage(data => {
          if (data.tag === "fileContent" || data.tag === "fileReloaded") window.reloadReceived = true;
        });
      });
      // Replay a real watcher event AFTER the save acknowledgement, removing
      // the platform-dependent timing that normally makes this intermittent.
      await sendFromElm(app, { tag: "fsEvent", event: "change", path: fence.file("note.md") });
      await window.waitForFunction(() => window.reloadReceived);
      await window.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
      const after = await editorViewport(window);
      assert.ok(after.visibleRows > 0, `Editor blank after save: ${JSON.stringify(after)}`);
      assert.deepEqual(after, before);
      await window.keyboard.press("Meta+z");
      await waitForEditorValue(window, source);
      await window.evaluate(() => window.stopReloadListener());
    } finally { await fence.close(); }
  });

  test("external reloads preserve the viewport and clamp it when the file shrinks", async () => {
    const fs = require("node:fs/promises");
    const source = Array.from({ length: 500 }, (_, i) => `Line ${i}: original text.`).join("\n");
    const fence = await launchFence({ files: { "note.md": source } });
    try {
      const { window } = fence;
      await window.locator(".veditor").evaluate(el => { el.scrollTop = 7000; });
      await window.waitForFunction(() => Number(document.querySelector(".veditor-row").dataset.sourceLine) > 100);
      const before = await editorViewport(window);
      const changed = source.replaceAll("original", "modified");
      await fs.writeFile(fence.file("note.md"), changed);
      await window.waitForFunction(() => document.querySelector(".veditor-row").textContent.includes("modified"));
      assert.deepEqual(await editorViewport(window), before);
      await fs.writeFile(fence.file("note.md"), "# Short\n");
      await waitForEditorValue(window, "# Short\n");
      await window.waitForFunction(() => document.querySelector(".veditor").scrollTop === 0);
      assert.ok((await editorViewport(window)).visibleRows > 0);
    } finally { await fence.close(); }
  });


  test("opening another long file synchronizes the browser and virtual scroll positions", async () => {
    const source = "first file line\n".repeat(500);
    const other = "second file line\n".repeat(500);
    const fence = await launchFence({ files: { "note.md": source, "other.md": other } });
    try {
      const { window } = fence;
      await window.locator(".veditor").evaluate(el => { el.scrollTop = 7000; });
      await window.waitForFunction(() => Number(document.querySelector(".veditor-row").dataset.sourceLine) > 100);
      await window.evaluate(path => window.electronAPI.readFile({ path }), fence.file("other.md"));
      await waitForEditorValue(window, other);
      await window.waitForFunction(() => document.querySelector(".veditor").scrollTop === 0);
      const viewport = await editorViewport(window);
      assert.equal(viewport.rowsTop, "0px");
      assert.ok(viewport.visibleRows > 0);
    } finally { await fence.close(); }
  });


  for (const softWrap of [true, false]) {
    test(`external truncation moves a deleted caret to EOF and remains editable (wrap=${softWrap})`, async () => {
      const fs = require("node:fs/promises");
      const source = "original line\n".repeat(500) + "x";
      const half = "original line\n".repeat(249) + "a longer final line " + "tail ".repeat(60);
      const fence = await launchFence({ files: { "note.md": source }, state: { softWrap } });
      try {
        const { window } = fence;
        await window.locator(".veditor").click({ position: { x: 100, y: 100 } });
        await window.keyboard.press("Meta+ArrowDown");
        await window.waitForFunction(() => Number(document.querySelector(".veditor-row").dataset.sourceLine) > 400);
        await fs.writeFile(fence.file("note.md"), half);
        await waitForEditorValue(window, half);
        await window.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
        assert.ok((await editorViewport(window)).visibleRows > 0);
        assert.ok(await window.locator(".veditor-caret").evaluate(caret => {
          const box = caret.closest(".veditor").getBoundingClientRect();
          const rect = caret.getBoundingClientRect();
          return rect.top >= box.top && rect.bottom <= box.bottom && rect.left >= box.left && rect.right <= box.right;
        }), "Clamped caret should remain visible");
        await window.keyboard.insertText("APPEND");
        await save(window);
        await waitForFile(fence.file("note.md"), half + "APPEND");
        await window.getByTestId("titlebar-filename").filter({ hasText: /^note\.md$/ }).waitFor();
        await fs.writeFile(fence.file("note.md"), "");
        await waitForEditorValue(window, "");
        await window.waitForFunction(() => document.querySelector(".veditor").scrollTop === 0);
        await window.keyboard.insertText("New text");
        await save(window);
        await waitForFile(fence.file("note.md"), "New text");
      } finally { await fence.close(); }
    });
  }

});


async function editorViewport(window) {
  return window.evaluate(() => {
    const editor = document.querySelector(".veditor");
    const box = editor.getBoundingClientRect();
    const caret = document.querySelector(".veditor-caret");
    return {
      scrollTop: editor.scrollTop,
      rowsTop: document.querySelector(".veditor-rows").style.top,
      caretTop: caret.style.top,
      caretLeft: caret.style.left,
      visibleRows: [...document.querySelectorAll(".veditor-row")].filter(row => {
        const rect = row.getBoundingClientRect();
        return rect.bottom > box.top && rect.top < box.bottom;
      }).length,
    };
  });
}
