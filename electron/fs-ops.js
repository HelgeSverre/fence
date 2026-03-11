const fs = require("fs");
const path = require("path");
const chokidar = require("chokidar");

const watchers = new Map();

function readDir(dirPath) {
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
  return fs.readFileSync(filePath, "utf-8");
}

function writeFile(filePath, content) {
  fs.writeFileSync(filePath, content, "utf-8");
}

function watchDir(dirPath, callback) {
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

module.exports = { readDir, readFile, writeFile, watchDir, unwatchDir };
