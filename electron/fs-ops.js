const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const chokidar = require("chokidar");

const { pathToFileURL, fileURLToPath } = require("node:url");

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
  const next = dirPath ? await fs.promises.realpath(path.resolve(dirPath)) : null;
  await closeWatchers();
  currentWorkspace = next;
  scanGeneration += 1;
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

// Bumped on every workspace switch so background discovery walks started for
// the old workspace stop instead of announcing folders into the new one.
let scanGeneration = 0;

// At most this many discovery walks read the disk at once, so a workspace
// with many large markdown-free folders cannot crowd out the file the user
// just asked to open. Walks past the limit wait their turn.
const MAX_CONCURRENT_SCANS = 4;
let activeScans = 0;
const waitingScans = [];

async function withScanSlot(run) {
  if (activeScans >= MAX_CONCURRENT_SCANS) await new Promise((resolve) => waitingScans.push(resolve));
  activeScans += 1;
  try {
    return await run();
  } finally {
    activeScans -= 1;
    waitingScans.shift()?.();
  }
}

// Caps for the whole-workspace walk behind quick-open and search. Generous
// enough for any notes folder, low enough that a wrong root can't hang the app.
const LIST_MAX_FILES = 20000;
const GREP_MAX_HITS = 500;
const GREP_MAX_FILE_BYTES = 4 * 1024 * 1024;

// A single path segment the user typed: no separators, no traversal, nothing
// that could reach outside the directory it is being created in.
function safeName(name) {
  if (typeof name !== "string" || name === "" || name === "." || name === "..") {
    throw new Error(`Invalid name: ${name}`);
  }
  if (name !== path.basename(name) || name.includes("/") || name.includes("\\")) {
    throw new Error(`Invalid name: ${name}`);
  }
  return name;
}

async function createFile(dirPath, name) {
  const canonical = await pathWithinWorkspace(dirPath);
  const target = path.join(canonical, safeName(name));
  let handle;
  try {
    handle = await fs.promises.open(target, "wx", 0o666);
  } catch (error) {
    if (error.code === "EEXIST") throw new Error(`${name} already exists`);
    throw error;
  }
  await handle.close();
  return { path: target };
}

async function createDir(dirPath, name) {
  const canonical = await pathWithinWorkspace(dirPath);
  const target = path.join(canonical, safeName(name));
  try {
    await fs.promises.mkdir(target);
  } catch (error) {
    if (error.code === "EEXIST") throw new Error(`${name} already exists`);
    throw error;
  }
  return { path: target };
}

async function renamePath(fromPath, name) {
  const canonical = await pathWithinWorkspace(fromPath);
  const target = path.join(path.dirname(canonical), safeName(name));
  await pathWithinWorkspace(target);
  if (target !== canonical && (await exists(target))) {
    throw new Error(`${name} already exists`);
  }
  await fs.promises.rename(canonical, target);
  return { from: canonical, path: target };
}

async function writeBinary(dirPath, name, data) {
  const canonical = await pathWithinWorkspace(dirPath);
  const target = path.join(canonical, safeName(name));
  await fs.promises.mkdir(canonical, { recursive: true });
  await fs.promises.writeFile(target, data);
  return { path: target };
}

async function exists(target) {
  return fs.promises
    .access(target)
    .then(() => true)
    .catch(() => false);
}

// Every markdown file under the workspace, for quick-open and search. Same
// pruning as the tree (hidden and noise directories), with its own file cap.
async function listMarkdownFiles(rootPath) {
  const root = await pathWithinWorkspace(rootPath);
  const found = [];

  async function walk(dirPath) {
    if (found.length >= LIST_MAX_FILES) return;
    let entries;
    try {
      entries = await fs.promises.readdir(dirPath, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      if (found.length >= LIST_MAX_FILES) return;
      if (entry.name.startsWith(".")) continue;
      const full = path.join(dirPath, entry.name);
      if (entry.isDirectory()) {
        if (!NOISE_DIRS.has(entry.name)) await walk(full);
      } else if (entry.isFile() && isMarkdownFile(entry.name)) {
        found.push({ path: full, relative: path.relative(root, full).split(path.sep).join("/") });
      }
    }
  }

  await walk(root);
  found.sort((a, b) => a.relative.localeCompare(b.relative, undefined, { sensitivity: "base" }));
  return found;
}

// Literal, case-insensitive substring search across the workspace's markdown.
// ponytail: plain read-and-scan; swap in ripgrep if a large workspace drags.
async function grep(rootPath, query, { limit = GREP_MAX_HITS } = {}) {
  if (typeof query !== "string" || query === "") return [];
  const needle = query.toLowerCase();
  const files = await listMarkdownFiles(rootPath);
  const hits = [];

  for (const file of files) {
    if (hits.length >= limit) break;
    let stats;
    try {
      stats = await fs.promises.stat(file.path);
    } catch {
      continue;
    }
    if (stats.size > GREP_MAX_FILE_BYTES) continue;
    let content;
    try {
      content = await fs.promises.readFile(file.path, "utf-8");
    } catch {
      continue;
    }
    if (!content.toLowerCase().includes(needle)) continue;
    const lines = content.split("\n");
    for (let i = 0; i < lines.length && hits.length < limit; i += 1) {
      const column = lines[i].toLowerCase().indexOf(needle);
      if (column === -1) continue;
      hits.push({
        path: file.path,
        relative: file.relative,
        line: i + 1,
        column,
        text: lines[i].length > 300 ? `${lines[i].slice(0, 300)}\u2026` : lines[i],
      });
    }
  }
  return hits;
}

function isMarkdownFile(name) {
  return MARKDOWN_EXTENSIONS.has(path.extname(name).toLowerCase());
}

function hasMarkdownEntry(entries) {
  return entries.some((entry) => entry.isFile() && isMarkdownFile(entry.name));
}

// Does this directory (recursively) contain a markdown file? Hidden and noise
// directories are skipped. There is no size budget: this runs in the
// background after the listing is sent, and stops if the workspace changes.
function containsMarkdown(dirPath) {
  const generation = scanGeneration;
  // Symlinked directories fail isDirectory(), so the walk cannot loop.
  async function walk(current) {
    let entries;
    try {
      entries = await fs.promises.readdir(current, { withFileTypes: true });
    } catch {
      return false;
    }
    if (generation !== scanGeneration) return false;
    if (hasMarkdownEntry(entries)) return true;
    for (const entry of entries) {
      if (!entry.isDirectory() || entry.name.startsWith(".") || NOISE_DIRS.has(entry.name)) continue;
      if (await walk(path.join(current, entry.name))) return true;
    }
    return false;
  }
  return withScanSlot(() => (generation === scanGeneration ? walk(dirPath) : false));
}

// Lists markdown files and the directories that directly hold some. A
// directory whose markdown sits deeper is confirmed in the background and
// reported through `onDiscovered`, so a huge markdown-free tree never delays
// the listing and never shows up.
async function readDir(dirPath, onDiscovered) {
  const canonical = await pathWithinWorkspace(dirPath);
  const entries = await fs.promises.readdir(canonical, { withFileTypes: true });
  const relevant = await Promise.all(
    entries.map(async (entry) => {
      if (entry.name.startsWith(".")) return false;
      if (!entry.isDirectory()) return isMarkdownFile(entry.name);
      if (NOISE_DIRS.has(entry.name)) return false;
      const child = path.join(canonical, entry.name);
      let children;
      try {
        children = await fs.promises.readdir(child, { withFileTypes: true });
      } catch {
        return false;
      }
      if (hasMarkdownEntry(children)) return true;
      if (onDiscovered) {
        containsMarkdown(child).then((yes) => yes && onDiscovered(child), () => {});
      }
      return false;
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

async function writeFile(filePath, content, expectedRevision = null, selectedBySaveDialog = false) {
  const canonical = selectedBySaveDialog ? await canonicalPath(filePath) : await pathWithinWorkspace(filePath);
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
    // Coalesce writes until stable instead of dropping change events in the
    // default 50 ms throttle window (e.g. an external edit just after a save).
    awaitWriteFinish: { stabilityThreshold: 100, pollInterval: 20 },
    ignored: (candidate) =>
      candidate !== canonical && path.basename(candidate).startsWith("."),
  });
  watcher.on("all", (event, filePath) => callback(event, filePath));
  watchers.set(canonical, watcher);
}

async function unwatchDir(dirPath) {
  const resolved = path.resolve(dirPath);
  const canonical = watchers.has(resolved) ? resolved : await pathWithinWorkspace(dirPath);
  const watcher = watchers.get(canonical);
  if (watcher) {
    await watcher.close();
    watchers.delete(canonical);
  }
}

// Every check behind a preview image: the document and the image must both
// canonicalize inside the workspace, the source must be a local relative or
// file: reference, and the target a bounded regular file of a known type.
// Serves both the fence-image:// protocol and export inlining.
async function resolveImagePath(documentPath, source) {
  const document = await pathWithinWorkspace(documentPath);
  const url = new URL(source, pathToFileURL(document));
  if (url.protocol !== "file:") throw new Error("Not a local image");
  const imagePath = await pathWithinWorkspace(fileURLToPath(url));
  const mime = {
    ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
    ".gif": "image/gif", ".webp": "image/webp", ".svg": "image/svg+xml",
    ".avif": "image/avif", ".bmp": "image/bmp", ".ico": "image/x-icon",
  }[path.extname(imagePath).toLowerCase()];
  if (!mime) throw new Error("Unsupported image type");
  const stat = await fs.promises.stat(imagePath);
  if (!stat.isFile() || stat.size > 32 * 1024 * 1024) throw new Error("Image exceeds 32 MiB or is not a file");
  return { imagePath, mime, hash: url.hash };
}

// Inline copy of an image for exports, which must stand on their own.
async function readImage(documentPath, source) {
  const { imagePath, mime, hash } = await resolveImagePath(documentPath, source);
  const bytes = await fs.promises.readFile(imagePath);
  return `data:${mime};base64,${bytes.toString("base64")}${hash}`;
}

module.exports = {
  FileConflictError,
  containsMarkdown,
  createDir,
  createFile,
  grep,
  listMarkdownFiles,
  renamePath,
  writeBinary,
  isMarkdownFile,
  readDir,
  readFile,
  readImage,
  resolveImagePath,
  resolvePath,
  revisionForContent,
  setWorkspace,
  watchDir,
  writeFile,
  unwatchDir,
};
