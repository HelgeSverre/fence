// Acceptance gate for the virtualized editor (slice 1, read-only): the 712KB
// reference document opens with only the visible rows in the DOM, paints its
// first screen well under the textarea editor's floor, and scrolls to the end
// without any long layout.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { test, describe } = require("node:test");
const { launchFence } = require("./helpers");

const SOURCE = process.env.FENCE_LARGE_FILE || "/Users/helge/code/access-virus-archive/Access-Virus-Soundsets.md";

async function withTrace(fence, body) {
  const cdp = await fence.app.context().newCDPSession(fence.window);
  const events = [];
  cdp.on("Tracing.dataCollected", (e) => events.push(...e.value));
  const finished = new Promise((resolve) => cdp.on("Tracing.tracingComplete", resolve));
  await cdp.send("Tracing.start", { categories: "devtools.timeline,disabled-by-default-devtools.timeline,blink.user_timing" });
  await body();
  await cdp.send("Tracing.end");
  await finished;
  events.sort((a, b) => a.ts - b.ts);
  return events;
}

describe("virtual editor", { skip: !fs.existsSync(SOURCE) && `no ${path.basename(SOURCE)}` }, () => {
  test("renders only visible rows, paints fast, and scrolls the reference file without long layouts", async () => {
    const content = fs.readFileSync(SOURCE, "utf-8");
    const lineCount = content.split("\n").length;
    const fence = await launchFence({ files: { "warmup.md": "# warm\n", "big.md": content }, open: "warmup.md", state: { virtualEditor: true } });
    try {
      const { window } = fence;
      await window.getByTestId("veditor").waitFor();
      if (process.env.FENCE_E2E_CSS) await window.evaluate((css) => { const st = document.createElement("style"); st.textContent = css; document.head.appendChild(st); }, process.env.FENCE_E2E_CSS);
      await window.evaluate(() => {
        new MutationObserver(() => {
          if (!window.__marked && document.querySelector("[data-testid=veditor] .veditor-spacer")?.style.height.replace("px", "") > 100000) {
            window.__marked = true;
            performance.mark("fence:content-in-dom");
          }
        }).observe(document.body, { childList: true, subtree: true, attributes: true });
      });

      const events = await withTrace(fence, async () => {
        await window.getByTestId("tree-file").filter({ hasText: "big.md" }).click();
        await window.waitForFunction(() => window.__marked);
        // let the preview's progressive fill-in finish so scroll layouts are the editor's alone
        await window.waitForFunction(
          () => new Promise((resolve) => { const n = document.querySelectorAll(".preview-chunk").length; setTimeout(() => resolve(n > 0 && document.querySelectorAll(".preview-chunk").length === n), 400); }),
          undefined,
          { timeout: 15000, polling: 100 },
        );
        // scroll to the end in a few jumps, like dragging the scrollbar
        await window.evaluate(async () => {
          performance.mark("fence:scroll-start");
          const el = document.querySelector("[data-testid=veditor]");
          for (let i = 1; i <= 5; i++) {
            el.scrollTop = (el.scrollHeight * i) / 5;
            await new Promise((r) => setTimeout(r, 80));
          }
          performance.mark("fence:scroll-end");
        });
        await window.waitForTimeout(300);
      });

      const click = events.find((e) => e.name === "EventDispatch" && e.args?.data?.type === "click");
      const mark = events.find((e) => e.name === "fence:content-in-dom");
      const commit = events.find((e) => e.name === "Commit" && e.pid === click.pid && e.tid === click.tid && e.ts > mark.ts);
      assert.ok(click && mark && commit, "trace incomplete");
      const paintedMs = Math.round((commit.ts + commit.dur - click.ts) / 1000);
      const scrollStart = events.find((e) => e.name === "fence:scroll-start").ts;
      const scrollEnd = events.find((e) => e.name === "fence:scroll-end").ts;
      const layoutsDuringScroll = events.filter((e) => e.name === "Layout" && e.ts > scrollStart && e.ts < scrollEnd);
      const worst = layoutsDuringScroll.sort((a, b) => b.dur - a.dur)[0];
      const worstLayout = worst ? worst.dur / 1000 : 0;
      const worstInfo = worst ? ` (dirty ${worst.args?.beginData?.dirtyObjects}/${worst.args?.beginData?.totalObjects} objects)` : "";

      const dom = await window.evaluate(() => ({
        rows: document.querySelectorAll(".veditor-row").length,
        lastRowText: [...document.querySelectorAll(".veditor-row")].pop()?.textContent,
        scrollTop: document.querySelector("[data-testid=veditor]").scrollTop,
      }));
      console.log(`virtual-editor: first frame ${paintedMs}ms, ${dom.rows} rows in DOM for ${lineCount} lines, worst layout during scroll ${worstLayout.toFixed(1)}ms${worstInfo}`);
      assert.ok(paintedMs < 150, `first frame painted after ${paintedMs}ms`);
      assert.ok(dom.rows < 200, `${dom.rows} rows rendered`);
      assert.ok(worstLayout < 16, `a layout during scroll took ${worstLayout.toFixed(1)}ms`);
      assert.equal(dom.lastRowText, content.split("\n").filter((l, i, a) => i === a.length - 1 || l !== "").pop() ?? "", "last line is not rendered at the end");
    } finally {
      await fence.close();
    }
  });
});
