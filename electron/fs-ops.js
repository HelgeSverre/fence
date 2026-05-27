const fs = require("fs");
const path = require("path");
const chokidar = require("chokidar");

const watchers = new Map();

// Currently open workspace. All read/write/watch operations are constrained
// to paths inside this directory. Set via setWorkspace() when a folder is
// opened; cleared on close.
let currentWorkspace = null;

function setWorkspace(dirPath) {
  currentWorkspace = dirPath ? path.resolve(dirPath) : null;
}

// Throws if the target path resolves outside the active workspace.
// No-op before a workspace is set (e.g. the very first openFolder dialog).
function assertWithinWorkspace(target) {
  if (!currentWorkspace) return;
  const resolved = path.resolve(target);
  if (
    resolved !== currentWorkspace &&
    !resolved.startsWith(currentWorkspace + path.sep)
  ) {
    throw new Error(`Path outside workspace: ${target}`);
  }
}

function readDir(dirPath) {
  assertWithinWorkspace(dirPath);
  const entries = fs.readdirSync(dirPath, { withFileTypes: true });
  return entries
    .filter((e) => !e.name.startsWith("."))
    .sort((a, b) => {
      // Directories first, then alphabetical
      if (a.isDirectory() && !b.isDirectory()) return -1;
      if (!a.isDirectory() && b.isDirectory()) return 1;
      return a.name.localeCompare(b.name, undefined, { sensitivity: "base" });
    })
    .map((e) => ({
      name: e.name,
      path: path.join(dirPath, e.name),
      fileType: e.isDirectory() ? "directory" : "file",
      children: e.isDirectory() ? null : undefined,
    }));
}

function readFile(filePath) {
  assertWithinWorkspace(filePath);
  return fs.readFileSync(filePath, "utf-8");
}

function writeFile(filePath, content) {
  assertWithinWorkspace(filePath);
  fs.writeFileSync(filePath, content, "utf-8");
}

function watchDir(dirPath, callback) {
  assertWithinWorkspace(dirPath);
  if (watchers.has(dirPath)) return;

  const watcher = chokidar.watch(dirPath, {
    depth: 0,
    ignoreInitial: true,
    ignored: /(^|[/\\])\./,
  });

  watcher.on("all", (event, filePath) => {
    callback(event, filePath);
  });

  watchers.set(dirPath, watcher);
}

function unwatchDir(dirPath) {
  const watcher = watchers.get(dirPath);
  if (watcher) {
    watcher.close();
    watchers.delete(dirPath);
  }
}

module.exports = {
  readDir,
  readFile,
  writeFile,
  watchDir,
  unwatchDir,
  setWorkspace,
};
