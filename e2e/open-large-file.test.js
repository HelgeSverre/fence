// Acceptance gate: a real 700KB reference document (10k lines, 265 tables,
// 28k rows) opens from the file tree to a painted first screen in under
// 300ms. "Painted" is the renderer's first compositor commit after the
// document's content reached the DOM, read from a DevTools trace, because
// in-page polling and requestAnimationFrame callbacks queue behind the
// frame work they are trying to measure.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { test, describe } = require("node:test");
const { launchFence } = require("./helpers");

const SOURCE = process.env.FENCE_LARGE_FILE || "/Users/helge/code/access-virus-archive/Access-Virus-Soundsets.md";
const BUDGET_MS = 300;

async function traceOpen(fence, name) {
  const cdp = await fence.app.context().newCDPSession(fence.window);
  const events = [];
  cdp.on("Tracing.dataCollected", (e) => events.push(...e.value));
  const finished = new Promise((resolve) => cdp.on("Tracing.tracingComplete", resolve));
  await cdp.send("Tracing.start", { categories: "devtools.timeline,disabled-by-default-devtools.timeline,blink.user_timing" });
  await fence.window.evaluate(() => {
    const ta = document.querySelector("[data-testid=editor-textarea]");
    new MutationObserver(() => {
      if (ta.value.length > 100000 && !window.__marked) {
        window.__marked = true;
        performance.mark("fence:content-in-dom");
      }
    }).observe(document.body, { childList: true, subtree: true });
  });
  await fence.window.getByTestId("tree-file").filter({ hasText: name }).click();
  await fence.window.waitForFunction(() => window.__marked);
  await fence.window.waitForTimeout(1500);
  await cdp.send("Tracing.end");
  await finished;

  events.sort((a, b) => a.ts - b.ts);
  const click = events.find((e) => e.name === "EventDispatch" && e.args?.data?.type === "click");
  const contentMark = events.find((e) => e.name === "fence:content-in-dom");
  const firstCommit = events.find((e) => e.name === "Commit" && e.pid === click.pid && e.tid === click.tid && e.ts > contentMark.ts);
  assert.ok(click && contentMark && firstCommit, `trace incomplete: click=${!!click} mark=${!!contentMark} commit=${!!firstCommit}`);
  const ms = (e) => Math.round((e.ts - click.ts) / 1000);
  return { contentInDomMs: ms(contentMark), paintedMs: ms(firstCommit) + Math.round(firstCommit.dur / 1000) };
}

describe("opening a large real-world document", { skip: !fs.existsSync(SOURCE) && `no ${path.basename(SOURCE)}` }, () => {
  test(`opens ${path.basename(SOURCE)} to a painted first screen in under ${BUDGET_MS}ms`, async () => {
    const content = fs.readFileSync(SOURCE, "utf-8");
    const fence = await launchFence({ files: { "warmup.md": "# warm\n", "big.md": content }, open: "warmup.md" });
    try {
      const t = await traceOpen(fence, "big.md");
      const state = await fence.window.evaluate(() => ({
        editorChars: document.querySelector("[data-testid=editor-textarea]").value.length,
        previewH1: document.querySelector("[data-testid=preview-content] h1")?.textContent,
      }));
      console.log(`open-large-file: content in DOM ${t.contentInDomMs}ms, first frame painted ${t.paintedMs}ms`);
      assert.equal(state.editorChars, content.length, "editor did not receive the whole document");
      assert.match(state.previewH1 || "", /Access Virus/, "preview did not render the document");
      assert.ok(t.paintedMs < BUDGET_MS, `first frame painted after ${t.paintedMs}ms (budget ${BUDGET_MS}ms)`);
    } finally {
      await fence.close();
    }
  });
});
