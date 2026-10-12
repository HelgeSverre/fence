const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const path = require("node:path");
const { test } = require("node:test");
const { launchFence, openSettings, setEditorContent, sendFromElm, stubSaveDialog, waitForPath, waitFor, captureClipboard } = require("./helpers");

const flow = 'flowchart LR\n A[Start] -->|continue| B{Ready?}\n B -->|yes| C[Finish]\n';
const fenceBlock = (source) => `\`\`\`mermaid\n${source}\`\`\`\n`;
const ready = (window) => window.locator('.mermaid[data-state="rendered"]');

test("mindmaps use their own layout and remain readable alongside graph diagrams", async () => {
  const mindmap = "mindmap\n root((Fence))\n  Editing\n   Virtual rows\n  Preview\n   Progressive parsing\n  Appearance\n   {{Themes}}\n   (Fonts)\n";
  const fence = await launchFence({ files: { "note.md": fenceBlock(mindmap) + "\n" + fenceBlock(flow) } });
  try {
    const { window } = fence;
    await window.waitForFunction(() => document.querySelectorAll('.preview-content .mermaid[data-state="rendered"]').length === 2);
    assert.match(await ready(window).first().locator("svg").textContent(), /Progressive parsing/);
    assert.equal(await window.locator('.preview-content .mermaid[data-state="error"]').count(), 0);
  } finally { await fence.close(); }
});

test("diagrams retain shapes, have SVG labels and unique references, including expanded cached copies", async () => {
  const fence = await launchFence({ files: { "note.md": fenceBlock(flow) + "\n" + fenceBlock(flow) } });
  try {
    const { window } = fence;
    await window.waitForFunction(() => document.querySelectorAll('.mermaid[data-state="rendered"]').length === 2);
    const first = ready(window).first();
    assert.equal(await first.locator("foreignObject").count(), 0);
    assert.ok(await first.locator("svg text").count() > 0);
    assert.equal(await first.locator("svg .node").count(), 3);
    assert.ok(await first.locator('.node[id*="B-"] polygon, .node[id*="B-"] path').count() > 0,
      "the decision must retain its authored shape");
    await first.hover();
    await first.getByRole("button", { name: "Expand diagram", exact: true }).click();
    const references = await window.evaluate(() => {
      const svgs = [...document.querySelectorAll(".mermaid svg, .mermaid-fullscreen svg")];
      const ids = svgs.flatMap((svg) => [svg.id, ...[...svg.querySelectorAll("[id]")].map((node) => node.id)]);
      return {
        count: svgs.length,
        unique: new Set(ids).size === ids.length,
        local: svgs.every((svg) => [...svg.querySelectorAll("[marker-end]")].every((edge) => {
          const id = edge.getAttribute("marker-end").match(/#([^)'"\s]+)/)?.[1];
          return !id || !!svg.querySelector(`[id="${id}"]`);
        })),
      };
    });
    assert.equal(references.count, 3);
    assert.equal(references.unique, true);
    assert.equal(references.local, true);

    await window.evaluate(() => getSelection().removeAllRanges());
    const label = window.locator(".mermaid-fullscreen svg text").first();
    assert.equal(await label.evaluate((node) => getComputedStyle(node).userSelect), "none");
    const box = await label.boundingBox();
    await window.mouse.move(box.x + 2, box.y + box.height / 2);
    await window.mouse.down();
    await window.mouse.move(box.x + 82, box.y + box.height / 2 + 30, { steps: 5 });
    await window.mouse.up();
    assert.equal(await window.evaluate(() => getSelection().toString()), "");
    const pan = await window.locator(".mermaid-fullscreen svg").evaluate((svg) => {
      const matrix = new DOMMatrix(getComputedStyle(svg).transform);
      return { x: matrix.m41, y: matrix.m42 };
    });
    assert.ok(Math.abs(pan.x - 80) < 0.01 && Math.abs(pan.y - 30) < 0.01);
    await window.keyboard.press("Escape");
    await first.getByRole("button", { name: "Show diagram source", exact: true }).click();
    assert.equal(await first.locator(".mermaid-source").textContent(), flow);
    assert.notEqual(await first.locator(".mermaid-source").evaluate((node) => getComputedStyle(node).userSelect), "none");
  } finally { await fence.close(); }
});

test("wide diagrams adapt to pane size and respect an explicit size choice", async () => {
  const source = "flowchart LR\n" + Array.from({ length: 12 }, (_, i) => ` N${i}[Step ${i}]`).join(" -->") + "\n";
  const fence = await launchFence({ files: { "note.md": fenceBlock(source) } });
  try {
    const { window } = fence;
    const diagram = ready(window);
    await diagram.waitFor();
    await window.waitForFunction(() => document.querySelector(".mermaid").dataset.size === "actual");
    assert.equal(await diagram.locator(".mermaid-diagram").evaluate((node) => node.scrollWidth > node.clientWidth), true);
    const intrinsic = await diagram.locator("svg").evaluate((svg) => svg.viewBox.baseVal.width);
    await diagram.evaluate((node, width) => { node.style.width = `${width}px`; }, intrinsic + 100);
    await window.waitForFunction(() => document.querySelector(".mermaid").dataset.size === "fit");
    await diagram.evaluate((node) => { node.style.width = "300px"; });
    await window.waitForFunction(() => document.querySelector(".mermaid").dataset.size === "actual");
    await diagram.getByRole("button", { name: "Show diagram at actual size", exact: true }).click();
    await diagram.evaluate((node) => { node.style.width = "250px"; });
    await window.waitForFunction(() => Math.abs(document.querySelector(".mermaid").getBoundingClientRect().width - 250) < 1);
    assert.equal(await diagram.getAttribute("data-size"), "fit");
  } finally { await fence.close(); }
});

test("theme and font changes redraw diagrams and refresh the expanded view; edits recover", async () => {
  const source = fenceBlock(flow) + "\n" + fenceBlock("sequenceDiagram\n participant A\n participant B\n A->>B: Hello\n")
    + "\n" + fenceBlock("stateDiagram-v2\n [*] --> Ready\n Ready --> Done\n");
  const fence = await launchFence({ files: { "note.md": source }, state: { theme: "catppuccin-mocha" } });
  try {
    const { window } = fence;
    await window.waitForFunction(() => document.querySelectorAll('.mermaid[data-state="rendered"]').length === 3);
    const first = ready(window).first();
    const initial = await first.locator("svg").getAttribute("id");
    const fill = await first.locator(".node rect").first().evaluate((node) => getComputedStyle(node).fill);
    await openSettings(window);
    await window.getByTestId("settings-picker-theme").click();
    await window.getByTestId("settings-option-theme-github-dark").click();
    await window.waitForFunction((id) => document.querySelector('.mermaid[data-state="rendered"] svg')?.id !== id, initial);
    assert.notEqual(await first.locator(".node rect").first().evaluate((node) => getComputedStyle(node).fill), fill);
    await window.getByTestId("settings-picker-ui-font").click();
    await window.getByTestId("settings-picker-search").fill("inter");
    await window.getByTestId("settings-option-ui-font-Inter").click();
    await window.waitForFunction(() => document.querySelector('.mermaid[data-state="rendered"] svg style')?.textContent.includes('Inter'));
    await window.keyboard.press("Escape");
    await first.hover();
    await first.getByRole("button", { name: "Expand diagram", exact: true }).click();
    const expandedId = await window.locator(".mermaid-fullscreen svg").getAttribute("id");
    // Programmatic activation avoids the popover's pointer light-dismissal;
    // the real settings/port path still changes the appearance.
    await window.getByTestId("settings-button").evaluate((node) => node.click());
    await window.getByTestId("settings-picker-theme").evaluate((node) => node.click());
    await window.getByTestId("settings-option-theme-light").evaluate((node) => node.click());
    await window.waitForFunction((id) => {
      const svg = document.querySelector(".mermaid-fullscreen svg");
      return svg && svg.id !== id;
    }, expandedId);
    // Elm owns data-source. Change it as an edit would, without a pointer
    // click in the editor dismissing the expanded view before the update.
    await first.evaluate((node) => { node.dataset.source = "flowchart LR\n A[Updated] --> B[Fresh]\n"; });
    await window.waitForFunction(() => document.querySelector('.mermaid-fullscreen svg')?.textContent.includes("Updated"));
    await first.evaluate((node) => { node.dataset.source = "flowchart LR\n A[unfinished\n"; });
    await window.locator('.mermaid[data-state="error"]').waitFor();
    assert.equal(await window.locator(".mermaid-fullscreen").evaluate((node) => node.matches(":popover-open")), false);
    await window.keyboard.press("Escape");
    // Use new source so Elm replaces the attribute we changed for the
    // retained-block checks above, rather than reusing its old virtual node.
    await setEditorContent(window, fenceBlock("flowchart TD\n A[Recovered] --> B[Fresh]\n"));
    await window.waitForFunction(() => document.querySelectorAll('.mermaid').length === 1
      && document.querySelector('.mermaid')?.dataset.state === "rendered");
    await openSettings(window);
    await window.getByTestId("preview-mono-toggle").click();
    await window.waitForFunction(() => document.querySelector('.mermaid[data-state="rendered"] svg style')?.textContent.includes('SF Mono'));
    await window.getByTestId("preview-mono-toggle").click();
    await window.getByTestId("settings-picker-theme").click();
    await window.getByTestId("settings-option-theme-github-dark").click();
    await window.keyboard.press("Escape");
    await setEditorContent(window, "# Diagrams\n\n" + source + "\n```javascript\n// Code has its own surface\nconst answer = 42;\n```\n");
    await window.waitForFunction(() => document.querySelectorAll('.mermaid[data-state="rendered"]').length === 3);
    if (await first.getAttribute("data-size") === "actual") {
      await first.getByRole("button", { name: "Show diagram at actual size", exact: true }).click();
    }
    if (process.env.FENCE_SCREENSHOT_DIR) {
      await fs.mkdir(process.env.FENCE_SCREENSHOT_DIR, { recursive: true });
      await window.screenshot({ path: path.join(process.env.FENCE_SCREENSHOT_DIR, "mermaid-dark.png") });
    }
  } finally { await fence.close(); }
});

test("code blocks and inline code are darker than the document in every theme", async () => {
  const fence = await launchFence({ files: { "note.md": "# Code surfaces\n\nAn `inline` snippet.\n\n```javascript\n// A comment\nconst answer = 42;\n```\n" } });
  try {
    const { window } = fence;
    await window.locator(".md-code-block").waitFor();
    const themes = ["catppuccin-mocha", "light", "polar-night", "deep-tide", "github-dark", "vscode-dark", "fleet-dark",
      "dracula", "one-dark", "tokyo-night", "nord", "jetbrains-dark", "jetbrains-light", "jetbrains-islands-dark", "jetbrains-islands-light"];
    for (const theme of themes) {
      const colors = await window.evaluate((name) => {
        document.documentElement.dataset.theme = name;
        const ctx = document.createElement("canvas").getContext("2d");
        const luminance = (node) => {
          ctx.fillStyle = getComputedStyle(node).backgroundColor;
          ctx.fillRect(0, 0, 1, 1);
          const rgb = [...ctx.getImageData(0, 0, 1, 1).data].slice(0, 3).map((v) => {
            const x = v / 255;
            return x <= 0.04045 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4;
          });
          return rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722;
        };
        return { document: luminance(document.querySelector(".preview-container")),
          code: luminance(document.querySelector(".md-code-block")), inline: luminance(document.querySelector(".preview-content .md-code-span")) };
      }, theme);
      assert.ok(colors.code < colors.document, `${theme}: code must be darker`);
      assert.ok(colors.inline < colors.document, `${theme}: inline code must be darker`);
    }
    if (process.env.FENCE_SCREENSHOT_DIR) {
      await fs.mkdir(process.env.FENCE_SCREENSHOT_DIR, { recursive: true });
      await window.screenshot({ path: path.join(process.env.FENCE_SCREENSHOT_DIR, "code-islands-light.png") });
    }
  } finally { await fence.close(); }
});

test("HTML and PDF exports include diagrams even when Source is shown, without controls or duplicate source", async () => {
  const fence = await launchFence({ files: { "note.md": fenceBlock(flow) + "\n" + fenceBlock(flow) } });
  try {
    const { window } = fence;
    await window.waitForFunction(() => document.querySelectorAll('.mermaid[data-state="rendered"]').length === 2);
    await ready(window).first().getByRole("button", { name: "Show diagram source", exact: true }).click();
    const target = path.join(fence.workspace, "diagrams.html");
    await stubSaveDialog(fence.app, target);
    await sendFromElm(fence.app, { tag: "exportRequested", format: "html" });
    await waitForPath(target, 20000);
    const html = await fs.readFile(target, "utf8");
    const body = html.slice(html.indexOf("<body>"));
    assert.equal((body.match(/<svg /g) || []).length, 2);
    assert.doesNotMatch(body, /<button|class="mermaid-bar"|class="mermaid-source|flowchart LR/);
    assert.match(body, /data-view="diagram"/);
    const clipboard = await captureClipboard(fence.app);
    await sendFromElm(fence.app, { tag: "exportRequested", format: "clipboard" });
    const copied = await waitFor(clipboard, { timeout: 10000 });
    assert.match(copied.text, /Start/);
    assert.doesNotMatch(copied.text, /Actual size|flowchart LR|font-family|fence-diagram-copy/);
    const pdf = path.join(fence.workspace, "diagrams.pdf");
    await stubSaveDialog(fence.app, pdf);
    await sendFromElm(fence.app, { tag: "exportRequested", format: "pdf" });
    const bytes = await waitFor(async () => {
      try {
        const bytes = await fs.readFile(pdf);
        return bytes.subarray(-16).includes(Buffer.from("%%EOF")) ? bytes : null;
      } catch (error) {
        if (error.code !== "ENOENT") throw error;
        return null;
      }
    }, { timeout: 20000 });
    assert.equal(bytes.subarray(0, 4).toString(), "%PDF");
  } finally { await fence.close(); }
});
