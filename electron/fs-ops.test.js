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
    // realpath: on macOS the temp dir is a symlink (/var -> /private/var) and
    // fs-ops canonicalizes every path it returns.
    workspace = await fs.promises.realpath(await fs.promises.mkdtemp(path.join(os.tmpdir(), "fence-workspace-")));
    outside = await fs.promises.realpath(await fs.promises.mkdtemp(path.join(os.tmpdir(), "fence-outside-")));
    await fsOps.setWorkspace(workspace);
  });

  afterEach(async () => {
    await fsOps.setWorkspace(null);
    await fs.promises.rm(workspace, { recursive: true, force: true });
    await fs.promises.rm(outside, { recursive: true, force: true });
  });

  test("resolves encoded image URLs beside the document, with parent paths and fragments", async () => {
    await fs.promises.mkdir(path.join(workspace, "docs"));
    await fs.promises.writeFile(path.join(workspace, "docs", "note.md"), "");
    await fs.promises.writeFile(path.join(workspace, "a b.svg"), "<svg/>");
    assert.equal(await fsOps.readImage(path.join(workspace, "docs", "note.md"), "../a%20b.svg?raw=1#icon"),
      `data:image/svg+xml;base64,${Buffer.from("<svg/>").toString("base64")}#icon`);
  });

  test("local image reads stay in the workspace and only accept bounded image files", async () => {
    const doc = path.join(workspace, "note.md");
    await fs.promises.writeFile(doc, "");
    await fs.promises.writeFile(path.join(outside, "private.svg"), "<svg/>");
    await fs.promises.symlink(outside, path.join(workspace, "linked"), "dir");
    await assert.rejects(fsOps.readImage(doc, "linked/private.svg"), /outside workspace/);
    await assert.rejects(fsOps.readImage(doc, "note.md"), /Unsupported image type/);
    await assert.rejects(fsOps.readImage(doc, "https://example.com/image.png"), /Not a local image/);
    await fs.promises.writeFile(path.join(workspace, "large.png"), "");
    await fs.promises.truncate(path.join(workspace, "large.png"), 33 * 1024 * 1024);
    await assert.rejects(fsOps.readImage(doc, "large.png"), /32 MiB/);
  });

  test("resolveImagePath rejects a missing image and a document outside the workspace", async () => {
    const doc = path.join(workspace, "note.md");
    await fs.promises.writeFile(doc, "");
    await assert.rejects(fsOps.resolveImagePath(doc, "missing.png"), { code: "ENOENT" });
    await assert.rejects(fsOps.resolveImagePath(doc, "docs"), /Unsupported image type/);
    await fs.promises.writeFile(path.join(outside, "note.md"), "");
    await fs.promises.writeFile(path.join(outside, "pic.png"), "");
    await assert.rejects(fsOps.resolveImagePath(path.join(outside, "note.md"), "pic.png"), /outside workspace/);
  });

  test("watchDir reports markdown changes until unwatchDir removes the watcher", async () => {
    const file = path.join(workspace, "watched.md");
    const events = [];
    const next = (predicate) => new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error(`timed out waiting; saw ${JSON.stringify(events)}`)), 5000);
      const tick = () => (predicate() ? (clearTimeout(timer), resolve()) : setTimeout(tick, 20));
      tick();
    });
    const seen = (event) => events.some((e) => e.event === event && e.path === file);
    await fsOps.watchDir(workspace, (event, p) => events.push({ event, path: p }));
    // chokidar needs a moment to be ready before the first write is noticed.
    await new Promise((resolve) => setTimeout(resolve, 300));

    await fs.promises.writeFile(file, "one");
    await next(() => seen("add"));
    await fs.promises.writeFile(file, "two");
    await next(() => seen("change"));
    await fs.promises.unlink(file);
    await next(() => seen("unlink"));

    await fsOps.unwatchDir(workspace);
    const before = events.length;
    await fs.promises.writeFile(file, "silent");
    await new Promise((resolve) => setTimeout(resolve, 400));
    assert.equal(events.length, before);

    // The map entry is gone: a fresh watchDir on the same path takes a new
    // callback instead of being ignored as a duplicate.
    const again = [];
    await fsOps.watchDir(workspace, (event) => again.push(event));
    await new Promise((resolve) => setTimeout(resolve, 300));
    await fs.promises.writeFile(file, "again");
    await next(() => again.includes("change"));
    await fsOps.unwatchDir(workspace);
  });

  test("grep treats regex metacharacters literally and skips oversized files", async () => {
    await fs.promises.writeFile(path.join(workspace, "a.md"), "price is $5.00 (approx)\nprice is 5x00", "utf-8");
    const hits = await fsOps.grep(workspace, "$5.00 (approx)");
    assert.equal(hits.length, 1);
    assert.equal(hits[0].line, 1);
    assert.deepEqual(await fsOps.grep(workspace, "5.00"), [{ ...hits[0], column: 10 }]);

    const big = path.join(workspace, "big.md");
    await fs.promises.writeFile(big, "needle", "utf-8");
    await fs.promises.truncate(big, 4 * 1024 * 1024 + 1);
    assert.deepEqual(await fsOps.grep(workspace, "needle"), []);
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

    const discovered = [];
    const names = (await fsOps.readDir(workspace, (p) => discovered.push(path.basename(p)))).map((e) => e.name);

    // Directories that hold markdown directly are listed at once; "deep" only
    // holds it further down and is confirmed in the background.
    assert.deepEqual(names, ["docs", "notes.MKD", "top.md"]);
    await new Promise((resolve) => setTimeout(resolve, 200));
    assert.deepEqual(discovered, ["deep"]);
  });

  test("a huge markdown-free tree is hidden, and its scan stops on workspace switch", async () => {
    const dir = path.join(workspace, "big");
    await fs.promises.mkdir(dir);
    await Promise.all(Array.from({ length: 6000 }, (_, i) => fs.promises.writeFile(path.join(dir, `f${i}.txt`), "")));
    assert.equal(await fsOps.containsMarkdown(dir), false);

    await fs.promises.mkdir(path.join(dir, "later"));
    await fs.promises.writeFile(path.join(dir, "later", "note.md"), "");
    const scan = fsOps.containsMarkdown(dir);
    await fsOps.setWorkspace(workspace);
    assert.equal(await scan, false);
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

  test("creates files and directories, refusing to clobber an existing name", async () => {
    const created = await fsOps.createFile(workspace, "new.md");
    assert.equal(created.path, path.join(workspace, "new.md"));
    assert.equal(await fs.promises.readFile(created.path, "utf-8"), "");

    await fs.promises.writeFile(path.join(workspace, "taken.md"), "keep", "utf-8");
    await assert.rejects(fsOps.createFile(workspace, "taken.md"), /already exists/);
    assert.equal(await fs.promises.readFile(path.join(workspace, "taken.md"), "utf-8"), "keep");

    const dir = await fsOps.createDir(workspace, "folder");
    assert.equal((await fs.promises.stat(dir.path)).isDirectory(), true);
    await assert.rejects(fsOps.createDir(workspace, "folder"), /already exists/);
  });

  test("rejects names that escape their parent directory", async () => {
    for (const name of ["../escape.md", "a/b.md", "", ".", "..", "/abs.md"]) {
      await assert.rejects(fsOps.createFile(workspace, name), /Invalid name/);
    }
    assert.equal(await fs.promises.readdir(outside).then((n) => n.length), 0);
  });

  test("renames within the workspace and refuses to overwrite", async () => {
    await fs.promises.writeFile(path.join(workspace, "old.md"), "body", "utf-8");
    await fs.promises.writeFile(path.join(workspace, "other.md"), "other", "utf-8");

    const renamed = await fsOps.renamePath(path.join(workspace, "old.md"), "new.md");
    assert.equal(renamed.path, path.join(workspace, "new.md"));
    assert.equal(await fs.promises.readFile(renamed.path, "utf-8"), "body");

    await assert.rejects(fsOps.renamePath(renamed.path, "other.md"), /already exists/);
    await assert.rejects(fsOps.renamePath(renamed.path, "../out.md"), /Invalid name/);
    assert.equal(await fs.promises.readFile(renamed.path, "utf-8"), "body");
  });

  test("lists every markdown file under the workspace", async () => {
    const mk = (rel) => fs.promises.mkdir(path.join(workspace, rel), { recursive: true });
    const touch = (rel) => fs.promises.writeFile(path.join(workspace, rel), "", "utf-8");
    await mk("docs/deep");
    await touch("docs/deep/inner.md");
    await touch("docs/guide.md");
    await touch("top.md");
    await touch("ignored.txt");
    await mk("node_modules");
    await touch("node_modules/README.md");
    await mk(".git");
    await touch(".git/notes.md");

    const files = await fsOps.listMarkdownFiles(workspace);

    assert.deepEqual(files.map((f) => f.relative).sort(), ["docs/deep/inner.md", "docs/guide.md", "top.md"]);
  });

  test("greps markdown files for a literal query, capped and case-insensitive", async () => {
    await fs.promises.writeFile(path.join(workspace, "a.md"), "alpha\nBETA line\ngamma", "utf-8");
    await fs.promises.writeFile(path.join(workspace, "b.md"), "nothing here", "utf-8");
    await fs.promises.writeFile(path.join(workspace, "c.txt"), "beta ignored", "utf-8");

    const hits = await fsOps.grep(workspace, "beta");

    assert.equal(hits.length, 1);
    assert.equal(hits[0].relative, "a.md");
    assert.equal(hits[0].line, 2);
    assert.equal(hits[0].text, "BETA line");
    assert.equal(hits[0].column, 0);

    assert.deepEqual(await fsOps.grep(workspace, ""), []);

    await fs.promises.writeFile(path.join(workspace, "many.md"), Array(50).fill("beta").join("\n"), "utf-8");
    assert.equal((await fsOps.grep(workspace, "beta", { limit: 10 })).length, 10);
  });

  test("writes binary attachments beside the document", async () => {
    const bytes = Buffer.from([0x89, 0x50, 0x4e, 0x47]);
    const written = await fsOps.writeBinary(path.join(workspace, "assets"), "image.png", bytes);

    assert.equal(written.path, path.join(workspace, "assets", "image.png"));
    assert.deepEqual(await fs.promises.readFile(written.path), bytes);
    await assert.rejects(fsOps.writeBinary(path.join(outside, "assets"), "x.png", bytes), /outside workspace/);
  });
});
