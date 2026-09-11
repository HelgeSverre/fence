const assert = require("node:assert/strict");
const { test } = require("node:test");
const { withFence, waitForEditorValue, setEditorContent, waitFor, sendFromElm, captureClipboard } = require("./helpers");

const svg = (width) => `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="10"><rect width="100%" height="100%" fill="red"/></svg>`;
const doc = '![](picture.svg)\n\n<img src="../assets/a%20b.svg" alt="HTML image">\n';

test("local Markdown and HTML images follow the document, including cached chunks and edits", async () => {
  await withFence({ open: null, files: {
    "one/note.md": doc, "two/note.md": doc,
    "one/picture.svg": svg(10), "two/picture.svg": svg(20), "assets/a b.svg": svg(30),
  } }, async (fence) => {
    await fence.window.getByTestId("tree-dir").filter({ hasText: "one" }).waitFor();
    for (const [folder, width] of [["one", 10], ["two", 20]]) {
      await fence.window.evaluate((path) => window.electronAPI.readFile({ path }), fence.file(`${folder}/note.md`));
      await waitForEditorValue(fence.window, doc);
      await fence.window.waitForFunction((width) => {
        const imgs = [...document.querySelectorAll(".preview-content img")];
        return imgs.length === 2 && imgs[0].naturalWidth === width && imgs[1].naturalWidth === 30;
      }, width, { timeout: 5000 });
    }
    await setEditorContent(fence.window, '![](../assets/a%20b.svg)\n');
    await fence.window.waitForFunction(() => {
      const imgs = [...document.querySelectorAll(".preview-content img")];
      return imgs.length === 1 && imgs[0].naturalWidth === 30;
    });
    // Export must carry the resolved local image, independent of the app base URL.
    const copied = await captureClipboard(fence.app);
    await sendFromElm(fence.app, { tag: "exportRequested", format: "clipboard" });
    assert.match((await waitFor(copied)).html, /src="data:image\/svg\+xml;base64,/);
  });
});

test("README-style PNGs load beside the file and missing images leave other images working", async () => {
  const png = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==", "base64");
  const inline = `data:image/png;base64,${png.toString("base64")}`;
  await withFence({ files: {
    "note.md": `<div align="center">\n<img src="screenshot.png" width="400" alt="Screenshot">\n</div>\n\n![missing](missing.png)\n\n![inline](${inline})\n\n![remote](https://example.com/logo.png)\n`,
    "screenshot.png": png,
  } }, async (fence) => {
    await fence.window.waitForFunction(() => {
      const imgs = [...document.querySelectorAll(".preview-content img")];
      return imgs.length === 4 && imgs[0].naturalWidth === 1 && imgs[2].naturalWidth === 1 && imgs[1].complete;
    });
    const img = (alt) => fence.window.locator(".preview-content").getByAltText(alt);
    assert.equal(await img("Screenshot").getAttribute("width"), "400");
    assert.match(await img("Screenshot").getAttribute("src"), /^fence-image:\/\/local\/\?doc=.*&src=screenshot\.png&v=\d+$/);
    assert.equal(await img("remote").getAttribute("src"), "https://example.com/logo.png");
    assert.equal(await img("missing").evaluate((img) => img.naturalWidth), 0);
    await setEditorContent(fence.window, '<img alt="Source removed">\n');
    await fence.window.waitForFunction(() => {
      const img = document.querySelector(".preview-content img");
      return img?.alt === "Source removed" && img.complete && img.naturalWidth === 0;
    });
  });
});
