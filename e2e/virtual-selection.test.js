// Selection, clipboard and IME composition.
const assert = require("node:assert/strict");
const { test, describe } = require("node:test");
const { openEditor, editorText, expectEditorText, MOD } = require("./helpers");

const selectionRects = (window) => window.locator(".veditor-selection").count();

describe("virtual editor: selection and clipboard", () => {
  test("shift+arrows select, the selection is drawn, and typing replaces it", async () => {
    const fence = await openEditor("hello world");
    try {
      const { window } = fence;
      for (let i = 0; i < 5; i++) await window.keyboard.press("Shift+ArrowRight");
      await window.waitForFunction(() => document.querySelectorAll(".veditor-selection").length === 1);
      await window.keyboard.type("bye");
      await expectEditorText(window, "bye world");
      assert.equal(await selectionRects(window), 0);
    } finally {
      await fence.close();
    }
  });

  test("Cmd+A selects everything and Backspace clears it; undo brings it back", async () => {
    const fence = await openEditor("one\ntwo\nthree");
    try {
      const { window } = fence;
      await window.keyboard.press(`${MOD}+a`);
      await window.waitForFunction(() => document.querySelectorAll(".veditor-selection").length === 3);
      await window.keyboard.press("Backspace");
      await expectEditorText(window, "");
      await window.keyboard.press(`${MOD}+z`);
      await expectEditorText(window, "one\ntwo\nthree");
    } finally {
      await fence.close();
    }
  });

  test("double-click selects a word and triple-click a line", async () => {
    const fence = await openEditor("alpha beta\nsecond");
    try {
      const { window } = fence;
      const cw = await window.evaluate(() => parseFloat(document.querySelector(".veditor-caret").style.left) || 0);
      await window.locator(".veditor-spacer").dblclick({ position: { x: 60, y: 8 } });
      await window.keyboard.type("X");
      await expectEditorText(window, "alpha X\nsecond");
      await window.locator(".veditor-spacer").click({ position: { x: 10, y: 8 }, clickCount: 3 });
      await window.keyboard.press("Backspace");
      await expectEditorText(window, "second");
    } finally {
      await fence.close();
    }
  });

  test("dragging with the mouse selects text", async () => {
    const fence = await openEditor("drag me please");
    try {
      const { window } = fence;
      const box = await window.locator(".veditor-spacer").boundingBox();
      await window.mouse.move(box.x + 2, box.y + 8);
      await window.mouse.down();
      await window.mouse.move(box.x + 40, box.y + 8, { steps: 4 });
      await window.mouse.up();
      await window.waitForFunction(() => document.querySelectorAll(".veditor-selection").length === 1);
      const selected = await window.evaluate(() => document.getElementById("veditor-input").dataset.selection);
      assert.match(selected, /^dra/);
      await window.keyboard.type("Z");
      await window.waitForFunction(() => document.querySelector(".veditor-row")?.textContent.startsWith("Z"));
      const text = await editorText(window);
      assert.ok(text.startsWith("Z") && text.endsWith("please"), text);
    } finally {
      await fence.close();
    }
  });

  test("Cmd+C copies and Cmd+X cuts the selection to the system clipboard", async () => {
    const fence = await openEditor("copy this\nkeep");
    try {
      const { window, app } = fence;
      await app.evaluate(({ clipboard }) => clipboard.writeText(""));
      await window.keyboard.press("Shift+End");
      // the selected text is exposed to the clipboard glue on the next frame
      await window.waitForFunction(() => document.getElementById("veditor-input").dataset.selection === "copy this");
      await window.keyboard.press(`${MOD}+c`);
      await new Promise((r) => setTimeout(r, 200));
      assert.equal(await app.evaluate(({ clipboard }) => clipboard.readText()), "copy this");
      await expectEditorText(window, "copy this\nkeep");
      await window.keyboard.press(`${MOD}+x`);
      await expectEditorText(window, "\nkeep");
      await new Promise((r) => setTimeout(r, 200));
      assert.equal(await app.evaluate(({ clipboard }) => clipboard.readText()), "copy this");
      await window.keyboard.press("ArrowDown");
      await window.keyboard.press("End");
      await window.keyboard.press(`${MOD}+v`);
      await expectEditorText(window, "\nkeepcopy this");
    } finally {
      await fence.close();
    }
  });

  test("Tab indents every selected line and Shift+Tab reverts it", async () => {
    const fence = await openEditor("a\nb\nc");
    try {
      const { window } = fence;
      await window.keyboard.press("Shift+ArrowDown");
      await window.keyboard.press("Shift+ArrowDown");
      await window.keyboard.press("Shift+End");
      await window.keyboard.press("Tab");
      await expectEditorText(window, "\ta\n\tb\n\tc");
      await window.keyboard.press("Shift+Tab");
      await expectEditorText(window, "a\nb\nc");
    } finally {
      await fence.close();
    }
  });

  test("IME composition commits the composed text only", async () => {
    const fence = await openEditor("");
    try {
      const { window, app } = fence;
      const cdp = await app.context().newCDPSession(window);
      await cdp.send("Input.imeSetComposition", { text: "ni", selectionStart: 2, selectionEnd: 2 });
      await new Promise((r) => setTimeout(r, 100));
      const during = await editorText(window);
      assert.ok(!during.includes("ni"), `composition text leaked into the document: ${JSON.stringify(during)}`);
      await cdp.send("Input.insertText", { text: "你" });
      await expectEditorText(window, "你");
    } finally {
      await fence.close();
    }
  });

  test("clicking, scrolling, then clicking again places the caret without jumping the view", async () => {
    const fence = await openEditor(Array.from({ length: 400 }, (_, i) => `line ${i}`).join("\n"));
    try {
      const { window } = fence;
      const lh = await window.evaluate(() => parseFloat(document.querySelector(".veditor-caret").style.height));
      await window.locator(".veditor-spacer").click({ position: { x: 10, y: lh * 5 + 2 } });
      await window.keyboard.press("Shift+End"); // leave a selection behind, like a user might
      await window.evaluate(() => { document.querySelector("[data-testid=veditor]").scrollTop = 4000; });
      await window.waitForFunction(() => document.querySelector(".veditor-row")?.textContent !== "line 0");
      const before = await window.evaluate(() => document.querySelector("[data-testid=veditor]").scrollTop);
      const target = await window.evaluate(() => document.querySelectorAll(".veditor-row")[12].textContent);
      const box = await window.locator(".veditor-row").nth(12).boundingBox();
      await window.mouse.click(box.x + 10, box.y + box.height / 2);
      await window.keyboard.type("|");
      // the marker must land in the clicked row (10px in, so column 1)
      await window.waitForFunction((t) => [...document.querySelectorAll(".veditor-row")].some((r) => r.textContent.includes("|") && r.textContent.replace("|", "") === t), target);
      const after = await window.evaluate(() => ({ scrollTop: document.querySelector("[data-testid=veditor]").scrollTop, selections: document.querySelectorAll(".veditor-selection").length, focused: document.activeElement?.id }));
      assert.ok(Math.abs(after.scrollTop - before) < 2, `view jumped from ${before} to ${after.scrollTop}`);
      assert.equal(after.selections, 0);
      assert.equal(after.focused, "veditor-input");
    } finally {
      await fence.close();
    }
  });
});
