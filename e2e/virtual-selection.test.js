// Slice 3 gate: selection, clipboard and IME composition in the virtual editor.
const assert = require("node:assert/strict");
const { test, describe } = require("node:test");
const { launchFence, MOD } = require("./helpers");

const editorText = (window) =>
  window.evaluate(() => [...document.querySelectorAll(".veditor-row")].map((r) => r.textContent).join("\n"));

async function expectEditorText(window, expected) {
  await window.waitForFunction(
    (want) => [...document.querySelectorAll(".veditor-row")].map((r) => r.textContent).join("\n") === want,
    expected,
    { timeout: 3000 },
  ).catch(async () => assert.equal(await editorText(window), expected));
}

async function open(content) {
  const fence = await launchFence({ files: { "note.md": content }, open: "note.md", state: { virtualEditor: true } });
  await fence.window.locator(".veditor-spacer").click({ position: { x: 2, y: 2 } });
  await fence.window.waitForFunction(() => document.activeElement?.id === "veditor-input");
  return fence;
}

const selectionRects = (window) => window.locator(".veditor-selection").count();

describe("virtual editor: selection and clipboard", () => {
  test("shift+arrows select, the selection is drawn, and typing replaces it", async () => {
    const fence = await open("hello world");
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
    const fence = await open("one\ntwo\nthree");
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
    const fence = await open("alpha beta\nsecond");
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
    const fence = await open("drag me please");
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
    const fence = await open("copy this\nkeep");
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
    const fence = await open("a\nb\nc");
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
    const fence = await open("");
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
});
