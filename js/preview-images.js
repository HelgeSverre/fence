// Elm owns the source attribute; this module owns src. Keeping them separate
// prevents cached Markdown chunks from retaining another document's base path.
const images = new WeakMap();

export function resolvePreviewImages() {
  const pane = document.querySelector(".preview-content");
  if (!pane) return Promise.resolve();
  const documentPath = pane.dataset.documentPath;
  const pending = [];
  for (const image of pane.querySelectorAll("img[data-image-source]")) {
    const source = image.dataset.imageSource;
    const previous = images.get(image);
    if (previous?.source === source && previous.documentPath === documentPath) {
      pending.push(previous.promise);
      continue;
    }
    const state = { source, documentPath };
    images.set(image, state);
    image.removeAttribute("src");
    if (/^(?:https?:|data:|blob:|\/\/)/i.test(source)) {
      image.src = source.startsWith("//") ? `https:${source}` : source;
      state.promise = Promise.resolve();
    } else {
      state.promise = (async () => {
        const url = source && documentPath
          ? await window.electronAPI?.readImage({ documentPath, source }).catch(() => null)
          : null;
        if (images.get(image) !== state || !image.isConnected
          || image.dataset.imageSource !== source || pane.dataset.documentPath !== documentPath) return;
        // An invalid data URL gives missing images a normal broken-image/alt
        // fallback without accidentally requesting an app-relative file.
        image.src = url || "data:image/png;base64,";
      })();
    }
    pending.push(state.promise);
  }
  return Promise.all(pending);
}

export function initPreviewImages() {
  const observer = new MutationObserver(() => { resolvePreviewImages(); });
  observer.observe(document.getElementById("app") || document.body, {
    childList: true, subtree: true, attributes: true,
    attributeFilter: ["data-image-source", "data-document-path"],
  });
  resolvePreviewImages();
}
