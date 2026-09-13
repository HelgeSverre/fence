// A browser-style status readout: hovering (or focusing) a link in the preview
// shows where it goes, pinned to the bottom-left corner of the preview pane.
//
// The element lives on <body> and is anchor-positioned to the pane, not nested
// inside it. That keeps it out of the export payload (built from
// `.preview-content`, see js/ports.js) for free, and keeps it out of the DOM
// Elm owns and diffs.
//
// Listeners are delegated from the pane: the preview re-renders constantly, so
// per-link listeners would be re-attached forever.

let el = null;

export function setupLinkStatus() {
  const attach = () => {
    const pane = document.querySelector(".preview-content");
    if (!pane) {
      requestAnimationFrame(attach);
      return;
    }
    el = document.createElement("div");
    el.className = "link-status";
    el.dataset.testid = "link-status";
    document.body.appendChild(el);

    pane.addEventListener("mouseover", (e) => show(e.target.closest?.("a[href]"), pane));
    pane.addEventListener("mouseout", (e) => {
      if (e.target.closest?.("a[href]")) hide();
    });
    pane.addEventListener("focusin", (e) => show(e.target.closest?.("a[href]"), pane));
    pane.addEventListener("focusout", hide);
  };
  attach();
}

function show(link, pane) {
  if (!link || !el) return;
  const text = describeTarget(link.getAttribute("href"), pane.dataset.documentPath);
  if (!text) return;
  el.textContent = text;
  // Move aside rather than sit on top of the link the reader is pointing at.
  el.dataset.side = inBottomLeft(link, pane) ? "right" : "left";
  el.classList.add("is-visible");
}

function hide() {
  el?.classList.remove("is-visible");
}

/** What the reader should see for this href: the URL as written for anything
    external, a resolved (workspace-relative where possible) path for a local
    document, and a plain statement for a same-document heading anchor. */
function describeTarget(href, documentPath) {
  if (!href) return "";
  if (href.startsWith("#")) return `In this document → ${decode(href.slice(1))}`;
  if (href.startsWith("//") || /^[a-z][a-z0-9+.-]*:/i.test(href)) return href;
  if (!documentPath) return href;
  const { path, fragment } = resolveLocal(href, documentPath);
  return shorten(path) + (fragment ? `#${fragment}` : "");
}

// `URL` does the `..`/`.` normalization and the percent-decoding; the document
// path is percent-encoded into a file: URL first so that spaces and `#` in a
// real path cannot break the parse.
function resolveLocal(href, documentPath) {
  try {
    const base = new URL(`file://${documentPath.split("/").map(encodeURIComponent).join("/")}`);
    const url = new URL(href, base);
    return { path: decode(url.pathname), fragment: decode(url.hash.slice(1)) };
  } catch {
    return { path: href, fragment: "" };
  }
}

function decode(value) {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

// The file tree's first `data-path` is its root, i.e. the open workspace.
// ponytail: no `~` shortening - the renderer has no home directory and asking
// for one would mean new IPC. Paths outside the workspace show absolute.
function shorten(target) {
  const root = document.querySelector(".file-tree [data-path]")?.dataset.path;
  return root && target.startsWith(`${root}/`) ? target.slice(root.length + 1) : target;
}

function inBottomLeft(link, pane) {
  const box = (pane.closest(".preview-container") ?? pane).getBoundingClientRect();
  const rect = link.getBoundingClientRect();
  return rect.bottom > box.bottom - 80 && rect.left < box.left + box.width / 2;
}
