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
});
