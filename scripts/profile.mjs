// Open each sample document and record how long it takes to become usable,
// how much DOM it costs and how much memory it holds.
//
// Run on an otherwise idle machine: these are wall-clock numbers and a busy
// box makes them meaningless.
//
//   bunx vite build && node scripts/profile.mjs [glob]
import { readFileSync, readdirSync, mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, basename, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import playwright from "playwright";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const only = process.argv[2];

const samples = readdirSync(join(root, "samples"))
  .filter((f) => f.endsWith(".md"))
  .filter((f) => !only || f.includes(only));

const ms = (n) => `${n.toFixed(0).padStart(6)}ms`;

async function profile(name) {
  const source = readFileSync(join(root, "samples", name), "utf8");
  const ws = mkdtempSync(join(tmpdir(), "fence-prof-"));
  const ud = mkdtempSync(join(tmpdir(), "fence-prof-ud-"));
  writeFileSync(join(ws, name), source, "utf8");

  const started = Date.now();
  const app = await playwright._electron.launch({
    args: [join(root, "dist-electron/main.js"), join(ws, name)],
    cwd: root,
    env: { ...process.env, FENCE_USER_DATA: ud, FENCE_QUIET_WINDOW: "1", ELECTRON_DISABLE_SECURITY_WARNINGS: "true" },
  });
  const w = await app.firstWindow();
  try {
    await w.getByTestId("veditor").waitFor({ state: "attached", timeout: 60000 });
    const editorReady = Date.now() - started;

    // First preview content on screen.
    await w.getByTestId("preview-content").locator("h1, h2, p, ul, table, pre").first().waitFor({ timeout: 60000 });
    const firstPaint = Date.now() - started;

    // Progressive parsing keeps appending chunks; settle when the node count
    // stops growing, which is when the document is fully rendered.
    let previous = -1;
    let settled = Date.now();
    for (let i = 0; i < 400; i += 1) {
      const count = await w.evaluate(() => document.querySelectorAll(".preview-content *").length);
      if (count === previous) break;
      previous = count;
      settled = Date.now();
      await w.waitForTimeout(100);
    }
    const fullRender = settled - started;

    const stats = await w.evaluate(() => ({
      previewNodes: document.querySelectorAll(".preview-content *").length,
      editorRows: document.querySelectorAll(".veditor-row").length,
      heapMB: performance.memory ? Math.round(performance.memory.usedJSHeapSize / 1048576) : null,
    }));

    // Typing latency: time from the keystroke to the editor reflecting it.
    await w.locator(".veditor-spacer").click({ position: { x: 2, y: 2 } });
    await w.waitForFunction(() => document.activeElement?.id === "veditor-input");
    const keystrokes = [];
    for (let i = 0; i < 12; i += 1) {
      const before = await w.evaluate(() => performance.now());
      await w.keyboard.insertText("x");
      const after = await w.evaluate(() => performance.now());
      keystrokes.push(after - before);
    }
    keystrokes.sort((a, b) => a - b);

    return {
      name,
      kb: Math.round(source.length / 1024),
      lines: source.split("\n").length,
      editorReady,
      firstPaint,
      fullRender,
      keyMedian: keystrokes[Math.floor(keystrokes.length / 2)],
      keyWorst: keystrokes.at(-1),
      ...stats,
    };
  } finally {
    await app.close().catch(() => {});
    rmSync(ws, { recursive: true, force: true });
    rmSync(ud, { recursive: true, force: true });
  }
}

const rows = [];
for (const name of samples) {
  process.stderr.write(`profiling ${name}…\n`);
  rows.push(await profile(name));
}

console.log("");
console.log("document           size   lines   ready  1st paint  full render  keypress med/worst  nodes   rows  heap");
console.log("-".repeat(108));
for (const r of rows.sort((a, b) => b.kb - a.kb)) {
  console.log(
    `${basename(r.name, ".md").padEnd(14)} ${String(r.kb).padStart(5)}KB ${String(r.lines).padStart(6)} ` +
      `${ms(r.editorReady)} ${ms(r.firstPaint)} ${ms(r.fullRender)}   ` +
      `${r.keyMedian.toFixed(0).padStart(4)}/${r.keyWorst.toFixed(0).padStart(4)}ms ` +
      `${String(r.previewNodes).padStart(6)} ${String(r.editorRows).padStart(5)} ${String(r.heapMB ?? "-").padStart(4)}MB`,
  );
}
