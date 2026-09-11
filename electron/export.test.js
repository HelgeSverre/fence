const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { test } = require("node:test");
const fsOps = require("./fs-ops");
const { escapeHtml, escapeAttribute, inlineImages } = require("./export");

test("escapeHtml and escapeAttribute neutralize markup", () => {
  assert.equal(escapeHtml(`<a href="x">Tom & Jerry</a>`), `&lt;a href="x"&gt;Tom &amp; Jerry&lt;/a&gt;`);
  assert.equal(escapeAttribute(`say "hi" & <bye>`), `say &quot;hi&quot; &amp; &lt;bye&gt;`);
  assert.equal(escapeHtml("plain"), "plain");
});

test("inlineImages swaps fence-image URLs for data URLs and blanks unresolvable ones", async () => {
  const workspace = await fs.promises.realpath(await fs.promises.mkdtemp(path.join(os.tmpdir(), "fence-export-")));
  try {
    await fsOps.setWorkspace(workspace);
    const doc = path.join(workspace, "note.md");
    await fs.promises.writeFile(doc, "");
    await fs.promises.writeFile(path.join(workspace, "icon.svg"), "<svg/>");
    const url = (src) => `fence-image://local/?doc=${encodeURIComponent(doc)}&amp;src=${encodeURIComponent(src)}&amp;v=3`;
    const html = `<p><img src="${url("icon.svg")}"><img src="${url("missing.png")}"></p>`;

    const out = await inlineImages(html);

    const data = `data:image/svg+xml;base64,${Buffer.from("<svg/>").toString("base64")}`;
    assert.equal(out, `<p><img src="${data}"><img src=""></p>`);
  } finally {
    await fsOps.setWorkspace(null);
    await fs.promises.rm(workspace, { recursive: true, force: true });
  }
});
