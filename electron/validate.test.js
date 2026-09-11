const assert = require("node:assert/strict");
const path = require("node:path");
const { pathToFileURL } = require("node:url");
const { test } = require("node:test");
const { requireString, preferenceRules, isAppUrl } = require("./validate");

test("requireString enforces presence, type and length", () => {
  assert.equal(requireString({ name: "ok" }, "name", 2), "ok");
  assert.throws(() => requireString({ name: "too long" }, "name", 3), /Invalid name/);
  assert.throws(() => requireString({}, "name"), /Invalid name/);
  assert.throws(() => requireString(undefined, "name"), /Invalid name/);
  assert.throws(() => requireString({ name: 42 }, "name"), /Invalid name/);
});

// Mirrors the rules table exactly: for each key, values that must pass and
// values that must fail (out of range or wrong type).
const cases = {
  theme: { ok: ["", "a".repeat(128)], bad: ["a".repeat(129), 1] },
  editorFont: { ok: ["Menlo", "a".repeat(256)], bad: ["a".repeat(257), null] },
  uiFont: { ok: ["Inter", "a".repeat(256)], bad: ["a".repeat(257), true] },
  editorFontSize: { ok: [8, 13.5, 32], bad: [7.9, 32.1, "12", NaN] },
  previewFontSize: { ok: [8, 32], bad: [0, 33, "16"] },
  uiFontSize: { ok: [8, 24], bad: [7, 25, "12"] },
  previewWidth: { ok: ["full", "narrow", "normal", "wide", "custom"], bad: ["huge", "", 1] },
  previewMaxWidth: { ok: [320, 2000], bad: [319, 2001, 800.5, "800"] },
  showPaneHeaders: { ok: [true, false], bad: ["true", 1, null] },
  previewUsesEditorFont: { ok: [true, false], bad: [0] },
  softWrap: { ok: [true, false], bad: ["yes"] },
  revealInSidebar: { ok: [true, false], bad: [undefined] },
};

test("preferenceRules cover exactly the documented keys and ranges", () => {
  assert.deepEqual(Object.keys(preferenceRules).sort(), Object.keys(cases).sort());
  for (const [key, { ok, bad }] of Object.entries(cases)) {
    for (const v of ok) assert.equal(preferenceRules[key](v), true, `${key} should accept ${String(v)}`);
    for (const v of bad) assert.equal(preferenceRules[key](v), false, `${key} should reject ${String(v)}`);
  }
  // The same filter main.js runs: unknown keys never reach state.json.
  const data = { theme: "x", bogus: 1, editorFontSize: 99 };
  const updates = {};
  for (const [key, valid] of Object.entries(preferenceRules)) if (valid(data[key])) updates[key] = data[key];
  assert.deepEqual(updates, { theme: "x" });
});

test("isAppUrl accepts only the dev server origin or the built index.html", () => {
  const saved = process.env.VITE_DEV_SERVER_URL;
  delete process.env.VITE_DEV_SERVER_URL;
  const index = pathToFileURL(path.join(__dirname, "../dist/index.html")).toString();
  assert.equal(isAppUrl(index), true);
  assert.equal(isAppUrl(`${index}#heading`), true);
  assert.equal(isAppUrl(pathToFileURL(path.join(__dirname, "../dist/other.html")).toString()), false);
  assert.equal(isAppUrl("https://example.com/"), false);
  assert.equal(isAppUrl("not a url"), false);

  process.env.VITE_DEV_SERVER_URL = "http://localhost:5173/";
  assert.equal(isAppUrl("http://localhost:5173/index.html?x=1"), true);
  assert.equal(isAppUrl("http://localhost:5174/"), false);
  assert.equal(isAppUrl(index), false);
  if (saved === undefined) delete process.env.VITE_DEV_SERVER_URL; else process.env.VITE_DEV_SERVER_URL = saved;
});
