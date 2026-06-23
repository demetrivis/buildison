#!/usr/bin/env node
// Wrapper npx do buildison — delega para o engine install.sh (validado).
// Uso: npx buildison install [--dir <path>] [--agents claude,codex,opencode] [--yes] [--force]
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { existsSync } from 'node:fs';

const pkgRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
const script = join(pkgRoot, 'install.sh');

if (!existsSync(script)) {
  console.error('install.sh não encontrado no pacote buildison.');
  process.exit(1);
}

const args = process.argv.slice(2);
if (args[0] === 'install') args.shift(); // aceita "buildison install ..." e "buildison ..."

const res = spawnSync('bash', [script, ...args], { stdio: 'inherit' });
if (res.error && res.error.code === 'ENOENT') {
  console.error('bash não encontrado.');
  console.error('No Windows, use o instalador nativo do PowerShell:');
  console.error('  irm https://raw.githubusercontent.com/demetrivis/buildison/main/install.ps1 | iex');
  console.error('(ou rode este npx dentro do Git Bash / WSL)');
  process.exit(1);
}
process.exit(res.status ?? 1);
