const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { test } = require("node:test");

// Control IPC completion order to reproduce stale replies deterministically.
test("late image reads cannot replace the image from a new document or edited source", async () => {
  const image = {
    dataset: { imageSource: "picture.png" }, isConnected: true,
    removeAttribute(name) { delete this[name]; },
  };
  const pane = { dataset: { documentPath: "/one/note.md" }, querySelectorAll: () => [image] };
  const requests = [];
  const source = fs.readFileSync(path.join(__dirname, "../js/preview-images.js"), "utf8");
  const { resolvePreviewImages } = vm.runInNewContext(
    source.replace(/^export /gm, "") + "\n({ resolvePreviewImages })",
    {
      document: { querySelector: () => pane },
      window: { electronAPI: { readImage: () => new Promise((resolve) => requests.push(resolve)) } },
    },
  );
  const first = resolvePreviewImages();
  pane.dataset.documentPath = "/two/note.md";
  const second = resolvePreviewImages();
  image.dataset.imageSource = "changed.png";
  const third = resolvePreviewImages();
  requests[2]("new-image");
  await third;
  requests[1]("previous-source");
  requests[0]("previous-document");
  await Promise.all([first, second]);
  assert.equal(image.src, "new-image");
  await resolvePreviewImages();
  assert.equal(requests.length, 3, "unchanged images reuse the completed request");
});
