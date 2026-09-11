// Portable fixtures: this test must not silently skip on another developer's machine.
const assert = require("node:assert/strict");
const { test } = require("node:test");
const { launchFence, waitForPreviewSettled } = require("./helpers");

async function trace(fence, body) {
  const cdp = await fence.app.context().newCDPSession(fence.window);
  const events = [];
  cdp.on("Tracing.dataCollected", (e) => events.push(...e.value));
  const done = new Promise((resolve) => cdp.on("Tracing.tracingComplete", resolve));
  await cdp.send("Tracing.start", { categories: "devtools.timeline,disabled-by-default-devtools.timeline,blink.user_timing" });
  await body();
  await cdp.send("Tracing.end");
  await done;
  await cdp.detach();
  return events.sort((a, b) => a.ts - b.ts);
}

const fixtures = {
  lines: Array.from({ length: 10000 }, (_, i) => i % 10 === 0 ? "" : `${i}: ordinary prose with **highlighted words** and a [link](note.md).`).join("\n"),
  prose: Array.from({ length: 1000 }, (_, i) => `${i}: ${"A longer paragraph with words and `inline code` to wrap. ".repeat(13)}\n`).join("\n"),
  paragraph: "A single paragraph with words and **syntax** to wrap. ".repeat(14000),
};

for (const [name, content] of Object.entries(fixtures)) {
  for (const softWrap of [false, true]) {
    test(`editor performance: ${name}, wrap ${softWrap ? "on" : "off"}`, async () => {
      const fence = await launchFence({ files: { "warm.md": "warm", "big.md": content }, open: "warm.md", state: { softWrap } });
      try {
        const { window } = fence;
        const started = performance.now();
        await window.getByTestId("tree-file").filter({ hasText: "big.md" }).click();
        await window.waitForFunction((length) => Number(document.querySelector(".veditor").dataset.length) === length, content.length);
        const openMs = performance.now() - started;
        // Let the independently progressive preview finish before measuring editor work.
        await waitForPreviewSettled(window);
        // Warm the first edit (dirty title/header and its preview update) before
        // measuring steady typing, just like the reference keystroke test.
        await window.evaluate(() => {
          const input = document.querySelector(".veditor-input");
          input.value = "x";
          input.dispatchEvent(new InputEvent("input", { data: "x", inputType: "insertText", bubbles: true }));
        });
        await window.waitForTimeout(500);
        const events = await trace(fence, async () => {
          await window.evaluate(async () => {
            const frame = () => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
            const editor = document.querySelector(".veditor");
            performance.mark("wrap:scroll:start");
            for (let i = 0; i < 12; i++) {
              editor.scrollTop = (editor.scrollHeight - editor.clientHeight) * i / 11;
              await frame();
            }
            performance.mark("wrap:scroll:end");
            // Place the cursor at the end via the editor's normal keyboard path.
            const input = document.querySelector(".veditor-input");
            input.focus({ preventScroll: true });
            input.dispatchEvent(new KeyboardEvent("keydown", { key: "End", ctrlKey: true, metaKey: true, bubbles: true, cancelable: true }));
            await frame();
            performance.mark("wrap:type:start");
            // One burst, then its paint: stay inside the preview debounce so
            // this phase measures the editor, as the reference keystroke test does.
            for (let i = 0; i < 8; i++) {
              input.value = "x";
              input.dispatchEvent(new InputEvent("input", { data: "x", inputType: "insertText", bubbles: true }));
            }
            await frame();
            performance.mark("wrap:type:end");
          });
          if (softWrap) {
            // The edit's preview work is outside the resize measurement too.
            await window.waitForTimeout(500);
            await window.evaluate(async () => {
              const container = document.querySelector(".editor-pane-wrap");
              performance.mark("wrap:resize:start");
              // The real pane width changes, exercising ResizeObserver and Elm reflow.
              const original = container.style.width;
              const width = container.getBoundingClientRect().width;
              for (let i = 0; i < 12; i++) {
                container.style.flex = "none";
                container.style.width = `${Math.max(150, width - i * 10)}px`;
                await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
              }
              container.style.width = original;
              container.style.flex = "";
              await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
              performance.mark("wrap:resize:end");
            });
          }
        });
        if (process.env.FENCE_PROFILE) require("node:fs").writeFileSync(`/tmp/fence-wrap-${name}-${softWrap}.json`, JSON.stringify(events));
        const phase = (name) => {
          const start = events.find((e) => e.name === `wrap:${name}:start`)?.ts;
          const end = events.find((e) => e.name === `wrap:${name}:end`)?.ts;
          return events.filter((e) => e.ts >= start && e.ts < end);
        };
        const worst = (items, event) => Math.max(0, ...items.filter((e) => e.name === event).map((e) => e.dur / 1000 || 0));
        const scroll = phase("scroll");
        const typing = phase("type");
        const resize = phase("resize");
        const dom = await window.getByTestId("veditor").evaluate((el) => ({
          rows: el.querySelectorAll(".veditor-row").length,
          limit: Math.ceil(el.clientHeight / parseFloat(el.querySelector(".veditor-caret").style.height)) + 20,
          length: Number(el.dataset.length), left: el.scrollLeft,
        }));
        const dirty = Math.max(0, ...scroll.filter((e) => e.name === "Layout").map((e) => e.args?.beginData?.dirtyObjects || 0));
        if (process.env.FENCE_PERF_LOG) console.log(`wrap-perf ${name} ${softWrap ? "on" : "off"}: open ${openMs.toFixed(1)}ms (driver included), scroll layout ${worst(scroll, "Layout").toFixed(2)}ms, typing layout ${worst(typing, "Layout").toFixed(2)}ms, input handler ${worst(typing, "EventDispatch").toFixed(2)}ms, resize frame ${worst(resize, "FireAnimationFrame").toFixed(2)}ms; ${dom.rows} rows, ${dirty} dirty objects`);
        assert.ok(dom.rows <= dom.limit, `${dom.rows} rendered rows exceed viewport budget ${dom.limit}`);
        assert.equal(dom.length, content.length + 9, "input was lost during virtual scrolling");
        assert.ok(dirty < 5000, `scroll dirtied ${dirty} objects`);
        assert.ok(worst(scroll, "Layout") < 50, "scroll layout exceeded 50ms");
        if (softWrap) {
          assert.equal(dom.left, 0);
          assert.ok(worst(typing, "Layout") < 2, "wrapped typing layout exceeded 2ms");
        }
      } finally { await fence.close(); }
    });
  }
}
