const assert = require("node:assert/strict");
const { test, describe } = require("node:test");
const { MOD, launchFence, waitForEditorValue } = require("./helpers");

const files = {
  "a.md": "# A\nalpha here\n",
  "b.md": "# B\nbeta here\n",
  "docs/plan.md": "# Plan\nalpha again\n",
};

const rows = (window) => window.getByTestId("palette-row").allTextContents();

describe("command palette", () => {
  test("quick-open lists every markdown file and filters as you type", async () => {
    const fence = await launchFence({ files, open: "a.md" });
    try {
      const { window } = fence;
      await window.keyboard.press(`${MOD}+p`);
      await window.getByTestId("palette-input").waitFor();
      await window.waitForFunction(() => document.querySelectorAll("[data-testid=palette-row]").length === 3, undefined, { timeout: 10000 });

      await window.getByTestId("palette-input").fill("plan");
      await window.waitForFunction(() => document.querySelectorAll("[data-testid=palette-row]").length === 1);
      assert.match((await rows(window))[0], /plan\.md/);
    } finally {
      await fence.close();
    }
  });

  test("Enter opens the highlighted file", async () => {
    const fence = await launchFence({ files, open: "a.md" });
    try {
      const { window } = fence;
      await window.keyboard.press(`${MOD}+p`);
      await window.getByTestId("palette-input").fill("b.md");
      await window.waitForFunction(() => document.querySelectorAll("[data-testid=palette-row]").length === 1);
      await window.keyboard.press("Enter");
      await waitForEditorValue(window, "# B\nbeta here\n");
      await window.getByTestId("palette").waitFor({ state: "detached" });
    } finally {
      await fence.close();
    }
  });

  test("arrow keys move the highlight", async () => {
    const fence = await launchFence({ files, open: "a.md" });
    try {
      const { window } = fence;
      await window.keyboard.press(`${MOD}+p`);
      await window.waitForFunction(() => document.querySelectorAll("[data-testid=palette-row]").length === 3, undefined, { timeout: 10000 });
      await window.keyboard.press("ArrowDown");
      await window.waitForFunction(() => document.querySelectorAll("[data-testid=palette-row]")[1]?.classList.contains("active"));
      await window.keyboard.press("ArrowUp");
      await window.waitForFunction(() => document.querySelectorAll("[data-testid=palette-row]")[0]?.classList.contains("active"));
    } finally {
      await fence.close();
    }
  });

  test("Cmd+Shift+C copies the highlighted file's workspace path, Opt+Cmd+C its full path", async () => {
    const fence = await launchFence({ files, open: "a.md" });
    const { window, app } = fence;
    const clipboard = () => app.evaluate(({ clipboard }) => clipboard.readText());
    // the system clipboard is shared with the developer: put it back afterwards
    const before = await clipboard();
    try {
      await window.keyboard.press(`${MOD}+p`);
      await window.getByTestId("palette-input").fill("plan");
      await window.waitForFunction(() => document.querySelectorAll("[data-testid=palette-row]").length === 1);
      // the write crosses IPC, so poll for it
      const copied = async (expected) => {
        for (let i = 0; i < 50 && (await clipboard()) !== expected; i += 1) await new Promise((r) => setTimeout(r, 50));
        return clipboard();
      };
      await window.keyboard.press(`${MOD}+Shift+c`);
      assert.equal(await copied("docs/plan.md"), "docs/plan.md");
      await window.keyboard.press(`Alt+${MOD}+c`);
      assert.equal(await copied(fence.file("docs/plan.md")), fence.file("docs/plan.md"));
      // the palette stays open: copying is not choosing
      await window.getByTestId("palette").waitFor();
    } finally {
      await app.evaluate(({ clipboard }, text) => clipboard.writeText(text), before).catch(() => {});
      await fence.close();
    }
  });

  test("rows name the file and its folder, and the footer lists the keys", async () => {
    const fence = await launchFence({ files, open: "a.md" });
    try {
      const { window } = fence;
      await window.keyboard.press(`${MOD}+p`);
      await window.getByTestId("palette-input").fill("plan");
      await window.waitForFunction(() => document.querySelectorAll("[data-testid=palette-row]").length === 1);
      assert.equal(await window.locator(".palette-row .palette-primary").textContent(), "plan.md");
      assert.equal(await window.locator(".palette-row [data-testid=palette-path]").textContent(), "docs");
      assert.equal(await window.locator(".palette-row mark").first().textContent(), "plan");
      assert.equal(await window.getByTestId("palette-mode").textContent(), "Files");
      assert.equal(await window.getByTestId("palette-count").textContent(), "1 / 3");
      assert.match(await window.getByTestId("palette-footer").textContent(), /Copy path/);
    } finally {
      await fence.close();
    }
  });

  test("the peek pane previews the highlighted document when turned on", async () => {
    const fence = await launchFence({ files, open: "a.md", state: { palettePeek: true } });
    try {
      const { window } = fence;
      await window.keyboard.press(`${MOD}+p`);
      await window.getByTestId("palette-input").fill("plan");
      await window.waitForFunction(() => document.querySelectorAll("[data-testid=palette-row]").length === 1);
      await window.locator("[data-testid=palette-peek] .palette-peek-line", { hasText: "alpha again" }).waitFor();
      const peek = await window.getByTestId("palette-peek").textContent();
      assert.match(peek, /^Plandocs\/plan\.md/);
      assert.match(peek, /2 lines/);
    } finally {
      await fence.close();
    }
  });

  test("the peek pane is off by default", async () => {
    const fence = await launchFence({ files, open: "a.md" });
    try {
      const { window } = fence;
      await window.keyboard.press(`${MOD}+p`);
      await window.getByTestId("palette-input").waitFor();
      assert.equal(await window.getByTestId("palette-peek").count(), 0);
    } finally {
      await fence.close();
    }
  });

  test("workspace search finds matching lines and opens one at its line", async () => {
    const fence = await launchFence({ files, open: "b.md" });
    try {
      const { window } = fence;
      await window.keyboard.press(`${MOD}+Shift+f`);
      await window.getByTestId("palette-input").waitFor();
      await window.getByTestId("palette-input").fill("alpha");
      await window.waitForFunction(() => document.querySelectorAll("[data-testid=palette-row]").length === 2, undefined, { timeout: 10000 });

      const labels = await rows(window);
      assert.ok(labels.some((l) => l.includes("a.md:2")), labels.join(" | "));

      await window.keyboard.press("Enter");
      await waitForEditorValue(window, "# A\nalpha here\n");
      // opened at the hit: the caret sits on line 2
      await window.waitForFunction(() => {
        const caret = document.querySelector("[data-testid=veditor-caret]");
        return caret && Math.round(parseFloat(caret.style.top)) > 0;
      });
    } finally {
      await fence.close();
    }
  });

  test("Escape closes the palette", async () => {
    const fence = await launchFence({ files, open: "a.md" });
    try {
      const { window } = fence;
      await window.keyboard.press(`${MOD}+p`);
      await window.getByTestId("palette-input").waitFor();
      await window.keyboard.press("Escape");
      await window.getByTestId("palette").waitFor({ state: "detached" });
    } finally {
      await fence.close();
    }
  });

  test("back and forward walk the recently opened files", async () => {
    const fence = await launchFence({ files, open: "a.md" });
    try {
      const { window } = fence;
      await window.getByTestId("tree-file").filter({ hasText: "b.md" }).click();
      await waitForEditorValue(window, "# B\nbeta here\n");

      await window.keyboard.press(`${MOD}+[`);
      await waitForEditorValue(window, "# A\nalpha here\n");
      await window.keyboard.press(`${MOD}+]`);
      await waitForEditorValue(window, "# B\nbeta here\n");
    } finally {
      await fence.close();
    }
  });


  test("opening a file from the palette reveals it in the sidebar", async () => {
    const fence = await launchFence({ files, open: "a.md" });
    try {
      const { window } = fence;
      await window.keyboard.press(`${MOD}+p`);
      await window.getByTestId("palette-input").fill("plan");
      // The file list arrives over IPC: Enter before it lands would no-op.
      await window.waitForFunction(() => document.querySelectorAll("[data-testid=palette-row]").length === 1);
      await window.keyboard.press("Enter");
      await waitForEditorValue(window, files["docs/plan.md"]);
      await window.locator("[data-testid=tree-file].selected", { hasText: "plan.md" }).waitFor();
      await window.locator('[aria-expanded="true"] > [data-testid=tree-dir]', { hasText: "docs" }).waitFor();
    } finally {
      await fence.close();
    }
  });

  test("with reveal turned off the tree is left alone", async () => {
    const fence = await launchFence({ files, open: "a.md", state: { revealInSidebar: false } });
    try {
      const { window } = fence;
      await window.keyboard.press(`${MOD}+p`);
      await window.getByTestId("palette-input").fill("plan");
      // The file list arrives over IPC: Enter before it lands would no-op.
      await window.waitForFunction(() => document.querySelectorAll("[data-testid=palette-row]").length === 1);
      await window.keyboard.press("Enter");
      await waitForEditorValue(window, files["docs/plan.md"]);
      assert.equal(await window.getByTestId("tree-file").filter({ hasText: "plan.md" }).count(), 0);
    } finally {
      await fence.close();
    }
  });

  test("the outline pane reports the document's counts", async () => {
    const fence = await launchFence({ files, open: "a.md" });
    try {
      await fence.window.waitForFunction(
        () => document.querySelector("[data-testid=word-count]")?.textContent === "4 words · 3 lines · 15 characters",
        undefined,
        { timeout: 10000 },
      );
    } finally {
      await fence.close();
    }
  });
});

for (const mode of ["editor", "split", "preview"]) {
  test(`workspace search centers the selected result and focuses ${mode}`, async () => {
    const content = "---\ntitle: needle\n---\n\n" + Array.from({ length: 1200 }, (_, i) => `Paragraph ${i}${i === 0 || i === 600 ? " needle" : ""}.\n`).join("\n");
    const fence = await launchFence({ files: { "a.md": "# Start", "long.md": content }, open: "a.md" });
    try {
      const { window } = fence;
      await window.getByTestId(`layout-${mode}`).click();
      await window.keyboard.press(`${MOD}+Shift+f`);
      await window.getByTestId("palette-input").fill("needle");
      await window.waitForFunction(() => document.querySelectorAll("[data-testid=palette-row]").length === 3);
      await window.keyboard.press("ArrowDown");
      await window.keyboard.press("ArrowDown");
      await window.keyboard.press("Enter");
      if (mode !== "preview") await waitForEditorValue(window, content);
      await window.waitForFunction((mode) => {
        const id = mode === "preview" ? "preview-container" : "veditor-input";
        if (document.activeElement?.id !== id) return false;
        if (mode !== "preview") {
          const caret = document.querySelector("[data-testid=veditor-caret]").getBoundingClientRect();
          const pane = document.getElementById("veditor").getBoundingClientRect();
          if (Math.abs(caret.top - pane.top - pane.height / 2) > 35) return false;
        }
        if (mode !== "editor") {
          const paragraph = [...document.querySelectorAll(".preview-content p")].find(p => p.textContent.includes("Paragraph 600"));
          if (!paragraph) return false;
          const rect = paragraph.getBoundingClientRect();
          const pane = document.getElementById("preview-container").getBoundingClientRect();
          if (Math.abs(rect.top + rect.height / 2 - pane.top - pane.height / 2) > 35) return false;
        }
        return true;
      }, mode).catch(async (error) => {
        const state = await window.evaluate(() => {
          const target = [...document.querySelectorAll(".preview-content p")].find(p => p.textContent.includes("Paragraph 600"));
          const rect = element => element?.getBoundingClientRect().toJSON();
          return { active: document.activeElement?.id, fonts: document.fonts.status, target: rect(target), preview: rect(document.getElementById("preview-container")), caret: rect(document.querySelector("[data-testid=veditor-caret]")), editor: rect(document.getElementById("veditor")) };
        });
        throw new Error(`${error.message}\nNavigation state: ${JSON.stringify(state)}`);
      });
      if (mode !== "preview") {
        await window.keyboard.type("X");
        await window.waitForFunction(() => document.querySelector('[data-source-line="1204"]')?.textContent.startsWith("XParagraph 600"));
      }
    } finally {
      await fence.close();
    }
  });
}

test("opening a metadata search result in preview reveals the collapsed fields", async () => {
  const fence = await launchFence({ files: { "a.md": "---\ntitle: hiddenneedle\n---\n\n# Document\n" }, open: "a.md" });
  try {
    const { window } = fence;
    await window.getByTestId("layout-preview").click();
    await window.keyboard.press(`${MOD}+Shift+f`);
    await window.getByTestId("palette-input").fill("hiddenneedle");
    await window.waitForFunction(() => document.querySelectorAll("[data-testid=palette-row]").length === 1);
    await window.keyboard.press("Enter");
    await window.waitForFunction(() => document.querySelector(".frontmatter")?.open && document.activeElement?.id === "preview-container");
  } finally {
    await fence.close();
  }
});
