const { BrowserWindow } = require("electron");
const fsOps = require("./fs-ops");
const { requireString } = require("./validate");

// Exports must stand on their own: swap every preview image URL for the
// file's data URL. The HTML is serialized DOM, so `&` arrives as `&amp;`.
async function inlineImages(html) {
  const pattern = /src="(fence-image:\/\/[^"]*)"/g;
  const inlined = await Promise.all([...html.matchAll(pattern)].map(async ([, raw]) => {
    try {
      const url = new URL(raw.replace(/&amp;/g, "&"));
      return await fsOps.readImage(url.searchParams.get("doc") ?? "", (url.searchParams.get("src") ?? "") + url.hash);
    } catch {
      return "";
    }
  }));
  let i = 0;
  return html.replace(pattern, () => `src="${inlined[i++]}"`);
}

// Build a standalone HTML document from the rendered preview: the renderer
// hands over the pane's markup and the stylesheet text it is using, so the
// export looks exactly like what is on screen, mermaid diagrams included.
async function exportDocument(data) {
  const html = await inlineImages(requireString(data, "html"));
  const css = requireString(data, "css");
  const title = requireString(data, "title", 512);
  const theme = typeof data.theme === "string" ? data.theme : "";
  const base = typeof data.base === "string" ? data.base : "";

  return `<!doctype html>
<html${theme ? ` data-theme="${escapeAttribute(theme)}"` : ""}>
<head>
<meta charset="utf-8">
<title>${escapeHtml(title)}</title>
${base ? `<base href="${escapeAttribute(base)}">` : ""}
<style>${css}
@page { margin: 1.5cm; }
body { margin: 0; }
.preview-pane, .preview-content { overflow: visible !important; height: auto !important; }
</style>
</head>
<body><div class="preview-pane"><div class="preview-content">${html}</div></div></body>
</html>`;
}

function escapeHtml(value) {
  return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function escapeAttribute(value) {
  return escapeHtml(value).replace(/"/g, "&quot;");
}

async function renderPdf(document_) {
  const printer = new BrowserWindow({ show: false, webPreferences: { javascript: false } });
  try {
    await printer.loadURL(`data:text/html;charset=utf-8,${encodeURIComponent(document_)}`);
    return await printer.webContents.printToPDF({ printBackground: true });
  } finally {
    printer.destroy();
  }
}

module.exports = { exportDocument, escapeHtml, escapeAttribute, inlineImages, renderPdf };
