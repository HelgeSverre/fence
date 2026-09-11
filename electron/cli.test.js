const { test } = require('node:test');
const assert = require('node:assert/strict');
const { parseCliArgs } = require('./cli');
test('CLI help and version do not require a workspace', () => {
  assert.deepEqual(parseCliArgs(['--help'], '/missing'), { help: true });
  assert.deepEqual(parseCliArgs(['--version'], '/missing'), { version: true });
});
test('CLI rejects invalid options and missing paths instead of opening an unrelated workspace', () => {
  assert.throws(() => parseCliArgs(['--oops'], __dirname), /Unknown option/);
  assert.throws(() => parseCliArgs(['missing-file.md'], __dirname), /does not exist/);
  assert.equal(parseCliArgs(['.'], __dirname).path, __dirname);
  assert.equal(parseCliArgs(['.', '--no-sandbox'], __dirname).path, __dirname); // vite-plugin-electron's default argv
});
test('argv forwarded by a second instance skips the switches Electron splices in', () => {
  const forwarded = ['--allow-file-access-from-files', '--enable-avfoundation', '.'];
  assert.equal(parseCliArgs(forwarded, __dirname, { forwarded: true }).path, __dirname);
  assert.throws(() => parseCliArgs(forwarded, __dirname), /Unknown option/);
});
