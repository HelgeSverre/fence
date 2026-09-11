const path = require("node:path");
const { pathToFileURL } = require("node:url");

function requireString(payload, key, maxLength = 100 * 1024 * 1024) {
  const value = payload?.[key];
  if (typeof value !== "string" || value.length > maxLength) {
    throw new TypeError(`Invalid ${key}`);
  }
  return value;
}

// Invalid or missing keys are skipped silently, as in save-splits in main.js.
const string = (max) => (v) => typeof v === "string" && v.length <= max;
const number = (lo, hi) => (v) => typeof v === "number" && v >= lo && v <= hi;
const integer = (lo, hi) => (v) => Number.isInteger(v) && v >= lo && v <= hi;
const boolean = (v) => typeof v === "boolean";
const oneOf = (values) => (v) => values.includes(v);

const preferenceRules = {
  theme: string(128), editorFont: string(256), uiFont: string(256),
  editorFontSize: number(8, 32), previewFontSize: number(8, 32), uiFontSize: number(8, 24),
  previewWidth: oneOf(["full", "narrow", "normal", "wide", "custom"]), previewMaxWidth: integer(320, 2000),
  showPaneHeaders: boolean, previewUsesEditorFont: boolean, softWrap: boolean,
  revealInSidebar: boolean,
};

function isAppUrl(candidate) {
  try {
    const url = new URL(candidate);
    if (process.env.VITE_DEV_SERVER_URL) {
      return url.origin === new URL(process.env.VITE_DEV_SERVER_URL).origin;
    }
    const appUrl = pathToFileURL(path.join(__dirname, "../dist/index.html"));
    return url.protocol === "file:" && url.pathname === appUrl.pathname;
  } catch {
    return false;
  }
}

module.exports = { requireString, string, number, integer, boolean, oneOf, preferenceRules, isAppUrl };
