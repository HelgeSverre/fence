// Glue for the virtual editor's hidden input. Elm reads the committed text
// from the `input` event; the value is cleared here afterwards (Elm's virtual
// DOM won't re-set an unchanged "" value). Paste is turned into a custom
// event carrying plain text, since Elm cannot call clipboardData.getData.
export function setupVirtualInput() {
  document.addEventListener("input", (e) => {
    const t = e.target;
    if (t?.classList?.contains("veditor-input") && !e.isComposing) t.value = "";
  });
  document.addEventListener("paste", (e) => {
    const t = e.target;
    if (!t?.classList?.contains("veditor-input")) return;
    e.preventDefault();
    const text = e.clipboardData?.getData("text/plain") ?? "";
    if (text) t.dispatchEvent(new CustomEvent("fencepaste", { detail: text, bubbles: true }));
  });
}
