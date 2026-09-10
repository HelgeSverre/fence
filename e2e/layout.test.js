const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const path = require("node:path");
const { test, describe } = require("node:test");
const { launchFence, openEditor, focusEditor, expectEditorText, MOD } = require("./helpers");

const modeIs = (window, mode) => window.waitForFunction((value) => document.querySelector(".app-layout")?.dataset.layout === value, mode);
const countIs = (window, text) => window.waitForFunction((value) => document.querySelector("[data-testid=find-count]")?.textContent === value, text);
const choose = async (window, mode) => {
  await window.getByTestId(`layout-${mode}`).click();
  await modeIs(window, mode);
};

describe("document layouts", () => {
  test("buttons and cycling preserve pane DOM, split width, sidebars, edits and undo", async () => {
    const fence = await openEditor("hello\n");
    try {
      const { window } = fence;
      await window.evaluate(() => {
        window.__editor = document.getElementById("veditor");
        window.__preview = document.querySelector(".preview-content");
      });
      const before = await window.getByTestId("veditor").boundingBox();
      await window.keyboard.insertText("new ");
      await window.keyboard.press("Meta+2");
      await modeIs(window, "preview");
      assert.equal(await window.getByTestId("veditor").isVisible(), false);
      const preview = await window.getByTestId("preview-pane").boundingBox();
      assert.ok(preview.width > before.width * 1.8);
      await window.keyboard.press("Meta+2");
      await modeIs(window, "editor");
      assert.ok((await window.getByTestId("veditor").boundingBox()).width > before.width * 1.8);
      await window.keyboard.press("Meta+2");
      await modeIs(window, "split");
      assert.ok(Math.abs((await window.getByTestId("veditor").boundingBox()).width - before.width) < 2);
      await focusEditor(window);
      await window.keyboard.press(`${MOD}+z`);
      await expectEditorText(window, "hello\n");
      await window.keyboard.press("Meta+1");
      await window.keyboard.press("Meta+1");
      await window.getByTestId("sidebar").waitFor();
      assert.equal(await window.evaluate(() => window.__editor === document.getElementById("veditor") && window.__preview === document.querySelector(".preview-content")), true);
    } finally { await fence.close(); }
  });

  test("radio group supports arrows and remembers the selected layout after restart", async () => {
    const first = await launchFence();
    const userDataDir = first.userDataDir;
    try {
      await first.window.getByTestId("layout-split").focus();
      await first.window.keyboard.press("ArrowRight");
      await modeIs(first.window, "preview");
      await first.window.waitForFunction(() => document.activeElement?.id === "layout-preview");
      await first.window.keyboard.press("Home");
      await modeIs(first.window, "editor");
      await first.window.keyboard.press("End");
      await modeIs(first.window, "preview");
      await first.window.waitForFunction(() => document.activeElement?.id === "layout-preview");
    } finally { await first.close({ keepUserData: true }); }
    const second = await launchFence({ userDataDir });
    try {
      await modeIs(second.window, "preview");
      assert.equal(await second.window.getByTestId("layout-preview").getAttribute("aria-checked"), "true");
      assert.equal(await second.window.getByTestId("veditor").isVisible(), false);
    } finally { await second.close(); }
  });

  test("cycle layout can be rebound and persists", async () => {
    const first = await launchFence();
    const userDataDir = first.userDataDir;
    try {
      await first.window.getByTestId("settings-button").click();
      await first.window.locator(".settings-dropdown-row").filter({ hasText: "Cycle layout" }).getByRole("button").click();
      await first.window.keyboard.press("Meta+4");
      await first.window.getByRole("button", { name: "⌘4", exact: true }).waitFor();
      await first.window.keyboard.press("Escape");
      await first.window.keyboard.press("Meta+4");
      await modeIs(first.window, "preview");
    } finally { await first.close({ keepUserData: true }); }
    const second = await launchFence({ userDataDir });
    try {
      await modeIs(second.window, "preview");
      await second.window.getByTestId("preview-container").focus();
      await second.window.keyboard.press("Meta+4");
      await modeIs(second.window, "editor");
      await second.window.keyboard.press("Meta+2");
      assert.equal(await second.window.locator(".app-layout").getAttribute("data-layout"), "editor");
    } finally { await second.close(); }
  });

  test("preview find searches rendered inline text, counts, navigates and handles case", async () => {
    const fence = await launchFence({ files: { "note.md": "# Heading\n\nAlpha **beta** and alpha **beta**. [link](hidden-url)\n\nsoft\nbreak    spaces 😀.\n" } });
    try {
      const { window } = fence;
      await choose(window, "preview");
      await window.keyboard.press(`${MOD}+f`);
      await window.getByTestId("find-input").fill("alpha beta");
      await countIs(window, "1 of 2");
      assert.equal(await window.evaluate(() => CSS.highlights.get("preview-matches").size), 2);
      assert.equal(await window.evaluate(() => [...CSS.highlights.get("preview-active")][0].toString()), "Alpha beta");
      await window.keyboard.press("Enter");
      await countIs(window, "2 of 2");
      await window.keyboard.press("Enter");
      await countIs(window, "1 of 2");
      await window.keyboard.press("Shift+Enter");
      await countIs(window, "2 of 2");
      await window.getByRole("button", { name: "Match case" }).click();
      await countIs(window, "1 of 1");
      await window.getByTestId("find-input").fill("soft break spaces 😀");
      await countIs(window, "1 of 1");
      await window.waitForFunction(() => /soft\s+break\s+spaces 😀/.test([...CSS.highlights.get("preview-active")][0]?.toString() ?? ""));
      await window.getByTestId("find-input").fill("hidden-url");
      await countIs(window, "No results");
      await window.getByTestId("find-input").fill("**");
      await countIs(window, "No results");
      await window.keyboard.press("Escape");
      await window.getByTestId("find-bar").waitFor({ state: "detached" });
      await window.waitForFunction(() => document.activeElement?.id === "preview-container" && !CSS.highlights.has("preview-matches"));
    } finally { await fence.close(); }
  });

  test("find follows layout changes and Replace reveals source without losing the query", async () => {
    const fence = await launchFence({ files: { "note.md": "alpha **beta**\n" } });
    try {
      const { window } = fence;
      await window.keyboard.press(`${MOD}+f`);
      await window.getByTestId("find-input").fill("**");
      await countIs(window, "1 of 2");
      await window.keyboard.press("Meta+2");
      await modeIs(window, "preview");
      await countIs(window, "No results");
      await window.keyboard.press(`${MOD}+Alt+f`);
      await modeIs(window, "split");
      await window.getByTestId("replace-input").waitFor();
      await countIs(window, "1 of 2");
      await window.getByTestId("replace-input").fill("");
      await window.getByTestId("replace-all").click();
      await expectEditorText(window, "alpha beta\n");
    } finally { await fence.close(); }
  });

  test("scroll position survives hidden editor and width changes; preview stays independently scrollable", async () => {
    const fence = await launchFence({ files: { "note.md": "# Top\n\n" + "some paragraph text\n\n".repeat(250) }, state: { softWrap: true } });
    try {
      const { window } = fence;
      await window.evaluate(() => { document.getElementById("veditor").scrollTop = 2000; });
      await window.waitForFunction(() => document.getElementById("preview-container").scrollTop > 100);
      await choose(window, "preview");
      await window.evaluate(() => { document.getElementById("preview-container").scrollTop = 3000; });
      await window.setViewportSize({ width: 1100, height: 750 });
      await window.waitForFunction(() => document.getElementById("preview-container").scrollTop > 2900);
      await choose(window, "editor");
      await window.waitForFunction(() => Math.abs(document.getElementById("veditor").scrollTop - 2000) < 2);
      await choose(window, "split");
      await window.waitForFunction(() => Math.abs(document.getElementById("veditor").scrollTop - 2000) < 2);
      await window.evaluate(() => { document.getElementById("veditor").scrollTop = 0; });
      await window.waitForFunction(() => document.getElementById("preview-container").scrollTop < 20);
    } finally { await fence.close(); }
  });

  test("diagrams render when starting editor-only and survive switching and theme changes", async () => {
    const fence = await launchFence({ files: { "note.md": "```mermaid\ngraph TD\n A --> B\n```\n" }, state: { layoutMode: "editor" } });
    try {
      const { window } = fence;
      await window.locator("pre.mermaid svg").waitFor({ state: "attached" });
      await choose(window, "preview");
      await window.locator("pre.mermaid svg").waitFor();
      await window.getByTestId("settings-button").click();
      await window.getByTestId("settings-item-light").click();
      await window.keyboard.press("Escape");
      await window.locator("pre.mermaid svg").waitFor();
      assert.ok((await window.locator("pre.mermaid svg").boundingBox()).width > 0);
    } finally { await fence.close(); }
  });

  test("outline navigation scrolls preview directly and export works in editor-only mode", async () => {
    const content = "# Start\n\n" + "paragraph\n\n".repeat(100) + "# Destination\n\n**Export me**\n";
    const fence = await launchFence({ files: { "note.md": content }, state: { rightSidebarVisible: true } });
    try {
      const { window } = fence;
      await choose(window, "preview");
      await window.getByTestId("outline-entry").filter({ hasText: "Destination" }).click();
      await window.waitForFunction(() => document.getElementById("preview-container").scrollTop > 1000);
      await choose(window, "editor");
      const target = path.join(fence.workspace, "export.html");
      await fence.app.evaluate(({ dialog }, filePath) => { dialog.showSaveDialog = async () => ({ canceled: false, filePath }); }, target);
      await fence.app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].webContents.send("fromElm", { tag: "exportRequested", format: "html" }));
      await window.waitForFunction(() => !document.querySelector(".error-banner"));
      let html;
      for (let i = 0; i < 100; i++) {
        html = await fs.readFile(target, "utf8").catch(() => "");
        if (html) break;
        await new Promise((resolve) => setTimeout(resolve, 50));
      }
      assert.match(html, /<strong>Export me<\/strong>/);
      assert.doesNotMatch(html.split("<body>")[1], /pane-offscreen/); // no hidden wrapper in the exported body (CSS is collected separately)
    } finally { await fence.close(); }
  });
});
