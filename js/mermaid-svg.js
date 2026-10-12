let nextCopy = 0;

// Shared IDs make markers and embedded CSS resolve to another diagram.
export function uniqueDiagramCopy(svg) {
  const copy = svg.cloneNode(true);
  const prefix = `fence-diagram-copy-${++nextCopy}-`;
  const nodes = [copy, ...copy.querySelectorAll("*")];
  const ids = new Map(nodes.filter((node) => node.id).map((node) => [node.id, prefix + node.id]));
  if (!ids.size) return copy;
  const escaped = [...ids.keys()].sort((a, b) => b.length - a.length)
    .map((id) => id.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"));
  const refs = new RegExp(`#(${escaped.join("|")})(?![\\w-])`, "g");
  const rewrite = (text) => text.replace(refs, (_, id) => `#${ids.get(id)}`);
  for (const node of nodes) {
    for (const attr of [...node.attributes]) {
      if (attr.name === "id") node.id = ids.get(attr.value);
      else if (attr.name === "aria-labelledby" || attr.name === "aria-describedby") {
        node.setAttribute(attr.name, attr.value.split(/\s+/).map((id) => ids.get(id) || id).join(" "));
      } else node.setAttribute(attr.name, rewrite(attr.value));
    }
    if (node.tagName.toLowerCase() === "style") node.textContent = rewrite(node.textContent);
  }
  return copy;
}
