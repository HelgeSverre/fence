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

async function readDir(dirPath) {
  const canonical = await pathWithinWorkspace(dirPath);
  const entries = await fs.promises.readdir(canonical, { withFileTypes: true });
  return entries
    .filter((entry) => !entry.name.startsWith("."))
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
  readDir,
  readFile,
  resolvePath,
  revisionForContent,
  setWorkspace,
  watchDir,
  writeFile,
  unwatchDir,
};
