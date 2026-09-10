// Search rendered text without inserting markup into Elm's DOM (or exported HTML).
// Ranges can span inline elements, but never bridge separate block elements.
export function setupPreviewFind(app) {
  let state = { opened: false, query: "", caseSensitive: false, limit: 1000 };
  let ranges = [];
  let active = 0;
  let observer;
  let observed;
  let scheduled = false;
  let rebuild = false;
  let pendingDelta = 0;
  let shouldScroll = false;

  function searchText(root) {
    const parts = [];
    let length = 0;
    let lastCharacter = "";
    const nodes = [];
    function blockBreak() {
      parts.push("\n");
      length++;
      lastCharacter = "\n";
    }
    function visit(node) {
      if (node.nodeType === Node.TEXT_NODE) {
        const collapse = ["normal", "nowrap"].includes(getComputedStyle(node.parentElement).whiteSpace);
        const start = length;
        const characters = [];
        const starts = [];
        const ends = [];
        for (let i = 0; i < node.length;) {
          const from = i;
          let character = node.data[i++];
          if (collapse && /[\t\n\f\r ]/.test(character)) {
            while (i < node.length && /[\t\n\f\r ]/.test(node.data[i])) i++;
            if (lastCharacter === " ") continue;
            character = " ";
          }
          characters.push(character);
          length++;
          lastCharacter = character;
          starts.push(from);
          ends.push(i);
        }
        parts.push(characters.join(""));
        if (starts.length) nodes.push({ node, start, end: length, starts, ends });
        return;
      }
      if (node.nodeType !== Node.ELEMENT_NODE) return;
      if (node.matches("script, style, [aria-hidden=true], .welcome")) return;
      const style = getComputedStyle(node);
      if (style.display === "none" || style.visibility === "hidden") return;
      const block = !["inline", "contents"].includes(style.display);
      if (block || node.tagName === "BR") blockBreak();
      for (const child of node.childNodes) visit(child);
      if (block) blockBreak();
    }
    visit(root);
    return { text: parts.join(""), nodes };
  }

  function findRanges(root) {
    if (!state.query) return [];
    const { text, nodes } = searchText(root);
    const escaped = state.query.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const pattern = new RegExp(escaped, state.caseSensitive ? "gu" : "giu");
    const matches = [];
    let cursor = 0;
    for (const match of text.matchAll(pattern)) {
      while (cursor < nodes.length && nodes[cursor].end <= match.index) cursor++;
      const start = nodes[cursor];
      let last = cursor;
      const endOffset = match.index + match[0].length;
      while (last < nodes.length && nodes[last].end < endOffset) last++;
      const end = nodes[last];
      if (!start || !end || match.index < start.start || endOffset <= end.start) continue;
      const range = new Range();
      range.setStart(start.node, start.starts[match.index - start.start]);
      range.setEnd(end.node, end.ends[endOffset - end.start - 1]);
      matches.push(range);
      if (matches.length >= state.limit) break;
    }
    return matches;
  }

  function refresh() {
    scheduled = false;
    const root = document.querySelector(".preview-content");
    if (root !== observed) {
      observer?.disconnect();
      observed = root;
      if (root && state.opened) {
        observer = new MutationObserver(() => schedule(true, false));
        observer.observe(root, { childList: true, characterData: true, subtree: true, attributes: true });
      }
      rebuild = true;
    }
    if (!state.opened || !root) {
      CSS.highlights.delete("preview-matches");
      CSS.highlights.delete("preview-active");
      observer?.disconnect();
      observed = null;
      ranges = [];
      pendingDelta = 0;
      return;
    }
    if (rebuild) ranges = findRanges(root);
    rebuild = false;
    active = ranges.length ? ((Math.min(active, ranges.length - 1) + pendingDelta) % ranges.length + ranges.length) % ranges.length : 0;
    pendingDelta = 0;
    CSS.highlights.set("preview-matches", new Highlight(...ranges));
    const current = ranges[active];
    const highlight = new Highlight(...(current ? [current] : []));
    highlight.priority = 1;
    CSS.highlights.set("preview-active", highlight);
    if (current && shouldScroll) {
      const container = document.getElementById("preview-container");
      const rect = current.getBoundingClientRect();
      const viewport = container.getBoundingClientRect();
      // Leave room for the overlaid Find bar.
      if (rect.top < viewport.top + 60 || rect.bottom > viewport.bottom) {
        container.scrollTop += rect.top - viewport.top - container.clientHeight / 2;
      }
    }
    shouldScroll = false;
    app.ports.fromElectron.send({
      tag: "previewFindResult", query: state.query, caseSensitive: state.caseSensitive,
      current: ranges.length ? active + 1 : 0, total: ranges.length,
    });
  }

  function schedule(reindex, scroll) {
    rebuild ||= reindex;
    shouldScroll ||= scroll;
    if (scheduled) return;
    scheduled = true;
    // Elm's next view must be painted before querying its text or visibility.
    requestAnimationFrame(() => requestAnimationFrame(refresh));
  }

  return (data) => {
    const changed = data.query !== state.query || data.caseSensitive !== state.caseSensitive || data.opened !== state.opened;
    if (changed) active = 0;
    state = data;
    pendingDelta += data.delta || 0;
    schedule(changed, true);
  };
}
