const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { test, describe } = require("node:test");
const { launchFence, waitForEditorValue, waitFor, waitForPath, sendFromElm, captureClipboard, stubSaveDialog } = require("./helpers");

const doc = "# Title\n\nSome **bold** body.\n";

// What the File > Export and Edit > Copy as Rich Text menu items send.
const menuCommand = sendFromElm;

describe("export", () => {
  test("exporting to HTML writes the rendered preview with its styles", async () => {
    const fence = await launchFence({ files: { "note.md": doc }, open: "note.md" });
    try {
      const target = path.join(fence.workspace, "out.html");
      await stubSaveDialog(fence.app, target);
      await menuCommand(fence.app, { tag: "exportRequested", format: "html" });

      await waitForPath(target, 20000);
      const html = await fs.promises.readFile(target, "utf-8");
      assert.match(html, /<h1[^>]*>Title<\/h1>/);
      assert.match(html, /<strong>bold<\/strong>/);
      assert.match(html, /\.preview-content/); // the stylesheet came along
      // the pane's own chrome is not in the body (the class name survives only
      // in the copied stylesheet)
      assert.doesNotMatch(html, /<div class="pane-header"/);
      assert.match(html, /<base href="file:\/\//);
    } finally {
      await fence.close();
    }
  });

  test("exporting to PDF writes a PDF file", async () => {
    const fence = await launchFence({ files: { "note.md": doc }, open: "note.md" });
    try {
      const target = path.join(fence.workspace, "out.pdf");
      await stubSaveDialog(fence.app, target);
      await menuCommand(fence.app, { tag: "exportRequested", format: "pdf" });

      // Creation precedes completion of writeFile: wait for the PDF trailer,
      // otherwise a fast poll can read the newly created, still-empty file.
      const bytes = await waitFor(async () => {
        try {
          const content = await fs.promises.readFile(target);
          return content.subarray(-16).includes(Buffer.from("%%EOF")) ? content : null;
        } catch (error) {
          if (error.code !== "ENOENT") throw error;
          return null;
        }
      }, { timeout: 10000 });
      assert.equal(bytes.subarray(0, 4).toString("latin1"), "%PDF");
      assert.ok(bytes.length > 1000, `PDF was only ${bytes.length} bytes`);
    } finally {
      await fence.close();
    }
  });

  test("copying as rich text puts HTML and plain text on the clipboard", async () => {
    const fence = await launchFence({ files: { "note.md": doc }, open: "note.md" });
    try {
      const clipboard = await captureClipboard(fence.app);
      await menuCommand(fence.app, { tag: "exportRequested", format: "clipboard" });

      const copied = await waitFor(clipboard, { timeout: 10000 });
      assert.equal(copied.text, "TitleSome bold body.");
      assert.match(copied.html, /<h1[^>]*>Title<\/h1>/);
      assert.match(copied.html, /<strong>bold<\/strong>/);
    } finally {
      await fence.close();
    }
  });

  test("a pasted image is written beside the document and linked from it", async () => {
    const fence = await launchFence({ files: { "note.md": "start\n" }, open: "note.md" });
    try {
      const { window } = fence;
      await window.locator(".veditor-spacer").click({ position: { x: 2, y: 2 } });
      // A 1x1 PNG delivered exactly as a clipboard image paste would be.
      await window.evaluate(async () => {
        const png = Uint8Array.from(
          atob(
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==",
          ),
          (c) => c.charCodeAt(0),
        );
        const file = new File([png], "pasted.png", { type: "image/png" });
        const data = new DataTransfer();
        data.items.add(file);
        document.getElementById("veditor-input").dispatchEvent(new ClipboardEvent("paste", { clipboardData: data, bubbles: true }));
      });

      await window.waitForFunction(
        () => [...document.querySelectorAll(".veditor-row")].map((r) => r.textContent).join("\n").includes("![](assets/"),
        undefined,
        { timeout: 10000 },
      );
      const written = await fs.promises.readdir(path.join(fence.workspace, "assets"));
      assert.equal(written.length, 1);
      assert.match(written[0], /\.png$/);
    } finally {
      await fence.close();
    }
  });

  // The drop handler resolves the dropped File to a path with webUtils and
  // hands it to `openPath`; Playwright cannot produce an OS-backed drop, so
  // this covers everything from `openPath` inwards.
  test("a dropped path opens the file, switching workspace when it is outside", async () => {
    const fence = await launchFence({ files: { "note.md": doc }, open: "note.md" });
    const elsewhere = await fs.promises.mkdtemp(path.join(require("node:os").tmpdir(), "fence-drop-"));
    try {
      const dropped = path.join(elsewhere, "dropped.md");
      await fs.promises.writeFile(dropped, "# Dropped\n", "utf-8");

      await fence.window.evaluate((target) => window.electronAPI.openPath({ path: target }), dropped);

      await waitForEditorValue(fence.window, "# Dropped\n");
      await fence.window.getByTestId("tree-file").filter({ hasText: "dropped.md" }).waitFor({ timeout: 10000 });
    } finally {
      await fs.promises.rm(elsewhere, { recursive: true, force: true });
      await fence.close();
    }
  });
});
