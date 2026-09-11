// Everything persisted under userData: state.json, the last-document session
// record, and per-file recovery drafts.
const { app } = require("electron");
const path = require("node:path");
const fs = require("node:fs");
const crypto = require("node:crypto");
const fsOps = require("./fs-ops");
const { requireString } = require("./validate");

function getStatePath() {
  return path.join(app.getPath("userData"), "state.json");
}

function loadState() {
  try {
    return JSON.parse(fs.readFileSync(getStatePath(), "utf-8"));
  } catch {
    return {};
  }
}

function saveState(state) {
  try {
    // Write-then-rename so a crash mid-write can't leave a truncated state.json.
    const statePath = getStatePath();
    fs.writeFileSync(`${statePath}.tmp`, JSON.stringify(state));
    fs.renameSync(`${statePath}.tmp`, statePath);
  } catch {
    /* ignore */
  }
}

// Load → mutate → save the persisted state file. Use for any IPC handler
// that needs to update one or more fields without dropping the others.
function updateState(updater) {
  const state = loadState();
  const updates = updater(state) || {};
  saveState({ ...state, ...updates });
}

let currentSession = null;
let sessionTimer;

function flushSession() {
  clearTimeout(sessionTimer);
  if (currentSession !== null) updateState(() => ({ lastDocument: currentSession }));
}

function rememberSession(data) {
  currentSession = {
    path: typeof data.path === "string" ? data.path : null,
    ...Object.fromEntries(["line", "col", "top", "left"].map(key => [key, Number.isFinite(data[key]) ? Math.max(0, data[key]) : 0])),
  };
  clearTimeout(sessionTimer);
  // Every cursor move lands here; the flush is a sync read+write of
  // state.json, so wait for a real pause. Close and navigation flush directly.
  sessionTimer = setTimeout(flushSession, 1000);
}

let recoveryWrites = Promise.resolve();

function recoveryDir() {
  return path.join(app.getPath("userData"), "recovery");
}

function recoveryPathFor(filePath) {
  const key = crypto.createHash("sha256").update(filePath).digest("hex");
  return path.join(recoveryDir(), `${key}.json`);
}

async function saveRecoveryDraft(payload) {
  const filePath = requireString(payload, "path", 32768);
  const content = requireString(payload, "content");
  const revision = payload.revision;
  const canonical = await fsOps.resolvePath(filePath);
  const destination = recoveryPathFor(canonical);
  const temp = `${destination}.${process.pid}.tmp`;
  await fs.promises.mkdir(path.dirname(destination), { recursive: true });
  await fs.promises.writeFile(
    temp,
    JSON.stringify({
      path: canonical,
      content,
      revision: typeof revision === "string" ? revision : null,
      savedAt: new Date().toISOString(),
    }),
    "utf-8",
  );
  await fs.promises.rename(temp, destination);
}

// Renderer draft saves are serialized so a fast typist's drafts land in order.
function queueRecoveryDraft(payload) {
  recoveryWrites = recoveryWrites.catch(() => {}).then(() => saveRecoveryDraft(payload));
  return recoveryWrites;
}

function awaitRecoveryWrites() {
  return recoveryWrites.catch(() => {});
}

async function clearRecoveryDraft(filePath) {
  await awaitRecoveryWrites();
  await fs.promises.unlink(recoveryPathFor(filePath)).catch((error) => {
    if (error.code !== "ENOENT") throw error;
  });
}

async function loadRecoveryDraft(filePath) {
  try {
    return JSON.parse(
      await fs.promises.readFile(recoveryPathFor(filePath), "utf-8"),
    );
  } catch {
    return null;
  }
}

// After a rename, re-key every draft whose path `follow` maps somewhere new.
async function relocateRecoveryDrafts(follow) {
  const directory = recoveryDir();
  for (const name of await fs.promises.readdir(directory).catch(() => [])) {
    if (!name.endsWith(".json")) continue;
    const file = path.join(directory, name);
    const draft = await fs.promises.readFile(file, "utf8").then(JSON.parse).catch(() => null);
    if (draft?.path && follow(draft.path) !== draft.path) {
      const target = follow(draft.path);
      await saveRecoveryDraft({ ...draft, path: target });
      await fs.promises.unlink(file);
    }
  }
}

module.exports = {
  loadState,
  updateState,
  flushSession,
  rememberSession,
  saveRecoveryDraft,
  queueRecoveryDraft,
  awaitRecoveryWrites,
  clearRecoveryDraft,
  loadRecoveryDraft,
  relocateRecoveryDrafts,
};
