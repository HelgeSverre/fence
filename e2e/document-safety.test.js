const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const { test } = require('node:test');
const { launchFence, setEditorContent, waitForEditorValue, editorText, waitForFile, waitFor, sendFromElm, openSettings, captureClipboard, stubSaveDialog, MOD } = require('./helpers');

test('navigation offers Cancel and Save before replacing dirty content', async () => {
  const f = await launchFence({ files: { 'note.md': '# Old\n', 'other.md': '# Other\n' } });
  try {
    await f.app.evaluate(({ dialog }) => { globalThis.answer = 2; globalThis.prompts = 0; dialog.showMessageBox = async () => { globalThis.prompts++; return { response: globalThis.answer }; }; });
    await setEditorContent(f.window, '# Unsaved\n');
    await f.window.getByTestId('tree-file').filter({ hasText: 'other.md' }).click();
    await waitFor(() => f.app.evaluate(() => globalThis.prompts === 1));
    assert.equal(await editorText(f.window), '# Unsaved\n');
    await f.app.evaluate(() => { globalThis.answer = 0; });
    await f.window.getByTestId('tree-file').filter({ hasText: 'other.md' }).click();
    await waitForEditorValue(f.window, '# Other\n');
    assert.equal(await fs.readFile(f.file('note.md'), 'utf8'), '# Unsaved\n');
  } finally { await f.close(); }
});

test('saving an untitled document uses Save As and preserves content', async () => {
  const f = await launchFence({ open: null });
  try {
    await f.window.getByTestId('tree-file').waitFor();
    await stubSaveDialog(f.app, f.file('new.md'));
    await setEditorContent(f.window, '# Scratch\n');
    await f.window.keyboard.press(`${MOD}+s`);
    await f.window.waitForFunction(() => document.querySelector('#veditor-input').dataset.path.endsWith('/new.md'));
    assert.equal(await fs.readFile(f.file('new.md'), 'utf8'), '# Scratch\n');
  } finally { await f.close(); }
});

test('renaming an open document parent updates its save path', async () => {
  const f = await launchFence({ files: { 'note.md': '', 'dir/child.md': '# Child\n' } });
  try {
    await f.window.getByTestId('tree-dir').filter({ hasText: 'dir' }).click();
    await f.window.getByTestId('tree-file').filter({ hasText: 'child.md' }).click();
    await waitForEditorValue(f.window, '# Child\n');
    await f.window.evaluate(args => window.electronAPI.renamePath(args), { path: f.file('dir'), name: 'renamed' });
    await f.window.waitForFunction(() => document.querySelector('#veditor-input').dataset.path.endsWith('/renamed/child.md'));
    await setEditorContent(f.window, '# Changed\n');
    await f.window.keyboard.press(`${MOD}+s`);
    await waitForFile(f.file('renamed/child.md'), '# Changed\n');
    assert.equal(await fs.readFile(f.file('renamed/child.md'), 'utf8'), '# Changed\n');
  } finally { await f.close(); }
});

test('export immediately after an edit includes the current source', async () => {
  const f = await launchFence();
  try {
    await f.window.getByTestId('preview-content').locator('h1').waitFor();
    const copied = await captureClipboard(f.app);
    await f.window.evaluate(() => document.querySelector('#veditor-input').dispatchEvent(new CustomEvent('fencepaste', { detail: 'FRESH ', bubbles: true })));
    await sendFromElm(f.app, { tag: 'exportRequested', format: 'clipboard' });
    assert.match((await waitFor(copied)).text, /FRESH/);
  } finally { await f.close(); }
});

test('switching workspace checks unsaved work and clears the previous editor', async () => {
  const f = await launchFence({ files: { 'note.md': '# Old\n', 'next/other.md': '# Next\n' } });
  try {
    await f.app.evaluate(({ dialog }, folder) => {
      dialog.showOpenDialog = async () => ({ canceled: false, filePaths: [folder] });
      dialog.showMessageBox = async () => ({ response: 0 });
    }, f.file('next'));
    await setEditorContent(f.window, '# Saved before switch\n');
    await f.window.evaluate(() => window.electronAPI.openFolder());
    await waitForEditorValue(f.window, '');
    assert.equal(await fs.readFile(f.file('note.md'), 'utf8'), '# Saved before switch\n');
    assert.equal(await f.window.locator('#veditor-input').getAttribute('data-path'), '');
    await f.window.getByTestId('tree-file').filter({ hasText: 'other.md' }).waitFor();
  } finally { await f.close(); }
});

test('local document links open beside the source and navigate to heading fragments', async () => {
  const f = await launchFence({ files: {
    'note.md': '[Other](docs/other%20note.md#target)\n',
    'docs/other note.md': '# Other\n\n' + 'Paragraph\n\n'.repeat(80) + '## Target\n',
  } });
  try {
    await f.window.getByTestId('preview-content').locator('a').click();
    await f.window.waitForFunction(() => document.querySelector('#veditor-input').dataset.path.endsWith('/docs/other note.md'));
    await f.window.waitForFunction(() => document.querySelector('#preview-container').scrollTop > 100);
    assert.equal(await f.window.getByTestId('preview-content').locator('#target').textContent(), 'Target');
  } finally { await f.close(); }
});

test('restart restores the last document, caret, and viewport', async () => {
  const content = Array.from({ length: 500 }, (_, i) => `Line ${i}`).join('\n');
  const first = await launchFence({ files: { 'note.md': content }, state: { softWrap: false } });
  let second;
  try {
    await first.window.locator('.veditor-spacer').click({ position: { x: 20, y: 5 } });
    await first.window.keyboard.press(`${MOD}+End`);
    // Direct scrolling is part of normal editor state, including when the caret is offscreen.
    await first.window.getByTestId('veditor').evaluate(e => { e.scrollTop = 2000; e.dispatchEvent(new Event('scroll')); });
    // The session flush is debounced; wait for the write rather than guess its delay.
    const statePath = require('node:path').join(first.userDataDir, 'state.json');
    const lastDocument = async () => JSON.parse(await fs.readFile(statePath, 'utf8').catch(() => '{}')).lastDocument;
    const session = await waitFor(async () => { const s = await lastDocument(); return s?.top > 1000 && s; });
    await first.close({ keepUserData: true, keepWorkspace: true });
    second = await launchFence({ restoreSession: true, userDataDir: first.userDataDir });
    await second.window.waitForFunction(path => document.querySelector('#veditor-input').dataset.path === path, first.file('note.md'));
    await second.window.waitForFunction(top => Math.abs(document.querySelector('.veditor').scrollTop - top) < 30, session.top);
    // The restored session is flushed back to state.json; wait for that write.
    const restored = await waitFor(async () => { const s = await lastDocument(); return s?.line === session.line && s?.col === session.col && s; });
    assert.equal(restored.line, session.line);
  } finally {
    if (second) await second.close();
    else await first.close();
    await fs.rm(first.workspace, { recursive: true, force: true });
  }
});

test('settings remains scrollable and inside a short viewport', async () => {
  const f = await launchFence({ state: { uiFontSize: 16 } });
  try {
    await f.window.setViewportSize({ width: 1100, height: 700 });
    await openSettings(f.window);
    const menu = f.window.getByTestId('settings-dropdown');
    const bounds = await menu.boundingBox();
    assert.ok(bounds.y + bounds.height <= 700);
    assert.equal(await menu.evaluate(e => e.scrollHeight > e.clientHeight), true);
    await menu.locator('.rebind-btn').last().scrollIntoViewIfNeeded();
    const last = await menu.locator('.rebind-btn').last().boundingBox();
    assert.ok(last.y + last.height < 700);
  } finally { await f.close(); }
});

test('cancelling Save As keeps an untitled document open, then Save on close writes it', async () => {
  const f = await launchFence({ open: null });
  try {
    await f.window.getByTestId('tree-file').waitFor();
    await setEditorContent(f.window, '# Keep me\n');
    await f.app.evaluate(({ dialog, BrowserWindow }) => {
      dialog.showMessageBox = async () => ({ response: 0 });
      globalThis.saveAsked = false;
      dialog.showSaveDialog = async () => { globalThis.saveAsked = true; return { canceled: true }; };
      // Reproduce a close arriving before the renderer dirty-state IPC.
      BrowserWindow.getAllWindows()[0]._isDirty = false;
      BrowserWindow.getAllWindows()[0].close();
    });
    await waitFor(() => f.app.evaluate(() => globalThis.saveAsked));
    assert.equal(await editorText(f.window), '# Keep me\n');
    await stubSaveDialog(f.app, f.file('kept.md'));
    const closed = f.window.waitForEvent('close');
    await f.app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].close());
    await closed;
    assert.equal(await fs.readFile(f.file('kept.md'), 'utf8'), '# Keep me\n');
  } finally { await f.close(); }
});

test('Save As writes a new file without changing the original', async () => {
  const f = await launchFence({ files: { 'note.md': '# Original\n' } });
  try {
    await stubSaveDialog(f.app, f.file('copy.md'));
    await setEditorContent(f.window, '# Copy\n');
    await f.window.keyboard.press(`${MOD}+Shift+s`);
    await f.window.waitForFunction(() => document.querySelector('#veditor-input').dataset.path.endsWith('/copy.md'));
    assert.equal(await fs.readFile(f.file('copy.md'), 'utf8'), '# Copy\n');
    assert.equal(await fs.readFile(f.file('note.md'), 'utf8'), '# Original\n');
  } finally { await f.close(); }
});

test('a clicked link can open a document above the current workspace', async () => {
  const f = await launchFence({ open: 'docs/note.md', files: { 'docs/note.md': '[Parent](../parent.md)\n', 'parent.md': '# Parent\n' } });
  try {
    await f.window.getByTestId('preview-content').locator('a').click();
    await waitForEditorValue(f.window, '# Parent\n');
    assert.equal(await f.window.locator('#veditor-input').getAttribute('data-path'), f.file('parent.md'));
  } finally { await f.close(); }
});

// A renderer that never answers the close guard's state probe must not make
// the window impossible to close: the guard falls back to the dirty flag the
// renderer last reported, and asks before discarding anything.
async function closeWithHungRenderer(f, dialogAnswer) {
  await f.app.evaluate(({ dialog }, answer) => {
    globalThis.__closeDialog = null;
    dialog.showMessageBox = async (_w, opts) => { globalThis.__closeDialog = opts.title; return { response: answer }; };
  }, dialogAnswer);
  // Block the renderer's JS thread outright; deliberately not awaited.
  f.window.evaluate(() => { const until = Date.now() + 20000; while (Date.now() < until) { /* hang */ } }).catch(() => {});
  await new Promise((resolve) => setTimeout(resolve, 400));
  const closed = await f.app.evaluate(async ({ BrowserWindow }) => {
    const win = BrowserWindow.getAllWindows()[0];
    win.close();
    for (let i = 0; i < 150; i += 1) {
      if (win.isDestroyed()) return true;
      await new Promise((r) => setTimeout(r, 100));
    }
    return false;
  });
  return { closed, dialog: await f.app.evaluate(() => globalThis.__closeDialog) };
}

test('an unresponsive renderer does not make a clean document impossible to close', async () => {
  const f = await launchFence({ files: { 'note.md': '# Clean\n' } });
  try {
    const { closed, dialog } = await closeWithHungRenderer(f, 1);
    assert.equal(closed, true, 'the window must still close');
    assert.equal(dialog, null, 'nothing was unsaved, so nothing to ask about');
  } finally { await f.close(); }
});

test('an unresponsive renderer asks before discarding unsaved changes', async () => {
  for (const [answer, shouldClose] of [[0, true], [1, false]]) {
    const f = await launchFence({ files: { 'note.md': '# Doc\n' } });
    try {
      await setEditorContent(f.window, '# Doc\n\nunsaved edit\n');
      await f.window.waitForFunction(() => window.electronAPI && document.querySelector('[data-testid=editor-header]').textContent.includes('*'));
      const { closed, dialog } = await closeWithHungRenderer(f, answer);
      assert.match(dialog ?? '', /not responding/i, 'the user must be asked before losing work');
      assert.equal(closed, shouldClose, answer === 0 ? 'Close Anyway must close' : 'Cancel must keep it open');
    } finally { await f.close(); }
  }
});
