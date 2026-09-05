const assert = require("node:assert/strict");
const { test, describe } = require("node:test");
const { MOD, openEditor, setEditorContent, expectEditorText } = require("./helpers");

const doc = "alpha beta\ngamma alpha\ndelta\n";

async function findIn(fence, query) {
  await fence.window.keyboard.press(`${MOD}+f`);
  await fence.window.getByTestId("find-input").waitFor();
  await fence.window.getByTestId("find-input").fill(query);
  return fence.window;
}

const expectCount = (window, text) =>
  window.waitForFunction((want) => document.querySelector("[data-testid=find-count]")?.textContent === want, text, { timeout: 5000 });

describe("find and replace", () => {
  test("typing a query counts the matches and highlights them", async () => {
    const fence = await openEditor(doc);
    try {
      const window = await findIn(fence, "alpha");
      await expectCount(window, "1 of 2");
      assert.equal(await window.locator(".veditor-highlight").count(), 3); // two matches plus the active overlay
      assert.equal(await window.locator(".veditor-highlight.active").count(), 1);
    } finally {
      await fence.close();
    }
  });

  test("Enter steps forward and wraps, shift-Enter steps back", async () => {
    const fence = await openEditor(doc);
    try {
      const window = await findIn(fence, "alpha");
      await window.keyboard.press("Enter");
      await expectCount(window, "2 of 2");
      await window.keyboard.press("Enter");
      await expectCount(window, "1 of 2");
      await window.keyboard.press("Shift+Enter");
      await expectCount(window, "2 of 2");
    } finally {
      await fence.close();
    }
  });

  test("a query with no matches says so", async () => {
    const fence = await openEditor(doc);
    try {
      const window = await findIn(fence, "zzz");
      await expectCount(window, "No results");
    } finally {
      await fence.close();
    }
  });

  test("matching is case-insensitive until case sensitivity is turned on", async () => {
    const fence = await openEditor("Alpha alpha\n");
    try {
      const window = await findIn(fence, "alpha");
      await expectCount(window, "1 of 2");
      await window.getByRole("button", { name: "Match case" }).click();
      await expectCount(window, "1 of 1");
    } finally {
      await fence.close();
    }
  });

  test("replace changes the active match, replace all changes the rest", async () => {
    const fence = await openEditor(doc);
    try {
      const { window } = fence;
      await window.keyboard.press(`${MOD}+Alt+f`);
      await window.getByTestId("replace-input").waitFor();
      await window.getByTestId("find-input").fill("alpha");
      await window.getByTestId("replace-input").fill("ALPHA");

      await window.getByTestId("replace-one").click();
      await expectEditorText(window, "ALPHA beta\ngamma alpha\ndelta\n");

      await window.getByTestId("replace-all").click();
      await expectEditorText(window, "ALPHA beta\ngamma ALPHA\ndelta\n");
    } finally {
      await fence.close();
    }
  });

  test("replace all is a single undo step", async () => {
    const fence = await openEditor(doc);
    try {
      const { window } = fence;
      await window.keyboard.press(`${MOD}+Alt+f`);
      await window.getByTestId("find-input").fill("alpha");
      await window.getByTestId("replace-input").fill("X");
      await window.getByTestId("replace-all").click();
      await expectEditorText(window, "X beta\ngamma X\ndelta\n");

      await window.locator(".veditor-spacer").click({ position: { x: 2, y: 2 } });
      await window.keyboard.press(`${MOD}+z`);
      await expectEditorText(window, doc);
    } finally {
      await fence.close();
    }
  });

  test("Escape closes the bar, leaving the match selected and the editor focused", async () => {
    const fence = await openEditor(doc);
    try {
      const window = await findIn(fence, "alpha");
      await window.keyboard.press("Escape");
      await window.getByTestId("find-bar").waitFor({ state: "detached" });
      await window.waitForFunction(() => document.activeElement?.id === "veditor-input");
      // the match is still selected, so typing replaces it
      await window.keyboard.type("!");
      await expectEditorText(window, "! beta\ngamma alpha\ndelta\n");
    } finally {
      await fence.close();
    }
  });

  test("the query is seeded from the selection", async () => {
    const fence = await openEditor(doc);
    try {
      const { window } = fence;
      await window.keyboard.press("Shift+ArrowRight");
      await window.keyboard.press("Shift+ArrowRight");
      await window.keyboard.press("Shift+ArrowRight");
      await window.keyboard.press(`${MOD}+f`);
      await window.getByTestId("find-input").waitFor();
      assert.equal(await window.getByTestId("find-input").inputValue(), "alp");
    } finally {
      await fence.close();
    }
  });

  test("matches follow an edit to the document", async () => {
    const fence = await openEditor(doc);
    try {
      const window = await findIn(fence, "alpha");
      await expectCount(window, "1 of 2");
      await setEditorContent(window, "alpha alpha alpha\n");
      await expectCount(window, "1 of 3");
    } finally {
      await fence.close();
    }
  });
});
