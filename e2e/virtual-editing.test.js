// Slice 2 gate: editing in the virtual editor through the hidden input,
// plus the cost of a keystroke in the 712KB reference document.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { test, describe } = require("node:test");
const { launchFence, waitForFile, save, MOD } = require("./helpers");

const SOURCE = process.env.FENCE_LARGE_FILE || "/Users/helge/code/access-virus-archive/Access-Virus-Soundsets.md";

const editorText = (window) =>
  window.evaluate(() => [...document.querySelectorAll(".veditor-row")].map((r) => r.textContent).join("\n"));

// Elm renders on the next animation frame, so poll instead of reading right after a key.
async function expectEditorText(window, expected) {
  await window.waitForFunction(
    (want) => [...document.querySelectorAll(".veditor-row")].map((r) => r.textContent).join("\n") === want,
    expected,
    { timeout: 3000 },
  ).catch(async () => assert.equal(await editorText(window), expected));
}

async function focusEditor(window) {
  await window.locator(".veditor-spacer").click({ position: { x: 5, y: 5 } });
  await window.waitForFunction(() => document.activeElement?.id === "veditor-input");
}

async function open(content) {
  const fence = await launchFence({ files: { "note.md": content }, open: "note.md" });
  await focusEditor(fence.window);
  return fence;
}

describe("virtual editor: editing", () => {
  test("typing, newlines, deletion and arrows edit the document and update the preview", async () => {
    const fence = await launchFence({ files: { "note.md": "" }, open: "note.md" });
    try {
      const { window } = fence;
      await focusEditor(window);
      await window.keyboard.type("# Hello");
      await window.keyboard.press("Enter");
      await window.keyboard.press("Enter");
      await window.keyboard.type("Some **bold** text");
      await window.keyboard.press("ArrowLeft");
      await window.keyboard.press("ArrowLeft");
      await window.keyboard.press("ArrowLeft");
      await window.keyboard.press("ArrowLeft");
      await window.keyboard.press("Backspace"); // caret sits before "text": the space goes
      await expectEditorText(window, "# Hello\n\nSome **bold**text");
      await window.getByTestId("preview-content").locator("h1").filter({ hasText: "Hello" }).waitFor();
      await window.getByTestId("preview-content").locator("strong").filter({ hasText: "bold" }).waitFor();
      await window.getByTestId("titlebar-filename").filter({ hasText: "note.md *" }).waitFor();
    } finally {
      await fence.close();
    }
  });

  test("Tab indents, Shift+Tab unindents, and Cmd+Z / Cmd+Shift+Z undo and redo", async () => {
    const fence = await launchFence({ files: { "note.md": "line" }, open: "note.md" });
    try {
      const { window } = fence;
      await focusEditor(window);
      await window.keyboard.press("End");
      await window.keyboard.press("Enter");
      await window.keyboard.press("Tab");
      await window.keyboard.type("in");
      await expectEditorText(window, "line\n\tin");
      await window.keyboard.press("Shift+Tab");
      await expectEditorText(window, "line\nin");
      await window.keyboard.press(`${MOD}+z`);
      await expectEditorText(window, "line\n\tin");
      await window.keyboard.press(`${MOD}+z`);
      await expectEditorText(window, "line\n\t");
      await window.keyboard.press(`${MOD}+Shift+z`);
      await expectEditorText(window, "line\n\tin");
    } finally {
      await fence.close();
    }
  });

  test("pasting inserts multi-line text at the caret", async () => {
    const fence = await launchFence({ files: { "note.md": "a\nb" }, open: "note.md" });
    try {
      const { window } = fence;
      await focusEditor(window);
      await window.keyboard.press("End");
      await fence.app.evaluate(({ clipboard }) => clipboard.writeText("X\nY"));
      await window.keyboard.press(`${MOD}+v`);
      await expectEditorText(window, "aX\nY\nb");
    } finally {
      await fence.close();
    }
  });

  test("Option and Ctrl arrows move, select and delete by word", async () => {
    const fence = await open("alpha beta gamma");
    try {
      const { window } = fence;
      // Option+Right stops at the end of the word
      await window.keyboard.press("Alt+ArrowRight");
      await window.keyboard.type("|");
      await expectEditorText(window, "alpha| beta gamma");

      // Ctrl+Right is the same motion, for Windows and Linux keyboards
      await window.keyboard.press("Control+ArrowRight");
      await window.keyboard.type("|");
      await expectEditorText(window, "alpha| beta| gamma");

      // Option+Shift+Right selects through the end of the next word
      await window.keyboard.press("Alt+Shift+ArrowRight");
      await window.keyboard.type("X");
      await expectEditorText(window, "alpha| beta|X");

      // Option+Backspace removes the word behind the caret
      await window.keyboard.press("Alt+Backspace");
      await expectEditorText(window, "alpha| beta|");
    } finally {
      await fence.close();
    }
  });

  test("the editor shows a text cursor, like the text field it replaced", async () => {
    const fence = await open("hello");
    try {
      const cursors = await fence.window.evaluate(() => ({
        editor: getComputedStyle(document.querySelector("[data-testid=veditor]")).cursor,
        preview: getComputedStyle(document.querySelector("[data-testid=preview-content]")).cursor,
      }));
      assert.equal(cursors.editor, "text");
      assert.notEqual(cursors.preview, "text");
    } finally {
      await fence.close();
    }
  });

  test("Cmd+S still saves and clears the dirty marker", async () => {
    const fence = await launchFence({ files: { "note.md": "x" }, open: "note.md" });
    try {
      const { window } = fence;
      await focusEditor(window);
      await window.keyboard.press("End");
      await window.keyboard.type("y");
      await window.getByTestId("titlebar-filename").filter({ hasText: "note.md *" }).waitFor();
      await save(window);
      await waitForFile(fence.file("note.md"), "xy");
      await window.getByTestId("titlebar-filename").filter({ hasText: /^note\.md$/ }).waitFor();
    } finally {
      await fence.close();
    }
  });

  test("clicking places the caret at that line and column", async () => {
    const fence = await launchFence({ files: { "note.md": "first\nsecond\nthird" }, open: "note.md" });
    try {
      const { window } = fence;
      const m = await window.evaluate(() => { const c = document.querySelector(".veditor-caret"); return { lh: parseFloat(c.style.height) }; });
      // click on line 2 ("second"), a few characters in
      await window.locator(".veditor-spacer").click({ position: { x: 30, y: m.lh * 1.5 } });
      await window.keyboard.type("|");
      const text = await editorText(window);
      assert.match(text.split("\n")[1], /^se|cond$|^sec\|ond$|^s\|econd$/);
      assert.equal(text.split("\n")[0], "first");
    } finally {
      await fence.close();
    }
  });
});

describe("virtual editor: keystroke cost", { skip: !fs.existsSync(SOURCE) && `no ${path.basename(SOURCE)}` }, () => {
  test("a keystroke in the 712KB reference document costs under 2ms of layout", async () => {
    const content = fs.readFileSync(SOURCE, "utf-8");
    const fence = await launchFence({ files: { "big.md": content }, open: "big.md" });
    try {
      const { window } = fence;
      await window.waitForFunction(() => document.querySelectorAll(".veditor-row").length > 10);
      await focusEditor(window);
      await window.keyboard.press("ArrowDown");
      await window.keyboard.press("End");
      // let the progressive preview finish so its steps don't pollute the trace
      await window.waitForFunction(
        () => new Promise((resolve) => { const n = document.querySelectorAll(".preview-chunk").length; setTimeout(() => resolve(n > 0 && document.querySelectorAll(".preview-chunk").length === n), 400); }),
        undefined,
        { timeout: 20000, polling: 100 },
      );
      const cdp = await fence.app.context().newCDPSession(window);
      const events = [];
      cdp.on("Tracing.dataCollected", (e) => events.push(...e.value));
      const finished = new Promise((resolve) => cdp.on("Tracing.tracingComplete", resolve));
      await cdp.send("Tracing.start", { categories: "devtools.timeline,disabled-by-default-devtools.timeline" });
      // Type faster than the preview debounce (50ms) and stop tracing before it
      // fires, so the layouts measured are the editor's alone.
      await window.keyboard.type("hello", { delay: 5 });
      await window.waitForFunction(() => document.querySelectorAll(".veditor-row")[1]?.textContent.endsWith("hello"));
      await cdp.send("Tracing.end");
      await finished;
      const layouts = events.filter((e) => e.name === "Layout" && e.dur).map((e) => e.dur / 1000).sort((a, b) => b - a);
      const worst = layouts[0] || 0;
      console.log(`virtual-editing: ${layouts.length} layouts for 5 keystrokes, worst ${worst.toFixed(2)}ms`);
      assert.ok(worst < 2, `a keystroke layout took ${worst.toFixed(2)}ms`);
    } finally {
      await fence.close();
    }
  });
});
