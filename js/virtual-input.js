// Glue for the virtual editor's hidden input. Elm reads the committed text
// from the `input` event; the value is cleared here afterwards (Elm's virtual
// DOM won't re-set an unchanged "" value). Paste is turned into a custom
// event carrying plain text, since Elm cannot call clipboardData.getData.
export function setupVirtualInput() {
  // Focus the hidden input on click without letting focus() scroll the
  // container (Elm's mousedown handler prevents the default focus change).
  document.addEventListener("mousedown", (e) => {
    if (!e.target?.closest?.(".veditor-spacer")) return;
    const input = document.getElementById("veditor-input");
    if (!input) return;
    // Elm moves the input to the new caret on the next frame; a key that
    // arrives before that would go to an input still at the old position
    // and Chromium would scroll to reveal it. Move it to the clicked row now.
    const lineHeight = parseFloat(input.style.height) || 20;
    input.style.top = `${Math.floor(e.offsetY / lineHeight) * lineHeight}px`;
    input.style.left = `${Math.max(0, e.offsetX)}px`;
    input.focus({ preventScroll: true });
  }, true);
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
