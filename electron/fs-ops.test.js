const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { afterEach, beforeEach, describe, test } = require("node:test");
const fsOps = require("./fs-ops");

describe("workspace filesystem operations", () => {
  let workspace;
  let outside;

  beforeEach(async () => {
    workspace = await fs.promises.mkdtemp(path.join(os.tmpdir(), "fence-workspace-"));
    outside = await fs.promises.mkdtemp(path.join(os.tmpdir(), "fence-outside-"));
    await fsOps.setWorkspace(workspace);
  });

  afterEach(async () => {
    await fsOps.setWorkspace(null);
    await fs.promises.rm(workspace, { recursive: true, force: true });
    await fs.promises.rm(outside, { recursive: true, force: true });
  });

  test("lists only markdown files and directories that lead to some", async () => {
    const mk = (rel) => fs.promises.mkdir(path.join(workspace, rel), { recursive: true });
    const touch = (rel) => fs.promises.writeFile(path.join(workspace, rel), "", "utf-8");
    await mk("docs");
    await touch("docs/guide.md");
    await mk("src");
    await touch("src/app.js");
    await mk("deep/a/b/c");
    await touch("deep/a/b/c/notes.markdown");
    await mk("node_modules/pkg");
    await touch("node_modules/pkg/README.md");
    await mk(".hidden");
    await touch(".hidden/secret.md");
    await mk("empty");
    await touch("top.md");
    await touch("top.txt");
    await touch("notes.MKD");

    const names = (await fsOps.readDir(workspace)).map((e) => e.name);

    assert.deepEqual(names, ["deep", "docs", "notes.MKD", "top.md"]);
  });

  test("a huge directory tree is shown rather than scanned exhaustively", async () => {
    // Above the walk budget the check gives up and reports "yes".
    const dir = path.join(workspace, "big");
    await fs.promises.mkdir(dir);
    await Promise.all(Array.from({ length: 6000 }, (_, i) => fs.promises.writeFile(path.join(dir, `f${i}.txt`), "")));
    assert.equal(await fsOps.containsMarkdown(dir), true);
  });

  test("reads content with a stable revision", async () => {
    const filePath = path.join(workspace, "note.md");
    await fs.promises.writeFile(filePath, "hello", "utf-8");

    const file = await fsOps.readFile(filePath);

    assert.equal(file.content, "hello");
    assert.equal(file.revision, fsOps.revisionForContent("hello"));
  });

  test("writes atomically and rejects stale revisions", async () => {
    const filePath = path.join(workspace, "note.md");
    await fs.promises.writeFile(filePath, "one", "utf-8");
    const original = await fsOps.readFile(filePath);

    const saved = await fsOps.writeFile(filePath, "two", original.revision);
    assert.equal(await fs.promises.readFile(filePath, "utf-8"), "two");
    assert.equal(saved.revision, fsOps.revisionForContent("two"));

    await fs.promises.writeFile(filePath, "external", "utf-8");
    await assert.rejects(
      fsOps.writeFile(filePath, "three", saved.revision),
      (error) => error instanceof fsOps.FileConflictError,
    );
    assert.equal(await fs.promises.readFile(filePath, "utf-8"), "external");
    assert.deepEqual(
      (await fs.promises.readdir(workspace)).filter((name) => name.endsWith(".tmp")),
      [],
    );
  });

  test("hides dotfiles and sorts directories before files", async () => {
    await fs.promises.writeFile(path.join(workspace, "z.md"), "", "utf-8");
    await fs.promises.writeFile(path.join(workspace, ".secret"), "", "utf-8");
    await fs.promises.mkdir(path.join(workspace, "docs"));
    await fs.promises.writeFile(path.join(workspace, "docs", "a.md"), "", "utf-8");

    const entries = await fsOps.readDir(workspace);
    assert.deepEqual(entries.map((entry) => entry.name), ["docs", "z.md"]);
  });

  test(
    "rejects symlinks that escape the workspace",
    { skip: process.platform === "win32" },
    async () => {
      const outsideFile = path.join(outside, "secret.md");
      const link = path.join(workspace, "linked.md");
      await fs.promises.writeFile(outsideFile, "secret", "utf-8");
      await fs.promises.symlink(outsideFile, link);

      await assert.rejects(fsOps.readFile(link), /Path outside workspace/);
      await assert.rejects(fsOps.writeFile(link, "changed"), /Path outside workspace/);
      assert.equal(await fs.promises.readFile(outsideFile, "utf-8"), "secret");
    },
  );
});
