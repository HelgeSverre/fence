// Glue for the virtual editor's hidden input. Elm reads the committed text
// from the `input` event; the value is cleared here afterwards (Elm's virtual
// DOM won't re-set an unchanged "" value). Paste is turned into a custom
// event carrying plain text, since Elm cannot call clipboardData.getData.
export function setupVirtualInput() {
  document.addEventListener("input", (e) => {
    const t = e.target;
    if (t?.classList?.contains("veditor-input") && !e.isComposing) t.value = "";
  });
  document.addEventListener("compositionend", (e) => {
    const t = e.target;
    if (t?.classList?.contains("veditor-input")) t.value = "";
  });
  document.addEventListener("paste", (e) => {
    const t = e.target;
    if (!t?.classList?.contains("veditor-input")) return;
    e.preventDefault();
    const text = e.clipboardData?.getData("text/plain") ?? "";
    if (text) t.dispatchEvent(new CustomEvent("fencepaste", { detail: text, bubbles: true }));
  });
}

// Copy/cut: Elm exposes the selected text on the hidden input. Both the Edit
// menu's copy/cut roles (webContents.copy()) and Cmd+C/X in the focused
// input arrive here as copy/cut events; fill the clipboard from the exposed
// text and tell Elm to remove the selection on cut. Handling the events, not
// the keydown, avoids racing the menu accelerator.
function handleClipboard(e, cut) {
  const t = document.activeElement;
  if (!t?.classList?.contains("veditor-input")) return;
  const text = t.dataset.selection || "";
  if (!text) return;
  e.preventDefault();
  e.clipboardData.setData("text/plain", text);
  if (cut) t.dispatchEvent(new CustomEvent("fencecut", { bubbles: true }));
}
document.addEventListener("copy", (e) => handleClipboard(e, false));
document.addEventListener("cut", (e) => handleClipboard(e, true));

// The keyboard shortcut also reaches the renderer; its default action would
// copy the hidden input's (empty) native selection after the menu path ran.
// Copy the selected text ourselves within the gesture instead.
document.addEventListener("keydown", (e) => {
  const t = e.target;
  if (!t?.classList?.contains("veditor-input") || !(e.metaKey || e.ctrlKey) || e.altKey) return;
  const key = e.key.toLowerCase();
  if (key !== "c" && key !== "x") return;
  const text = t.dataset.selection || "";
  if (!text) return;
  e.preventDefault();
  t.value = text;
  t.select();
  document.execCommand("copy"); // fires our copy handler above, which sets the clipboard text
  t.value = "";
  if (key === "x") t.dispatchEvent(new CustomEvent("fencecut", { bubbles: true }));
});
