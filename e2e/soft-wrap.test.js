const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const { test, describe } = require("node:test");
const { launchFence, focusEditor, save, waitForFile, MOD } = require("./helpers");

async function rows(window) {
  return window.locator(".veditor-row").evaluateAll((items) => items.map((row) => ({
    line: Number(row.dataset.sourceLine), start: Number(row.dataset.sourceStart),
    end: Number(row.dataset.sourceEnd), text: row.dataset.sourceText, painted: row.textContent,
  })));
}

async function toggle(window) {
  await window.getByTestId("settings-button").click();
  await window.getByTestId("soft-wrap-toggle").click();
  await window.locator(".settings-backdrop").click({ position: { x: 10, y: 100 } });
}

async function caret(window) {
  return window.getByTestId("veditor-caret").evaluate((el) => ({ x: parseFloat(el.style.left), y: parseFloat(el.style.top), h: parseFloat(el.style.height) }));
}

describe("soft wrap", () => {
  test("screen-row navigation, selection, replacement and undo preserve source text", async () => {
    const content = "one two three four five six seven eight nine ten ".repeat(4);
    const fence = await launchFence({ files: { "note.md": content } });
    try {
      const { window } = fence;
      await focusEditor(window);
      const rendered = await rows(window);
      assert.ok(rendered.length > 2);
      assert.equal(rendered.map((r) => r.text).join(""), content);
      assert.equal(rendered.map((r) => r.painted).join(""), content, "painted fragments preserve the text");
      const boundary = rendered[0].end;
      await window.keyboard.press("End");
      await window.waitForFunction(() => parseFloat(document.querySelector(".veditor-caret").style.left) > 20);
      const end = await caret(window);
      assert.equal(end.y, 0, "End stays on the first screen row");
      await window.keyboard.press("ArrowRight");
      await window.keyboard.press("Home");
      await window.waitForFunction(() => {
        const caret = document.querySelector(".veditor-caret");
        return parseFloat(caret.style.left) === 0 && parseFloat(caret.style.top) >= parseFloat(caret.style.height);
      });
      assert.ok((await caret(window)).y >= end.h, "Home lands at the next screen row start");
      await window.keyboard.press(`${MOD}+Home`);
      await window.keyboard.press("End");
      await window.keyboard.press("Shift+ArrowRight");
      await window.waitForFunction(() => document.querySelector(".veditor-input").dataset.selection.length === 1);
      assert.equal(await window.locator(".veditor-input").getAttribute("data-selection"), content.slice(boundary, boundary + 1));
      await window.keyboard.insertText("X");
      await save(window);
      await waitForFile(fence.file("note.md"), content.slice(0, boundary) + "X" + content.slice(boundary + 1));
      await window.keyboard.press(`${MOD}+z`);
      await save(window);
      await waitForFile(fence.file("note.md"), content);
    } finally { await fence.close(); }
  });

  test("clicking a continuation row edits that source offset, including tabs and syntax spans", async () => {
    const content = "alpha **bold** `code` [link](somewhere) \t".repeat(8);
    const fence = await launchFence({ files: { "note.md": content } });
    try {
      const { window } = fence;
      const rendered = await rows(window);
      let column = 0;
      const expanded = [...content].map((char) => {
        const width = char === "\t" ? 2 - column % 2 : 1;
        column += width;
        return char === "\t" ? " ".repeat(width) : char;
      }).join("");
      assert.equal(rendered.map((r) => r.painted).join(""), expanded, "syntax fragments keep logical tab stops");
      const box = await window.locator(".veditor-spacer").boundingBox();
      const h = (await caret(window)).h;
      await window.mouse.click(box.x + 1, box.y + h * 2 + h / 2);
      await window.keyboard.insertText("HERE");
      await save(window);
      await waitForFile(fence.file("note.md"), content.slice(0, rendered[2].start) + "HERE" + content.slice(rendered[2].start));
      const extent = await window.getByTestId("veditor").evaluate((el) => ({ scroll: el.scrollWidth, width: el.clientWidth, left: el.scrollLeft }));
      assert.equal(extent.left, 0);
      assert.ok(extent.scroll <= extent.width + 1);
    } finally { await fence.close(); }
  });

  test("search highlights cross a soft break and IME commits at the wrapped caret", async () => {
    const content = Array.from({ length: 40 }, (_, i) => `word${i}`).join(" ");
    const fence = await launchFence({ files: { "note.md": content } });
    try {
      const { window } = fence;
      const rendered = await rows(window);
      const boundary = rendered[0].end;
      const query = content.slice(boundary - 4, boundary + 5);
      await window.keyboard.press(`${MOD}+f`);
      await window.getByTestId("find-input").fill(query);
      await window.waitForFunction(() => document.querySelectorAll(".veditor-highlight.active").length === 2);
      await window.keyboard.press("Escape");
      // Commit IME input through the same compositionend event used by the editor.
      await window.locator(".veditor-input").evaluate((input) => {
        input.dispatchEvent(new CompositionEvent("compositionstart", { bubbles: true }));
        input.value = "日本";
        input.dispatchEvent(new InputEvent("input", { data: "日本", isComposing: true, bubbles: true }));
        input.dispatchEvent(new CompositionEvent("compositionend", { data: "日本", bubbles: true }));
      });
      await save(window);
      await waitForFile(fence.file("note.md"), content.replace(query, "日本"));
    } finally { await fence.close(); }
  });

  test("font size changes reflow the rows and keep the caret inside the viewport", async () => {
    const content = "some words to wrap at different font sizes ".repeat(20);
    const fence = await launchFence({ files: { "note.md": content } });
    try {
      const { window } = fence;
      await focusEditor(window);
      await window.keyboard.press("ArrowDown");
      const before = (await rows(window))[0].end;
      await window.getByTestId("settings-button").click();
      const editorSize = window.locator(".settings-dropdown-row").filter({ has: window.locator(".settings-dropdown-row-label", { hasText: /^Editor$/ }) }).locator("input");
      await editorSize.fill("22");
      await window.waitForFunction((oldEnd) => Number(document.querySelector(".veditor-row").dataset.sourceEnd) < oldEnd, before);
      const actual = await caret(window);
      const viewport = await window.getByTestId("veditor").evaluate((el) => ({ width: el.clientWidth, height: el.clientHeight, top: el.scrollTop }));
      assert.ok(actual.x < viewport.width && actual.y >= viewport.top && actual.y + actual.h <= viewport.top + viewport.height);
      assert.equal(await fs.readFile(fence.file("note.md"), "utf8"), content);
    } finally { await fence.close(); }
  });

  test("toggle persists across restart and does not dirty or rewrite the document", async () => {
    const content = "long source line ".repeat(50);
    const first = await launchFence({ files: { "note.md": content } });
    const userDataDir = first.userDataDir;
    try {
      assert.equal(await first.window.getByTestId("veditor").getAttribute("data-wrap"), "true");
      await toggle(first.window);
      await first.window.waitForFunction(() => document.querySelector(".veditor").dataset.wrap === "false");
      assert.equal((await rows(first.window)).length, 1);
      assert.equal(await fs.readFile(first.file("note.md"), "utf8"), content);
      assert.ok(!(await first.window.getByTestId("editor-header").textContent()).includes("*"));
      await first.window.waitForFunction(() => window.electronAPI.getInitialState().softWrap === false);
    } finally { await first.close({ keepUserData: true }); }
    const second = await launchFence({ files: { "note.md": content }, userDataDir });
    try {
      assert.equal(await second.window.getByTestId("veditor").getAttribute("data-wrap"), "false");
      await toggle(second.window);
      await second.window.waitForFunction(() => document.querySelectorAll(".veditor-row").length > 1);
      assert.equal(await second.window.getByTestId("veditor").getAttribute("data-wrap"), "true");
    } finally { await second.close(); }
  });

  test("resize preserves the reading position inside a long paragraph", async () => {
    const content = "a paragraph with many words to wrap ".repeat(3000);
    const fence = await launchFence({ files: { "note.md": content } });
    try {
      const { window } = fence;
      const topOffset = () => window.evaluate(() => {
        const scroller = document.querySelector(".veditor");
        const h = parseFloat(document.querySelector(".veditor-caret").style.height);
        const target = Math.floor(scroller.scrollTop / h);
        const base = Math.round(parseFloat(document.querySelector(".veditor-rows").style.top) / h);
        return Number(document.querySelectorAll(".veditor-row")[target - base]?.dataset.sourceStart);
      });
      await window.getByTestId("veditor").evaluate((el) => { el.scrollTop = 3000; });
      await window.waitForFunction(() => Number(document.querySelector(".veditor-row").dataset.sourceStart) > 1000);
      const before = await topOffset();
      await fence.app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].setSize(1000, 800));
      await window.waitForTimeout(200);
      const after = await topOffset();
      assert.ok(Math.abs(after - before) < 100, `anchor moved from ${before} to ${after}`);
      assert.ok((await rows(window)).length < 100);
    } finally { await fence.close(); }
  });
});
