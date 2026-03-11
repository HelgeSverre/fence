export function setupEditorKeys() {
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") {
      const ta = document.querySelector(".editor-textarea");
      if (!ta || document.activeElement !== ta) return;
      if (ta.selectionStart !== ta.selectionEnd) {
        e.preventDefault();
        ta.selectionEnd = ta.selectionStart;
      }
      return;
    }

    if (e.key !== "Tab") return;
    const ta = document.querySelector(".editor-textarea");
    if (!ta || document.activeElement !== ta) return;

    e.preventDefault();
    const { selectionStart, selectionEnd, value } = ta;

    if (e.shiftKey) {
      if (selectionStart === selectionEnd) {
        unindentAtCursor(ta, value, selectionStart);
      } else {
        unindentSelection(ta, value, selectionStart, selectionEnd);
      }
    } else {
      if (selectionStart === selectionEnd) {
        insertAtCursor(ta, value, selectionStart);
      } else {
        indentSelection(ta, value, selectionStart, selectionEnd);
      }
    }

    ta.dispatchEvent(new InputEvent("input", { bubbles: true }));
  });
}

function insertAtCursor(ta, value, pos) {
  ta.value = value.slice(0, pos) + "\t" + value.slice(pos);
  ta.selectionStart = ta.selectionEnd = pos + 1;
}

function unindentAtCursor(ta, value, pos) {
  const lineStart = value.lastIndexOf("\n", pos - 1) + 1;
  const ch = value[lineStart];

  if (ch === "\t") {
    ta.value = value.slice(0, lineStart) + value.slice(lineStart + 1);
    ta.selectionStart = ta.selectionEnd = Math.max(lineStart, pos - 1);
  } else if (ch === " ") {
    const remove = value[lineStart + 1] === " " ? 2 : 1;
    ta.value = value.slice(0, lineStart) + value.slice(lineStart + remove);
    ta.selectionStart = ta.selectionEnd = Math.max(lineStart, pos - remove);
  }
}

function indentSelection(ta, value, start, end) {
  const lineStart = value.lastIndexOf("\n", start - 1) + 1;
  const lineEnd = value.indexOf("\n", end);
  const blockEnd = lineEnd === -1 ? value.length : lineEnd;

  const before = value.slice(0, lineStart);
  const block = value.slice(lineStart, blockEnd);
  const after = value.slice(blockEnd);

  const indented = block.replace(/^/gm, "\t");
  const lineCount = block.split("\n").length;

  ta.value = before + indented + after;
  ta.selectionStart = lineStart;
  ta.selectionEnd = blockEnd + lineCount;
}

function unindentSelection(ta, value, start, end) {
  const lineStart = value.lastIndexOf("\n", start - 1) + 1;
  const lineEnd = value.indexOf("\n", end);
  const blockEnd = lineEnd === -1 ? value.length : lineEnd;

  const before = value.slice(0, lineStart);
  const block = value.slice(lineStart, blockEnd);
  const after = value.slice(blockEnd);

  let totalRemoved = 0;
  const unindented = block.replace(/^(\t| {1,2})/gm, (match) => {
    totalRemoved += match.length;
    return "";
  });

  ta.value = before + unindented + after;
  ta.selectionStart = lineStart;
  ta.selectionEnd = blockEnd - totalRemoved;
}
