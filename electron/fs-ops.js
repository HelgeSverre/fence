const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const chokidar = require("chokidar");

const watchers = new Map();
let currentWorkspace = null;

class FileConflictError extends Error {
  constructor(filePath) {
    super(`File changed outside Fence: ${filePath}`);
    this.name = "FileConflictError";
    this.code = "FILE_CONFLICT";
    this.path = filePath;
  }
}

function revisionForContent(content) {
  return crypto.createHash("sha256").update(content).digest("hex");
}

async function closeWatchers() {
  await Promise.all([...watchers.values()].map((watcher) => watcher.close()));
  watchers.clear();
}

async function setWorkspace(dirPath) {
  await closeWatchers();
  currentWorkspace = dirPath
    ? await fs.promises.realpath(path.resolve(dirPath))
    : null;
}

async function canonicalPath(target) {
  const resolved = path.resolve(target);
  try {
    return await fs.promises.realpath(resolved);
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
    const parent = await fs.promises.realpath(path.dirname(resolved));
    return path.join(parent, path.basename(resolved));
  }
}

async function pathWithinWorkspace(target) {
  if (!currentWorkspace) throw new Error("No workspace is open");
  const canonical = await canonicalPath(target);
  if (
    canonical !== currentWorkspace &&
    !canonical.startsWith(currentWorkspace + path.sep)
  ) {
    throw new Error(`Path outside workspace: ${target}`);
  }
  return canonical;
}

async function resolvePath(target) {
  return pathWithinWorkspace(target);
}

const MARKDOWN_EXTENSIONS = new Set([".md", ".markdown", ".mdown", ".mkd"]);

// Directories that never hold a user's notes but can hold thousands of
// READMEs; pruned from the "contains markdown" walk so they stay hidden.
const NOISE_DIRS = new Set(["node_modules", "vendor", "dist", "build", "target", "out", "coverage", "__pycache__"]);
const WALK_MAX_DEPTH = 12;
const WALK_MAX_ENTRIES = 5000;

function isMarkdownFile(name) {
  return MARKDOWN_EXTENSIONS.has(path.extname(name).toLowerCase());
}

// Does this directory (recursively) contain a markdown file? Hidden and
// noise directories are skipped. Huge trees give up early and count as
// "yes" so a big workspace is never silently hidden.
async function containsMarkdown(dirPath, budget = { entries: WALK_MAX_ENTRIES }, depth = 0) {
  if (depth > WALK_MAX_DEPTH || budget.entries <= 0) return true;
  let entries;
  try {
    entries = await fs.promises.readdir(dirPath, { withFileTypes: true });
  } catch {
    return false;
  }
  if (entries.some((entry) => entry.isFile() && isMarkdownFile(entry.name))) return true;
  budget.entries -= entries.length;
  if (budget.entries <= 0) return true;
  for (const entry of entries) {
    if (!entry.isDirectory() || entry.name.startsWith(".") || NOISE_DIRS.has(entry.name)) continue;
    if (await containsMarkdown(path.join(dirPath, entry.name), budget, depth + 1)) return true;
  }
  return false;
}

async function readDir(dirPath) {
  const canonical = await pathWithinWorkspace(dirPath);
  const entries = await fs.promises.readdir(canonical, { withFileTypes: true });
  // Only markdown files and directories that lead to some are worth showing.
  const relevant = await Promise.all(
    entries.map(async (entry) => {
      if (entry.name.startsWith(".")) return false;
      if (entry.isDirectory()) {
        return !NOISE_DIRS.has(entry.name) && (await containsMarkdown(path.join(canonical, entry.name)));
      }
      return isMarkdownFile(entry.name);
    }),
  );
  return entries
    .filter((_, i) => relevant[i])
    .sort((a, b) => {
      if (a.isDirectory() && !b.isDirectory()) return -1;
      if (!a.isDirectory() && b.isDirectory()) return 1;
      return a.name.localeCompare(b.name, undefined, { sensitivity: "base" });
    })
    .map((entry) => ({
      name: entry.name,
      path: path.join(canonical, entry.name),
      fileType: entry.isDirectory() ? "directory" : "file",
      children: entry.isDirectory() ? null : undefined,
    }));
}

async function readFile(filePath) {
  const canonical = await pathWithinWorkspace(filePath);
  const content = await fs.promises.readFile(canonical, "utf-8");
  return { path: canonical, content, revision: revisionForContent(content) };
}

async function writeFile(filePath, content, expectedRevision = null) {
  const canonical = await pathWithinWorkspace(filePath);
  let mode = 0o666;

  try {
    const [current, stats] = await Promise.all([
      fs.promises.readFile(canonical, "utf-8"),
      fs.promises.stat(canonical),
    ]);
    mode = stats.mode;
    if (
      expectedRevision !== null &&
      revisionForContent(current) !== expectedRevision
    ) {
      throw new FileConflictError(canonical);
    }
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
    if (expectedRevision !== null) throw new FileConflictError(canonical);
  }

  const tempPath = path.join(
    path.dirname(canonical),
    `.${path.basename(canonical)}.${process.pid}.${crypto.randomUUID()}.tmp`,
  );
  let handle;
  try {
    handle = await fs.promises.open(tempPath, "wx", mode);
    await handle.writeFile(content, "utf-8");
    await handle.sync();
    await handle.close();
    handle = null;
    await fs.promises.rename(tempPath, canonical);
  } catch (error) {
    if (handle) await handle.close().catch(() => {});
    await fs.promises.unlink(tempPath).catch(() => {});
    throw error;
  }

  return {
    path: canonical,
    revision: revisionForContent(content),
  };
}

async function watchDir(dirPath, callback) {
  const canonical = await pathWithinWorkspace(dirPath);
  if (watchers.has(canonical)) return;

  const watcher = chokidar.watch(canonical, {
    depth: 0,
    ignoreInitial: true,
    ignored: (candidate) =>
      candidate !== canonical && path.basename(candidate).startsWith("."),
  });
  watcher.on("all", (event, filePath) => callback(event, filePath));
  watchers.set(canonical, watcher);
}

async function unwatchDir(dirPath) {
  const canonical = await pathWithinWorkspace(dirPath);
  const watcher = watchers.get(canonical);
  if (watcher) {
    await watcher.close();
    watchers.delete(canonical);
  }
}

module.exports = {
  FileConflictError,
  containsMarkdown,
  isMarkdownFile,
  readDir,
  readFile,
  resolvePath,
  revisionForContent,
  setWorkspace,
  watchDir,
  writeFile,
  unwatchDir,
};
