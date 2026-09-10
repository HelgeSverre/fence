const fs = require('node:fs');
const path = require('node:path');

function parseCliArgs(args, cwd) {
  let target = null;
  let positional = false;
  for (const arg of args) {
    if (!positional && arg === '--') { positional = true; continue; }
    if (!positional && (arg === '--help' || arg === '-h')) return { help: true };
    if (!positional && (arg === '--version' || arg === '-v')) return { version: true };
    // Electron/Playwright debugging flags belong to the runtime.
    if (!positional && /^(--inspect(?:-brk)?|--remote-debugging-port)(=|$)/.test(arg)) continue;
    if (!positional && arg.startsWith('-')) throw new Error(`Unknown option: ${arg}. Use fence --help.`);
    if (target) throw new Error('Open one file or folder at a time.');
    target = path.resolve(cwd, arg);
    if (!fs.existsSync(target)) throw new Error(`Path does not exist: ${arg}`);
    if (!fs.statSync(target).isDirectory() && !/\.(md|markdown|mdown|mkd)$/i.test(target)) throw new Error(`Not a Markdown file: ${arg}`);
  }
  return { path: target };
}
const help = 'Usage: fence [file.md | folder]\n\nOpen a Markdown file or workspace in Fence.\n\n  -h, --help       Show this help\n  -v, --version    Print the installed version\n  --              Treat subsequent arguments as paths\n';
module.exports = { parseCliArgs, help };
