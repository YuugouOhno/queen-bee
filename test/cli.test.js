const { describe, it, after } = require('node:test');
const assert = require('node:assert');
const { execFile } = require('node:child_process');
const { promisify } = require('node:util');
const path = require('node:path');
const fs = require('node:fs');
const os = require('node:os');

const execFileAsync = promisify(execFile);
const CLI = path.join(__dirname, '..', 'bin', 'beeops.js');

describe('beeops CLI', () => {
  it('--help shows usage and exits 0', async () => {
    const { stdout } = await execFileAsync(process.execPath, [CLI, '--help']);
    assert.match(stdout, /Usage:/);
    assert.match(stdout, /Commands:/);
  });

  it('--version shows version and exits 0', async () => {
    const { stdout } = await execFileAsync(process.execPath, [CLI, '--version']);
    const pkg = require('../package.json');
    assert.match(stdout, new RegExp(pkg.version.replace(/\./g, '\\.')));
  });

  it('init --help shows help', async () => {
    const { stdout } = await execFileAsync(process.execPath, [CLI, 'init', '--help']);
    assert.match(stdout, /Usage:/);
  });

  describe('check outside git repo', () => {
    let tmpDir;

    after(() => {
      if (tmpDir && fs.existsSync(tmpDir)) {
        fs.rmSync(tmpDir, { recursive: true, force: true });
      }
    });

    it('check errors outside a git repo', async () => {
      tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'bo-test-'));
      try {
        await execFileAsync(process.execPath, [CLI, 'check'], { cwd: tmpDir });
        assert.fail('Expected command to exit with non-zero code');
      } catch (err) {
        assert.match(err.stderr, /Not inside a git repository/);
      }
    });
  });
});
