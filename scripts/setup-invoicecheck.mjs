#!/usr/bin/env node
import { existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

const repoUrl = process.env.INVOICECHECK_REPO_URL ?? 'https://github.com/dharmendra26-wiz/Enterprise-AP-Environment.git';
const targetDir = resolve(process.cwd(), 'InvoiceCheck');
const installDeps = process.argv.includes('--install-deps');

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: options.cwd ?? process.cwd(),
    env: process.env,
    shell: false,
    stdio: 'inherit',
  });

  if (result.error) {
    throw result.error;
  }

  if (result.status !== 0) {
    throw new Error(`${command} ${args.join(' ')} exited with code ${result.status}`);
  }
}

function pythonCommand() {
  return process.platform === 'win32' ? 'python' : 'python3';
}

function venvPythonPath() {
  return process.platform === 'win32'
    ? join(targetDir, '.venv', 'Scripts', 'python.exe')
    : join(targetDir, '.venv', 'bin', 'python');
}

if (existsSync(targetDir)) {
  console.log(`InvoiceCheck already exists at ${targetDir}`);
} else {
  console.log(`Cloning InvoiceCheck from ${repoUrl}`);
  run('git', ['clone', repoUrl, targetDir]);
}

if (installDeps) {
  const venvDir = join(targetDir, '.venv');
  const venvPython = venvPythonPath();

  if (!existsSync(venvPython)) {
    console.log('Creating InvoiceCheck Python virtual environment');
    run(pythonCommand(), ['-m', 'venv', venvDir]);
  }

  console.log('Installing InvoiceCheck Python dependencies');
  run(venvPython, ['-m', 'pip', 'install', '--upgrade', 'pip']);

  const requirementsPath = join(targetDir, 'requirements.txt');
  if (existsSync(requirementsPath)) {
    run(venvPython, ['-m', 'pip', 'install', '-r', requirementsPath]);
  }
}

console.log('InvoiceCheck is ready. Run `npm run ai:env` to start the local sidecar.');